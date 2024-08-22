const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.host; //b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const server = b.option(bool, "server", "build for server? otherwise client") orelse false;

    var name = "combatrpg_client";
    if (server) {
        std.debug.print("building for server\n", .{});
        name = "combatrpg_server";
    }
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = if (server) b.path("server/src/server.zig") else b.path("client/src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (!server) {
        exe.linkSystemLibrary("SDL2");
        exe.linkLibC();
    }

    //const httpz = b.dependency("httpz", .{
    //    .target = b.host,
    //    .optimize = b.standardOptimizeOption(.{}),
    //});
    //exe.root_module.addImport("httpz", httpz.module("httpz"));

    const mod = b.createModule(.{ .root_source_file = b.path("common/lib.zig"), .target = target });
    exe.root_module.addImport("lib", mod);
    b.installArtifact(exe);
}
