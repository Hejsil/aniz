const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const strip = b.option(bool, "strip", "Omit debug symbols") orelse false;

    const aniz = b.addExecutable(.{
        .name = "aniz",
        .root_source_file = b.path("src/aniz.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    b.installArtifact(aniz);

    const aniz_gui = b.addExecutable(.{
        .name = "aniz-gui",
        .root_source_file = b.path("src/aniz-gui.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    b.installArtifact(aniz_gui);

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/aniz.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const datetime = b.dependency("datetime", .{});
    const folders = b.dependency("folders", .{});
    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
    });

    for ([_]*std.Build.Step.Compile{ aniz, aniz_gui, tests }) |comp| {
        comp.root_module.addImport("datetime", datetime.module("zig-datetime"));
        comp.root_module.addImport("folders", folders.module("known-folders"));
    }

    aniz_gui.root_module.addImport("webui", webui.module("webui"));
}
