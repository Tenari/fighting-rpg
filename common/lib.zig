const std = @import("std");
const posix = std.posix;
const expect = std.testing.expect;

pub const DEFAULT_SERVER_HOST = "127.0.0.1";
pub const DEFAULT_SERVER_PORT = 31173;

pub const MAX_CHARACTERS: usize = 16;
const MAX_ROOMS: usize = 8;
const MAX_ITEMS: usize = 2048 * 2;
pub const Game = struct {
    characters: [MAX_CHARACTERS]?Character,
    map: [MAX_ROOMS]Room,
    items: [MAX_ITEMS]?Item,

    pub fn init(self: *Game) void {
        for (0..MAX_CHARACTERS) |i| {
            self.characters[i] = null;
        }
        for (0..MAX_ROOMS) |i| {
            self.map[i] = Room.default(@intCast(i));
        }
        self.map[0].setTilesFromBytes(@embedFile("map.txt"));
        for (0..MAX_ITEMS) |i| {
            self.items[i] = null;
        }
    }
};

const MAX_ROOM_SIZE: usize = 32 * 32;
pub const RoomId = u32;
pub const Room = struct {
    id: RoomId,
    tiles: [MAX_ROOM_SIZE]Tile,
    height: u32,
    width: u32,

    pub fn default(id: RoomId) Room {
        return .{
            .id = id,
            .tiles = [_]Tile{Tile.default(id)} ** MAX_ROOM_SIZE,
            .height = 0,
            .width = 0,
        };
    }

    pub fn setTilesFromBytes(self: *Room, bytes: []const u8) void {
        var i: u32 = 0;
        for (bytes) |byte| {
            std.debug.print("{d}", .{byte});
            switch (byte) {
                119 => { // w = wall
                    self.tiles[i].index = i;
                    self.tiles[i].terrain = Terrain.wall;
                    i += 1;
                },
                32 => { // space = dirt
                    self.tiles[i].index = i;
                    self.tiles[i].terrain = Terrain.dirt;
                    i += 1;
                },
                10 => { // newline
                    // intentionally don't update `i` here
                    std.debug.print("\n", .{});
                    if (self.width == 0) {
                        self.width = i;
                    }
                    self.height += 1;
                },
                else => {
                    i += 1;
                },
            }
        }
    }

    pub fn get(self: *Room, location: Location) *Tile {
        const access = (location.y * self.width) + location.x;
        return &self.tiles[access];
    }

    pub fn toBytes(self: *Room) []u8 {
        var id_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &id_bytes, self.id, std.builtin.Endian.little);
        var height: [4]u8 = undefined;
        std.mem.writeInt(u32, &height, self.height, std.builtin.Endian.little);
        var width: [4]u8 = undefined;
        std.mem.writeInt(u32, &width, self.width, std.builtin.Endian.little);
        var tile_bytes: [MAX_ROOM_SIZE]u8 = undefined;
        var last_valid_tile: usize = 0;
        for (&self.tiles, 0..) |*tile, i| {
            tile_bytes[i] = tile.asByte();
            if (tile.terrain != Terrain.blank) {
                last_valid_tile = i;
            }
        }

        const hilen = id_bytes.len + height.len;
        const wilen = hilen + width.len;
        const finalen = wilen + last_valid_tile;
        var bytes: [wilen + MAX_ROOM_SIZE]u8 = undefined;
        @memcpy(bytes[0..id_bytes.len], id_bytes[0..]);
        @memcpy(bytes[id_bytes.len..hilen], height[0..]);
        @memcpy(bytes[hilen..wilen], width[0..]);
        @memcpy(bytes[wilen..finalen], tile_bytes[0..last_valid_tile]);
        return bytes[0..finalen];
    }
};

