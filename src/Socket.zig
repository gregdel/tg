const std = @import("std");

const signal = @import("signal.zig");
const pkt = @import("pkt.zig");
const Config = @import("Config.zig");
const CpuSet = @import("CpuSet.zig");
const Stats = @import("Stats.zig");
const Layer = @import("layers/layer.zig").Layer;

const xsk = @cImport({
    @cInclude("xdp/xsk.h");
});

const xdp = @cImport({
    @cInclude("linux/if_xdp.h");
});

const page_size = std.heap.pageSize();

const SocketError = error{
    UmemCreate,
    SocketCreate,
    SocketFD,
};

pub const Socket = @This();

pkt_size: u16,
entries: u32, // XSK_RING_PROD__DEFAULT_NUM_DESCS;
count: ?u64,
batch: u32,
pre_fill: bool,
umem_area: []align(page_size) u8,
cq: xsk.xsk_ring_cons,
tx: xsk.xsk_ring_prod,
fd: std.posix.socket_t,
stats: *Stats,
layers: []const Layer,

pub fn init(config: *const Config, queue_id: u32, stats: *Stats) !Socket {
    // Bind the thread to the proper CPU
    var cpu_set = config.device_info.queues[queue_id] orelse CpuSet.zero();
    if (cpu_set.isEmpty()) {
        const cpu = queue_id;
        cpu_set.setFallback(cpu);
        std.log.debug(
            "cpu_set empty queue:{d} is falling back to cpu:{d}",
            .{ queue_id, cpu },
        );
    }
    try cpu_set.apply();

    const size: usize = page_size * config.entries;

    const addr = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1, // No file descriptor
        0, // No offset
    );
    errdefer std.posix.munmap(addr);

    const umem_config: xsk.xsk_umem_config = .{
        .fill_size = 0,
        .comp_size = config.ring_size,
        .frame_size = page_size,
        .frame_headroom = 0,
    };

    var fq: xsk.xsk_ring_prod = undefined;
    var cq: xsk.xsk_ring_cons = undefined;
    var umem: *xsk.xsk_umem = undefined;
    var socket: *xsk.xsk_socket = undefined;
    var tx: xsk.xsk_ring_prod = undefined;

    // TODO use create opts
    var ret = xsk.xsk_umem__create(
        @ptrCast(&umem),
        addr.ptr,
        size,
        @ptrCast(&fq),
        @ptrCast(&cq),
        @ptrCast(&umem_config),
    );
    if (ret < 0) return SocketError.UmemCreate;

    const socket_config: xsk.xsk_socket_config = .{
        .rx_size = 0,
        .tx_size = config.ring_size,
        .unnamed_0 = .{
            .libbpf_flags = xsk.XSK_LIBBPF_FLAGS__INHIBIT_PROG_LOAD,
        },
        .bind_flags = xsk.XDP_USE_NEED_WAKEUP,
    };

    ret = xsk.xsk_socket__create(
        @ptrCast(&socket),
        @ptrCast(config.dev),
        queue_id,
        @ptrCast(umem),
        null, // No consumer
        @ptrCast(&tx),
        @ptrCast(&socket_config),
    );
    if (ret < 0) return SocketError.SocketCreate;

    const socket_fd = xsk.xsk_socket__fd(@ptrCast(socket));
    if (socket_fd < 0) return SocketError.SocketFD;

    return .{
        .cq = cq,
        .fd = socket_fd,
        .tx = tx,
        .umem_area = addr[0..size],
        .entries = config.entries,
        .pkt_size = config.pkt_size,
        .stats = stats,
        .layers = config.layers.asSlice(),
        .count = config.count,
        .batch = config.batch,
        .pre_fill = config.pre_fill,
    };
}

pub fn deinit(self: *Socket) void {
    std.posix.munmap(self.umem_area);
    return;
}

fn umemAddr(self: *Socket, id: usize) usize {
    return (id % self.entries) * page_size;
}

pub fn run(self: *Socket) !void {
    if (self.pre_fill) try self.fillAll();
    while (signal.running.load(.acquire)) {
        if (self.count) |limit| {
            const remaining = limit - self.stats.sent;
            if (remaining == 0) break;
            try self.send(@min(self.batch, remaining));
        } else {
            try self.send(self.batch);
        }

        try self.wakeup();
        try self.checkCompleted();
    }
    try self.updateXskStats();
}

pub fn fillAll(self: *Socket) !void {
    return self.fill(0, self.entries);
}

pub fn fill(self: *Socket, id_start: usize, count: usize) !void {
    for (id_start..(id_start + count)) |id| {
        const start = self.umemAddr(id);
        const end = start + self.pkt_size;
        try pkt.build(
            self.layers,
            self.umem_area[start..end],
            id,
        );
    }
}

pub inline fn wakeup(self: *Socket) !void {
    if (xsk.xsk_ring_prod__needs_wakeup(@ptrCast(&self.tx)) == 0) {
        return;
    }

    while (true) {
        _ = std.posix.send(
            self.fd,
            "",
            std.os.linux.MSG.DONTWAIT,
        ) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => |e| return e,
        };
        break;
    }
}

pub inline fn checkCompleted(self: *Socket) !void {
    if (self.stats.pending == 0) return;

    var id: u32 = undefined;
    const count = xsk.xsk_ring_cons__peek(
        @ptrCast(&self.cq),
        self.stats.pending,
        &id,
    );
    if (count == 0) return;

    // std.log.debug("completed count:{any} pending:{d}", .{
    //     count, self.pending,
    // });

    xsk.xsk_ring_cons__release(@ptrCast(&self.cq), count);
    self.stats.pending -= count;
    self.stats.sent += count;
}

pub fn send(self: *Socket, count: u32) !void {
    var id: u32 = 0;

    const free = xsk.xsk_prod_nb_free(@ptrCast(&self.tx), count);
    if (free < count) return; // TODO

    const reserved = xsk.xsk_ring_prod__reserve(
        @ptrCast(&self.tx),
        count,
        &id,
    );
    if (reserved != count) return; // TODO

    if (!self.pre_fill) {
        try self.fill(id, count);
    }

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const desc = xsk.xsk_ring_prod__tx_desc(@ptrCast(&self.tx), id);
        if (desc == null) return error.NullDesc;
        desc.* = .{
            .addr = self.umemAddr(id),
            .len = @intCast(self.pkt_size),
            .options = 0,
        };
        // std.log.debug("new desc id:{d} desc:{any}", .{ id, desc.* });
        id +%= 1;
    }

    xsk.xsk_ring_prod__submit(@ptrCast(&self.tx), count);
    self.stats.pending += count;
}

pub fn updateXskStats(self: *Socket) !void {
    var stats: xdp.xdp_statistics = undefined;
    try std.posix.getsockopt(
        self.fd,
        std.os.linux.SOL.XDP,
        std.os.linux.XDP.STATISTICS,
        std.mem.asBytes(&stats),
    );

    self.stats.rx_dropped = stats.rx_dropped;
    self.stats.rx_invalid_descs = stats.rx_invalid_descs;
    self.stats.tx_invalid_descs = stats.tx_invalid_descs;
    self.stats.rx_ring_full = stats.rx_ring_full;
    self.stats.rx_fill_ring_empty_descs = stats.rx_fill_ring_empty_descs;
    self.stats.tx_ring_empty_descs = stats.tx_ring_empty_descs;
}
