const c = @cImport({
    @cInclude("SDL2/SDL_image.h");
});
pub const TILE_SIZE = 32;
pub const ClientState = struct {
    player: Entity,
    in_combat: bool,
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
            .x = 0,
            .y = 0,
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
