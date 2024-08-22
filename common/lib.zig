const std = @import("std");
const posix = std.posix;
const expect = std.testing.expect;

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
            self.map[i] = Room.default();
        }
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
    salt: []const u8,
    character: *Character,
};

const MAX_ROOM_SIZE: usize = 256;
pub const Room = struct {
    tiles: [MAX_ROOM_SIZE]Tile,
    height: usize,
    width: usize,

    pub fn default() Room {
        return .{
            .tiles = [_]Tile{Tile.default()} ** MAX_ROOM_SIZE,
            .height = 0,
            .width = 0,
        };
    }
};

const MAX_ITEMS_PER_TILE = 256;
const MAX_CHARACTERS_PER_TILE = 4;
pub const Tile = struct {
    parent: ?*Room,
    terrain: Terrain,
    items: [MAX_ITEMS_PER_TILE]?*Item,
    characters: [MAX_CHARACTERS_PER_TILE]?*Character,
    npc: ?*Npc,
    connect: ?*Tile, // when a character/NPC steps on this tile, they are auto-warped to the other tile, for things like doors

    fn default() Tile {
        return .{
            .parent = null,
            .terrain = Terrain.blank,
            .items = [_]?*Item{null} ** MAX_ITEMS_PER_TILE,
            .characters = [_]?*Character{null} ** MAX_CHARACTERS_PER_TILE,
            .npc = null,
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

pub const Terrain = enum { blank, dirt, grass1, grass2, grass3, grass4, path_north, sand, water, exit };

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

pub const Character = struct {
    name: []const u8 = "",
    race: Race,
    realm: Realm = Realm.earthly,
    stage: Stage = Stage.earthly_dirt,
    level: u2 = 0,

    pub fn init(name: []const u8, race: Race) Character {
        return Character{
            .name = name,
            .race = race,
        };
    }
};

test Socket {
    const socket = try Socket.init("127.0.0.1", 3000);
    try expect(@TypeOf(socket.socket) == posix.socket_t);
}
pub const Socket = struct {
    address: std.net.Address,
    socket: posix.socket_t,
    closed: bool,

    pub fn init(ip: []const u8, port: u16) !Socket {
        const parsed_address = try std.net.Address.parseIp4(ip, port);
        const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        errdefer posix.close(sock);
        return Socket{ .address = parsed_address, .socket = sock, .closed = false };
    }

    pub fn deinit(self: *Socket) void {
        self.closed = true;
        posix.close(self.socket);
    }

    pub fn bind(self: *Socket) !void {
        if (self.closed) return error.SocketClosedAlready;
        try posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
    }

    pub fn recv(self: *Socket, buf: []u8) !usize {
        if (self.closed) return error.SocketClosedAlready;
        return try posix.recvfrom(self.socket, buf, 0, null, null);
    }

    pub fn listen(self: *Socket) !void {
        if (self.closed) return error.SocketClosedAlready;
        var buffer: [1024]u8 = undefined;

        while (true) {
            const received_bytes = try posix.recvfrom(self.socket, buffer[0..], 0, null, null);
            std.debug.print("Received {d} bytes: {s}\n", .{ received_bytes, buffer[0..received_bytes] });
        }
    }

    pub fn connect(self: *Socket) !void {
        if (self.closed) return error.SocketClosedAlready;
        try posix.connect(self.socket, &self.address.any, self.address.getOsSockLen());
    }

    pub fn send(self: *Socket, buf: []const u8) !void {
        if (self.closed) return error.SocketClosedAlready;
        _ = try posix.send(self.socket, buf, 0);
    }
};

pub const Message = enum {
    sign_up,
    move,
};
