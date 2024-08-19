const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "combatrpg_server",
        .root_source_file = b.path("src/server.zig"),
        .target = b.host,
    });

    const httpz = b.dependency("httpz", .{
        .target = b.host,
        .optimize = b.standardOptimizeOption(.{}),
    });
    exe.root_module.addImport("httpz", httpz.module("httpz"));

    b.installArtifact(exe);
}
