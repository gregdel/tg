const std = @import("std");

const signal = @import("signal.zig");
const Socket = @import("Socket.zig");
const Config = @import("Config.zig");
const Stats = @import("Stats.zig");

const max_queues = @import("DeviceInfo.zig").max_queues;

pub const Tg = @This();

config: *const Config,
stats: Stats = .{},

pub fn init(config: *const Config) !Tg {
    return .{
        .config = config,
    };
}

pub fn threadRun(socket: *Socket, stats: *Stats, config: *const Config, queue_id: usize) !void {
    std.log.debug("starting thread for queue {d}", .{queue_id});
    if (queue_id >= max_queues) return error.TooManyQueues;
    socket.* = try Socket.init(config, @truncate(queue_id), stats);
    defer socket.deinit();

    std.log.debug("socket init done for queue {d}", .{queue_id});

    try socket.fillAll();
    try signal.setup();
    while (signal.running.load(.acquire)) {
        if (socket.config.count) |limit| {
            const remaining = limit - socket.stats.sent;
            if (remaining == 0) break;
            try socket.send(@min(socket.config.batch, remaining));
        } else {
            try socket.send(socket.config.batch);
        }

        try socket.wakeup();
        try socket.checkCompleted();
    }

    try socket.updateXskStats();
}

pub fn run(self: *Tg) !void {
    // TODO: cache align ?
    var stats: [max_queues]Stats = undefined;
    var sockets: [max_queues]Socket = undefined;
    var threads: [max_queues]std.Thread = undefined;
    var queues: usize = 0;

    for (0..self.config.threads) |queue| {
        stats[queue] = .{};
        sockets[queue] = undefined;
        threads[queue] = try std.Thread.spawn(.{}, Tg.threadRun, .{
            &sockets[queue],
            &stats[queue],
            self.config,
            queue,
        });
        queues += 1;
    }

    for (0..queues) |queue| {
        threads[queue].join();
        self.stats.add(&stats[queue]);
    }
}

pub fn format(self: *const Tg, writer: anytype) !void {
    try writer.print("{f}", .{self.stats});
}
