const std = @import("std");

const Xsk = @cImport({
    @cInclude("xdp/xsk.h");
});

const page_size = std.heap.pageSize();

pub const Socket = struct {
    fq: Xsk.xsk_ring_prod,
    cq: Xsk.xsk_ring_cons,
    umem: ?*Xsk.xsk_umem,
    socket: ?*Xsk.xsk_socket,
    tx: ?*Xsk.xsk_ring_prod,
    umem_area: []align(page_size) u8,

    pub fn init(dev: []const u8, queue_id: u32) !Socket {
        const entries = 512;
        const ring_size = entries;
        const size: usize = page_size * entries;

        const addr = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1, // No file descriptor
            0, // No offset
        );

        const umem_config: Xsk.xsk_umem_config = .{
            .fill_size = entries,
            .comp_size = entries,
            .frame_size = page_size,
            .frame_headroom = 0,
        };

        var fq: Xsk.xsk_ring_prod = undefined;
        var cq: Xsk.xsk_ring_cons = undefined;
        var umem: ?*Xsk.xsk_umem = undefined;
        var socket: ?*Xsk.xsk_socket = undefined;
        var tx: ?*Xsk.xsk_ring_prod = undefined;

        var ret = Xsk.xsk_umem__create(
            @ptrCast(&umem),
            addr[0..size],
            size,
            @ptrCast(&fq),
            @ptrCast(&cq),
            @ptrCast(&umem_config),
        );
        if (ret < 0) {
            // TODO
            // errdefer deinit
            //
            return error.FuckYou;
        }

        const socket_config: Xsk.xsk_socket_config = .{
            .rx_size = 0,
            .tx_size = ring_size,
            .unnamed_0 = .{ .libbpf_flags = Xsk.XSK_LIBBPF_FLAGS__INHIBIT_PROG_LOAD },
        };

        ret = Xsk.xsk_socket__create(@ptrCast(&socket), @ptrCast(dev), queue_id, @ptrCast(umem), null, // No consumer
            @ptrCast(&tx), @ptrCast(&socket_config));
        if (ret < 0) {
            // TODO
            // errdefer deinit
            //
            return error.FuckYou;
        }

        const socket_fd = Xsk.xsk_socket__fd(@ptrCast(&socket));
        if (socket_fd <= 0) {
            // TODO
            // errdefer deinit
            //
            return error.FuckYou;
        }

        std.log.debug("xsk fd:{d}\n", .{socket_fd});

        return .{
            .fq = fq,
            .cq = cq,
            .umem = umem,
            .socket = socket,
            .tx = tx,
            .umem_area = addr[0..size],
        };
    }

    pub fn deinit(self: *Socket) void {
        std.posix.munmap(self.umem_area);
        return;
    }
};

pub const Tg = struct {
    allocator: std.mem.Allocator,

    dev: []const u8,
    pkt_size: usize,
    batch: usize,
    ring_size: usize,
    socket: Socket,

    pub fn init(allocator: std.mem.Allocator, dev: []const u8) !Tg {
        return .{
            .allocator = allocator,
            .pkt_size = 1500,
            .batch = 64,
            .ring_size = 1024,
            .socket = try Socket.init(dev, 0),
            .dev = dev,
        };
    }

    pub fn deinit(self: *Tg) void {
        self.socket.deinit();
        return;
    }

    pub fn print(self: *Tg) void {
        std.log.debug("pkt_size:{d} batch:{d} ring_size:{d}", .{ self.pkt_size, self.batch, self.ring_size });
    }
};
