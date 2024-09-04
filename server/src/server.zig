const std = @import("std");
const posix = std.posix;
const lib = @import("lib");
const Input = lib.Input;
const Game = lib.Game;
const Message = lib.Message;

const fps: i128 = 1;
const goal_loop_time: i128 = std.time.ns_per_s / fps;

pub fn main() !void {
    const seed: [32]u8 = [4]u8{ 1, 2, 3, 4 } ** 8;
    const keys = try std.crypto.sign.ecdsa.EcdsaP256Sha256.KeyPair.create(seed);
    const public_key = keys.public_key.toCompressedSec1();
    std.debug.print("public_key_sec1: {any}\npk_obj {any}\n", .{ public_key, keys.public_key });

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
    const server_address = try std.net.Address.parseIp4(lib.DEFAULT_SERVER_HOST, lib.DEFAULT_SERVER_PORT);
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    try posix.bind(socket, &server_address.any, server_address.getOsSockLen());
    var buffer: [1024]u8 = undefined;
    var request_source_address: posix.sockaddr = undefined;
    var addr_len: u32 = @sizeOf(posix.sockaddr);
    while (true) {
        const byte_count = try posix.recvfrom(socket, buffer[0..], 0, &request_source_address, &addr_len);
        std.debug.print("Received {d} bytes: {s}\n", .{ byte_count, buffer[0..byte_count] });
        // there are 2 kinds of requests:
        // 1. public, which don't need ownership verification
        // 2. player, which are connection-info whitelisted for a specific player
        const msg: Message = @enumFromInt(buffer[0]);
        switch (msg) {
            .get_pub_key => {
                std.debug.print(".get_pub_key {any}\n", .{request_source_address});
                buffer[0] = @intFromEnum(Message.pub_key_is);
                const buffer_slice_end = (public_key.len + 1);
                @memcpy(buffer[1..buffer_slice_end], &public_key);
                const bytes_sent = try posix.sendto(socket, buffer[0..buffer_slice_end], 0, &request_source_address, addr_len);
                std.debug.print("bytes_sent {d}\n", .{bytes_sent});
            },
            .get_local_state => {
                // TODO: actually return the game state for the character
                std.debug.print(".get_local_state {any}\n", .{request_source_address});
                buffer[0] = @intFromEnum(Message.pub_key_is);
                const buffer_slice_end = (public_key.len + 1);
                @memcpy(buffer[1..buffer_slice_end], &public_key);
                const bytes_sent = try posix.sendto(socket, buffer[0..buffer_slice_end], 0, &request_source_address, addr_len);
                std.debug.print("bytes_sent {d}\n", .{bytes_sent});
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
