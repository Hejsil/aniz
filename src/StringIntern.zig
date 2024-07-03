//! Datastructure for interning strings. Interned strings are stored in the `StringIntern` and can be accessed by their
//! index. Strings are stored null terminated. The index 0 is reserved for the empty string.

dedupe: std.ArrayHashMapUnmanaged(Index, void, IndexContext, true),
data: std.ArrayListUnmanaged(u8),

pub fn init(allocator: std.mem.Allocator) !StringIntern {
    var data = std.ArrayListUnmanaged(u8){};
    errdefer data.deinit(allocator);

    // Ensure there is at least one null byte at the start of the data. We can point empty strings here.
    try data.append(allocator, 0);

    return .{ .data = data, .dedupe = .{} };
}

pub fn deinit(intern: *StringIntern, allocator: std.mem.Allocator) void {
    intern.dedupe.deinit(allocator);
    intern.data.deinit(allocator);
}

pub fn sliceZ(intern: StringIntern) [:0]const u8 {
    return intern.data.items[0 .. intern.data.items.len - 1 :0];
}

pub fn put(intern: *StringIntern, allocator: std.mem.Allocator, string: []const u8) !Index {
    if (string.len == 0)
        return @enumFromInt(0);

    try intern.data.ensureUnusedCapacity(allocator, string.len + 1);

    const key_ctx = StringToIndexContext{ .intern = intern };
    const ctx = IndexContext{ .intern = intern };
    const entry = try intern.dedupe.getOrPutContextAdapted(allocator, string, key_ctx, ctx);
    if (entry.found_existing)
        return entry.key_ptr.*;

    const index = std.math.cast(u32, intern.data.items.len) orelse return error.OutOfMemory;
    const res: Index = @enumFromInt(index);
    entry.key_ptr.* = res;

    intern.data.appendSliceAssumeCapacity(string);
    intern.data.appendAssumeCapacity(0);

    return res;
}

pub const Index = enum(u32) {
    empty = 0,
    _,

    pub fn slice(index: @This(), data: [:0]const u8) [:0]const u8 {
        return std.mem.sliceTo(index.ptr(data), 0);
    }

    pub fn ptr(index: @This(), data: [:0]const u8) [*:0]const u8 {
        return data[@intFromEnum(index)..].ptr;
    }
};

const StringToIndexContext = struct {
    intern: *StringIntern,

    pub fn eql(ctx: StringToIndexContext, a: []const u8, b: Index, b_index: usize) bool {
        _ = b_index;
        const b_srt = b.slice(ctx.intern.data.items[0 .. ctx.intern.data.items.len - 1 :0]);
        return std.mem.eql(u8, a, b_srt);
    }

    pub fn hash(ctx: StringToIndexContext, s: []const u8) u32 {
        _ = ctx;
        return std.array_hash_map.hashString(s);
    }
};

const IndexContext = struct {
    intern: *StringIntern,

    pub fn eql(ctx: IndexContext, a: Index, b: Index, b_index: usize) bool {
        _ = ctx;
        _ = b_index;
        return a == b;
    }

    pub fn hash(ctx: IndexContext, key: Index) u32 {
        const str = key.slice(ctx.intern.sliceZ());
        return std.array_hash_map.hashString(str);
    }
};

const StringIntern = @This();

const std = @import("std");
