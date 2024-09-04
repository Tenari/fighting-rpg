const std = @import("std");
const posix = std.posix;
const expect = std.testing.expect;

pub const DEFAULT_SERVER_HOST = "127.0.0.1";
pub const DEFAULT_SERVER_PORT = 31173;

const MAX_PLAYERS: usize = 16;
const MAX_ROOMS: usize = 8;
const MAX_ITEMS: usize = 2048 * 2;
pub const Game = struct {
    players: [MAX_PLAYERS]?Player,
    characters: [MAX_PLAYERS]?Character,
    map: [MAX_ROOMS]Room,
    items: [MAX_ITEMS]?Item,

    pub fn init(self: *Game) void {
        for (0..MAX_PLAYERS) |i| {
            self.players[i] = null;
            self.characters[i] = null;
        }
        for (0..MAX_ROOMS) |i| {
            self.map[i] = Room.default(i);
        }
        self.map[0].setTilesFromBytes(@embedFile("map.txt"));
        for (0..MAX_ITEMS) |i| {
            self.items[i] = null;
        }
    }
};

const default: [16]u8 = [_]u8{0} ** 16;
const default64: [64]u8 = [_]u8{0} ** 64;

pub const Player = struct {
    username: [16]u8 = default,
    pw_hash: [64]u8 = default64,
    salt: u8,
    character: *Character,
    last_sign_in_at: u128 = 0,
    allowed_source: std.net.Address,
};

const MAX_ROOM_SIZE: usize = 256;
pub const RoomId = usize;
pub const Room = struct {
    id: RoomId,
    tiles: [MAX_ROOM_SIZE]Tile,
    height: usize,
    width: usize,

    pub fn default(id: RoomId) Room {
        return .{
            .id = id,
            .tiles = [_]Tile{Tile.default(id)} ** MAX_ROOM_SIZE,
            .height = 0,
            .width = 0,
        };
    }

    pub fn setTilesFromBytes(self: Room, bytes: []u8) Room {
        var i: usize = 0;
        for (bytes) |byte| {
            switch (byte) {
                119 => { // w = wall
                    self.tiles[i].terrain = Terrain.wall;
                    i += 1;
                },
                10 => { // newline
                    // intentionally don't update `i` here
                },
                else => {
                    i += 1;
                },
            }
        }
    }

    pub fn get(self: Room, location: Location) *Tile {
        const access = (location.y * self.width) + location.x;
        return &self.tiles[access];
    }
};

const MAX_ITEMS_PER_TILE = 256;
const MAX_CHARACTERS_PER_TILE = 4;
pub const Tile = struct {
    parent_id: RoomId,
    terrain: Terrain,
    connect: ?*Tile, // when a character/NPC steps on this tile, they are auto-warped to the other tile, for things like doors

    fn default(id: RoomId) Tile {
        return .{
            .parent_id = id,
            .terrain = Terrain.blank,
            .connect = null,
        };
    }
};

pub const Item = struct {
    class: ItemClass,
    damage: u8,
    qi: u32,
};
pub const ItemClass = enum { weapon, material, qistal };

pub const Npc = enum { squirrel, wolf, bear, teacher };

pub const Terrain = enum { blank, dirt, grass1, grass2, grass3, grass4, path_north, sand, water, exit, wall };

pub const Realm = enum { earthly, metallic, precious, heavenly };
pub const EarthlyStage = enum { dirt, clay, wood, stone };
pub const MetallicStage = enum { copper, bronze, iron, steel };
pub const PreciousStage = enum { jade, silver, gold, diamond };
pub const HeavenlyStage = enum { cloud, moon, sun, star };
pub const Stage = enum {
    earthly_dirt,
    earthly_clay,
    earthly_wood,
    earthly_stone,
    metallic_copper,
    metallic_bronze,
    metallic_iron,
    metallic_steel,
    precious_jade,
    precious_silver,
    precious_gold,
    precious_diamond,
    heavenly_cloud,
    heavenly_moon,
    heavenly_sun,
    heavenly_star,
};
pub const Race = enum { human, rat, ox, tiger, rabbit, dragon, snake, horse, sheep, monkey, rooster, dog, pig };

pub const Location = struct {
    x: u32,
    y: u32,
    room: RoomId,
};
pub const Character = struct {
    name: []const u8 = "",
    race: Race,
    realm: Realm = Realm.earthly,
    stage: Stage = Stage.earthly_dirt,
    level: u2 = 0,
    location: Location,

    pub fn init(name: []const u8, race: Race) Character {
        return Character{
            .name = name,
            .race = race,
        };
    }
};

/// send an Input to the server, and receive an Input back
pub fn request_response(input: Input, s: posix.socket_t, addr: *std.net.Address) !Input {
    // make the message as array of bytes
    var buffer: [1024]u8 = undefined;
    buffer[0] = @intFromEnum(input.msg);
    const input_buf_len = input.data.len + 1;
    if (input.data.len > 0) {
        @memcpy(buffer[1..input_buf_len], input.data);
    }
    // send it
    var addr_len = addr.getOsSockLen();
    _ = try posix.sendto(s, buffer[0..input_buf_len], 0, &addr.*.any, addr_len);
    // get response (overwriting buffer)
    const byte_count = try posix.recvfrom(s, buffer[0..], 0, &addr.*.any, &addr_len);
    const msg_type: Message = @enumFromInt(buffer[0]);
    return .{ .msg = msg_type, .data = buffer[1..byte_count] };
}

pub const Input = struct {
    msg: Message,
    data: []u8,
};

pub const Message = enum(u8) {
    // server responses
    pub_key_is,
    // server-public messages
    sign_up,
    get_pub_key,
    update_player_source, // so the server knows the IP/connection-info allowed to control this player. must provide player_id and `proof` of ownership of that id. This is essentially our 'sign in' message
    // server-player-whitelist messages (only allowed to come from proven owners of a player)
    get_local_state, // asking for current state "around" the player for client to render
    create_character,
    move,
    clear_player_source, // server "signs out" the player
};
