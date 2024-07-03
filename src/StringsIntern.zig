//! Datastructure for interning slices of already interned strings.

dedupe: std.ArrayHashMapUnmanaged(Span, void, SpanContext, true) = .{},
data: std.ArrayListUnmanaged(StringIntern.Index) = .{},

pub fn deinit(intern: *StringsIntern, allocator: std.mem.Allocator) void {
    intern.dedupe.deinit(allocator);
    intern.data.deinit(allocator);
}

pub fn put(intern: *StringsIntern, allocator: std.mem.Allocator, strings: []const StringIntern.Index) !Span {
    if (strings.len == 0)
        return Span{ .index = 0, .len = 0 };

    try intern.data.ensureUnusedCapacity(allocator, strings.len);

    const key_ctx = SliceToSpanContext{ .intern = intern };
    const ctx = SpanContext{ .intern = intern };
    const entry = try intern.dedupe.getOrPutContextAdapted(allocator, strings, key_ctx, ctx);
    if (entry.found_existing)
        return entry.key_ptr.*;

    const index = std.math.cast(u32, intern.data.items.len) orelse return error.OutOfMemory;
    const len = std.math.cast(u32, strings.len) orelse return error.OutOfMemory;
    const res = Span{ .index = index, .len = len };
    entry.key_ptr.* = res;

    intern.data.appendSliceAssumeCapacity(strings);

    return res;
}

pub const Span = extern struct {
    index: u32,
    len: u32,

    pub fn slice(span: @This(), data: []const StringIntern.Index) []const StringIntern.Index {
        return data[span.index..][0..span.len];
    }
};

const SliceToSpanContext = struct {
    intern: *StringsIntern,

    pub fn eql(ctx: SliceToSpanContext, a: []const StringIntern.Index, b: Span, b_index: usize) bool {
        _ = b_index;
        const b_slice = b.slice(ctx.intern.data.items);
        return std.mem.eql(StringIntern.Index, a, b_slice);
    }

    pub fn hash(ctx: SliceToSpanContext, s: []const StringIntern.Index) u32 {
        _ = ctx;
        return hashStringIndexs(s);
    }
};

const SpanContext = struct {
    intern: *StringsIntern,

    pub fn eql(ctx: SpanContext, a: Span, b: Span, b_index: usize) bool {
        _ = ctx;
        _ = b_index;
        return std.meta.eql(a, b);
    }

    pub fn hash(ctx: SpanContext, key: Span) u32 {
        const slice = key.slice(ctx.intern.data.items);
        return hashStringIndexs(slice);
    }
};

fn hashStringIndexs(slice: []const StringIntern.Index) u32 {
    const bytes = std.mem.sliceAsBytes(slice);
    return @as(u32, @truncate(std.hash.Wyhash.hash(0, bytes)));
}

test {
    _ = StringIntern;
}

const StringsIntern = @This();

const StringIntern = @import("StringIntern.zig");

const std = @import("std");
