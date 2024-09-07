const std = @import("std");
const lib = @import("lib");
const types = @import("types.zig");
const c = types.c;
const Entity = types.Entity;
const ClientState = types.ClientState;

pub fn initClientState(allocator: std.mem.Allocator, server_state: lib.Room, renderer: *c.SDL_Renderer) !*ClientState {
    var state = try allocator.create(ClientState);
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
    state.input_username = [_]u8{0} ** 64;
    state.in_combat = false;
    state.room = server_state;
    state.making_new_character = false;
    state.prompt_text_texture = null;
    state.name_text_texture = null;
    return state;
}

pub fn makeTextTexture(font: *c.TTF_Font, font_color: c.SDL_Color, renderer: *c.SDL_Renderer, text: []const u8) !*c.SDL_Texture {
    const text_surface = c.TTF_RenderText_Solid(font, @ptrCast(text), font_color) orelse {
        std.debug.print("error {s}", .{c.TTF_GetError()});
        return error.TTFOpenFontError;
    };
    defer c.SDL_FreeSurface(text_surface);
    return c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
        std.debug.print("error {s}", .{c.TTF_GetError()});
        return error.TTFOpenFontError;
    };
}

pub fn gameUpdateAndRender(renderer: *c.SDL_Renderer, state: *ClientState, input: *types.AllInputSnapshot) !void {
    if (state.making_new_character) {
        var font_color: c.SDL_Color = undefined;
        font_color.r = 0;
        font_color.g = 0;
        font_color.b = 0;
        font_color.a = 0;

        if (state.prompt_text_texture == null) {
            state.prompt_text_texture =
                try makeTextTexture(state.font, font_color, renderer, "Enter your name");
        }

        var dest: c.SDL_Rect = undefined;
        dest.w = 400;
        dest.h = 30;
        dest.x = 50;
        dest.y = 50;

        // sdl setup
        _ = c.SDL_RenderClear(renderer);

        // render the new character ui
        _ = c.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
        _ = c.SDL_RenderCopyEx(renderer, state.prompt_text_texture.?, null, &dest, 0.0, null, c.SDL_FLIP_NONE);
        if (state.input_username[0] != 0) {
            var name_dest: c.SDL_Rect = dest;
            name_dest.y += 100;
            if (state.need_to_update_name_text_texture) {
                state.name_text_texture =
                    try makeTextTexture(state.font, font_color, renderer, &state.input_username);
            }
            if (state.name_text_texture) |texture| {
                _ = c.SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
                _ = c.SDL_RenderCopyEx(renderer, texture, null, &name_dest, 0.0, null, c.SDL_FLIP_NONE);
            }
            state.need_to_update_name_text_texture = false;
        }

        // sdl finish
        return c.SDL_RenderPresent(renderer);
    }

    // update
    const player: *Entity = &state.player;
    const old_x = player.location.x;
    const old_y = player.location.y;
    if (input.*.controllers[0].direction.x > 0) {
        player.location.x += 1;
    }
    if (input.*.controllers[0].direction.x < 0 and player.location.x > 0) {
        player.location.x -= 1;
    }
    if (input.*.controllers[0].direction.y > 0) {
        player.location.y += 1;
    }
    if (input.*.controllers[0].direction.y < 0 and player.location.y > 0) {
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
}
