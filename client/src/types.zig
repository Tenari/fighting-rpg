pub const c = @cImport({
    //@cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_custom.h");
});
const lib = @import("lib");

pub const TILE_SIZE = 32;
pub const ClientState = struct {
    input_username: [64]u8 = [_]u8{0} ** 64,
    making_new_character: bool = false,
    player: Entity,
    in_combat: bool = false,
    room: lib.Room,
    font: *c.TTF_Font,
    prompt_text_texture: ?*c.SDL_Texture,
    need_to_update_name_text_texture: bool,
    name_text_texture: ?*c.SDL_Texture,
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
pub const Coord = struct {};
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
