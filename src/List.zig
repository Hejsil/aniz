//! The list of animes the user is tracking. Stored in a TSV file.

intern: StringIntern,
entries: std.ArrayListUnmanaged(Entry),

pub fn init(allocator: std.mem.Allocator) !List {
    return .{
        .intern = try StringIntern.init(allocator),
        .entries = .{},
    };
}

pub fn deinit(list: *List, allocator: std.mem.Allocator) void {
    list.intern.deinit(allocator);
    list.entries.deinit(allocator);
}

pub fn deserializeFromTsv(allocator: std.mem.Allocator, csv: []const u8) !List {
    var list = try List.init(allocator);
    errdefer list.deinit(allocator);

    var lines = std.mem.tokenizeScalar(u8, csv, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        const date_str = fields.first();
        const status_str = fields.next() orelse return error.Invalid;
        const episodes_str = fields.next() orelse return error.Invalid;
        const watched_str = fields.next() orelse return error.Invalid;
        const title = fields.next() orelse return error.Invalid;
        const id_str = fields.next() orelse return error.Invalid;
        if (fields.next() != null)
            return error.Invalid;

        try list.entries.append(allocator, .{
            .date = try datetime.datetime.Date.parseIso(date_str),
            .status = Entry.Status.fromString(status_str) orelse return error.Invalid,
            .episodes = try std.fmt.parseUnsigned(u16, episodes_str, 0),
            .watched = try std.fmt.parseUnsigned(u16, watched_str, 0),
            .title = try list.intern.put(allocator, title),
            .id = try Id.fromUrl(id_str),
        });
    }

    return list;
}

pub fn serializeToTsv(list: List, writer: anytype) !void {
    for (list.entries.items) |entry| {
        try entry.serializeToTsv(list.intern.sliceZ(), writer);
        try writer.writeAll("\n");
    }
}

pub fn addEntry(list: *List, allocator: std.mem.Allocator, id: Id, title: []const u8) !*Entry {
    const entry = list.find(id) orelse blk: {
        const entry = try list.entries.addOne(allocator);
        entry.* = .{
            .date = datetime.datetime.Date.now(),
            .status = .watching,
            .episodes = 0,
            .watched = 0,
            .title = .empty,
            .id = id,
        };
        break :blk entry;
    };

    // Always update the entry to have newest link id and title.
    entry.id = id;
    entry.title = try list.intern.put(allocator, title);

    return entry;
}

pub fn find(list: List, id: Id) ?*Entry {
    for (list.entries.items) |*entry| {
        if (entry.id.id == id.id and entry.id.site == id.site)
            return entry;
    }

    return null;
}

pub fn sort(list: List) void {
    std.mem.sort(Entry, list.entries.items, list.intern.sliceZ(), struct {
        fn lessThan(strings: [:0]const u8, a: Entry, b: Entry) bool {
            // Sort from biggest datetime to smallest. Most people would expect that the
            // newest entry they've seen is then one that ends up at the top of their list
            return b.lessThan(a, strings);
        }
    }.lessThan);
}

fn testTransform(input: []const u8, expected_output: []const u8) !void {
    var list = try deserializeFromTsv(std.testing.allocator, input);
    defer list.deinit(std.testing.allocator);

    var actual_output = std.ArrayList(u8).init(std.testing.allocator);
    defer actual_output.deinit();
    try list.serializeToTsv(actual_output.writer());

    try std.testing.expectEqualStrings(expected_output, actual_output.items);
}

fn testCanonical(input: []const u8) !void {
    return testTransform(input, input);
}

test "tsv" {
    try testCanonical(
        "2000-10-10\tw\t12\t10\tMahou Shoujo Madoka★Magica\thttps://anidb.net/anime/8069\n",
    );
}

test {
    _ = Entry;
    _ = Database;
    _ = StringIntern;
}

const List = @This();

const Id = Database.Id;

pub const Entry = @import("list/Entry.zig");

const Database = @import("Database.zig");
const StringIntern = @import("StringIntern.zig");

const datetime = @import("datetime");
const std = @import("std");
