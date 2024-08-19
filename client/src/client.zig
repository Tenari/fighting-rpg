const std = @import("std");
const Socket = @import("../../common/lib.zig").Socket;

pub fn main() !void {
    std.debug.print("Starting CombatRPG client...\n", .{});
    var socket = try Socket.init("127.0.0.1", 13370);
    defer socket.deinit();
    try socket.connect();
    try socket.send("fuck you");
}
