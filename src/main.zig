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
const process = std.process;

const list_name = "list";
const program_name = "aniz";

pub fn main() !void {
    var gba = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gba.allocator();
    defer _ = gba.deinit();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.next();

    const command_str = args_iter.next() orelse "help";

    for ([_][]const SubCommand{
        &list_modifying_sub_commands,
        &print_csv_sub_commands,
        &other_sub_commands,
    }) |sub_commands| {
        for (sub_commands) |sub_command| {
            if (mem.eql(u8, command_str, sub_command.name)) {
                sub_command.func(sub_command, allocator, &args_iter) catch |err| switch (err) {
                    // BrokenPipe is in most cases expected. It will be triggered just by doing
                    // `aniz database | head -n1`. It is not an error for our program so let's
                    // ignore it and exit cleanly.
                    error.BrokenPipe => {},
                    else => return err,
                };
                return;
            }
        }
    }

    return helpMain(help_sub_command, allocator, &args_iter);
}

const SubCommand = struct {
    name: []const u8,
    func: *const fn (SubCommand, mem.Allocator, *process.ArgIterator) anyerror!void,
    description: []const u8,

    fn help(sub_command: SubCommand, writer: anytype) !void {
        const spaces = " " ** 20;
        try writer.writeAll("    ");
        try writer.writeAll(sub_command.name);
        try writer.writeAll(spaces[sub_command.name.len..]);
        try writer.writeAll(sub_command.description);
        try writer.writeAll("\n");
    }

    fn usageOut(sub_command: SubCommand, p: []const clap.Param(clap.Help)) !void {
        var stdout_buffered = io.bufferedWriter(io.getStdOut().writer());
        try sub_command.usage(stdout_buffered.writer(), p);
        try stdout_buffered.flush();
    }

    fn usageErr(sub_command: SubCommand, p: []const clap.Param(clap.Help)) !void {
        var stderr_buffered = io.bufferedWriter(io.getStdErr().writer());
        try sub_command.usage(stderr_buffered.writer(), p);
        try stderr_buffered.flush();
    }

    fn usage(sub_command: SubCommand, stream: anytype, p: []const clap.Param(clap.Help)) !void {
        try stream.print("Usage: {s} {s} ", .{ program_name, sub_command.name });
        try clap.usage(stream, clap.Help, p);
        try stream.writeAll("\n\n");
        try stream.writeAll(sub_command.description);
        try stream.writeAll(
            \\
            \\
            \\Options:
            \\
        );
        try clap.help(stream, clap.Help, p, .{});
    }
};

const list_modifying_sub_commands = [_]SubCommand{
    .{ .name = "complete", .func = completeMain, .description = "Mark animes as completed." },
    .{ .name = "drop", .func = dropMain, .description = "Mark animes as dropped." },
    .{ .name = "on-hold", .func = onHoldMain, .description = "Mark animes as on hold." },
    .{ .name = "plan-to-watch", .func = planToWatchMain, .description = "Mark animes as plan to watch." },
    .{ .name = "remove", .func = removeMain, .description = "Remove animes from your list." },
    .{ .name = "update", .func = updateMain, .description = "Update animes information in your list." },
    .{ .name = "watch-episode", .func = watchEpisodeMain, .description = "Increase the number of episodes watched on animes by one." },
    .{ .name = "watching", .func = watchingMain, .description = "Mark animes as watching." },
};

const print_csv_sub_commands = [_]SubCommand{
    .{ .name = "database", .func = databaseMain, .description = "Print the entire database as tsv." },
    .{ .name = "list", .func = listMain, .description = "Print your entire anime list as tsv." },
};

const help_sub_command = SubCommand{
    .name = "help",
    .func = helpMain,
    .description = "Print this help message and exit.",
};
const other_sub_commands = [_]SubCommand{help_sub_command};

const clap_parsers = .{
    .anime = clap.parsers.string,
    .str = clap.parsers.string,
};

