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
const alignement = @import("CpuSet.zig").alignement;

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

const Tg = @This();

allocator: std.mem.Allocator,
config: *const Config,
stats: Stats = .{},

pub fn init(allocator: std.mem.Allocator, config: *const Config) !Tg {
    return .{
        .config = config,
        .allocator = allocator,
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

pub fn distributeToThread(self: *const Tg, total: ?u64, thread_idx: usize) ?u64 {
    return distributeWork(total, self.config.threads, thread_idx);
}

pub fn distributeWork(total: ?u64, thread_count: u32, thread_idx: usize) ?u64 {
    const count = total orelse return null;
    const per_thread = count / thread_count;
    const remaining = count % thread_count;
    return if (thread_idx < remaining) per_thread + 1 else per_thread;
}

pub fn run(self: *Tg) !void {
    const thread_count = self.config.threads;

    var threads = try std.ArrayList(std.Thread)
        .initCapacity(self.allocator, thread_count);
    defer threads.deinit(self.allocator);

    var threads_ctx = try std.ArrayListAligned(ThreadContext, alignement)
        .initCapacity(self.allocator, thread_count);
    defer threads_ctx.deinit(self.allocator);

    try signal.setup();

    const default_config = self.config.socket_config;
    for (0..thread_count) |i| {
        try threads_ctx.append(
            self.allocator,
            ThreadContext.init(default_config),
        );

        var ctx = &threads_ctx.items[i];
        ctx.config.queue_id = @truncate(i);
        ctx.config.affinity = self.config.device_info.queues[i] orelse CpuSet.zero();
        ctx.config.pkt_count = self.distributeToThread(default_config.pkt_count, i);
        if (default_config.rate_limit_pps) |pps| {
            ctx.config.rate_limit_pps = self.distributeToThread(pps, i);
            if (ctx.config.rate_limit_pps == 0) {
                std.log.debug("No work to do on thread {d}", .{i});
                continue;
            }

            if (pps < ctx.config.pkt_batch) {
                std.log.debug("Adjusting batch_size of thread {d} to {d}", .{
                    i,
                    pps,
                });
                ctx.config.pkt_batch = @truncate(pps);
            }
        }

        const thread = try std.Thread.spawn(.{}, Tg.threadRun, .{ctx});
        var buf: [16]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "tg_q_{d}", .{i});
        try thread.setName(name);

        try threads.append(self.allocator, thread);
    }

    std.log.debug("Waiting for {d} threads", .{threads.items.len});
    for (threads.items, 0..) |thread, i| {
        thread.join();
        self.stats.add(&threads_ctx.items[i].stats);
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

test "distributeWork" {
    // 10 packets total on 5 threads -> 2 per thread
    inline for (0..5) |thread| {
        try std.testing.expectEqual(2, distributeWork(10, 5, thread));
    }

    // 6 packets total on 4 threads:
    // Thread 0 -> 2
    // Thread 1 -> 2
    // Thread 2 -> 1
    // Thread 3 -> 1
    try std.testing.expectEqual(2, distributeWork(6, 4, 0));
    try std.testing.expectEqual(2, distributeWork(6, 4, 1));
    try std.testing.expectEqual(1, distributeWork(6, 4, 2));
    try std.testing.expectEqual(1, distributeWork(6, 4, 3));

    // No limit
    try std.testing.expectEqual(null, distributeWork(null, 1, 0));
}
