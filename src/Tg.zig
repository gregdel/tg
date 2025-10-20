const std = @import("std");

const signal = @import("signal.zig");
const Socket = @import("Socket.zig");
const Config = @import("Config.zig");

const max_queues = @import("DeviceInfo.zig").max_queues;

pub const Tg = @This();

config: *const Config,
sockets: [max_queues]?Socket = .{null} ** max_queues,
socket_count: usize = 0,
threads: [max_queues]?std.Thread = .{null} ** max_queues,
thread_count: usize = 0,

pub fn init(config: *const Config) !Tg {
    return .{
        .config = config,
    };
}

pub fn threadRun(self: *Tg, queue_id: usize) !void {
    if (queue_id >= max_queues) return error.TooManyQueues;
    self.sockets[queue_id] = try Socket.init(self.config, @truncate(queue_id));
    self.socket_count += 1;
    var socket = self.sockets[queue_id] orelse unreachable;
    defer socket.deinit();

    try socket.fillAll();
    try signal.setup();
    while (signal.running) {
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
    for (0..self.config.threads) |queue| {
        self.threads[queue] = try std.Thread.spawn(.{}, Tg.threadRun, .{
            self,
            queue,
        });
        self.thread_count += 1;
    }

    while (signal.running) {
        // Sleep 10ms
        std.posix.nanosleep(0, 10_000_000);
    }

    for (0..self.thread_count) |i| {
        if (self.threads[i]) |thread| {
            thread.join();
        }
    }
}

pub fn format(self: *const Tg, writer: anytype) !void {
    for (0..self.socket_count) |i| {
        if (self.sockets[i]) |socket| {
            try writer.print("Socket: {d}\n{f}", .{
                i,
                socket.stats,
            });
        }
    }
}