const MAX_ITEMS_PER_TILE = 256;
pub const Tile = struct {
    parent_id: RoomId,
    index: u32,
    terrain: Terrain,
    connect: ?u32, // when a character/NPC steps on this tile, they are auto-warped to the other tile, for things like doors

    fn default(id: RoomId) Tile {
        return .{
            .parent_id = id,
            .index = 0,
            .terrain = Terrain.blank,
            .connect = null,
        };
    }

    pub fn asByte(self: *Tile) u8 {
        switch (self.terrain) {
            .wall => {
                return 119;
            },
            .dirt => {
                return 32;
            },
            else => {
                return 0;
            },
        }
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

pub const Point = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,

    pub fn default() Point {
        return .{};
    }
};
pub const Location = struct {
    room_id: RoomId = 0,
    x: u16 = 1,
    y: u16 = 1,

    pub fn default() Location {
        return .{};
    }
};
pub const MAX_USERNAME_SIZE = 32;
pub const Character = struct {
    id: u32 = 0,
    username: [MAX_USERNAME_SIZE]u8 = [_]u8{0} ** MAX_USERNAME_SIZE,
    name: []const u8 = "", // TODO: allow username/name distinction?
    race: Race,
    realm: Realm = Realm.earthly,
    stage: Stage = Stage.earthly_dirt,
    level: u6 = 0,
    location: Location,
    allowed_source: posix.sockaddr,
    //    pw_hash: [64]u8 = [_]u8{0} ** 64,
    //    salt: u8,
    //    character: *Character,
    //    last_sign_in_at: u128 = 0,

    pub fn init(username: *[MAX_USERNAME_SIZE]u8, race: Race) Character {
        return Character{
            .username = username.*,
            .race = race,
            .location = Location.default(),
            .allowed_source = undefined,
        };
    }

    pub fn toBytes(self: *Character) []u8 {
        var id_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &id_bytes, self.id, std.builtin.Endian.little);

        //TODO: name, race, realm, stage, level serialization
        var location: [4 + 2 + 2]u8 = undefined;
        std.mem.writeInt(RoomId, location[0..4], self.location.room_id, std.builtin.Endian.little);
        std.mem.writeInt(@TypeOf(self.location.x), location[4..6], self.location.x, std.builtin.Endian.little);
        std.mem.writeInt(@TypeOf(self.location.y), location[6..], self.location.y, std.builtin.Endian.little);

        const ulen = id_bytes.len + self.username.len;
        const loclen = ulen + location.len;

        var bytes: [loclen]u8 = undefined;
        @memcpy(bytes[0..id_bytes.len], id_bytes[0..]);
        @memcpy(bytes[id_bytes.len..ulen], self.username[0..]);
        @memcpy(bytes[ulen..loclen], &location);
        return bytes[0..loclen];
    }

    pub fn fromBytes(bytes: []u8) Character {
        var c: Character = undefined;
        // defaults
        c.name = "";
        c.race = Race.human;
        c.realm = Realm.earthly;
        c.stage = Stage.earthly_dirt;
        c.level = 0;
        // id deserialization
        c.id = std.mem.readInt(u32, bytes[0..4], std.builtin.Endian.little);
        // username deserialization
        const uei = MAX_USERNAME_SIZE + 4;
        @memcpy(&c.username, bytes[4..uei]);
        // location deserialization
        const rei = uei + 4;
        c.location.room_id = std.mem.readInt(u32, bytes[uei..rei], std.builtin.Endian.little);
        const xei = rei + 2;
        c.location.x = std.mem.readInt(u16, bytes[rei..xei], std.builtin.Endian.little);
        const yei = xei + 2;
        c.location.y = std.mem.readInt(u16, bytes[xei..yei], std.builtin.Endian.little);

        return c;
    }
};

/// send an Input to the server
pub fn request(input: Input, s: posix.socket_t, addr: *std.net.Address) !posix.socklen_t {
    // make the message as array of bytes
    var buffer: [1024 * 32]u8 = undefined;
    buffer[0] = @intFromEnum(input.msg);
    const input_buf_len = input.data.len + 1;
    if (input.data.len > 0) {
        @memcpy(buffer[1..input_buf_len], input.data);
    }
    // send it
    const addr_len = addr.getOsSockLen();
    _ = try posix.sendto(s, buffer[0..input_buf_len], 0, &addr.*.any, addr_len);
    return addr_len;
}

/// send an Input to the server, and receive an Input back
pub fn request_response(input: Input, s: posix.socket_t, addr: *std.net.Address) !Input {
    var buffer: [1024 * 32]u8 = undefined;
    var addr_len = try request(input, s, addr);
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
    state_is,
    character_created,
    no_character_slots_left,
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
