const clap = @import("clap");
const datetime = @import("datetime");
const folders = @import("known_folders");
const std = @import("std");

const anime = @import("anime.zig");

const base64 = std.base64;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const json = std.json;
const math = std.math;
const mem = std.mem;
const meta = std.meta;

const database_name = "database";
const database_url = "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json";
const image_cache_name = "images";
const list_name = "list";
const program_name = "anilist";

// TODO: One of these days, we will have a good networking library
//       and a proper event loop in std. When that happens I'll look
//       into downloading/writing things in parallel.

const params = [_]clap.Param(clap.Help){
    clap.parseParam("-h, --help           Print this message to stdout") catch unreachable,
    clap.parseParam("-t, --token <TOKEN>  The discord token.") catch unreachable,
};

fn usage(stream: anytype, command: Command, p: []const clap.Param(clap.Help)) !void {
    _ = command;

    try stream.writeAll("Usage: ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Help message here
        \\
        \\Options:
        \\
    );
    try clap.help(stream, p);
}

const Command = enum {
    @"--help",
    complete,
    database,
    drop,
    fetch,
    help,
    list,
    plan_to_watch,
    put_on_hold,
    remove,
    start_watching,
    update,
    watch_episode,
};

pub fn main() !u8 {
    var gba = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gba.allocator();
    defer _ = gba.deinit();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.next();

    const command_str = args_iter.next() orelse "help";
    const command = std.meta.stringToEnum(Command, command_str) orelse .help;

    return switch (command) {
        .help, .@"--help" => try helpMain(allocator, &args_iter),

        .database => try databaseMain(allocator),
        .fetch => try fetchMain(allocator, &args_iter),
        .list => try listMain(allocator),

        .complete => try listManipulateMain(allocator, &args_iter, .complete),
        .drop => try listManipulateMain(allocator, &args_iter, .dropped),
        .plan_to_watch => try listManipulateMain(allocator, &args_iter, .plan_to_watch),
        .put_on_hold => try listManipulateMain(allocator, &args_iter, .on_hold),
        .remove => try listManipulateMain(allocator, &args_iter, .remove),
        .start_watching => try listManipulateMain(allocator, &args_iter, .watching),
        .update => try listManipulateMain(allocator, &args_iter, .update),
        .watch_episode => try listManipulateMain(allocator, &args_iter, .watch_episode),
    };
}

fn helpMain(allocator: mem.Allocator, args_iter: *std.process.ArgIterator) !u8 {
    _ = allocator;
    _ = args_iter;

    // TODO
    return 0;
}

fn fetchMain(allocator: mem.Allocator, args_iter: *std.process.ArgIterator) !u8 {
    _ = args_iter;

    var dir = try openFolder(.cache, .{});
    defer dir.close();

    const database_json = try curlAlloc(allocator, database_url);
    defer allocator.free(database_json);

    // Validate the json
    var database = try anime.Info.fromJsonList(
        &json.TokenStream.init(database_json),
        allocator,
    );
    defer database.deinit(allocator);

    var database_writing_job = async writeDatabaseFile(dir, database);
    var update_image_cache_job = async updateImageCache(allocator, dir, &database);

    try await database_writing_job;
    try await update_image_cache_job;
    return 0;
}

fn listMain(allocator: mem.Allocator) !u8 {
    var cache_dir = try openFolder(.cache, .{});
    defer cache_dir.close();

    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const image_dir_path = try cache_dir.realpath(image_cache_name, &buf);

    var list = blk: {
        const data = data_dir.readFileAlloc(
            allocator,
            list_name,
            math.maxInt(usize),
        ) catch |err| switch (err) {
            error.FileNotFound => "",
            else => |e| return e,
        };
        defer allocator.free(data);

        break :blk try anime.List.fromDsv(allocator, data);
    };
    defer list.deinit(allocator);

    const stdout = io.bufferedWriter(io.getStdOut().writer()).writer();
    for (list.entries.items) |entry| {
        try entry.writeToDsv(stdout);
        try stdout.print("\t{s}/{s}\n", .{
            image_dir_path,
            bufToBase64(hash(entry.id)),
        });
    }
    try stdout.context.flush();
    return 0;
}

fn databaseMain(allocator: mem.Allocator) !u8 {
    var dir = try openFolder(.cache, .{});
    defer dir.close();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const image_dir_path = try dir.realpath(image_cache_name, &buf);

    var database = readDatabaseFile(dir, allocator) catch |err| {
        std.log.err("Could not read database file: {s}", .{@errorName(err)});
        std.log.err("Try running 'anilist fetch' to download a new database", .{});
        return 1;
    };
    defer database.deinit(allocator);

    const stdout = io.bufferedWriter(io.getStdOut().writer()).writer();
    for (database.items(.type)) |_, i| {
        const info = database.get(i);
        const id = info.id();
        try stdout.print("{s}\t{}\t{s}\t{}\t{s}\t{s}{d}\t{s}/{s}\n", .{
            @tagName(info.type),
            info.year,
            @tagName(info.season),
            info.episodes,
            mem.sliceTo(&info.title, 0),
            id.site.url(),
            id.id,
            image_dir_path,
            bufToBase64(hash(id)),
        });
    }
    try stdout.context.flush();
    return 0;
}