fn helpMain(
    _: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    _ = allocator;
    _ = args_iter;

    var stdout_buffered = io.bufferedWriter(io.getStdOut().writer());
    const stdout = stdout_buffered.writer();

    try stdout.writeAll("Usage: ");
    try stdout.writeAll(program_name);
    try stdout.writeAll(
        \\ [command] [option]...
        \\
        \\
    );

    try stdout.print("{s} is a program for keeping a local list of anime you have watched. " ++
        "It ships with an anime database embedded in the executable, so it does not require " ++
        "an internet connection to function. You need to update it to get an up to date anime " ++
        "database.\n\n", .{program_name});

    try stdout.print("{s} uses existing site urls as ids for anime. When any help " ++
        "message refers to <anime>, it refers to such a url.\n\n", .{program_name});

    try stdout.writeAll("Current urls supported are:\n");
    inline for (@typeInfo(anime.Id.Site).Enum.fields) |field| {
        try stdout.writeAll("    ");
        try stdout.writeAll(@field(anime.Id.Site, field.name).url());
        try stdout.writeAll("<id>\n");
    }

    try stdout.writeAll("\n");
    try stdout.writeAll("To get started, lets try to add Clannad to our list:\n");
    try stdout.print("    {s} complete 'https://anidb.net/anime/5101'\n\n", .{program_name});

    try stdout.writeAll("We can then see our list with:\n");
    try stdout.print("    {s} list\n\n", .{program_name});

    try stdout.writeAll("You have now started your own list. Have a look at the other sub " ++
        "commands to modify your list in different ways.\n\n");

    try stdout.print(
        "Your list is stored in \"${{XDG_CONFIG_HOME}}/{s}/{s}\".\n",
        .{ program_name, list_name },
    );

    try stdout.writeAll(
        \\
        \\List Manipulation Commands:
        \\
        \\
    );
    for (list_modifying_sub_commands) |sub_command|
        try sub_command.help(stdout);

    try stdout.writeAll(
        \\
        \\
        \\List Printing Commands:
        \\
        \\
    );
    for (print_csv_sub_commands) |sub_command|
        try sub_command.help(stdout);

    try stdout.writeAll(
        \\
        \\
        \\Other Commands:
        \\
        \\
    );
    for (other_sub_commands) |sub_command|
        try sub_command.help(stdout);

    try stdout_buffered.flush();
}

fn completeMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .complete);
}

fn dropMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .drop);
}

fn planToWatchMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .plan_to_watch);
}

fn onHoldMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .on_hold);
}

fn watchingMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .watching);
}

fn watchEpisodeMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .watch_episode);
}

fn removeMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .remove);
}

fn updateMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    return listManipulateMain(sub_command, allocator, args_iter, .update);
}

fn databaseMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help          Print this help message and exit
        \\-s, --search <str>  Only print entries that matches a search
        \\<anime>...
    );

    var diag = clap.Diagnostic{};
    var args = clap.parseEx(clap.Help, &params, clap_parsers, args_iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.args.help != 0)
        return sub_command.usageOut(&params);

    const m_search = args.args.search;

    var entries_to_print = std.ArrayList(usize).init(allocator);
    defer entries_to_print.deinit();
    var scores = std.ArrayList(usize).init(allocator);
    defer scores.deinit();

    const max_to_print = if (args.positionals.len == 0) database.anidb.len else args.positionals.len;
    try entries_to_print.ensureUnusedCapacity(max_to_print);
    if (m_search) |_|
        try scores.ensureUnusedCapacity(max_to_print);

    var stdout_buffered = io.bufferedWriter(io.getStdOut().writer());
    const stdout = stdout_buffered.writer();

    for (args.positionals) |link| {
        const link_id = anime.Id.fromUrl(link) catch continue;
        const i = database.findWithId(link_id) orelse continue;
        if (m_search) |search| {
            const score = infoScoredMatch(search, i);
            if (score == math.maxInt(usize))
                continue;

            scores.appendAssumeCapacity(score);
        }
        entries_to_print.appendAssumeCapacity(i);
    }

    if (args.positionals.len == 0) for (database.anidb, 0..) |_, i| {
        if (m_search) |search| {
            const score = infoScoredMatch(search, i);
            if (score == math.maxInt(usize))
                continue;

            scores.appendAssumeCapacity(score);
        }
        entries_to_print.appendAssumeCapacity(i);
    };

    if (m_search) |_| {
        mem.sortContext(0, entries_to_print.items.len, SortContext{
            .entries = entries_to_print.items,
            .scores = scores.items,
        });
    }

    for (entries_to_print.items) |entry| {
        const info = database.info(entry);
        try info.writeToDsv(stdout);
        try stdout.writeAll("\n");
    }
    try stdout_buffered.flush();
}

