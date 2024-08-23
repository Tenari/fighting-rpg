const std = @import("std");
const posix = std.posix;
const lib = @import("lib");
const Game = lib.Game;
const Message = lib.Message;
const Socket = lib.Socket;

const fps: i128 = 1;
const goal_loop_time: i128 = std.time.ns_per_s / fps;

pub fn main() !void {
    const seed: [32]u8 = [4]u8{ 1, 2, 3, 4 } ** 8;
    const keys = try std.crypto.sign.ecdsa.EcdsaP256Sha256.KeyPair.create(seed);
    std.debug.print("keys: {any} {any}\n", .{ keys.public_key, keys.secret_key });
    // 1. allocate server memory
    // 2. start gameloop
    // 3. start net server

    // requests come in to the server, which saves them as inputs to be read on the next gameloop frame
    // gameloop frames update game state in memeory, periodically (every N frames) saving to disk

    // allocate the game-state
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var game = try allocator.create(Game);
    defer allocator.destroy(game);
    std.debug.print("game memory size: {d}\n", .{@sizeOf(Game)});
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
    var request_source_address: posix.sockaddr = undefined;
    var addr_len: u32 = @sizeOf(posix.sockaddr);
    while (true) {
        const byte_count = try posix.recvfrom(socket.socket, buffer[0..], 0, &request_source_address, &addr_len);
        std.debug.print("Received {d} bytes: {s}\n", .{ byte_count, buffer[0..byte_count] });
        // there are 2 kinds of requests:
        // 1. public, which don't need ownership verification
        // 2. player, which are connection-info whitelisted for a specific player
        const msg: Message = @enumFromInt(buffer[0]);
        switch (msg) {
            // handle the "misc" messages
            .get_pub_key => {
                std.debug.print(".get_pub_key {any}\n", .{request_source_address});
                buffer[0] = @intFromEnum(Message.pub_key_is);
                //TODO actually return the pubkey
                buffer[1] = 1;
                buffer[2] = 2;
                buffer[3] = 3;
                const bytes_sent = try posix.sendto(socket.socket, buffer[0..3], 0, &request_source_address, addr_len);
                std.debug.print("bytes_sent {d}\n", .{bytes_sent});
                //try Socket.respond(request_source_address, buffer[0..3]);
            },
            // assume anything else is player-input affecting game-state in a real-time manner
            else => {
                try inputs.append(.{ .msg = msg, .data = buffer[1..byte_count] });
            },
        }
    }
}

fn gameLoop(inputs: *std.ArrayList(Input), game: *Game) void {
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
    msg: Message,
    data: []u8,
};
