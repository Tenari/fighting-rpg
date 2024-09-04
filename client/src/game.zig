const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL_image.h");
});
const lib = @import("lib");
const types = @import("types.zig");
const Entity = types.Entity;
const ClientState = types.ClientState;

pub fn initClientState(allocator: std.mem.Allocator, server_state: *lib.Game, renderer: *c.SDL_Renderer) !*ClientState {
    _ = &server_state;
    var state = try allocator.create(ClientState);
    const player_texture = c.IMG_LoadTexture(renderer, "/Users/tenari/code/combatrpg/sprite1.png") orelse return error.NullPlayerSprite;
    state.player = .{
        .location = types.WorldLocation.default(),
        .render = .{
            .texture = player_texture,
        },
    };
    state.in_combat = false;
    return state;
}

pub fn gameUpdateAndRender(renderer: *c.SDL_Renderer, state: *ClientState, input: *types.AllInputSnapshot) !void {
    // update
    const player: *Entity = &state.player;
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

    // render
    _ = c.SDL_RenderClear(renderer);
    var dest: c.SDL_Rect = undefined;
    const point = player.screenLocation();
    dest.x = @intFromFloat(point.x);
    dest.y = @intFromFloat(point.y);
    _ = c.SDL_QueryTexture(player.render.texture, 0, 0, &dest.w, &dest.h);
    _ = c.SDL_RenderCopy(renderer, player.render.texture, 0, &dest);
    //     _ = c.SDL_RenderCopy(renderer, zig_texture, null, null);
    c.SDL_RenderPresent(renderer);
}
