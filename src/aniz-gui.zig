pub fn main() !void {
    var nwin = webui.newWindow();
    // _ = nwin.bind("aniz", jsAniz);
    _ = nwin.show(@embedFile("aniz-gui.html"));
    webui.wait();
}

fn jsAniz(e: webui.Event) void {
    _ = e; // autofix
    std.log.info("Yo", .{});
    // anizMain(e) catch {};
}

fn anizMain(e: webui.Event) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const len = e.getCount();
    var args = try std.ArrayList([:0]const u8).initCapacity(arena, len);
    for (0..len) |i|
        args.appendAssumeCapacity(e.getStringAt(i));

    var stdout_list = std.ArrayList(u8).init(arena);
    const stdout = stdout_list.writer();

    try aniz.mainFull(.{
        .allocator = arena,
        .args = args.items,
        .stdout = stdout.any(),
    });

    e.returnString(try stdout_list.toOwnedSliceSentinel(0));
}

const aniz = @import("aniz.zig");
const webui = @import("webui");
const std = @import("std");
