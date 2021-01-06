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

const database_url = "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json";
const database_name = "database";
const image_cache_name = "images";
const list_name = "list";
const program_name = "anilist";

// TODO: One of these days, we will have a good networking library
//       and a proper event loop in std. When that happens I'll look
//       into downloading/writing things in parallel.

const params = comptime blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help           Print this message to stdout") catch unreachable,
        clap.parseParam("-t, --token <TOKEN>  The discord token.") catch unreachable,
    };
};

fn usage(stream: anytype, command: Command, p: []const clap.Param(clap.Help)) !void {
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
};

pub fn main() !void {
    var gba = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gba.allocator;
    defer _ = gba.deinit();

    var args_iter = try clap.args.OsIterator.init(allocator);
    defer args_iter.deinit();

    const command_str = (try args_iter.next()) orelse "help";
    const command = std.meta.stringToEnum(Command, command_str) orelse .help;

    switch (command) {
        .complete => try listManipulateMain(allocator, &args_iter, .complete),
        .database => try databaseMain(allocator),
        .drop => try listManipulateMain(allocator, &args_iter, .dropped),
        .fetch => try fetchMain(allocator, &args_iter),
        .help, .@"--help" => try helpMain(allocator, &args_iter),
        .list => try listMain(allocator),
        .plan_to_watch => try listManipulateMain(allocator, &args_iter, .plan_to_watch),
        .put_on_hold => try listManipulateMain(allocator, &args_iter, .on_hold),
        .remove => try listManipulateMain(allocator, &args_iter, .remove),
        .start_watching => try listManipulateMain(allocator, &args_iter, .watching),
        .update => try listManipulateMain(allocator, &args_iter, .update),
    }
}

fn helpMain(allocator: *mem.Allocator, args_iter: *clap.args.OsIterator) !void {
    unreachable; // TODO
}

fn fetchMain(allocator: *mem.Allocator, args_iter: *clap.args.OsIterator) !void {
    var dir = try openFolder(.cache, .{});
    defer dir.close();

    const database_json = try curlAlloc(allocator, database_url);
    defer allocator.free(database_json);

    // Validate the json
    const database = try anime.Info.fromJsonList(
        &json.TokenStream.init(database_json),
        allocator,
    );
    defer allocator.free(database);

    var database_writing_job = async writeDatabaseFile(dir, database);
    var update_image_cache_job = async updateImageCache(allocator, dir, database);

    try await database_writing_job;
    try await update_image_cache_job;
}

fn listMain(allocator: *mem.Allocator) !void {
    var cache_dir = try openFolder(.cache, .{});
    defer cache_dir.close();

    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const image_dir_path = try cache_dir.realpath(image_cache_name, &buf);

    var list = blk: {
        const data = try data_dir.readFileAlloc(allocator, list_name, math.maxInt(usize));
        defer allocator.free(data);

        break :blk try anime.List.fromDsv(allocator, data);
    };
    defer list.deinit(allocator);

    const stdout = io.bufferedOutStream(io.getStdOut().writer()).writer();
    for (list.entries.items) |entry| {
        try entry.writeToDsv(stdout);
        try stdout.print("\t{s}/{s}\n", .{
            image_dir_path,
            bufToBase64(hash(&entry.link)),
        });
    }
    try stdout.context.flush();
}

fn databaseMain(allocator: *mem.Allocator) !void {
    var dir = try openFolder(.cache, .{});
    defer dir.close();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const image_dir_path = try dir.realpath(image_cache_name, &buf);

    const database_data = try dir.readFileAlloc(allocator, database_name, math.maxInt(usize));
    defer allocator.free(database_data);

    const stdout = io.bufferedOutStream(io.getStdOut().writer()).writer();
    for (mem.bytesAsSlice(anime.Info, database_data)) |info| {
        try stdout.print("{s}\t{}\t{s}\t{}\t{s}\t{s}\t{s}/{s}\n", .{
            @tagName(info.type),
            info.year,
            @tagName(info.season),
            info.episodes,
            mem.spanZ(&info.title),
            mem.spanZ(&info.links[0]),
            image_dir_path,
            bufToBase64(hash(&info.links[0])),
        });
    }
    try stdout.context.flush();
}

const Action = enum {
    complete,
    dropped,
    on_hold,
    plan_to_watch,
    remove,
    update,
    watching,
};

