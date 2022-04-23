const anime = @import("anime");
const clap = @import("clap");
const database = @import("database");
const datetime = @import("datetime");
const folders = @import("known_folders");
const std = @import("std");

const fs = std.fs;
const heap = std.heap;
const io = std.io;
const json = std.json;
const math = std.math;
const mem = std.mem;
const meta = std.meta;

const list_name = "list";
const program_name = "anilist";

const Command = enum {
    @"--help",
    complete,
    database,
    drop,
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

        .database => try databaseMain(&args_iter),
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

fn listMain(allocator: mem.Allocator) !u8 {
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
    defer list.deinit();

    const stdout = io.bufferedWriter(io.getStdOut().writer()).writer();
    for (list.entries.items) |entry| {
        try entry.writeToDsv(stdout);
        try stdout.writeAll("\n");
    }
    try stdout.context.flush();
    return 0;
}

fn databaseMain(args_iter: *std.process.ArgIterator) !u8 {
    const stdout = io.bufferedWriter(io.getStdOut().writer()).writer();

    var have_searched = false;
    while (args_iter.next()) |link| : (have_searched = true) {
        const link_id = anime.Id.fromUrl(link) catch continue;
        const i = database.findWithId(link_id) orelse continue;
        const info = database.get(i);
        info.writeToDsv(stdout) catch |err| switch (err) {
            error.InfoHasNoId => continue,
            else => |e| return e,
        };
        try stdout.writeAll("\n");
    }

    if (!have_searched) for (database.kind) |_, i| {
        const info = database.get(i);
        info.writeToDsv(stdout) catch |err| switch (err) {
            error.InfoHasNoId => continue,
            else => |e| return e,
        };
        try stdout.writeAll("\n");
    };

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
    defer list.deinit();

    while (args_iter.next()) |anime_link|
        try manipulateList(allocator, &list, anime_link, action);

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
    link: []const u8,
    action: Action,
) !void {
    const link_id = try anime.Id.fromUrl(link);
    const i = database.findWithId(link_id) orelse {
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
    entry.id = database_entry.id().?;
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

fn openFolder(folder: folders.KnownFolder, flags: fs.Dir.OpenDirOptions) !fs.Dir {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    var dir = (try folders.open(fba.allocator(), folder, flags)) orelse
        return error.NoCacheDir;
    defer dir.close();

    return makeAndOpenDir(dir, program_name);
}

fn makeAndOpenDir(dir: fs.Dir, sub_path: []const u8) !fs.Dir {
    dir.makeDir(sub_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |new_err| return new_err,
    };
    return dir.openDir(sub_path, .{});
}

fn usageCommand(stream: anytype, command: Command, p: []const clap.Param(clap.Help)) !void {
    try stream.print("Usage: {s} {s} ", .{ program_name, @tagName(command) });
    try clap.usage(stream, p);
    try stream.writeAll(
        \\
        \\Help message here
        \\
        \\Options:
        \\
    );
    try clap.help(stream, p);
}
