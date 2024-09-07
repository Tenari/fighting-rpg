const std = @import("std");
const posix = std.posix;
const Address = std.net.Address;
pub const c = @cImport({
    //@cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_custom.h");
});
const lib = @import("lib");

pub const RenderableText = struct {
    texture: ?*c.SDL_Texture,
    width: c_int,
    height: c_int,

    pub fn default() RenderableText {
        return .{ .texture = null, .width = 0, .height = 0 };
    }
};

pub const TILE_SIZE = 32;
pub const INPUT_HISTORY_LEN = 64;
pub const ClientState = struct {
    sock: posix.socket_t,
    server_address: Address,
    frame: u64 = 0,
    should_quit: bool,
    input_history: [INPUT_HISTORY_LEN]AllInputSnapshot,
    input_username: [lib.MAX_USERNAME_SIZE]u8 = [_]u8{0} ** lib.MAX_USERNAME_SIZE,
    making_new_character: bool = false,
    player: Entity,
    in_combat: bool = false,
    room: lib.Room,
    font: *c.TTF_Font,
    prompt_text: RenderableText,
    need_to_update_name_text_texture: bool,
    name_text: RenderableText,

    pub fn currentInput(self: *ClientState) *AllInputSnapshot {
        return &self.input_history[self.frame % INPUT_HISTORY_LEN];
    }
};
pub const Entity = struct {
    location: WorldLocation,
    render: RenderInfo,

    pub fn screenLocation(self: Entity) Point {
        // TODO implement
        return .{
            .x = @floatFromInt(self.location.x * TILE_SIZE),
            .y = @floatFromInt(self.location.y * TILE_SIZE),
        };
    }
};
pub const RenderInfo = struct {
    texture: *c.SDL_Texture,
};
pub const WorldLocation = struct {
    room_id: u32,
    x: u16,
    y: u16,

    pub fn default() WorldLocation {
        return .{
            .room_id = 0,
            .x = 1,
            .y = 1,
        };
    }
};
pub const Point = struct {
    x: f64,
    y: f64,
};
pub const ControllerInputSnapshot = struct {
    direction: Point,
    secondary_direction: Point,
    a: bool,
    b: bool,
    jump: bool,
    defense: bool,
    start: bool,
    back: bool,
    key: i32, // character byte where 97 = 'a'
};
pub const MouseInputSnapshot = struct {
    location: Point,
    mouseWheel: f64,
    buttons: [5]bool,
};
pub const AllInputSnapshot = struct {
    mouse: MouseInputSnapshot,
    controllers: [5]ControllerInputSnapshot,
};
