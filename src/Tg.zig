const std = @import("std");

const signal = @import("signal.zig");
const Socket = @import("Socket.zig");
const SocketConfig = @import("Socket.zig").SocketConfig;
const Config = @import("Config.zig");
const Stats = @import("Stats.zig");
const CpuSet = @import("CpuSet.zig");

const max_queues = @import("DeviceInfo.zig").max_queues;

pub const Tg = @This();

config: *const Config,
stats: Stats = .{},

pub fn init(config: *const Config) !Tg {
    return .{
        .config = config,
    };
}

pub fn threadRun(config: *const SocketConfig, stats: *Stats) !void {
    if (config.queue_id >= max_queues) return error.TooManyQueues;
    var socket = try Socket.init(config, stats);
    defer socket.deinit();
    std.log.debug("Thread started for queue {d}", .{config.queue_id});
    try socket.run();
    try socket.updateXskStats();
}

pub fn run(self: *Tg) !void {
    // TODO: cache align ?
    var threads: [max_queues]std.Thread = undefined;
    var socket_stats: [max_queues]Stats = undefined;
    var sockets_config: [max_queues]SocketConfig = undefined;

    try signal.setup();
    var queues: usize = 0;
    const default_config = self.config.socket_config;
    for (0..self.config.device_info.queue_count) |queue_id| {
        socket_stats[queue_id] = .{};
        sockets_config[queue_id] = default_config;

        var config = &sockets_config[queue_id];
        const stats = &socket_stats[queue_id];

        config.queue_id = @truncate(queue_id);
        config.affinity = self.config.device_info.queues[queue_id] orelse CpuSet.zero();

        threads[queue_id] = try std.Thread.spawn(.{}, Tg.threadRun, .{ config, stats });
        queues += 1;
    }

    for (0..queues) |queue| {
        threads[queue].join();
        self.stats.add(&socket_stats[queue]);
    }
}

pub fn format(self: *const Tg, writer: anytype) !void {
    try writer.print("{f}", .{self.stats});
}