fn listMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Print this help message and exit
        \\-s, --search <str>  Only print entries that matches a search
        \\<anime>...
        \\
    );

    var diag = clap.Diagnostic{};
    var args = clap.parseEx(clap.Help, &params, clap_parsers, args_iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.args.help != 0)
        return sub_command.usageOut(&params);

    var list = try loadList(allocator);
    defer list.deinit();

    const m_search = args.args.search;

    var entries_to_print = std.ArrayList(usize).init(allocator);
    defer entries_to_print.deinit();
    var scores = std.ArrayList(usize).init(allocator);
    defer scores.deinit();

    const max_to_print = if (args.positionals.len == 0) database.anidb.len else args.positionals.len;
    try entries_to_print.ensureUnusedCapacity(max_to_print);
    if (m_search) |_|
        try scores.ensureUnusedCapacity(max_to_print);

    var stdout_buffered = io.bufferedWriter(io.getStdOut().writer());
    const stdout = stdout_buffered.writer();

    for (args.positionals) |link| {
        const link_id = anime.Id.fromUrl(link) catch continue;
        const entry_i = list.findIndexWithId(link_id) orelse continue;
        if (m_search) |search| {
            const database_i = database.findWithId(list.entries.items[entry_i].id) orelse continue;
            const score = infoScoredMatch(search, database_i);
            if (score == math.maxInt(usize))
                continue;

            scores.appendAssumeCapacity(score);
        }
        entries_to_print.appendAssumeCapacity(entry_i);
    }

    if (args.positionals.len == 0) for (list.entries.items, 0..) |entry, entry_i| {
        if (m_search) |search| {
            const database_i = database.findWithId(entry.id) orelse continue;
            const score = infoScoredMatch(search, database_i);
            if (score == math.maxInt(usize))
                continue;

            scores.appendAssumeCapacity(score);
        }
        entries_to_print.appendAssumeCapacity(entry_i);
    };

    if (m_search) |_| {
        mem.sortContext(0, entries_to_print.items.len, SortContext{
            .entries = entries_to_print.items,
            .scores = scores.items,
        });
    }

    for (entries_to_print.items) |entry_i| {
        const entry = list.entries.items[entry_i];
        try entry.writeToDsv(stdout);
        try stdout.writeAll("\n");
    }
    try stdout_buffered.flush();
}

const SortContext = struct {
    entries: []usize,
    scores: []usize,

    pub fn swap(ctx: SortContext, a_index: usize, b_index: usize) void {
        mem.swap(usize, &ctx.entries[a_index], &ctx.entries[b_index]);
        mem.swap(usize, &ctx.scores[a_index], &ctx.scores[b_index]);
    }

    pub fn lessThan(ctx: SortContext, a_index: usize, b_index: usize) bool {
        return ctx.scores[a_index] < ctx.scores[b_index];
    }
};

const Action = enum {
    complete,
    drop,
    on_hold,
    plan_to_watch,
    remove,
    update,
    watch_episode,
    watching,
};

