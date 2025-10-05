const std = @import("std");
const Socket = @import("xsk.zig").Socket;
const Sysfs = @import("sysfs.zig");
const signal = @import("signal.zig");

pub const Tg = struct {
    dev: []const u8,
    pkt_size: usize,
    batch: usize,
    ring_size: usize,
    socket: Socket,

    pub fn init(dev: []const u8) !Tg {
        const device_info = try Sysfs.getDeviceInfo(dev);
        std.log.debug("device_info {f}", .{device_info});

        return .{
            .pkt_size = 1500,
            .batch = 64,
            .ring_size = 1024,
            .socket = try Socket.init(dev, 0),
            .dev = dev,
        };
    }

    pub fn run(self: *Tg) !void {
        try self.socket.fill_all();
        try signal.setup();
        while (signal.running.load(.seq_cst)) {
            try self.socket.send(64);
            try self.socket.wakeup();
            try self.socket.check_completed();
        }
        const stats = try self.socket.xdp_stats();
        std.log.debug("{any}", .{stats});
    }

    pub fn deinit(self: *Tg) void {
        self.socket.deinit();
        return;
    }

    pub fn print(self: *Tg) void {
        std.log.debug("pkt_size:{d} batch:{d} ring_size:{d}", .{ self.pkt_size, self.batch, self.ring_size });
        self.socket.print();
    }
};
