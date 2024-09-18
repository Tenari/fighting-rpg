const std = @import("std");
const Hash = std.array_hash_map.AutoArrayHashMap;
const List = std.ArrayList;
const posix = std.posix;
const lib = @import("lib");
const Packet = lib.Packet;
const Game = lib.Game;
const Character = lib.Character;
const Location = lib.Location;
const Terrain = lib.Terrain;
const Room = lib.Room;
const Message = lib.Message;
const Serializer = lib.Serializer;

const fps: i128 = 66;
const GOAL_LOOP_TIME: i128 = std.time.ns_per_s / fps;

const SEND_PACKETS_PER_SECOND: i128 = 20;
const SEND_GOAL_LOOP_TIME: i128 = std.time.ns_per_s / SEND_PACKETS_PER_SECOND;

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
    var inputs = List(lib.MoveCommand).init(allocator);
    defer inputs.deinit();

    // spin off thread for the game-loop
    var mutex = std.Thread.Mutex{};
    const game_thread_handle = try std.Thread.spawn(.{}, gameLoop, .{ &inputs, game, &mutex });
    game_thread_handle.detach();

    // start the udp server for setting inputs
    std.debug.print("Starting CombatRPG server...\n", .{});
    const server_address = try std.net.Address.parseIp4(lib.DEFAULT_SERVER_HOST, lib.DEFAULT_SERVER_PORT);
    var socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    try posix.bind(socket, &server_address.any, server_address.getOsSockLen());
    var buffer: [1024 * 32]u8 = undefined;
    var request_source_address: posix.sockaddr = undefined;
    var addr_len: u32 = @sizeOf(posix.sockaddr);
    // spin off thread for sending clients game world snapshots
    const sending_handle = try std.Thread.spawn(.{}, sendUpdatesLoop, .{ game, &mutex, &socket });
    sending_handle.detach();
    while (true) {
        const byte_count = try posix.recvfrom(socket, buffer[0..], 0, &request_source_address, &addr_len);
        std.debug.print("Received {d} bytes: {s}\n", .{ byte_count, buffer[0..byte_count] });
        const msg: Message = @enumFromInt(buffer[0]);
        mutex.lock();
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
                std.debug.print(".get_local_state {any}\n", .{request_source_address});
                buffer[0] = @intFromEnum(Message.state_is);
                var serializer = Serializer.init(buffer[1..]);
                serializer.write(Room, game.map[0]);
                const buffer_slice_end = (serializer.index + 1);
                const bytes_sent = try posix.sendto(socket, buffer[0..buffer_slice_end], 0, &request_source_address, addr_len);
                std.debug.print("bytes_sent {d}\n{any}\n", .{ bytes_sent, buffer[0..buffer_slice_end] });
            },
            .create_character => {
                const username = buffer[1..(lib.MAX_USERNAME_SIZE + 1)];
                std.debug.print(".create_character with data: {s}\n", .{username});
                var i: usize = 0;
                var found = false;
                for (game.characters) |character| {
                    if (character == null) {
                        found = true;
                        break;
                    }
                    i += 1;
                }
                var end_index: usize = 1;
                if (found) {
                    game.characters[i] = Character.init(username, lib.Race.human);
                    game.characters[i].?.id = @intCast(i);
                    game.characters[i].?.allowed_source = request_source_address;

                    buffer[0] = @intFromEnum(Message.character_created);
                    var serializer = Serializer.init(buffer[1..]);
                    serializer.write(Character, game.characters[i].?);
                    end_index = (serializer.index + 1);
                } else {
                    buffer[0] = @intFromEnum(Message.no_character_slots_left);
                }
                _ = try posix.sendto(socket, buffer[0..end_index], 0, &request_source_address, addr_len);
            },
            // assume anything else is player-input affecting game-state in a real-time manner
            else => {
                var des = lib.Deserializer.init(allocator, buffer[1..byte_count]);
                try inputs.append(try des.read(lib.MoveCommand));
            },
        }
        mutex.unlock();
    }
}

fn gameLoop(inputs: *List(lib.MoveCommand), game: *Game, mutex: *std.Thread.Mutex) void {
    while (true) {
        const loop_start = std.time.nanoTimestamp();
        mutex.lock();
        for (inputs.items) |i| {
            std.debug.print("character_id {d}; x = {d}; y = {d}\n", .{ i.character_id, i.point.x, i.point.y });
            if (game.characters[@intCast(i.character_id)]) |*character| {
                _ = character.attemptMoveFromInput(i.point, &game.map[@intCast(character.location.room_id)]);
            }
        }
        inputs.clearRetainingCapacity();
        for (game.characters) |c| {
            if (c) |character| {
                std.debug.print("known character {s} @ ({d},{d})\n", .{ character.username, character.location.x, character.location.y });
            }
        }
        mutex.unlock();
        const loop_duration = std.time.nanoTimestamp() - loop_start;
        const remaining_time = GOAL_LOOP_TIME - loop_duration;
        if (remaining_time > 0) {
            std.time.sleep(@intCast(remaining_time));
        }
    }
}

fn sendUpdatesLoop(game: *Game, mutex: *std.Thread.Mutex, socket: *posix.socket_t) !void {
    const addr_len: u32 = @sizeOf(posix.sockaddr);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var rooms = Hash(lib.RoomId, lib.Snapshot).init(allocator);
    while (true) {
        const loop_start = std.time.nanoTimestamp();
        mutex.lock();
        // take a snapshot of each room
        for (game.map) |room| {
            var snapshot = lib.Snapshot{
                .room = room,
                .characters = &.{},
            };
            var characters = List(Character).init(allocator);
            for (game.characters) |c| {
                if (c) |character| {
                    if (character.location.room_id == room.id) {
                        characters.append(character) catch {
                            std.debug.print("failed to add character {d} to the snapshot for network updates", .{character.id});
                        };
                    }
                }
            }
            snapshot.characters = characters.toOwnedSlice() catch continue;
            const maybe_old = rooms.get(room.id);
            if (maybe_old) |old| {
                allocator.free(old.characters);
            }
            rooms.put(room.id, snapshot) catch {
                std.debug.print("failed to add room {d} to the snapshot hash for network updates", .{room.id});
            };
        }
        for (game.characters) |c| {
            if (c) |character| {
                // TODO: figure out the "delta snapshot" relevant to this character
                const snapshot = rooms.get(character.location.room_id) orelse {
                    std.debug.print("failed to get room {d} from the hash for sending to character {d}", .{ character.location.room_id, character.id });
                    continue;
                };
                var bytes: [1024 * 8]u8 = undefined;
                bytes[0] = @intFromEnum(Message.snapshot);
                var serializer = Serializer.init(bytes[1..]);
                serializer.write(lib.Snapshot, snapshot);
                std.debug.print("bytes sending {d}", .{serializer.index + 1});
                _ = try posix.sendto(socket.*, bytes[0 .. serializer.index + 1], 0, &character.allowed_source, addr_len);
            }
        }
        mutex.unlock();
        const loop_duration = std.time.nanoTimestamp() - loop_start;
        const remaining_time = SEND_GOAL_LOOP_TIME - loop_duration;
        if (remaining_time > 0) {
            std.time.sleep(@intCast(remaining_time));
        }
    }
}
