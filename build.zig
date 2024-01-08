const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mecha_module = b.createModule(.{
        .root_source_file = .{ .path = "lib/mecha/mecha.zig" },
    });
    const datetime_module = b.createModule(.{
        .root_source_file = .{ .path = "lib/zig-datetime/src/datetime.zig" },
    });
    const clap_module = b.createModule(.{
        .root_source_file = .{ .path = "lib/zig-clap/clap.zig" },
    });
    const folders_module = b.createModule(.{
        .root_source_file = .{ .path = "lib/known-folders/known-folders.zig" },
    });
    const anime_module = b.createModule(.{
        .root_source_file = .{ .path = "src/anime.zig" },
        .imports = &.{
            .{ .name = "mecha", .module = mecha_module },
            .{ .name = "datetime", .module = datetime_module },
        },
    });
    const database_module = b.createModule(.{
        .root_source_file = .{ .path = "zig-cache/database.zig" },
        .imports = &.{
            .{ .name = "anime", .module = anime_module },
        },
    });

    const generate_database = b.addExecutable(.{
        .name = "generate-database",
        .root_source_file = .{ .path = "tools/generate-database.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_generate_database = b.addRunArtifact(generate_database);

    generate_database.root_module.addImport("anime", anime_module);

    run_generate_database.addArgs(
        &.{
            "lib/anime-offline-database/anime-offline-database.json",
            "zig-cache/database.zig",
        },
    );

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    tests.step.dependOn(&run_generate_database.step);
    test_step.dependOn(&run_tests.step);

    const aniz = b.addExecutable(.{
        .name = "aniz",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    aniz.root_module.addImport("clap", clap_module);
    aniz.root_module.addImport("datetime", datetime_module);
    aniz.root_module.addImport("known_folders", folders_module);
    aniz.root_module.addImport("anime", anime_module);
    aniz.root_module.addImport("database", database_module);

    aniz.step.dependOn(&run_generate_database.step);
    b.installArtifact(generate_database);
    b.installArtifact(aniz);
}
