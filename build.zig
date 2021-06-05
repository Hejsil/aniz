const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseSafe);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable("anilist", "src/main.zig");
    exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
    exe.addPackagePath("datetime", "lib/zig-datetime/src/datetime.zig");
    exe.addPackagePath("known_folders", "lib/known-folders/known-folders.zig");
    exe.addPackagePath("mecha", "lib/mecha/mecha.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
}
