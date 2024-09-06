const std = @import("std");
const lib = @import("lib");
const types = @import("types.zig");
const c = types.c;
const Entity = types.Entity;
const ClientState = types.ClientState;

pub fn initClientState(allocator: std.mem.Allocator, server_state: lib.Room, renderer: *c.SDL_Renderer) !*ClientState {
    var state = try allocator.create(ClientState);
    const player_texture = c.IMG_LoadTexture(renderer, "/Users/tenari/code/combatrpg/sprite1.png") orelse return error.NullPlayerSprite;
    state.player = .{
        .location = types.WorldLocation.default(),
        .render = .{
            .texture = player_texture,
        },
    };
    state.in_combat = false;
    state.room = server_state;
    return state;
}

pub fn gameUpdateAndRender(renderer: *c.SDL_Renderer, state: *ClientState, input: *types.AllInputSnapshot) !void {
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
