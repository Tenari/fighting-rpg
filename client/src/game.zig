const std = @import("std");
const lib = @import("lib");
const Message = lib.Message;
const Character = lib.Character;
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
                    current_input.*.controllers[0].start = true;
                },
                8 => { // backspace
                    current_input.*.controllers[0].back = true;
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
    state.world.room = server_state;
    state.making_new_character = false;
    state.prompt_text = types.RenderableText.default();
    state.name_text = types.RenderableText.default();
    clearControllerInputs(state);

    const player_texture = c.IMG_LoadTexture(renderer, "/Users/tenari/code/combatrpg/sprite1.png") orelse return error.NullPlayerSprite;
    state.font = c.TTF_OpenFont("/Users/tenari/code/combatrpg/client/assets/edo.ttf", 30) orelse {
        std.debug.print("error {s}", .{c.TTF_GetError()});
        return error.TTFOpenFontError;
    };
    state.player = .{
        .character_id = 0,
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

pub fn update(state: *ClientState) !void {
    // cleanup/prep for next frame
    defer clearControllerInputs(state);
    defer state.frame += 1;

    const current_input = state.currentInput();

    if (state.making_new_character) {
        // currently 'start' is only meaningful in the context of making a character
        if (current_input.controllers[0].start) {
            const character_response = try lib.request_response(.{ .msg = Message.create_character, .data = &state.input_username }, state.sock, &state.server_address);
            std.debug.print("server character create response:\n{any}\n", .{character_response});
            if (character_response.msg == Message.no_character_slots_left) {
                // TODO: show error message saying that the server is full
            } else {
                std.debug.assert(character_response.msg == Message.character_created);
                state.making_new_character = false;
                const temp_char = Character.fromBytes(character_response.data[0..]);
                const char_id: usize = @intCast(temp_char.id);
                state.world.characters[char_id] = temp_char;
                state.player.character_id = temp_char.id;
                std.debug.print("me: {any}\n", .{state.world.characters[char_id].?});
            }
        }

        if (state.input_username[0] != 0 and current_input.controllers[0].back) {
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
        return;
    }

    // TODO: rollback/update state based on server snapshots. Gotta figure out how to read server snapshots

    var tried_to_change_world: bool = false;
    const player: *Entity = &state.player;
    if (state.world.characters[@intCast(player.character_id)]) |*char| {
        tried_to_change_world = char.attemptMoveFromInput(current_input.controllers[0].direction, &state.world.room);
    }

    // TODO: if the current_input is one that needs to be sent to the server, send it. This happens when our own prediction of the new state.world *might* be different. "Might be" because we can't assume that e.g. players blocking our path are actually still in the way. So essentially, if we had a user input state that was "trying" to affect the `state.world`, whether or not it actually did affect it (according to our simulation) we still need to send that input.
    if (tried_to_change_world) {
        const input_bytes = current_input.controllers[0].toBytes();
        var buffer: [20]u8 = undefined;
        @memcpy(buffer[0..input_bytes.len], input_bytes[0..]);
        var id_buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &id_buffer, player.character_id, std.builtin.Endian.little);
        @memcpy(buffer[input_bytes.len..], id_buffer[0..]);
        std.debug.print("tried_to_change_world sending {any}\n", .{buffer});
        _ = try lib.request(.{ .msg = Message.move, .data = &buffer }, state.sock, &state.server_address);
    }
}

pub fn render(renderer: *c.SDL_Renderer, state: *ClientState) !void {
    // sdl setup
    _ = c.SDL_RenderClear(renderer);

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

    // draw the map
    var dest: c.SDL_Rect = undefined;
    dest.w = types.TILE_SIZE;
    dest.h = types.TILE_SIZE;
    for (&state.world.room.tiles, 0..) |*tile, i| {
        if (tile.terrain == lib.Terrain.blank) {
            continue;
        }
        if (tile.terrain == lib.Terrain.wall) {
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 255, 0);
        } else {
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 0);
        }
        dest.x = @intCast((i % state.world.room.width) * types.TILE_SIZE);
        dest.y = @intCast((i / state.world.room.width) * types.TILE_SIZE);
        _ = c.SDL_RenderFillRect(renderer, &dest);
    }
    // draw the player
    const player: *Entity = &state.player;
    const point = player.screenLocation(state);
    dest.x = @intFromFloat(point.x);
    dest.y = @intFromFloat(point.y);
    //_ = c.SDL_QueryTexture(player.render.texture, 0, 0, &dest.w, &dest.h);
    _ = c.SDL_RenderCopy(renderer, player.render.texture, 0, &dest);
    //     _ = c.SDL_RenderCopy(renderer, zig_texture, null, null);
    c.SDL_RenderPresent(renderer);
}

fn clearControllerInputs(state: *ClientState) void {
    const current_input = state.currentInput();
    for (&current_input.controllers) |*controller| {
        controller.*.direction = .{ .x = 0.0, .y = 0.0 };
        controller.*.start = false;
        controller.*.back = false;
    }
}
