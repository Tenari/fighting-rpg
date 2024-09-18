const std = @import("std");
const posix = std.posix;
const Address = std.net.Address;
pub const c = @cImport({
    //@cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_custom.h");
});
const lib = @import("lib");
const Packet = lib.Packet;
const Character = lib.Character;
const Point = lib.Point;
const ArrayList = std.array_list.ArrayList;

pub const RenderableText = struct {
    texture: ?*c.SDL_Texture,
    width: c_int,
    height: c_int,

    pub fn default() RenderableText {
        return .{ .texture = null, .width = 0, .height = 0 };
    }
};

const LocalWorld = struct {
    characters: [lib.MAX_CHARACTERS]?Character,
    room: lib.Room,
};

pub const TILE_SIZE = 32;
pub const INPUT_HISTORY_LEN = 64;
pub const MAX_QUEUED_REQUESTS = 8;
pub const ClientState = struct {
    // "public" state which mirrors what's on the server
    world: LocalWorld,

    // "private" state which is just for the client's own purposes
    outgoing_requests: [MAX_QUEUED_REQUESTS]?Packet,
    incoming_response: ?Packet,
    response_condition: std.Thread.Condition,
    response_mutex: std.Thread.Mutex,
    sock: posix.socket_t,
    server_address: Address,

    frame: u64 = 0,
    should_quit: bool,
    input_history: [INPUT_HISTORY_LEN]AllInputSnapshot,
    input_username: [lib.MAX_USERNAME_SIZE]u8 = [_]u8{0} ** lib.MAX_USERNAME_SIZE,
    making_new_character: bool = false,
    waiting_on_character_create_response: bool = false,
    player: Entity,
    in_combat: bool = false,
    font: *c.TTF_Font,
    prompt_text: RenderableText,
    need_to_update_name_text_texture: bool,
    name_text: RenderableText,

    pub fn currentInput(self: *ClientState) *AllInputSnapshot {
        return &self.input_history[self.frame % INPUT_HISTORY_LEN];
    }

    pub fn addRequest(self: *ClientState, r: Packet) void {
        for (&self.outgoing_requests) |*maybe_req| {
            if (maybe_req.* == null) {
                maybe_req.* = r;
                break;
            }
        }
    }
};
pub const Entity = struct {
    character_id: lib.CharacterId,
    render: RenderInfo,

    pub fn screenLocation(self: Entity, state: *ClientState) Point {
        if (state.world.characters[@intCast(self.character_id)]) |character| {
            return .{
                .x = @floatFromInt(character.location.x * TILE_SIZE),
                .y = @floatFromInt(character.location.y * TILE_SIZE),
            };
        } else {
            return .{
                .x = 0.0,
                .y = 0.0,
            };
        }
    }
};
pub const RenderInfo = struct {
    texture: *c.SDL_Texture,
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
