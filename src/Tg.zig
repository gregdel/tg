const std = @import("std");

const signal = @import("signal.zig");
const Socket = @import("Socket.zig");
const Config = @import("Config.zig");

pub const Tg = @This();

config: *const Config,
socket: Socket,
stats: Socket.XdpStats,

pub fn init(config: *const Config) !Tg {
    // TODO: do this in the thread
    try setCpuAffinity(0);

    return .{
        .config = config,
        .socket = try Socket.init(config, 0),
        .stats = .{},
    };
}

pub fn deinit(self: *Tg) void {
    self.socket.deinit();
    return;
}

pub fn run(self: *Tg) !void {
    try self.socket.fillAll();
    try signal.setup();
    while (signal.running) {
        try self.socket.send(self.config.batch);
        try self.socket.wakeup();
        try self.socket.checkCompleted();
    }
    self.stats = try self.socket.xdpStats();
}

pub fn format(self: *const Tg, writer: anytype) !void {
    try writer.print("{f}", .{self.stats});
}

// TODO: do this the proper way
pub fn setCpuAffinity(cpu: u6) !void {
    var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);
    cpu_set[0] = @as(usize, 1) << cpu;
    try std.os.linux.sched_setaffinity(0, &cpu_set);
}
