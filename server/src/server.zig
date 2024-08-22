const std = @import("std");
const lib = @import("lib");
const Socket = @import("lib").Socket;

const fps: i128 = 1;
const goal_loop_time: i128 = std.time.ns_per_s / fps;

pub fn main() !void {
    // 1. allocate server memory
    // 2. start gameloop
    // 3. start net server

    // requests come in to the server, which saves them as inputs to be read on the next gameloop frame
    // gameloop frames update game state in memeory, periodically (every N frames) saving to disk

    // allocate the game-state
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var game = try allocator.create(lib.Game);
    defer allocator.destroy(game);
    std.debug.print("game memory size: {d}\n", .{@sizeOf(lib.Game)});
    game.init();

    var inputs = std.ArrayList(Input).init(allocator);
    defer inputs.deinit();

    // spin off thread for the game-loop
    const game_thread_handle = try std.Thread.spawn(.{}, gameLoop, .{ &inputs, game });
    game_thread_handle.detach();

    // start the udp server for setting inputs
    std.debug.print("Starting CombatRPG server...\n", .{});
    var socket = try Socket.init("127.0.0.1", 13370);
    try socket.bind();
    var buffer: [1024]u8 = undefined;
    while (true) {
        const byte_count = try socket.recv(buffer[0..]);
        std.debug.print("Received {d} bytes: {s}\n", .{ byte_count, buffer[0..byte_count] });
        if (buffer[0] == 's') {
            try inputs.append(.{ .msg = lib.Message.sign_up, .data = buffer[0..byte_count] });
        }
    }
}

fn gameLoop(inputs: *std.ArrayList(Input), game: *lib.Game) void {
    while (true) {
        const loop_start = std.time.nanoTimestamp();
        for (inputs.items) |i| {
            std.debug.print("known input {any}\n", .{i.msg});
        }
        for (game.players) |p| {
            if (p) |player| {
                std.debug.print("known player {any}\n", .{player.username});
            }
        }
        const loop_duration = std.time.nanoTimestamp() - loop_start;
        const remaining_time = goal_loop_time - loop_duration;
        if (remaining_time > 0) {
            std.time.sleep(@intCast(remaining_time));
        }
    }
}

pub const Input = struct {
    msg: lib.Message,
    data: []u8,
};
