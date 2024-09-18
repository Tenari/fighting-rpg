const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const expect = std.testing.expect;

pub const DEFAULT_SERVER_HOST = "127.0.0.1";
pub const DEFAULT_SERVER_PORT = 31173;

pub const MAX_CHARACTERS: usize = 16;
const MAX_ROOMS: usize = 8;
const RESERVED_TILE_COUNT = 1024 * MAX_ROOMS; // reserve 32x32 tiles per room
//const MAX_ITEMS: usize = 2; //2048 * 2;
pub const Game = struct {
    characters: [MAX_CHARACTERS]?Character,
    map: [MAX_ROOMS]Room,
    //items: [MAX_ITEMS]?Item,
    tiles: [RESERVED_TILE_COUNT]Tile,

    pub fn init(self: *Game) void {
        for (0..MAX_CHARACTERS) |i| {
            self.characters[i] = null;
        }
        for (0..MAX_ROOMS) |i| {
            self.map[i] = Room.default(@intCast(i));
        }
        const map = @embedFile("map.txt");
        self.map[0].tiles = self.tiles[0..map.len];
        self.map[0].setTilesFromBytes(map);
        //for (0..MAX_ITEMS) |i| {
        //    self.items[i] = null;
        //}
    }
};

pub const RoomId = u32;
pub const Room = struct {
    id: RoomId,
    tiles: []Tile,
    height: u32,
    width: u32,

    pub fn default(id: RoomId) Room {
        return .{
            .id = id,
            .tiles = &.{},
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
                    self.tiles[i].parent_id = self.id;
                    self.tiles[i].index = i;
                    self.tiles[i].terrain = Terrain.wall;
                    i += 1;
                },
                32 => { // space = dirt
                    self.tiles[i].parent_id = self.id;
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
        self.tiles.len = i;
    }

    pub fn get(self: *Room, location: Location) *Tile {
        const access = (location.y * self.width) + location.x;
        return &self.tiles[access];
    }
};

pub const Tile = struct {
    parent_id: RoomId,
    index: u32,
    terrain: Terrain,
    //connect: ?u32, // when a character/NPC steps on this tile, they are auto-warped to the other tile, for things like doors

    pub fn default(id: RoomId) Tile {
        return .{
            .parent_id = id,
            .index = 0,
            .terrain = Terrain.blank,
            //.connect = null,
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
pub const Terrain = enum(u8) { blank, dirt, grass1, grass2, grass3, grass4, path_north, sand, water, exit, wall };
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

pub const MoveCommand = struct {
    character_id: CharacterId,
    point: Point,
};
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
pub const CharacterId = u32;
pub const Character = struct {
    id: CharacterId = 0,
    username: [MAX_USERNAME_SIZE]u8 = [_]u8{0} ** MAX_USERNAME_SIZE,
    //    name: []const u8 = "", // TODO: allow username/name distinction?
    race: Race,
    realm: Realm = Realm.earthly,
    stage: Stage = Stage.earthly_dirt,
    level: u8 = 0,
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

    pub fn attemptMoveFromInput(self: *Character, p: Point, room: *Room) bool {
        var tried_to_change_world: bool = false;
        const old_x = self.location.x;
        const old_y = self.location.y;
        if (p.x > 0.01) {
            std.debug.print("moving right\n", .{});
            self.location.x += 1;
            tried_to_change_world = true;
        }
        if (p.x < -0.01 and self.location.x > 0) {
            std.debug.print("moving left\n", .{});
            self.location.x -= 1;
            tried_to_change_world = true;
        }
        if (p.y > 0.01) {
            std.debug.print("moving down\n", .{});
            self.location.y += 1;
            tried_to_change_world = true;
        }
        if (p.y < -0.01 and self.location.y > 0) {
            std.debug.print("moving up\n", .{});
            self.location.y -= 1;
            tried_to_change_world = true;
        }
        const new_tile = room.get(.{ .x = self.location.x, .y = self.location.y });
        if (new_tile.terrain == Terrain.wall) {
            self.location.x = old_x;
            self.location.y = old_y;
        }
        return tried_to_change_world;
    }
};

/// send a Packet to the server
pub fn request(packet: Packet, s: posix.socket_t, addr: *std.net.Address) !posix.socklen_t {
    // make the message as array of bytes
    var buffer: [1024 * 32]u8 = undefined;
    buffer[0] = @intFromEnum(packet.msg);
    const buf_len = packet.data.len + 1;
    if (packet.data.len > 0) {
        @memcpy(buffer[1..buf_len], packet.data);
    }
    // send it
    const addr_len = addr.getOsSockLen();
    _ = try posix.sendto(s, buffer[0..buf_len], 0, &addr.*.any, addr_len);
    return addr_len;
}

/// send a Packet to the server, and receive a Packet back
pub fn request_response(allocator: Allocator, packet: Packet, s: posix.socket_t, addr: *std.net.Address) !Packet {
    var addr_len = try request(packet, s, addr);
    return try receive(allocator, s, addr, &addr_len);
}

pub fn receive(allocator: Allocator, s: posix.socket_t, addr: *std.net.Address, addr_len: *posix.socklen_t) !Packet {
    var buffer: [1024 * 32]u8 = undefined;
    const byte_count = try posix.recvfrom(s, buffer[0..], 0, &addr.*.any, addr_len);
    const msg_type: Message = @enumFromInt(buffer[0]);
    var result = Packet.init(allocator, msg_type, &.{});
    if (byte_count > 1) {
        try result.addData(buffer[1..byte_count]);
    }
    return result;
}

pub fn receiveInto(buffer: []u8, s: posix.socket_t, addr: *std.net.Address, addr_len: *posix.socklen_t) !Packet {
    const byte_count = try posix.recvfrom(s, buffer[0..], 0, &addr.*.any, addr_len);
    const msg_type: Message = @enumFromInt(buffer[0]);
    var slice: []u8 = &.{};
    if (byte_count > 1) {
        slice = buffer[1..byte_count];
    }
    return Packet{
        .msg = msg_type,
        .data = slice,
    };
}

pub const Packet = struct {
    const Self = @This();
    msg: Message,
    data: []u8,
    allocator: ?Allocator = null,

    pub fn init(allocator: Allocator, msg: Message, data: []u8) Self {
        return .{ .allocator = allocator, .msg = msg, .data = data };
    }

    pub fn deinit(self: *Self) void {
        if (self.allocator) |alloc| {
            alloc.free(self.data);
        }
    }

    // allocates and copies the given data
    pub fn addData(self: *Self, data: []u8) !void {
        if (self.allocator) |alloc| {
            self.data = try alloc.alloc(u8, data.len);
            @memcpy(self.data, data);
        } else {
            return error.AllocatorNotDefined;
        }
    }
};

pub const Message = enum(u8) {
    // server "push" messages
    snapshot,
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

pub const Snapshot = struct {
    room: Room,
    characters: []Character,
};

test Serializer {
    const size = 16 + 4 + (4 * 2 * 3);
    var bytes: [size]u8 = [_]u8{0} ** size;

    const En = enum(u2) { zero, one, two, three };
    var s = Serializer.init(&bytes);
    s.write(En, En.one);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    const read_val: En = @enumFromInt(std.mem.readInt(u8, bytes[0..1], std.builtin.Endian.little));
    try std.testing.expect(En.one == read_val);

    s = Serializer.init(&bytes);
    s.write(u16, 245);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    try std.testing.expect(245 == std.mem.readInt(u16, bytes[0..2], std.builtin.Endian.little));

    s = Serializer.init(&bytes);
    s.write(i32, -245);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    try std.testing.expect(-245 == std.mem.readInt(i32, bytes[0..4], std.builtin.Endian.little));

    s = Serializer.init(&bytes);
    s.write(f32, -245.6);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    try std.testing.expect(-245.6 == std.mem.littleToNative(f32, std.mem.bytesToValue(f32, bytes[0..4])));

    const Str = struct { a: i32, b: f64 };
    s = Serializer.init(&bytes);
    s.write(Str, Str{ .a = -1, .b = 0.5 });
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    try std.testing.expect(-1 == std.mem.readInt(i32, bytes[0..4], std.builtin.Endian.little));
    try std.testing.expect(0.5 == std.mem.littleToNative(f64, std.mem.bytesToValue(f64, bytes[4..12])));

    const Str2 = struct { a: u8, b: Str };
    s = Serializer.init(&bytes);
    s.write(Str2, Str2{ .a = 100, .b = .{ .a = 1024, .b = -101.101 } });
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    try std.testing.expect(100 == std.mem.readInt(u8, bytes[0..1], std.builtin.Endian.little));

    s = Serializer.init(&bytes);
    const array = [2]Str2{ Str2{ .a = 100, .b = .{ .a = 1024, .b = -101.101 } }, Str2{ .a = 100, .b = .{ .a = 1024, .b = -101.101 } } };
    s.write([]const Str2, array[0..]);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    try std.testing.expect(2 == std.mem.readInt(u32, bytes[0..4], std.builtin.Endian.little));
    try std.testing.expect(100 == std.mem.readInt(u8, bytes[4..5], std.builtin.Endian.little));
}
pub const Serializer = struct {
    const Self = @This();
    index: usize,
    into: []u8,

    pub fn init(into: []u8) Self {
        return .{ .index = 0, .into = into };
    }

    fn writeInt(self: *Self, comptime T: type, value: T, info: std.builtin.Type.Int) void {
        var bytes: usize = info.bits / 8 + 1;
        if (info.bits % 8 == 0) {
            bytes = info.bits / 8;
        }
        @memcpy(self.into[self.index .. self.index + bytes], std.mem.asBytes(&std.mem.nativeToLittle(T, value)));
        self.index += bytes;
    }

    fn writeFloat(self: *Self, comptime T: type, value: T, info: std.builtin.Type.Float) void {
        var bytes: usize = info.bits / 8 + 1;
        if (info.bits % 8 == 0) {
            bytes = info.bits / 8;
        }
        @memcpy(self.into[self.index .. self.index + bytes], std.mem.asBytes(&std.mem.nativeToLittle(T, value)));
        self.index += bytes;
    }

    fn writeEnum(self: *Self, comptime T: type, value: T, info: std.builtin.Type.Enum) void {
        switch (@typeInfo(info.tag_type)) {
            .Int => |tag_info| {
                var bytes: usize = tag_info.bits / 8 + 1;
                if (tag_info.bits % 8 == 0) {
                    bytes = tag_info.bits / 8;
                }
                @memcpy(self.into[self.index .. self.index + bytes], std.mem.asBytes(&std.mem.nativeToLittle(info.tag_type, @intFromEnum(value))));
                self.index += bytes;
            },
            else => @compileError("unsupported type"),
        }
    }

    fn writeStruct(self: *Self, comptime T: type, obj: T) void {
        const fields = std.meta.fields(T);
        inline for (fields) |field| {
            self.write(field.type, @field(obj, field.name));
        }
    }

    fn writeArray(self: *Self, comptime T: type, arr: T, info: std.builtin.Type.Array) void {
        for (arr) |item| {
            self.write(info.child, item);
        }
    }

    pub fn write(self: *Self, comptime T: type, value: T) void {
        switch (@typeInfo(T)) {
            .Int => |info| self.writeInt(T, value, info),
            .Float => |info| self.writeFloat(T, value, info),
            .Enum => |info| self.writeEnum(T, value, info),
            .Struct => self.writeStruct(T, value),
            .Array => |info| self.writeArray(T, value, info),
            .Pointer => |ptr| {
                switch (ptr.size) {
                    // TODO: make this work for more than just slices of structs
                    .Slice => {
                        std.mem.writeInt(u32, @ptrCast(self.into[self.index .. self.index + 4]), @intCast(value.len), std.builtin.Endian.little);
                        self.index += 4;
                        for (value) |item| {
                            self.write(ptr.child, item);
                        }
                    },
                    else => @compileError("unsupported pointer serializtion attempt"),
                }
            },
            else => @compileError("unsupported type"),
        }
    }
};

test Deserializer {
    const size = 16 + 4 + (4 * 2 * 3);
    var bytes: [size]u8 = [_]u8{0} ** size;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // int
    var s = Serializer.init(&bytes);
    s.write(u16, 123);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    var d = Deserializer.init(allocator, &bytes);
    try std.testing.expect(123 == try d.read(u16));

    // float
    s = Serializer.init(&bytes);
    s.write(f32, 123.123);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    d = Deserializer.init(allocator, &bytes);
    try std.testing.expect(123.123 == try d.read(f32));

    // enum
    const En = enum(u2) { zero, one, two, three };
    s = Serializer.init(&bytes);
    s.write(En, En.one);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    d = Deserializer.init(allocator, &bytes);
    try std.testing.expect(En.one == try d.read(En));

    // struct
    const Str = struct { a: i32, b: f64 };
    s = Serializer.init(&bytes);
    const example = Str{ .a = -1, .b = 0.5 };
    s.write(Str, example);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    d = Deserializer.init(allocator, &bytes);
    const result = try d.read(Str);
    try std.testing.expect(example.a == result.a);
    try std.testing.expect(example.b == result.b);

    // slice
    s = Serializer.init(&bytes);
    const array = [2]Str{ Str{ .a = 100, .b = -101.101 }, Str{ .a = 100, .b = -101.101 } };
    s.write([]const Str, array[0..]);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    d = Deserializer.init(allocator, &bytes);
    const slice_result = try d.read([]const Str);
    try std.testing.expect(slice_result.len == array.len);
    try std.testing.expect(slice_result[0].a == array[0].a);
    try std.testing.expect(slice_result[0].b == array[0].b);
}
test "Serialize and Deserialize a Room" {
    var bytes: [1024]u8 = [_]u8{0} ** 1024;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var tiles: [4]Tile = [_]Tile{
        .{
            .parent_id = 100,
            .index = 0,
            .terrain = Terrain.dirt,
        },
        .{
            .parent_id = 100,
            .index = 1,
            .terrain = Terrain.dirt,
        },
        .{
            .parent_id = 100,
            .index = 2,
            .terrain = Terrain.dirt,
        },
        .{
            .parent_id = 100,
            .index = 3,
            .terrain = Terrain.dirt,
        },
    };
    _ = &tiles;
    const test_room = Room{
        .id = 100,
        .tiles = tiles[0..],
        .height = 2,
        .width = 2,
    };
    std.debug.print("test_room now {}\n", .{test_room});

    // actual test
    var s = Serializer.init(&bytes);
    s.write(Room, test_room);
    std.debug.print("bytes now {any}\n", .{bytes[0..s.index]});
    var d = Deserializer.init(allocator, &bytes);
    const result = try d.read(Room);
    std.debug.print("result room now {}\n", .{result});
    try std.testing.expect(result.id == test_room.id);
    try std.testing.expect(result.height == test_room.height);
    try std.testing.expect(result.height == test_room.height);
    try std.testing.expect(result.tiles[0].terrain == test_room.tiles[0].terrain);
    try std.testing.expect(result.tiles[0].parent_id == test_room.id);
    std.debug.print("tiles.len {d}\n", .{result.tiles.len});
    try std.testing.expect(result.tiles.len == test_room.tiles.len);
}
/// warning: this will leak memory if you don't free the slices it produces.
/// i.e. when Deserializing a struct { a: []u8 } into `const val`, you will need to call `allocator.free(val.a)`
pub const Deserializer = struct {
    const Self = @This();
    index: usize,
    from: []u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, from: []u8) Self {
        return .{
            .index = 0,
            .from = from,
            .allocator = allocator,
        };
    }

    fn readInt(self: *Self, comptime T: type, info: std.builtin.Type.Int) T {
        var bytes: usize = info.bits / 8 + 1;
        if (info.bits % 8 == 0) {
            bytes = info.bits / 8;
        }
        const result = std.mem.readInt(T, @ptrCast(self.from[self.index .. self.index + bytes]), std.builtin.Endian.little);
        self.index += bytes;
        return result;
    }

    fn readFloat(self: *Self, comptime T: type, info: std.builtin.Type.Float) T {
        var bytes: usize = info.bits / 8 + 1;
        if (info.bits % 8 == 0) {
            bytes = info.bits / 8;
        }
        const result = std.mem.littleToNative(T, std.mem.bytesToValue(T, self.from[self.index .. self.index + bytes]));
        self.index += bytes;
        return result;
    }

    fn readEnum(self: *Self, comptime T: type, info: std.builtin.Type.Enum) T {
        switch (@typeInfo(info.tag_type)) {
            .Int => |tag_info| {
                var bytes: usize = tag_info.bits / 8 + 1;
                if (tag_info.bits % 8 == 0) {
                    bytes = tag_info.bits / 8;
                }
                const result: T = @enumFromInt(std.mem.littleToNative(info.tag_type, std.mem.bytesToValue(info.tag_type, self.from[self.index .. self.index + bytes])));
                self.index += bytes;
                return result;
            },
            else => @compileError("unsupported type"),
        }
    }

    fn readStruct(self: *Self, comptime T: type) !T {
        const fields = std.meta.fields(T);
        var item: T = undefined;
        inline for (fields) |field| {
            @field(item, field.name) = try self.read(field.type);
        }
        return item;
    }

    fn readArray(self: *Self, comptime T: type, info: std.builtin.Type.Array) !T {
        var arr: T = undefined;
        var i: usize = 0;
        while (i < info.len) : (i += 1) {
            arr[i] = try self.read(info.child);
        }
        return arr;
    }

    pub fn read(self: *Self, comptime T: type) !T {
        return switch (@typeInfo(T)) {
            .Int => |info| self.readInt(T, info),
            .Float => |info| self.readFloat(T, info),
            .Enum => |info| self.readEnum(T, info),
            .Struct => try self.readStruct(T),
            .Array => |info| try self.readArray(T, info),
            .Pointer => |ptr| {
                switch (ptr.size) {
                    .Slice => {
                        const len: usize = @intCast(std.mem.readInt(u32, @ptrCast(self.from[self.index .. self.index + 4]), std.builtin.Endian.little));
                        self.index += 4;
                        var slice = try self.allocator.alloc(ptr.child, len);
                        var i: usize = 0;
                        while (i < len) : (i += 1) {
                            slice[i] = try self.read(ptr.child);
                        }
                        return slice;
                    },
                    else => @compileError("unsupported pointer serializtion attempt"),
                }
            },
            else => @compileError("unsupported type"),
        };
    }
};
