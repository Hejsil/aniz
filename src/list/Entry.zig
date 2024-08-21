date: datetime.datetime.Date,
status: Status,
episodes: u16,
watched: u16,
title: StringIntern.Index,
id: Id,

pub const Status = enum(u3) {
    complete,
    dropped,
    on_hold,
    plan_to_watch,
    watching,

    pub fn fromString(str: []const u8) ?Status {
        const map = comptime std.StaticStringMap(Status).initComptime(.{
            .{ "c", .complete },
            .{ "d", .dropped },
            .{ "o", .on_hold },
            .{ "p", .plan_to_watch },
            .{ "w", .watching },
        });
        return map.get(str);
    }

    pub fn toString(s: Status) []const u8 {
        return switch (s) {
            .complete => "c",
            .dropped => "d",
            .on_hold => "o",
            .plan_to_watch => "p",
            .watching => "w",
        };
    }
};

pub fn lessThan(a: Entry, b: Entry, strings: [:0]const u8) bool {
    switch (a.date.cmp(b.date)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.math.order(@intFromEnum(a.status), @intFromEnum(b.status))) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.math.order(a.episodes, b.episodes)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.math.order(a.watched, b.watched)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.mem.order(u8, a.title.slice(strings), b.title.slice(strings))) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.math.order(@intFromEnum(a.id.site), @intFromEnum(b.id.site))) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.math.order(a.id.id, b.id.id)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return false;
}

pub fn serializeToTsv(entry: Entry, strings: [:0]const u8, writer: anytype) !void {
    try writer.print("{d:4>2}-{d:0>2}-{d:0>2}\t{s}\t{}\t{}\t{s}\t{s}{d}", .{
        entry.date.year,
        entry.date.month,
        entry.date.day,
        entry.status.toString(),
        entry.episodes,
        entry.watched,
        entry.title.slice(strings),
        entry.id.site.url(),
        entry.id.id,
    });
}

test {
    _ = Database;
    _ = StringIntern;
}

const Entry = @This();

const Id = Database.Id;

const Database = @import("../Database.zig");
const StringIntern = @import("../StringIntern.zig");

const datetime = @import("datetime");
const std = @import("std");
