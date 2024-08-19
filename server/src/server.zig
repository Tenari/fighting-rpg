const std = @import("std");
const expect = std.testing.expect;
const posix = std.posix;

var reqno: u2 = 0;

pub fn main() !void {
    // 1. allocate server memory
    // 2. start gameloop
    // 3. start net server

    // requests come in to the server, which saves them as inputs to be read on the next gameloop frame
    // gameloop frames update game state in memeory, periodically (every N frames) saving to disk

    // allocate 3GB of ram for the game state
    //    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //    const allocator = gpa.allocator();

    std.debug.print("Starting CombatRPG server...\n", .{});
    var socket = try Socket.init("127.0.0.1", 13370);
    try socket.bind();
    try socket.listen();
}

test Socket {
    const socket = try Socket.init("127.0.0.1", 3000);
    try expect(@TypeOf(socket.socket) == posix.socket_t);
}
const Socket = struct {
    address: std.net.Address,
    socket: posix.socket_t,

    fn init(ip: []const u8, port: u16) !Socket {
        const parsed_address = try std.net.Address.parseIp4(ip, port);
        const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        errdefer posix.closeSocket(sock);
        return Socket{ .address = parsed_address, .socket = sock };
    }

    fn bind(self: *Socket) !void {
        try posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
    }

    fn listen(self: *Socket) !void {
        var buffer: [1024]u8 = undefined;

        while (true) {
            const received_bytes = try posix.recvfrom(self.socket, buffer[0..], 0, null, null);
            reqno +%= 1;
            std.debug.print("#{d} Received {d} bytes: {s}\n", .{ reqno, received_bytes, buffer[0..received_bytes] });
        }
    }
};
