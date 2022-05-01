const std = @import("std");

const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseSafe);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const strip = b.option(bool, "strip", "") orelse false;

    const generate_database = b.addExecutable("generate-database", "tools/generate-database.zig");
    generate_database.addPackagePath("anime", "src/anime.zig");
    generate_database.setTarget(target);
    generate_database.setBuildMode(mode);
    generate_database.strip = strip;
    generate_database.install();

    const generate_database_step = generate_database.run();
    generate_database_step.addArgs(
        &.{
            "lib/anime-offline-database/anime-offline-database.json",
            "zig-cache/database.zig",
        },
    );

    const anime_pkg = Pkg{
        .name = "anime",
        .path = .{ .path = "src/anime.zig" },
        .dependencies = &.{ .{
            .name = "mecha",
            .path = .{ .path = "lib/mecha/mecha.zig" },
        }, .{
            .name = "datetime",
            .path = .{ .path = "lib/zig-datetime/src/datetime.zig" },
        } },
    };

    const anilist = b.addExecutable("anilist", "src/main.zig");
    anilist.addPackagePath("clap", "lib/zig-clap/clap.zig");
    anilist.addPackagePath("datetime", "lib/zig-datetime/src/datetime.zig");
    anilist.addPackagePath("known_folders", "lib/known-folders/known-folders.zig");
    anilist.addPackage(anime_pkg);
    anilist.addPackage(.{
        .name = "database",
        .path = .{ .path = "zig-cache/database.zig" },
        .dependencies = &.{anime_pkg},
    });
    anilist.setTarget(target);
    anilist.setBuildMode(mode);
    anilist.strip = strip;
    anilist.install();

    anilist.step.dependOn(&generate_database_step.step);
}
