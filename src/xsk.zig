const std = @import("std");
const Packet = @import("pkt.zig").Packet;

const Xsk = @cImport({
    @cInclude("xdp/xsk.h");
});

const page_size = std.heap.pageSize();

const SocketError = error{
    UmemCreate,
    SocketCreate,
    SocketFD,
};

pub const Socket = struct {
    fq: Xsk.xsk_ring_prod,
    cq: Xsk.xsk_ring_cons,
    umem: ?*Xsk.xsk_umem,
    socket: ?*Xsk.xsk_socket,
    tx: ?*Xsk.xsk_ring_prod,
    umem_area: []align(page_size) u8,
    allocator: std.mem.Allocator,

    umem_status: []bool,
    entries: u16,
    free_count: u16,

    pub fn init(allocator: std.mem.Allocator, dev: []const u8, queue_id: u32) !Socket {
        const entries = 32;
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
        if (ret < 0) return SocketError.UmemCreate;

        const socket_config: Xsk.xsk_socket_config = .{
            .rx_size = 0,
            .tx_size = ring_size,
            .unnamed_0 = .{ .libbpf_flags = Xsk.XSK_LIBBPF_FLAGS__INHIBIT_PROG_LOAD },
        };

        ret = Xsk.xsk_socket__create(@ptrCast(&socket), @ptrCast(dev), queue_id, @ptrCast(umem), null, // No consumer
            @ptrCast(&tx), @ptrCast(&socket_config));
        if (ret < 0) return SocketError.SocketCreate;

        const socket_fd = Xsk.xsk_socket__fd(@ptrCast(&socket));
        if (ret < 0) return SocketError.SocketFD;

        std.log.debug("xsk fd:{d}\n", .{socket_fd});

        const umem_status = try allocator.alloc(bool, entries);
        @memset(umem_status, false);

        return .{
            .allocator = allocator,
            .fq = fq,
            .cq = cq,
            .umem = umem,
            .socket = socket,
            .tx = tx,
            .umem_area = addr[0..size],
            .umem_status = umem_status,
            .entries = entries,
            .free_count = entries,
        };
    }

    pub fn fill_all(self: *Socket) void {
        var addr: u64 = 0;
        var pkt: Packet = .{
            .data = undefined,
            .position = undefined,
            .id = 0,
            .size = 64,
        };
        var id: u64 = 0;
        while (addr < self.umem_area.len) : (addr += page_size) {
            pkt.data = self.umem_area[addr .. addr + pkt.size];
            pkt.position = pkt.data;
            pkt.id = id;
            id += 1;
            std.log.debug("addr:{any}\n", .{pkt.position.ptr});
        }
    }

    pub fn print(self: *Socket) void {
        std.log.debug("fq:{any}\n", .{self.fq});
    }

    pub fn deinit(self: *Socket) void {
        std.posix.munmap(self.umem_area);
        return;
    }
};