fn listManipulateMain(
    sub_command: SubCommand,
    allocator: mem.Allocator,
    args_iter: *std.process.ArgIterator,
    action: Action,
) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Print this help message and exit
        \\<anime>...
        \\
    );

    var diag = clap.Diagnostic{};
    var args = clap.parseEx(clap.Help, &params, clap_parsers, args_iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.args.help != 0)
        return sub_command.usageOut(&params);

    var list = try loadList(allocator);
    defer list.deinit();

    for (args.positionals) |anime_link|
        try manipulateList(allocator, &list, anime_link, action);

    try saveList(list);
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

    const database_entry = database.info(i);
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
        .drop => {
            entry.date = datetime.Date.now();
            entry.status = .dropped;
        },
        .on_hold => {
            entry.date = datetime.Date.now();
            entry.status = .on_hold;
        },
        .plan_to_watch => {
            entry.date = datetime.Date.now();
            entry.status = .plan_to_watch;
        },
        .watching => {
            entry.date = datetime.Date.now();
            entry.status = .watching;
        },
        .watch_episode => if (entry.episodes < database_entry.episodes) {
            entry.date = datetime.Date.now();
            entry.episodes += 1;
            entry.status = .watching;
            if (entry.episodes == database_entry.episodes) {
                entry.status = .complete;
                entry.watched += 1;
            }
        },
        .remove => {
            const index = (@intFromPtr(entry) - @intFromPtr(list.entries.items.ptr)) /
                @sizeOf(anime.Entry);
            _ = list.entries.swapRemove(index);
        },
        .update => switch (entry.status) {
            .complete => entry.episodes = database_entry.episodes,
            .dropped, .on_hold, .plan_to_watch, .watching => entry.watched = 0,
        },
    }
}

fn loadList(allocator: mem.Allocator) !anime.List {
    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    const data = data_dir.readFileAlloc(
        allocator,
        list_name,
        math.maxInt(usize),
    ) catch |err| switch (err) {
        error.FileNotFound => "",
        else => |e| return e,
    };
    defer allocator.free(data);

    return try anime.List.fromDsv(allocator, data);
}

fn saveList(list: anime.List) !void {
    var data_dir = try openFolder(.data, .{});
    defer data_dir.close();

    var file = try data_dir.atomicFile(list_name, .{});
    defer file.deinit();

    var buffered_file = io.bufferedWriter(file.file.writer());
    const writer = buffered_file.writer();
    try list.writeToDsv(writer);
    try buffered_file.flush();
    try file.finish();
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

fn infoScoredMatch(pattern: []const u8, info_index: usize) usize {
    var score = scoredMatch(pattern, database.title[info_index].toStringZ());
    for (database.synonyms(info_index)) |synonym|
        score = @min(score, scoredMatch(pattern, synonym.toStringZ()));

    return score;
}

// Lower score is better
fn scoredMatch(pattern: []const u8, str: [*:0]const u8) usize {
    var score: usize = 0;
    var last_match: usize = 0;
    var i: usize = 0;
    for (pattern) |c| {
        while (str[i] != 0) {
            defer i += 1;

            if (std.ascii.toLower(c) != std.ascii.toLower(str[i]))
                continue;

            score += @intFromBool(c != str[i]);
            score += i -| (last_match + 1);
            last_match = i;
            break;
        } else return math.maxInt(usize);
    }

    // Find length by going to end of string
    while (str[i] != 0) : (i += 1) {}

    const len = i;
    score += ((len - pattern.len) * 2) * @intFromBool(pattern.len != 0);
    return score;
}

test "match" {
    try std.testing.expectEqual(@as(usize, math.maxInt(usize)), scoredMatch("abc", "ab"));
    try std.testing.expectEqual(@as(usize, 0), scoredMatch("", "abc"));
    try std.testing.expectEqual(@as(usize, 0), scoredMatch("abc", "abc"));
    try std.testing.expectEqual(@as(usize, 1), scoredMatch("abc", "Abc"));
    try std.testing.expectEqual(@as(usize, 2), scoredMatch("abc", "ABc"));
    try std.testing.expectEqual(@as(usize, 3), scoredMatch("abc", "ABC"));
    try std.testing.expectEqual(@as(usize, 3), scoredMatch("abc", "abdc"));
    try std.testing.expectEqual(@as(usize, 0), scoredMatch("attack on titan", "attack on titan"));
    try std.testing.expectEqual(@as(usize, 3), scoredMatch("attack on titan", "Attack On Titan"));
    try std.testing.expectEqual(@as(usize, 0), scoredMatch("Clannad", "Clannad"));
    try std.testing.expectEqual(@as(usize, 125), scoredMatch("Clannad", "BJ Special: Hyakumannen Chikyuu no Tabi Bander Book"));
}