const Action = enum {
    complete,
    dropped,
    on_hold,
    plan_to_watch,
    remove,
    update,
    watch_episode,
    watching,
};

fn listManipulateMain(
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
    action: Action,
) !u8 {
    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    var list = blk: {
        const data = data_dir.readFileAlloc(
            allocator,
            list_name,
            math.maxInt(usize),
        ) catch |err| switch (err) {
            error.FileNotFound => "",
            else => |e| return e,
        };
        defer allocator.free(data);

        break :blk try anime.List.fromDsv(allocator, data);
    };
    defer list.deinit(allocator);

    var database = blk: {
        var cache_dir = try openFolder(.cache, .{});
        defer cache_dir.close();

        break :blk try readDatabaseFile(cache_dir, allocator);
    };
    defer database.deinit(allocator);

    while (args_iter.next()) |anime_link|
        try manipulateList(allocator, &list, &database, anime_link, action);

    var file = try data_dir.atomicFile(list_name, .{});
    defer file.deinit();

    const writer = io.bufferedWriter(file.file.writer()).writer();
    try list.writeToDsv(writer);
    try writer.context.flush();
    try file.finish();
    return 0;
}

fn manipulateList(
    allocator: mem.Allocator,
    list: *anime.List,
    database: *std.MultiArrayList(anime.Info),
    link: []const u8,
    action: Action,
) !void {
    const link_id = try anime.Id.fromUrl(link);
    const slice_to_search = switch (link_id.site) {
        .anidb => database.items(.anidb),
        .anilist => database.items(.anilist),
        .anisearch => database.items(.anisearch),
        .kitsu => database.items(.kitsu),
        .livechart => database.items(.livechart),
        .myanimelist => database.items(.myanimelist),
    };
    const i = for (slice_to_search) |id, i| {
        if (link_id.id == id)
            break i;
    } else {
        std.log.err("Anime '{s}' was not found in the database", .{link});
        return error.NoSuchAnime;
    };

    const database_entry = database.get(i);
    const entry = list.findWithId(link_id) orelse blk: {
        const entry = try list.entries.addOne(allocator);
        entry.* = .{
            .date = datetime.Date.now(),
            .status = .watching,
            .episodes = 0,
            .watched = 0,
            .title = undefined,
            .id = undefined,
        };
        break :blk entry;
    };

    // Always update the entry to have newest link id and title.
    entry.id = database_entry.id();
    entry.title = database_entry.title;

    switch (action) {
        .complete => {
            entry.date = datetime.Date.now();
            entry.status = .complete;
            entry.watched += 1;
            entry.episodes = database_entry.episodes;
        },
        .dropped => {
            entry.date = datetime.Date.now();
            entry.watched = 0;
            entry.status = .dropped;
        },
        .on_hold => {
            entry.date = datetime.Date.now();
            entry.watched = 0;
            entry.status = .on_hold;
        },
        .plan_to_watch => {
            entry.date = datetime.Date.now();
            entry.watched = 0;
            entry.status = .plan_to_watch;
        },
        .watching => {
            entry.date = datetime.Date.now();
            entry.watched = 0;
            entry.status = .watching;
        },
        .watch_episode => {
            entry.date = datetime.Date.now();
            entry.episodes = math.min(
                database_entry.episodes,
                entry.episodes + 1,
            );
        },
        .remove => {
            const index = (@ptrToInt(entry) - @ptrToInt(list.entries.items.ptr)) /
                @sizeOf(anime.Entry);
            _ = list.entries.swapRemove(index);
        },
        .update => switch (entry.status) {
            .complete => entry.episodes = database_entry.episodes,
            .dropped, .on_hold, .plan_to_watch, .watching => entry.watched = 0,
        },
    }
}

// TODO: Replace with LiniarFifo.pump or fs.sendFile when these
//       apies exists.
fn cat(reader: anytype, writer: anytype) !void {
    var buf: [mem.page_size]u8 = undefined;
    while (true) {
        const read_len = try reader.read(&buf);
        if (read_len == 0)
            break;

        try writer.writeAll(buf[0..read_len]);
    }
}

fn openFolder(folder: folders.KnownFolder, flags: fs.Dir.OpenDirOptions) !fs.Dir {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    var dir = (try folders.open(fba.allocator(), folder, flags)) orelse
        return error.NoCacheDir;
    defer dir.close();

    return makeAndOpenDir(dir, program_name);
}

