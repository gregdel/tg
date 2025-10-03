const std = @import("std");
const Packet = @import("pkt.zig").Packet;

const Xsk = @cImport({
    @cInclude("xdp/xsk.h");
});

const Xdp = @cImport({
    @cInclude("linux/if_xdp.h");
});

const page_size = std.heap.pageSize();

const SocketError = error{
    UmemCreate,
    SocketCreate,
    SocketFD,
};

pub const Socket = struct {
    umem: *Xsk.xsk_umem,
    socket: *Xsk.xsk_socket,
    cq: Xsk.xsk_ring_cons,
    tx: Xsk.xsk_ring_prod,
    fd: std.posix.socket_t,

    umem_area: []align(page_size) u8,
    entries: usize,
    idx: usize,
    pkt_size: usize,

    pub fn init(dev: []const u8, queue_id: u32) !Socket {
        const entries = 32;
        const pkt_size = 64;
        const ring_size = Xsk.XSK_RING_PROD__DEFAULT_NUM_DESCS;
        const size: usize = page_size * entries;

        const addr = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1, // No file descriptor
            0, // No offset
        );
        errdefer std.posix.munmap(addr);

        const umem_config: Xsk.xsk_umem_config = .{
            .fill_size = 0,
            .comp_size = entries,
            .frame_size = page_size,
            .frame_headroom = 0,
        };

        var fq: Xsk.xsk_ring_prod = undefined;
        var cq: Xsk.xsk_ring_cons = undefined;
        var umem: *Xsk.xsk_umem = undefined;
        var socket: *Xsk.xsk_socket = undefined;
        var tx: Xsk.xsk_ring_prod = undefined;

        var ret = Xsk.xsk_umem__create(
            @ptrCast(&umem),
            addr[0..size],
            size,
            @ptrCast(&fq),
            @ptrCast(&cq),
            @ptrCast(&umem_config),
        );
        if (ret < 0) return SocketError.UmemCreate;

        const socket_config: Xsk.xsk_socket_config = .{
            .rx_size = 0,
            .tx_size = ring_size,
            .unnamed_0 = .{
                .libbpf_flags = Xsk.XSK_LIBBPF_FLAGS__INHIBIT_PROG_LOAD,
            },
        };

        ret = Xsk.xsk_socket__create(
            @ptrCast(&socket),
            @ptrCast(dev),
            queue_id,
            @ptrCast(umem),
            null, // No consumer
            @ptrCast(&tx),
            @ptrCast(&socket_config),
        );
        if (ret < 0) return SocketError.SocketCreate;

        const socket_fd = Xsk.xsk_socket__fd(@ptrCast(socket));
        if (ret < 0) return SocketError.SocketFD;

        return .{
            .cq = cq,
            .umem = umem,
            .socket = socket,
            .fd = socket_fd,
            .tx = tx,
            .umem_area = addr[0..size],
            .entries = entries,
            .pkt_size = pkt_size,
            .idx = 0,
        };
    }

    fn umem_addr(self: *Socket, id: usize) usize {
        return (id % self.entries) * page_size;
    }

    pub fn fill_all(self: *Socket) !void {
        var id: u32 = 0;
        while (id < self.entries) : (id += 1) {
            const start = self.umem_addr(id);
            const end = start + self.pkt_size;
            var pkt = Packet.init(id, self.umem_area[start..end]);
            _ = try pkt.write_stuff();
            // const written = try pkt.write_stuff();
            // std.log.debug("written:{any}", .{pkt.data[0..written]});
        }

        std.log.debug("tx before: {any}", .{self.tx});

        const reserved = Xsk.xsk_ring_prod__reserve(@ptrCast(&self.tx), 1, &id);
        std.log.debug("reserved:{d} id:{d}", .{ reserved, id });

        const desc = Xsk.xsk_ring_prod__tx_desc(@ptrCast(&self.tx), id);
        if (desc == null) return error.NullDesc;
        desc.* = .{
            .addr = self.umem_addr(id),
            .len = @intCast(self.pkt_size),
            .options = 0,
        };
        std.log.debug("desc:{any}", .{desc.*});

        Xsk.xsk_ring_prod__submit(@ptrCast(&self.tx), 1);

        if (Xsk.xsk_ring_prod__needs_wakeup(@ptrCast(&self.tx)) != 0) {
            _ = try std.posix.send(self.fd, "", std.os.linux.MSG.DONTWAIT);
        }

        const stats = try self.xdp_stats();
        std.log.debug("{any}", .{stats});

        std.log.debug("tx after: {any}", .{self.tx});
    }

    pub fn xdp_stats(self: *Socket) !Xdp.xdp_statistics {
        var stats: Xdp.xdp_statistics = undefined;
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
