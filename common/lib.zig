const std = @import("std");
const posix = std.posix;

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

    pub fn listen(self: *Socket) !void {
        if (self.closed) return error.SocketClosedAlready;
        var buffer: [1024]u8 = undefined;

        while (true) {
            const received_bytes = try posix.recvfrom(self.socket, buffer[0..], 0, null, null);
            std.debug.print("#{d} Received {d} bytes: {s}\n", .{ received_bytes, buffer[0..received_bytes] });
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
