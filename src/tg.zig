const std = @import("std");
const Socket = @import("xsk.zig").Socket;
const Sysfs = @import("sysfs.zig");
const signal = @import("signal.zig");
const Config = @import("config.zig");

pub const Tg = struct {
    config: *const Config,
    socket: Socket,

    pub fn init(config: *const Config) !Tg {
        const device_info = try Sysfs.getDeviceInfo(config.dev);
        std.log.debug("device_info {f}", .{device_info});

        // TODO: do this in the thread
        try setCpuAffinity(0);

        return .{
            .config = config,
            .socket = try Socket.init(config, 0),
        };
    }

    pub fn run(self: *Tg) !void {
        try self.socket.fill_all();
        try signal.setup();
        while (signal.running) {
            try self.socket.send(self.config.batch);
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
        std.log.debug("config: {any}", .{self.config});
        self.socket.print();
    }
};

// TODO: do this the proper way
pub fn setCpuAffinity(cpu: u6) !void {
    var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);
    cpu_set[0] = @as(usize, 1) << cpu;
    try std.os.linux.sched_setaffinity(0, &cpu_set);
}
