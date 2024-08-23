const std = @import("std");
const posix = std.posix;
const assert = std.debug.assert;
const lib = @import("lib");
const Socket = lib.Socket;
const Message = lib.Message;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub fn main() !void {
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

    var addr_len: u32 = @sizeOf(posix.sockaddr);
    var server_address = try std.net.Address.parseIp4("127.0.0.1", 13370);
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    errdefer posix.close(sock);
    const get_pub_key_bytes = [_]u8{@intFromEnum(Message.get_pub_key)};
    _ = try posix.sendto(sock, get_pub_key_bytes[0..], 0, &server_address.any, server_address.getOsSockLen());
    var buffer: [1024]u8 = undefined;
    const byte_count = try posix.recvfrom(sock, buffer[0..], 0, &server_address.any, &addr_len);
    std.debug.print("Received {d} bytes: {any}\n", .{ byte_count, buffer[0..byte_count] });
    //var socket = try Socket.init("127.0.0.1", 13370);
    //defer socket.deinit();
    //try socket.connect();
    // get server public-key
    //const get_pub_key_bytes = [_]u8{@intFromEnum(Message.get_pub_key)};
    //try socket.send(&get_pub_key_bytes);
    //var buffer: [1024]u8 = undefined;
    //const read_byte_count = try Socket.receive_response(&socket.address.any, buffer[0..]);
    //std.debug.print("Received {d} bytes: {s}\n", .{ read_byte_count, buffer[0..read_byte_count] });
    //try createGui(&sock);
    try createGui();
}

//fn createGui(socket: *Socket) !void {
fn createGui() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();
    const screen = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 400, 140, c.SDL_WINDOW_OPENGL) orelse
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

    const zig_bmp = @embedFile("zig.bmp");
    const rw = c.SDL_RWFromConstMem(zig_bmp, zig_bmp.len) orelse {
        c.SDL_Log("Unable to get RWFromConstMem: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer assert(c.SDL_RWclose(rw) == 0);

    const zig_surface = c.SDL_LoadBMP_RW(rw, 0) orelse {
        c.SDL_Log("Unable to load bmp: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_FreeSurface(zig_surface);

    const zig_texture = c.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(zig_texture);

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    std.debug.print("{any}\n", .{event.key});
                    //try handleKeyPress(event.key.keysym.sym, socket);
                    try handleKeyPress(event.key.keysym.sym);
                },
                else => {},
            }
        }

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, zig_texture, null, null);
        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

//fn handleKeyPress(byte: i32, socket: *Socket) !void {
fn handleKeyPress(byte: i32) !void {
    switch (byte) {
        97 => { // a
        },
        98 => { // b
        },
        99 => { // c
        },
        100 => { // d
        },
        106 => { // j
            //try socket.send("\x00");
        },
        else => {},
    }
}