fn listManipulateMain(
    allocator: *mem.Allocator,
    args_iter: *clap.args.OsIterator,
    action: Action,
) !void {
    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    var list = blk: {
        const data = try data_dir.readFileAlloc(allocator, list_name, math.maxInt(usize));
        defer allocator.free(data);

        break :blk try anime.List.fromDsv(allocator, data);
    };
    defer list.deinit(allocator);

    const database = blk: {
        var cache_dir = try openFolder(.cache, .{});
        defer cache_dir.close();

        const database = try cache_dir.readFileAlloc(allocator, database_name, math.maxInt(usize));
        errdefer allocator.free(database);

        break :blk mem.bytesAsSlice(anime.Info, database);
    };
    defer allocator.free(database);

    while (try args_iter.next()) |anime_link|
        try manipulateList(allocator, &list, database, anime_link, action);

    var file = try data_dir.atomicFile(list_name, .{});
    defer file.deinit();

    const writer = io.bufferedWriter(file.file.writer()).writer();
    try list.writeToDsv(writer);
    try writer.context.flush();
    try file.finish();
}

fn manipulateList(
    allocator: *mem.Allocator,
    list: *anime.List,
    database: []const anime.Info,
    link: []const u8,
    action: Action,
) !void {
    const database_entry = outer: for (database) |entry| {
        for (entry.links) |entry_link| {
            if (mem.eql(u8, mem.spanZ(&entry_link), link))
                break :outer entry;
        }
    } else {
        std.log.err("Anime '{}' was not found in the database", .{link});
        return error.NoSuchAnime;
    };

    const entry = list.findWithLink(link) orelse blk: {
        const entry = try list.entries.addOne(allocator);
        entry.* = .{
            .date = datetime.Date.now(),
            .status = .plan_to_watch,
            .episodes = 0,
            .watched = 0,
            .title = undefined,
            .link = undefined,
        };
        break :blk entry;
    };

    // Always update the entry to have newest link id and title.
    entry.link = database_entry.links[0];
    entry.title = database_entry.title;

    switch (action) {
        .complete => {
            if (entry.status != .complete)
                entry.date = datetime.Date.now();

            entry.status = .complete;
            entry.watched += 1;
            entry.episodes = database_entry.episodes;
        },
        .dropped => entry.status = .dropped,
        .on_hold => entry.status = .on_hold,
        .plan_to_watch => entry.status = .plan_to_watch,
        .watching => entry.status = .watching,
        .remove => {
            const index = (@ptrToInt(entry) - @ptrToInt(list.entries.items.ptr)) /
                @sizeOf(anime.Entry);
            _ = list.entries.swapRemove(index);
        },
        .update => {},
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
    var dir = (try folders.open(&fba.allocator, folder, flags)) orelse
        return error.NoCacheDir;
    defer dir.close();

    return makeAndOpenDir(dir, program_name);
}

fn updateImageCache(allocator: *mem.Allocator, dir: fs.Dir, database: []const anime.Info) !void {
    var image_dir = try makeAndOpenDir(dir, image_cache_name);
    defer image_dir.close();

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var progress = std.Progress{};
    const root_node = try progress.start("", database.len);
    defer root_node.end();

    // TODO: Have a channel, and push links into that channel. Have N
    //       jobs that pulls download tasks from the channel and downloads
    //       in parallel.
    for (database) |entry| {
        const image_name = bufToBase64(hash(&entry.image));
        if (image_dir.createFile(&image_name, .{ .exclusive = true })) |file| {
            errdefer image_dir.deleteFile(&image_name) catch {};
            defer file.close();

            // File didn't exist. Download it!
            result.resize(0) catch unreachable;
            try curl(result.writer(), mem.spanZ(&entry.image));

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

        const link_name = bufToBase64(hash(&entry.links[0]));
        image_dir.deleteFile(&link_name) catch {};
        image_dir.symLink(&image_name, &link_name, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |new_err| return new_err,
        };
        root_node.completeOne();
    }
}

fn hash(src: []const u8) [24]u8 {
    var out: [24]u8 = undefined;
    std.crypto.hash.Blake3.hash(src, &out, .{});
    return out;
}

fn bufToBase64(buf: anytype) [base64.Base64Encoder.calcSize(buf.len)]u8 {
    var res: [base64.Base64Encoder.calcSize(buf.len)]u8 = undefined;
    fs.base64_encoder.encode(&res, &buf);
    return res;
}

fn makeAndOpenDir(dir: fs.Dir, sub_path: []const u8) !fs.Dir {
    dir.makeDir(sub_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |new_err| return new_err,
    };
    return dir.openDir(sub_path, .{});
}

fn writeDatabaseFile(dir: fs.Dir, database: []const anime.Info) !void {
    var file = try dir.atomicFile(database_name, .{});
    defer file.deinit();

    try file.file.writeAll(mem.sliceAsBytes(database));
    try file.finish();
}

fn curlAlloc(allocator: *mem.Allocator, link: []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try curl(list.writer(), link);
    return list.toOwnedSlice();
}

fn curl(writer: anytype, link: []const u8) !void {
    var alloc_buf: [std.mem.page_size * 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&alloc_buf);
    const proc = try std.ChildProcess.init(&[_][]const u8{ "curl", "-s", link }, &fba.allocator);
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
