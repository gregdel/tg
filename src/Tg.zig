const std = @import("std");

const signal = @import("signal.zig");
const Socket = @import("Socket.zig");
const Config = @import("Config.zig");

const max_queues = @import("DeviceInfo.zig").max_queues;

pub const Tg = @This();

config: *const Config,
socket: Socket,

pub fn init(config: *Config) !Tg {
    var queue: u32 = 0;
    var i: u8 = 0;
    var found: u8 = 0;
    while (i < max_queues) : (i += 1) {
        if (config.device_info.queues[i]) |*cpu_set| {
            found += 1;
            if (found == 1) {
                // TODO: only 1 queue for now
                queue = i;
                if (cpu_set.isEmpty()) {
                    // Queue n <=> CPU n
                    cpu_set.setFallback(queue + 1);
                } else {
                    try cpu_set.apply();
                }
            }
        }
        if (found == config.device_info.queue_count) break;
    }

    return .{
        .config = config,
        .socket = try Socket.init(config, queue),
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
        if (self.config.count) |limit| {
            const remaining = limit - self.socket.stats.sent;
            if (remaining == 0) break;
            try self.socket.send(@min(self.config.batch, remaining));
        } else {
            try self.socket.send(self.config.batch);
        }

        try self.socket.wakeup();
        try self.socket.checkCompleted();
    }
    try self.socket.updateXskStats();
}

pub fn format(self: *const Tg, writer: anytype) !void {
    try writer.print("{f}", .{self.socket.stats});
}