fn updateImageCache(allocator: mem.Allocator, dir: fs.Dir, database: *std.MultiArrayList(anime.Info)) !void {
    var image_dir = try makeAndOpenDir(dir, image_cache_name);
    defer image_dir.close();

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var progress = std.Progress{};
    const root_node = progress.start("", database.len);
    defer root_node.end();

    // TODO: Have a channel, and push links into that channel. Have N
    //       jobs that pulls download tasks from the channel and downloads
    //       in parallel.
    for (database.items(.image)) |*image, i| {
        const image_name = bufToBase64(hash(image));
        if (image_dir.createFile(&image_name, .{ .exclusive = true })) |file| {
            errdefer image_dir.deleteFile(&image_name) catch {};
            defer file.close();

            // File didn't exist. Download it!
            result.resize(0) catch unreachable;
            try curl(result.writer(), mem.sliceTo(image, 0));

            // Some images might have moved. In that case the html will specify
            // the new position.
            const url_start = "<p>The document has moved <a href=\"";
            while (mem.indexOf(u8, result.items, url_start)) |url_start_index| {
                const start = url_start_index + url_start.len;
                const end = mem.indexOfPos(u8, result.items, start, "\"") orelse break;
                const link = try allocator.dupe(u8, result.items[start..end]);
                defer allocator.free(link);

                result.resize(0) catch unreachable;
                try curl(result.writer(), link);
            }

            try file.writeAll(result.items);
        } else |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |new_err| return new_err,
        }

        const id = database.get(i).id();
        const link_name = bufToBase64(hash(id));
        image_dir.deleteFile(&link_name) catch {};
        image_dir.symLink(&image_name, &link_name, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |new_err| return new_err,
        };
        root_node.completeOne();
    }
}

fn hash(things: anytype) [24]u8 {
    var out: [24]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    std.hash.autoHashStrat(&hasher, things, .DeepRecursive);
    hasher.final(&out);
    return out;
}

fn bufToBase64(buf: anytype) [fs.base64_encoder.calcSize(buf.len)]u8 {
    var res: [fs.base64_encoder.calcSize(buf.len)]u8 = undefined;
    _ = fs.base64_encoder.encode(&res, &buf);
    return res;
}

fn makeAndOpenDir(dir: fs.Dir, sub_path: []const u8) !fs.Dir {
    dir.makeDir(sub_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |new_err| return new_err,
    };
    return dir.openDir(sub_path, .{});
}

fn writeDatabaseFile(dir: fs.Dir, database: std.MultiArrayList(anime.Info)) !void {
    var file = try dir.atomicFile(database_name, .{});
    defer file.deinit();

    const Enum = meta.FieldEnum(anime.Info);
    inline for (@typeInfo(anime.Info).Struct.fields) |field| {
        const field_enum = comptime meta.stringToEnum(Enum, field.name).?;
        try file.file.writeAll(mem.sliceAsBytes(database.items(field_enum)));
    }
    try file.finish();
}

fn readDatabaseFile(dir: fs.Dir, allocator: mem.Allocator) !std.MultiArrayList(anime.Info) {
    const info_size = comptime blk: {
        var res: usize = 0;
        for (@typeInfo(anime.Info).Struct.fields) |field|
            res += @sizeOf(field.field_type);
        break :blk res;
    };

    var res = std.MultiArrayList(anime.Info){};
    errdefer res.deinit(allocator);
    const file = try dir.openFile(database_name, .{});
    defer file.close();

    const stat = try file.stat();
    const count = @intCast(usize, stat.size / info_size);
    try res.resize(allocator, count);

    @setEvalBranchQuota(10000);
    const Enum = meta.FieldEnum(anime.Info);
    inline for (@typeInfo(anime.Info).Struct.fields) |field| {
        const field_enum = comptime meta.stringToEnum(Enum, field.name).?;
        try file.reader().readNoEof(mem.sliceAsBytes(res.items(field_enum)));
    }

    return res;
}

fn curlAlloc(allocator: mem.Allocator, link: []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try curl(list.writer(), link);
    return list.toOwnedSlice();
}

fn curl(writer: anytype, link: []const u8) !void {
    var alloc_buf: [std.mem.page_size * 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    const proc = try std.ChildProcess.init(&[_][]const u8{ "curl", "-s", link }, fba.allocator());
    proc.stdin_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    proc.stdout_behavior = .Pipe;

    try proc.spawn();
    errdefer _ = proc.kill() catch undefined;

    try cat(proc.stdout.?.reader(), writer);
    switch (try proc.wait()) {
        .Exited => |status| if (status != 0) return error.CurlFailed,
        else => return error.CurlFailed,
    }
}
