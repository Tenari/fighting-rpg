const std = @import("std");
const posix = std.posix;
const assert = std.debug.assert;
const lib = @import("lib");
const Message = lib.Message;
const c = @cImport({
    @cInclude("SDL2/SDL_image.h");
});
const game = @import("game.zig");
const types = @import("types.zig");

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 720;

pub fn main() !void {
    // allocate the game-state
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    //var game = try allocator.create(Game);
    //defer allocator.destroy(game);
    //std.debug.print("game memory size: {d}\n", .{@sizeOf(Game)});

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
    const pk_response = try lib.request_response(.{ .msg = Message.get_pub_key, .data = &.{} }, sock, &server_address);
    std.debug.assert(pk_response.msg == Message.pub_key_is);
    const public_key = try std.crypto.sign.ecdsa.EcdsaP256Sha256.PublicKey.fromSec1(pk_response.data);
    std.debug.print("server public_key: {any}\n", .{public_key.toCompressedSec1()});

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
        //TODO: show signup form
    }

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
    // const zig_bmp = @embedFile("zig.bmp");
    // const rw = c.SDL_RWFromConstMem(zig_bmp, zig_bmp.len) orelse {
    //     c.SDL_Log("Unable to get RWFromConstMem: %s", c.SDL_GetError());
    //     return error.SDLInitializationFailed;
    // };
    // defer assert(c.SDL_RWclose(rw) == 0);

    // const zig_surface = c.SDL_LoadBMP_RW(rw, 0) orelse {
    //     c.SDL_Log("Unable to load bmp: %s", c.SDL_GetError());
    //     return error.SDLInitializationFailed;
    // };
    // defer c.SDL_FreeSurface(zig_surface);

    // const zig_texture = c.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
    //     c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
    //     return error.SDLInitializationFailed;
    // };
    // defer c.SDL_DestroyTexture(zig_texture);

    var input_history: [64]types.AllInputSnapshot = undefined;
    var frame: u64 = 0;
    var quit = false;
    // TODO: actually get the server state
    var server_state: lib.Game = undefined;
    const state: *types.ClientState = try game.initClientState(allocator, &server_state, renderer);
    while (!quit) {
        const current_input: *types.AllInputSnapshot = &input_history[frame % input_history.len];
        current_input.*.controllers[0].direction = .{ .x = -0.0, .y = 0.0 };
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    std.debug.print("{any}\n", .{event.key});
                    current_input.*.controllers[0].key = event.key.keysym.sym;
                    switch (event.key.keysym.sym) {
                        97 => { // a
                            current_input.*.controllers[0].direction.x = -1.0;
                        },
                        100 => { // d
                            current_input.*.controllers[0].direction.x = 1.0;
                        },
                        119 => { // w
                            current_input.*.controllers[0].direction.y = -1.0;
                        },
                        115 => { // s
                            current_input.*.controllers[0].direction.y = 1.0;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        game.gameUpdateAndRender(renderer, state, current_input) catch |err| {
            std.debug.print("error", .{});
            return err;
        };
        c.SDL_Delay(17);
        frame += 1;
    }
}

const SaveFile = struct {
    player_id: u64,
};
