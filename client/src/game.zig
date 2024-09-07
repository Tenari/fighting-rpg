const std = @import("std");
const lib = @import("lib");
const Message = lib.Message;
const types = @import("types.zig");
const c = types.c;
const Entity = types.Entity;
const ClientState = types.ClientState;

pub fn pollInput(event: *c.SDL_Event, state: *ClientState) !void {
    const current_input = state.currentInput();
    switch (event.type) {
        c.SDL_QUIT => {
            state.should_quit = true;
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
                10, 13 => { // return
                    // currently enter/return is only meaningful in the context of making a character
                    if (!state.making_new_character) {
                        return;
                    }
                    const character_response = try lib.request_response(.{ .msg = Message.create_character, .data = &state.input_username }, state.sock, &state.server_address);
                    std.debug.print("server character create response:\n{any}\n", .{character_response});
                    if (character_response.msg == Message.no_character_slots_left) {
                        // TODO: show error message saying that the server is full
                    } else {
                        std.debug.assert(character_response.msg == Message.character_created);
                        state.making_new_character = false;
                    }
                },
                8 => { // backspace
                    if (state.making_new_character and state.input_username[0] != 0) {
                        for (state.input_username, 0..) |byte, i| {
                            if (byte == 0) {
                                state.input_username[i - 1] = 0;
                                state.need_to_update_name_text_texture = true;
                                break;
                            } else if (i == state.input_username.len - 1) {
                                state.input_username[i] = 0;
                                state.need_to_update_name_text_texture = true;
                            }
                        }
                    }
                },
                else => {},
            }
        },
        c.SDL_TEXTINPUT => {
            //std.debug.print("got textinput event: {any}\n", .{event.text.text});
            for (state.input_username, 0..) |byte, i| {
                if (byte == 0) {
                    for (event.text.text, 0..) |b, j| {
                        if (b != 0) {
                            state.input_username[i + j] = b;
                        } else {
                            break;
                        }
                    }
                    state.need_to_update_name_text_texture = true;
                    break;
                }
            }
        },
        else => {},
    }
}

pub fn initClientState(allocator: std.mem.Allocator, server_state: lib.Room, renderer: *c.SDL_Renderer) !*ClientState {
    var state = try allocator.create(ClientState);
    state.frame = 0;
    state.input_username = [_]u8{0} ** lib.MAX_USERNAME_SIZE;
    state.in_combat = false;
    state.room = server_state;
    state.making_new_character = false;
    state.prompt_text = types.RenderableText.default();
    state.name_text = types.RenderableText.default();

    const player_texture = c.IMG_LoadTexture(renderer, "/Users/tenari/code/combatrpg/sprite1.png") orelse return error.NullPlayerSprite;
    state.font = c.TTF_OpenFont("/Users/tenari/code/combatrpg/client/assets/edo.ttf", 30) orelse {
        std.debug.print("error {s}", .{c.TTF_GetError()});
        return error.TTFOpenFontError;
    };
    state.player = .{
        .location = types.WorldLocation.default(),
        .render = .{
            .texture = player_texture,
        },
    };
    return state;
}

pub fn makeTextTexture(font: *c.TTF_Font, font_color: c.SDL_Color, renderer: *c.SDL_Renderer, text: []const u8) !types.RenderableText {
    const text_surface = c.TTF_RenderText_Solid(font, @ptrCast(text), font_color) orelse {
        std.debug.print("error {s}", .{c.TTF_GetError()});
        return error.TTFOpenFontError;
    };
    defer c.SDL_FreeSurface(text_surface);
    const texture = c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
        std.debug.print("error {s}", .{c.TTF_GetError()});
        return error.TTFOpenFontError;
    };
    return .{
        .texture = texture,
        .width = text_surface.*.w,
        .height = text_surface.*.h,
    };
}

pub fn updateAndRender(renderer: *c.SDL_Renderer, state: *ClientState) !void {
    if (state.making_new_character) {
        var font_color: c.SDL_Color = undefined;
        font_color.r = 0;
        font_color.g = 0;
        font_color.b = 0;
        font_color.a = 0;

        if (state.prompt_text.texture == null) {
            state.prompt_text =
                try makeTextTexture(state.font, font_color, renderer, "Enter your name");
        }

        var dest: c.SDL_Rect = undefined;
        dest.w = state.prompt_text.width;
        dest.h = state.prompt_text.height;
        dest.x = 50;
        dest.y = 50;

        // sdl setup
        _ = c.SDL_RenderClear(renderer);

        // render the new character ui
        _ = c.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
        _ = c.SDL_RenderCopyEx(renderer, state.prompt_text.texture.?, null, &dest, 0.0, null, c.SDL_FLIP_NONE);
        if (state.input_username[0] != 0) {
            if (state.need_to_update_name_text_texture) {
                state.name_text =
                    try makeTextTexture(state.font, font_color, renderer, &state.input_username);
            }
            var name_dest: c.SDL_Rect = dest;
            name_dest.w = state.name_text.width;
            name_dest.h = state.name_text.height;
            name_dest.y += 100;
            if (state.name_text.texture) |texture| {
                _ = c.SDL_RenderCopyEx(renderer, texture, null, &name_dest, 0.0, null, c.SDL_FLIP_NONE);
            }
            state.need_to_update_name_text_texture = false;
        }

        // sdl finish
        return c.SDL_RenderPresent(renderer);
    }

    // update
    const current_input = state.currentInput();
    const player: *Entity = &state.player;
    const old_x = player.location.x;
    const old_y = player.location.y;
    if (current_input.*.controllers[0].direction.x > 0) {
        player.location.x += 1;
    }
    if (current_input.*.controllers[0].direction.x < 0 and player.location.x > 0) {
        player.location.x -= 1;
    }
    if (current_input.*.controllers[0].direction.y > 0) {
        player.location.y += 1;
    }
    if (current_input.*.controllers[0].direction.y < 0 and player.location.y > 0) {
        player.location.y -= 1;
    }
    const new_tile = state.room.get(.{ .x = player.location.x, .y = player.location.y });
    if (new_tile.terrain == lib.Terrain.wall) {
        player.location.x = old_x;
        player.location.y = old_y;
    }

    // render
    _ = c.SDL_RenderClear(renderer);
    // draw the map
    var dest: c.SDL_Rect = undefined;
    dest.w = types.TILE_SIZE;
    dest.h = types.TILE_SIZE;
    for (&state.room.tiles, 0..) |*tile, i| {
        if (tile.terrain == lib.Terrain.blank) {
            continue;
        }
        if (tile.terrain == lib.Terrain.wall) {
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 255, 0);
        } else {
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 0);
        }
        dest.x = @intCast((i % state.room.width) * types.TILE_SIZE);
        dest.y = @intCast((i / state.room.width) * types.TILE_SIZE);
        _ = c.SDL_RenderFillRect(renderer, &dest);
    }
    // draw the player
    const point = player.screenLocation();
    dest.x = @intFromFloat(point.x);
    dest.y = @intFromFloat(point.y);
    //_ = c.SDL_QueryTexture(player.render.texture, 0, 0, &dest.w, &dest.h);
    _ = c.SDL_RenderCopy(renderer, player.render.texture, 0, &dest);
    //     _ = c.SDL_RenderCopy(renderer, zig_texture, null, null);
    c.SDL_RenderPresent(renderer);

    // cleanup/prep for next frame
    current_input.*.controllers[0].direction = .{ .x = -0.0, .y = 0.0 };
}
