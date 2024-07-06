const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const strip = b.option(bool, "strip", "Omit debug symbols") orelse false;

    const aniz = b.addExecutable(.{
        .name = "aniz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
    b.installArtifact(aniz);

    const datetime_module = b.createModule(.{
        .root_source_file = b.path("lib/zig-datetime/src/datetime.zig"),
    });
    const folders_module = b.createModule(.{
        .root_source_file = b.path("lib/known-folders/known-folders.zig"),
    });

    for ([_]*std.Build.Step.Compile{ aniz, tests }) |comp| {
        comp.root_module.addImport("datetime", datetime_module);
        comp.root_module.addImport("folders", folders_module);
    }
}
