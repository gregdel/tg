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
        try setCpuAffinity(0);

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
        var i: usize = 0;
        try signal.setup();
        while (signal.running) : (i += 1) {
            try self.socket.send(64);
            if ((i % 10) == 0) {
                try self.socket.wakeup();
            }
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

// TODO: do this the proper way
pub fn setCpuAffinity(cpu: u6) !void {
    var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);
    cpu_set[0] = @as(usize, 1) << cpu;
    try std.os.linux.sched_setaffinity(0, &cpu_set);
}
