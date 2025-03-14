pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var stdout_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buffered.writer();

    try mainFull(.{
        .allocator = gpa,
        .args = args[1..],
        .stdout = stdout.any(),
    });

    return stdout_buffered.flush();
}

pub fn mainFull(options: struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: std.io.AnyWriter,
}) !void {
    var program = Program{
        .allocator = options.allocator,
        .args = .{ .args = options.args },
        .stdout = options.stdout,
    };

    return program.mainCommand();
}

const Program = @This();

allocator: std.mem.Allocator,
args: ArgParser,
stdout: std.io.AnyWriter,

const main_usage =
    \\Usage: aniz [command] [args]
    \\
    \\Commands:
    \\  database <subcommand>
    \\  list     <subcommand>
    \\  help                   Display this message
    \\
;

pub fn mainCommand(program: *Program) !void {
    while (program.args.next()) {
        if (program.args.flag(&.{"database"}))
            return program.databaseSubCommand();
        if (program.args.flag(&.{"list"}))
            return program.listSubCommand();
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(main_usage);
        if (program.args.positional()) |_| {
            try std.io.getStdErr().writeAll(main_usage);
            return error.InvalidArgument;
        }
    }

    try std.io.getStdErr().writeAll(main_usage);
    return error.InvalidArgument;
}

const database_sub_usage =
    \\Usage:
    \\  aniz database [command] [args]
    \\  aniz database [options] [ids]...
    \\
    \\Commands:
    \\  download               Download newest version of the database
    \\  help                   Display this message
    \\  [ids]...
    \\
;

fn databaseSubCommand(program: *Program) !void {
    if (program.args.next()) {
        if (program.args.flag(&.{"download"}))
            return program.databaseDownloadCommand();
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(database_sub_usage);
    }

    return program.databaseCommand();
}

fn databaseCommand(program: *Program) !void {
    var m_search: ?[]const u8 = null;
    var ids = std.AutoArrayHashMap(Database.Id, void).init(program.allocator);
    defer ids.deinit();

    while (program.args.next()) {
        if (program.args.option(&.{ "-s", "--search" })) |search|
            m_search = search;
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(database_sub_usage);
        if (program.args.positional()) |url| {
            const id = try Database.Id.fromUrl(url);
            try ids.put(id, {});
        }
    }

    var db = loadDatabase(program.allocator) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("error: Database doesn't exists. " ++
                "Use `aniz database download` to get it", .{});
            return error.DatabaseDoesntExist;
        },
        else => |e| return e,
    };
    defer db.deinit(program.allocator);

    if (ids.count() == 0 and m_search == null) {
        // Fast path if no ids or search is provided.
        for (db.entries) |entry| {
            try entry.serializeToDsv(db.strings, program.stdout);
            try program.stdout.writeAll("\n");
        }
        return;
    }

    var entries_to_print = std.ArrayList(Database.Entry).init(program.allocator);
    defer entries_to_print.deinit();

    try db.filterEntries(&entries_to_print, .{
        .search = m_search,
        .ids = if (ids.count() == 0) null else ids.keys(),
    });

    for (entries_to_print.items) |entry| {
        try entry.serializeToDsv(db.strings, program.stdout);
        try program.stdout.writeAll("\n");
    }
}

const database_download_usage =
    \\Usage: aniz download
    \\
;

fn databaseDownloadCommand(program: *Program) !void {
    while (program.args.next()) {
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(database_download_usage);
        if (program.args.positional()) |_| {
            try std.io.getStdErr().writeAll(database_download_usage);
            return error.InvalidArgument;
        }
    }

    var http_client = std.http.Client{ .allocator = program.allocator };
    defer http_client.deinit();

    var data_dir = try openFolder(.cache, .{});
    defer data_dir.close();

    const database_json_file = try data_dir.createFile(database_json_name, .{ .read = true });
    defer database_json_file.close();

    const database_json_url = "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database-minified.json";
    try download(&http_client, database_json_url, database_json_file.writer());

    try database_json_file.seekTo(0);
    const database_json = try database_json_file.readToEndAlloc(program.allocator, std.math.maxInt(usize));
    defer program.allocator.free(database_json);

    var db = try Database.deserializeFromJson(program.allocator, database_json);
    defer db.deinit(program.allocator);

    const database_bin_file = try data_dir.createFile(database_bin_name, .{});
    defer database_bin_file.close();

    var buffered_writer = std.io.bufferedWriter(database_bin_file.writer());
    try db.serializeToBinary(buffered_writer.writer());
    try buffered_writer.flush();
}

