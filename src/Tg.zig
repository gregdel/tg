const std = @import("std");

const signal = @import("signal.zig");
const Socket = @import("Socket.zig");
const SocketConfig = @import("Socket.zig").SocketConfig;
const Config = @import("Config.zig");
const Stats = @import("Stats.zig");
const CpuSet = @import("CpuSet.zig");
const CliArgs = @import("CliArgs.zig");
const bpf = @import("bpf.zig");

const max_queues = @import("DeviceInfo.zig").max_queues;

const ThreadContext = struct {
    stats: Stats,
    config: SocketConfig,

    pub fn init(default_config: SocketConfig) ThreadContext {
        return .{
            .stats = .{},
            .config = default_config,
        };
    }
};

pub const Tg = @This();

config: *const Config,
stats: Stats = .{},

pub fn init(config: *const Config) !Tg {
    return .{
        .config = config,
    };
}

pub fn threadRun(ctx: *ThreadContext) !void {
    if (ctx.config.queue_id >= max_queues) return error.TooManyQueues;
    var socket = try Socket.init(&ctx.config, &ctx.stats);
    defer socket.deinit();
    std.log.debug("Thread started for queue {d}", .{ctx.config.queue_id});
    try socket.run();
    try socket.updateXskStats();
}

pub fn run(self: *Tg) !void {
    // TODO: cache align ?
    var threads: [max_queues]std.Thread = undefined;
    var threads_ctx: [max_queues]ThreadContext = undefined;

    try signal.setup();
    var queues: usize = 0;
    var buf: [16]u8 = undefined;
    const default_config = self.config.socket_config;
    for (0..self.config.threads) |queue_id| {
        threads_ctx[queue_id] = ThreadContext.init(default_config);

        var ctx = &threads_ctx[queue_id];
        ctx.config.queue_id = @truncate(queue_id);
        ctx.config.affinity = self.config.device_info.queues[queue_id] orelse CpuSet.zero();

        threads[queue_id] = try std.Thread.spawn(.{}, Tg.threadRun, .{ctx});
        const name = try std.fmt.bufPrint(&buf, "tg_q_{d}", .{queue_id});
        try threads[queue_id].setName(name);

        queues += 1;
    }

    for (0..queues) |queue| {
        threads[queue].join();
        self.stats.add(&threads_ctx[queue].stats);
    }
}

pub fn attach(cli_args: *const CliArgs) !void {
    const dev = cli_args.dev orelse return error.CliUsage;
    const prog = cli_args.prog orelse return error.CliUsage;
    try bpf.attach(dev, prog);
}

pub fn detach(cli_args: *const CliArgs) !void {
    const dev = cli_args.dev orelse return error.CliUsage;
    try bpf.detach(dev);
}

pub fn format(self: *const Tg, writer: anytype) !void {
    try writer.print(
        \\Stats:
        \\  Packets sent: {d}
        \\{f}
        \\
    ,
        .{
            self.stats.frames_sent / self.config.socket_config.frames_per_packet,
            self.stats,
        },
    );
}
