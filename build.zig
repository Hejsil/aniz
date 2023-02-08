const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const strip = b.option(bool, "strip", "") orelse false;

    const mecha_module = b.createModule(.{
        .source_file = .{ .path = "lib/mecha/mecha.zig" },
    });
    const datetime_module = b.createModule(.{
        .source_file = .{ .path = "lib/zig-datetime/src/datetime.zig" },
    });
    const clap_module = b.createModule(.{
        .source_file = .{ .path = "lib/zig-clap/clap.zig" },
    });
    const folders_module = b.createModule(.{
        .source_file = .{ .path = "lib/known-folders/known-folders.zig" },
    });
    const anime_module = b.createModule(.{
        .source_file = .{ .path = "src/anime.zig" },
        .dependencies = &.{
            .{ .name = "mecha", .module = mecha_module },
            .{ .name = "datetime", .module = datetime_module },
        },
    });
    const database_module = b.createModule(.{
        .source_file = .{ .path = "zig-cache/database.zig" },
        .dependencies = &.{
            .{ .name = "anime", .module = anime_module },
        },
    });

    const generate_database = b.addExecutable(.{
        .name = "generate-database",
        .root_source_file = .{ .path = "tools/generate-database.zig" },
        .target = target,
        .optimize = optimize,
    });
    generate_database.addModule("anime", anime_module);
    generate_database.strip = strip;
    generate_database.install();

    const generate_database_step = generate_database.run();
    generate_database_step.addArgs(
        &.{
            "lib/anime-offline-database/anime-offline-database.json",
            "zig-cache/database.zig",
        },
    );

    const aniz = b.addExecutable(.{
        .name = "aniz",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    aniz.addModule("clap", clap_module);
    aniz.addModule("datetime", datetime_module);
    aniz.addModule("known_folders", folders_module);
    aniz.addModule("anime", anime_module);
    aniz.addModule("database", database_module);
    aniz.strip = strip;
    aniz.install();

    aniz.step.dependOn(&generate_database_step.step);
}