const list_sub_usage =
    \\Usage:
    \\  aniz list [command] [args]
    \\  aniz list [options] [ids]...
    \\
    \\Commands:
    \\  complete
    \\  drop
    \\  on-hold
    \\  plan-to-watch
    \\  remove
    \\  update
    \\  watch-episode
    \\  watching
    \\  help                   Display this message
    \\  [ids]...
    \\
;

fn listSubCommand(program: *Program) !void {
    if (program.args.next()) {
        if (program.args.flag(&.{"complete"}))
            return program.manipulateListCommand(completeAction);
        if (program.args.flag(&.{"drop"}))
            return program.manipulateListCommand(dropAction);
        if (program.args.flag(&.{"on-hold"}))
            return program.manipulateListCommand(onHoldAction);
        if (program.args.flag(&.{"plan-to-watch"}))
            return program.manipulateListCommand(planToWatchAction);
        if (program.args.flag(&.{"remove"}))
            return program.manipulateListCommand(removeAction);
        if (program.args.flag(&.{"update"}))
            return program.manipulateListCommand(updateAction);
        if (program.args.flag(&.{"watch-episode"}))
            return program.manipulateListCommand(watchEpisodeAction);
        if (program.args.flag(&.{"watching"}))
            return program.manipulateListCommand(watchingAction);
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(list_sub_usage);
    }

    return program.listCommand();
}

fn listCommand(program: *Program) !void {
    var m_search: ?[]const u8 = null;
    var ids = std.AutoArrayHashMap(Database.Id, void).init(program.allocator);
    defer ids.deinit();

    while (program.args.next()) {
        if (program.args.option(&.{ "-s", "--search" })) |search|
            m_search = search;
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(list_sub_usage);
        if (program.args.positional()) |url| {
            const id = try Database.Id.fromUrl(url);
            try ids.put(id, {});
        }
    }

    var list = try loadList(program.allocator);
    defer list.deinit(program.allocator);

    if (ids.count() == 0 and m_search == null) {
        // Fast path if no ids or search is provided.
        for (list.entries.items) |entry| {
            try entry.serializeToTsv(list.intern.sliceZ(), program.stdout);
            try program.stdout.writeAll("\n");
        }
        return;
    }

    var db = loadDatabase(program.allocator) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("error: Database doesn't exists. " ++
                "Use `aniz database download` to get it", .{});
            return error.DatabaseDoesntExist;
        },
        else => |e| return e,
    };
    defer db.deinit(program.allocator);

    var entries_to_print = std.ArrayList(Database.Entry).init(program.allocator);
    defer entries_to_print.deinit();

    try db.filterEntries(&entries_to_print, .{
        .search = m_search,
        .ids = if (ids.count() == 0) null else ids.keys(),
    });

    for (entries_to_print.items) |entry| {
        for (entry.ids.all()) |m_id| {
            const id = m_id orelse continue;
            const list_entry = list.find(id) orelse continue;
            try list_entry.serializeToTsv(list.intern.sliceZ(), program.stdout);
            try program.stdout.writeAll("\n");
        }
    }
}

const manipuate_list_usage =
    \\Usage: aniz list <action> [ids]...
    \\
    \\Commands:
    \\  help                   Display this message
    \\  [ids]...
    \\
;

fn manipulateListCommand(program: *Program, action: Action) !void {
    var ids = std.AutoArrayHashMap(Database.Id, void).init(program.allocator);
    defer ids.deinit();

    while (program.args.next()) {
        if (program.args.flag(&.{ "-h", "--help", "help" }))
            return program.stdout.writeAll(manipuate_list_usage);
        if (program.args.positional()) |url| {
            const id = try Database.Id.fromUrl(url);
            try ids.put(id, {});
        }
    }

    var db = loadDatabase(program.allocator) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("error: Database doesn't exists. " ++
                "Use `aniz database download` to get it", .{});
            return error.DatabaseDoesntExist;
        },
        else => |e| return e,
    };
    defer db.deinit(program.allocator);

    var list = try loadList(program.allocator);
    defer list.deinit(program.allocator);

    for (ids.keys()) |id| {
        const database_entry = db.findWithId(id) orelse {
            std.log.err("Anime '{}' was not found in the database", .{id});
            return error.NoSuchAnime;
        };

        const title = database_entry.title.slice(db.strings);
        const entry = try list.addEntry(program.allocator, id, title);

        action(&list, entry, database_entry.*);
    }

    try saveList(list);
}

const Action = *const fn (*List, *List.Entry, Database.Entry) void;

