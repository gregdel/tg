const std = @import("std");
const PacketBuilder = @import("pkt.zig").PacketBuilder;
const Config = @import("config.zig");

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

pub const Socket = struct {
    umem: *xsk.xsk_umem,
    socket: *xsk.xsk_socket,
    cq: xsk.xsk_ring_cons,
    tx: xsk.xsk_ring_prod,
    fd: std.posix.socket_t,

    config: *const Config,
    umem_area: []align(page_size) u8,
    pending: u32,

    pub fn init(config: *const Config, queue_id: u32) !Socket {
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
        if (ret < 0) return SocketError.SocketFD;

        return .{
            .cq = cq,
            .umem = umem,
            .socket = socket,
            .fd = socket_fd,
            .tx = tx,
            .umem_area = addr[0..size],
            .pending = 0,
            .config = config,
        };
    }

    fn umem_addr(self: *Socket, id: usize) usize {
        return (id % self.config.entries) * page_size;
    }

    pub fn fill_all(self: *Socket) !void {
        const builder = try PacketBuilder.init(self.config.pkt_size);
        var id: u32 = 0;
        while (id < self.config.entries) : (id += 1) {
            const start = self.umem_addr(id);
            const end = start + self.config.pkt_size;
            _ = try builder.build(self.umem_area[start..end]);
        }
    }

    pub inline fn wakeup(self: *Socket) !void {
        if (xsk.xsk_ring_prod__needs_wakeup(@ptrCast(&self.tx)) == 0) {
            return;
        }

        _ = std.posix.send(
            self.fd,
            "",
            std.os.linux.MSG.DONTWAIT,
        ) catch |err| switch (err) {
            error.WouldBlock => return,
            else => |e| return e,
        };
    }

    pub inline fn check_completed(self: *Socket) !void {
        if (self.pending == 0) return;

        var id: u32 = undefined;
        const count = xsk.xsk_ring_cons__peek(
            @ptrCast(&self.cq),
            self.pending,
            &id,
        );
        if (count == 0) return;

        // std.log.debug("completed count:{any} pending:{d}", .{
        //     count, self.pending,
        // });

        xsk.xsk_ring_cons__release(@ptrCast(&self.cq), count);
        self.pending -= count;
    }

    pub fn send(self: *Socket, count: u32) !void {
        var id: u32 = 0;

        const reserved = xsk.xsk_ring_prod__reserve(
            @ptrCast(&self.tx),
            count,
            &id,
        );
        if (reserved != count) return; // TODO

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const desc = xsk.xsk_ring_prod__tx_desc(@ptrCast(&self.tx), id);
            if (desc == null) return error.NullDesc;
            desc.* = .{
                .addr = self.umem_addr(id),
                .len = @intCast(self.config.pkt_size),
                .options = 0,
            };
            // std.log.debug("new desc id:{d} desc:{any}", .{ id, desc.* });
            id +%= 1;
        }

        xsk.xsk_ring_prod__submit(@ptrCast(&self.tx), count);
        self.pending += count;
    }

    pub fn xdp_stats(self: *Socket) !xdp.xdp_statistics {
        var stats: xdp.xdp_statistics = undefined;
        try std.posix.getsockopt(
            self.fd,
            std.os.linux.SOL.XDP,
            std.os.linux.XDP.STATISTICS,
            std.mem.asBytes(&stats),
        );
        return stats;
    }

    pub fn print(self: *Socket) void {
        std.log.debug("fq:{any}\n", .{self.tx});
    }

    pub fn deinit(self: *Socket) void {
        std.posix.munmap(self.umem_area);
        return;
    }
};
