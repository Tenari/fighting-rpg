const std = @import("std");
const posix = std.posix;
const assert = std.debug.assert;
const lib = @import("lib");
const Message = lib.Message;
const Tile = lib.Tile;
const game = @import("game.zig");
const types = @import("types.zig");
const c = types.c;

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 720;

const SEND_PACKETS_PER_SECOND = 30;
const SEND_GOAL_LOOP_TIME = std.time.ns_per_s / SEND_PACKETS_PER_SECOND;

pub fn main() !void {
    // allocate the game-state
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // on startup:
    // - get server public-key for secure messages
    // if local savefile:
    // 1. verify ownership of savefile (password)
    // 2. send Message.update_player_source request (to sign in)
    // 3. get current character state from server
    // else:
    // 1. signup view (username+password inputs)
    // 2. send to server
    // 3. get current character state from server

    // connection setup
    std.debug.print("Starting CombatRPG client...\n", .{});
    var server_address = try std.net.Address.parseIp4(lib.DEFAULT_SERVER_HOST, lib.DEFAULT_SERVER_PORT);
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);

    // get server public-key
    var server_response_buffer: [1024 * 8]u8 = undefined;
    var fa = std.heap.FixedBufferAllocator.init(&server_response_buffer);
    const fixed_allocator = fa.allocator();
    var pk_response = try lib.request_response(fixed_allocator, .{ .msg = Message.get_pub_key, .data = &.{}, .allocator = allocator }, sock, &server_address);
    std.debug.assert(pk_response.msg == Message.pub_key_is);
    const public_key = try std.crypto.sign.ecdsa.EcdsaP256Sha256.PublicKey.fromSec1(pk_response.data);
    std.debug.print("server public_key: {any}\n", .{public_key.toCompressedSec1()});
    pk_response.deinit();

    // get current room from the server
    var state_response = try lib.request_response(fixed_allocator, .{ .msg = Message.get_local_state, .data = &.{}, .allocator = allocator }, sock, &server_address);
    std.debug.assert(state_response.msg == Message.state_is);
    var room_reader = lib.Deserializer.init(allocator, state_response.data[0..]);
    const room = try room_reader.read(lib.Room);
    //defer allocator.free(room.tiles); // TODO: we actually need to figure out the lifecycle for this better; needs to happen after the last use of room
    state_response.deinit();

    // prep the gui
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();
    const screen = c.SDL_CreateWindow("Wuxia Wars", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_WINDOW_OPENGL) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);
    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.IMG_Init(c.IMG_INIT_PNG | c.IMG_INIT_JPG);
    _ = c.TTF_Init();
    c.SDL_StartTextInput();

    // init the client game state
    const state: *types.ClientState = try game.initClientState(allocator, room, renderer);
    state.sock = sock;
    state.server_address = server_address;

    // see if the save file exists
    const maybe_file: ?std.fs.File = std.fs.cwd().openFile("save.json", .{}) catch null;
    if (maybe_file) |file| {
        defer file.close();
        var file_buffer: [1024]u8 = undefined;
        const file_read_size = try file.readAll(file_buffer[0..]);
        _ = file_read_size;
        const parsed = try std.json.parseFromSlice(SaveFile, allocator, file_buffer[0..], .{ .allocate = .alloc_always });
        defer parsed.deinit();
        const save_file = parsed.value;
        //TODO: request password from user to prove ownership. this is just to make the compiler happy currently
        _ = save_file;
    } else {
        // show signup form
        state.making_new_character = true;
    }

    // TODO: spin off thread for recieving server snapshots and sending client inputs
    var mutex = std.Thread.Mutex{};
    const send_thread_handle = try std.Thread.spawn(.{}, sendNetworking, .{ state, &mutex });
    send_thread_handle.detach();
    const recv_thread_handle = try std.Thread.spawn(.{}, recvNetworking, .{state});
    recv_thread_handle.detach();

    // the main game loop for rendering and updating our state. this just drops requests in the server communication thread, doesn't actually do any networking. it has mutexed-shared memory for figuring out if it needs to rollback/re-simulate the world to match the server.
    while (!state.should_quit) {
        // poll all input devices
        mutex.lock();
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            try game.pollInput(&event, state);
        }

        // update current game state
        try game.update(allocator, state);

        // render current game state
        game.render(renderer, state) catch |err| {
            std.debug.print("error", .{});
            return err;
        };
        mutex.unlock();
        c.SDL_Delay(17);
    }
}

const SaveFile = struct {
    player_id: u64,
};

fn sendNetworking(state: *types.ClientState, mutex: *std.Thread.Mutex) void {
    while (true) {
        const loop_start = std.time.nanoTimestamp();

        mutex.lock();
        for (&state.outgoing_requests) |*maybe_req| {
            if (maybe_req.*) |*req| {
                _ = lib.request(req.*, state.sock, &state.server_address) catch |err| {
                    std.debug.print("failed sending request {any}\n{any}", .{ err, req });
                };
                req.deinit();
                maybe_req.* = null;
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

fn recvNetworking(state: *types.ClientState) void {
    var temp_buffer: [1024 * 32]u8 = undefined;
    var server_response_buffer: [1024 * 32]u8 = undefined;
    var socklen = state.server_address.getOsSockLen();
    while (true) {
        // blocking, waiting for a message from the server
        var server_msg = lib.receiveInto(&temp_buffer, state.sock, &state.server_address, &socklen) catch |err| {
            std.debug.print("failed receiving from server {any}\n", .{err});
            continue;
        };
        std.debug.print("got a {} from server\n", .{server_msg.msg});
        // block until we see that there is empty space for the server_msg
        state.response_mutex.lock();
        while (state.incoming_response != null) {
            state.response_condition.wait(&state.response_mutex);
        }
        if (server_msg.data.len > 0) {
            // copy the data from the temp_buffer to the longer lasting buffer
            @memcpy(server_response_buffer[0..server_msg.data.len], server_msg.data);
            server_msg.data = server_response_buffer[0..server_msg.data.len];
        }
        state.incoming_response = server_msg;
        state.response_mutex.unlock();
    }
}
