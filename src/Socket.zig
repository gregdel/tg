const std = @import("std");

const signal = @import("signal.zig");
const pkt = @import("pkt.zig");
const Config = @import("Config.zig");
const CpuSet = @import("CpuSet.zig");
const Stats = @import("Stats.zig");
const Layers = @import("layers/Layers.zig");

const xsk = @cImport({
    @cInclude("xdp/xsk.h");
});

const xdp = @cImport({
    @cInclude("linux/if_xdp.h");
});

const page_size = std.heap.pageSize();

pub const ring_size: u32 = xsk.XSK_RING_PROD__DEFAULT_NUM_DESCS;

const SocketError = error{
    UmemCreate,
    SocketCreate,
    SocketFD,
};

pub const SocketConfig = struct {
    dev: []const u8,
    queue_id: u8 = 0,
    layers: Layers,
    affinity: ?CpuSet = null,
    pkt_size: u16,
    frames_per_packet: u8,
    pkt_count: ?u64,
    pkt_batch: u32,
    umem_entries: u32,
    pre_fill: bool,

    pub fn format(self: *const SocketConfig, writer: anytype) !void {
        try writer.print(
            \\Socket config:
            \\  Ring size:{d}
            \\  UMEM entries:{d} pre-fill:{}
            \\  Packet batch:{d} size:{d}
        ,
            .{
                ring_size,
                self.umem_entries,
                self.pre_fill,
                self.pkt_batch,
                self.pkt_size,
            },
        );

        if (self.frames_per_packet > 1) {
            try writer.print("\n  Frames per packet:{d}", .{self.frames_per_packet});
        }
        if (self.pkt_count != null) {
            try writer.print("\n  Packet count:{d}", .{self.pkt_count.?});
        }
    }
};

pub const Socket = @This();

config: *const SocketConfig,
stats: *Stats,
umem_area: []align(page_size) u8,
cq: xsk.xsk_ring_cons,
tx: xsk.xsk_ring_prod,
fd: std.posix.socket_t,

pub fn init(config: *const SocketConfig, stats: *Stats) !Socket {
    // Bind the thread to the proper CPU
    const queue_id = config.queue_id;
    var cpu_set = config.affinity orelse CpuSet.zero();
    if (cpu_set.isEmpty()) {
        const cpu = queue_id;
        cpu_set.setFallback(cpu);
        std.log.debug(
            "cpu_set empty queue:{d} is falling back to cpu:{d}",
            .{ queue_id, cpu },
        );
    }
    try cpu_set.apply();

    const size: usize = page_size * config.umem_entries;

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
        .comp_size = ring_size,
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

    var bind_flags: u16 = xsk.XDP_USE_NEED_WAKEUP;
    if (config.frames_per_packet > 1) {
        bind_flags |= xsk.XDP_USE_SG;
    }

    const socket_config: xsk.xsk_socket_config = .{
        .rx_size = 0,
        .tx_size = ring_size,
        .unnamed_0 = .{
            .libbpf_flags = xsk.XSK_LIBBPF_FLAGS__INHIBIT_PROG_LOAD,
        },
        .bind_flags = bind_flags,
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
        .config = config,
        .stats = stats,
        .umem_area = addr[0..size],
        .cq = cq,
        .tx = tx,
        .fd = socket_fd,
    };
}

pub fn deinit(self: *Socket) void {
    std.posix.munmap(self.umem_area);
    return;
}

fn umemAddr(self: *Socket, id: usize) usize {
    return (id % self.config.umem_entries) * page_size;
}

pub fn run(self: *Socket) !void {
    var seed: u64 = 0;
    if (self.config.pre_fill) try self.fillAll();
    while (signal.running.load(.acquire)) {
        var to_send: u32 = self.config.pkt_batch;
        if (self.config.pkt_count) |limit| {
            const pkt_sent = self.stats.frames_sent / self.config.frames_per_packet;
            const remaining = limit - pkt_sent;
            if (remaining == 0) break;
            to_send = @min(self.config.pkt_batch, remaining);
        }

        try self.send(to_send, seed);
        try self.wakeup();
        try self.checkCompleted();
        seed +%= to_send;
    }
    try self.updateXskStats();
}

pub fn fillAll(self: *Socket) !void {
    return self.fill(0, self.config.umem_entries, 0);
}

pub fn fill(self: *Socket, id_start: usize, pkt_count: usize, seed_start: u64) !void {
    var seed = seed_start;
    const total_frames = pkt_count * self.config.frames_per_packet;
    var id = id_start;
    const id_end = id_start + total_frames;

    // Only fill the first packet of a multi packet frame.
    while (id < id_end) : (id += self.config.frames_per_packet) {
        const buf_start = self.umemAddr(id);
        const buf_end = buf_start + page_size;
        const buf = self.umem_area[buf_start..buf_end];
        try pkt.build(self.config.layers, buf, seed);
        seed += 1;
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
    if (self.stats.frames_pending == 0) return;

    var id: u32 = undefined;
    const frames = xsk.xsk_ring_cons__peek(
        @ptrCast(&self.cq),
        self.stats.frames_pending,
        &id,
    );
    if (frames == 0) return;

    xsk.xsk_ring_cons__release(@ptrCast(&self.cq), frames);
    self.stats.frames_pending -= frames;
    self.stats.frames_sent += frames;
}

pub fn send(self: *Socket, pkt_count: u32, seed_start: u64) !void {
    var id: u32 = 0;

    const frames = pkt_count * self.config.frames_per_packet;

    const reserved = xsk.xsk_ring_prod__reserve(
        @ptrCast(&self.tx),
        frames,
        &id,
    );
    if (reserved != frames) return; // TODO

    if (!self.config.pre_fill) {
        try self.fill(id, pkt_count, seed_start);
    }

    const last_frame_id = self.config.frames_per_packet - 1;
    var i: usize = 0;
    while (i < frames) : (i += self.config.frames_per_packet) {
        var len: u32 = self.config.pkt_size;
        for (0..self.config.frames_per_packet) |frame_id| {
            const has_more = (frame_id != last_frame_id);
            const desc_len: u32 = if (has_more) page_size else len;

            const desc = xsk.xsk_ring_prod__tx_desc(@ptrCast(&self.tx), id);
            if (desc == null) return error.NullDesc;
            desc.* = .{
                .addr = self.umemAddr(id),
                .len = @intCast(desc_len),
                .options = if (has_more) xsk.XDP_PKT_CONTD else 0,
            };
            len -= desc_len;
            id +%= 1;
        }
    }

    xsk.xsk_ring_prod__submit(@ptrCast(&self.tx), frames);
    self.stats.frames_pending += frames;
}

pub fn updateXskStats(self: *Socket) !void {
    var stats: xdp.xdp_statistics = undefined;
    try std.posix.getsockopt(
        self.fd,
        std.os.linux.SOL.XDP,
        std.os.linux.XDP.STATISTICS,
        std.mem.asBytes(&stats),
    );

    self.stats.tx_invalid_descs = stats.tx_invalid_descs;
    self.stats.tx_ring_empty_descs = stats.tx_ring_empty_descs;
}