fn completeAction(_: *List, list_entry: *List.Entry, database_entry: Database.Entry) void {
    list_entry.date = datetime.datetime.Date.now();
    list_entry.status = .complete;
    list_entry.watched += 1;
    list_entry.episodes = database_entry.episodes;
}

fn onHoldAction(_: *List, list_entry: *List.Entry, _: Database.Entry) void {
    list_entry.date = datetime.datetime.Date.now();
    list_entry.status = .on_hold;
}

fn dropAction(_: *List, list_entry: *List.Entry, _: Database.Entry) void {
    list_entry.date = datetime.datetime.Date.now();
    list_entry.status = .dropped;
}

fn planToWatchAction(_: *List, list_entry: *List.Entry, _: Database.Entry) void {
    list_entry.date = datetime.datetime.Date.now();
    list_entry.status = .plan_to_watch;
}

fn watchingAction(_: *List, list_entry: *List.Entry, _: Database.Entry) void {
    list_entry.date = datetime.datetime.Date.now();
    list_entry.status = .watching;
}

fn watchEpisodeAction(_: *List, list_entry: *List.Entry, database_entry: Database.Entry) void {
    if (list_entry.episodes < database_entry.episodes) {
        list_entry.date = datetime.datetime.Date.now();
        list_entry.episodes += 1;
        list_entry.status = .watching;
        if (list_entry.episodes == database_entry.episodes) {
            list_entry.status = .complete;
            list_entry.watched += 1;
        }
    }
}

fn removeAction(list: *List, list_entry: *List.Entry, _: Database.Entry) void {
    const index = (@intFromPtr(list_entry) - @intFromPtr(list.entries.items.ptr)) /
        @sizeOf(List.Entry);
    _ = list.entries.swapRemove(index);
}

fn updateAction(_: *List, list_entry: *List.Entry, database_entry: Database.Entry) void {
    switch (list_entry.status) {
        .complete => list_entry.episodes = database_entry.episodes,
        .dropped, .on_hold, .plan_to_watch, .watching => list_entry.watched = 0,
    }
}

const program_name = "aniz";
const list_name = "list";
const database_json_name = "database.json";
const database_bin_name = "database.bin";

fn download(client: *std.http.Client, uri_str: []const u8, writer: anytype) !void {
    const uri = try std.Uri.parse(uri_str);
    var header_buffer: [1024 * 4]u8 = undefined;
    var request = try client.open(.GET, uri, .{
        .server_header_buffer = &header_buffer,
        .keep_alive = false,
    });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    if (request.response.status != .ok)
        return error.HttpServerRepliedWithUnsuccessfulResponse;

    return pipe(request.reader(), writer);
}

fn pipe(reader: anytype, writer: anytype) !void {
    var buf: [1024 * 4]u8 = undefined;
    while (true) {
        const len = try reader.read(&buf);
        if (len == 0)
            break;

        try writer.writeAll(buf[0..len]);
    }
}

fn loadDatabase(allocator: std.mem.Allocator) !Database {
    var data_dir = try openFolder(.cache, .{});
    defer data_dir.close();

    const file = try data_dir.openFile(database_bin_name, .{});
    defer file.close();

    var res = try Database.deserializeFromBinary(allocator, file.reader());
    errdefer res.deinit(allocator);

    if ((try file.getPos()) != (try file.getEndPos()))
        return error.FileNotFullyRead;

    return res;
}

fn loadList(allocator: std.mem.Allocator) !List {
    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    const data = data_dir.readFileAlloc(
        allocator,
        list_name,
        std.math.maxInt(usize),
    ) catch |err| switch (err) {
        error.FileNotFound => "",
        else => |e| return e,
    };
    defer allocator.free(data);

    return List.deserializeFromTsv(allocator, data);
}

fn saveList(list: List) !void {
    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    var file = try data_dir.atomicFile(list_name, .{});
    defer file.deinit();

    list.sort();

    var buffered_file = std.io.bufferedWriter(file.file.writer());
    try list.serializeToTsv(buffered_file.writer());

    try buffered_file.flush();
    try file.finish();
}

fn openFolder(folder: folders.KnownFolder, flags: std.fs.Dir.OpenDirOptions) !std.fs.Dir {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var dir = (try folders.open(fba.allocator(), folder, flags)) orelse
        return error.NoCacheDir;
    defer dir.close();

    return dir.makeOpenPath(program_name, flags);
}

test {
    _ = ArgParser;
    _ = Database;
    _ = List;
}

const ArgParser = @import("ArgParser.zig");
const Database = @import("Database.zig");
const List = @import("List.zig");

const datetime = @import("datetime");
const folders = @import("folders");
const std = @import("std");
