const std = @import("std");
const DeviceInfo = @import("DeviceInfo.zig");

const bpf = @cImport({
    @cInclude("bpf/libbpf.h");
});

const linux = @cImport({
    @cInclude("linux/netdev.h");
    @cInclude("linux/if_link.h");
});

const tg_xdp = @embedFile("tg_xdp");

const programs = std.StaticStringMap(void).initComptime(.{
    .{ "tg_pass", .{} },
    .{ "tg_drop", .{} },
});

fn handleError(err: c_int, msg: []const u8) anyerror {
    var buf: [64]u8 = undefined;
    const ret = bpf.libbpf_strerror(err, @ptrCast(&buf), buf.len);
    if (ret < 0) {
        std.log.err("failed to show libbpf error: {d}", .{ret});
    } else {
        std.log.err("{s}: {s}", .{ msg, buf });
    }
    return error.LibBpf;
}

pub fn attach(dev: []const u8, prog: []const u8) !void {
    programs.get(prog) orelse return error.InvalidXdpProgram;

    const device_info = try DeviceInfo.init(dev);

    // Disable libbpf logging
    _ = bpf.libbpf_set_print(null);

    const obj = bpf.bpf_object__open_mem(@ptrCast(tg_xdp.ptr), tg_xdp.len, null) orelse {
        return error.BpfObjectOpen;
    };

    var ret = bpf.bpf_object__load(obj);
    if (ret < 0) {
        return handleError(ret, "Failed to load BPF object");
    }
    errdefer bpf.bpf_object__close(obj);
    defer bpf.bpf_object__close(obj);

    const bpf_prog = bpf.bpf_object__find_program_by_name(obj, @ptrCast(prog)) orelse {
        return error.BpfFindByName;
    };

    const prog_fd = bpf.bpf_program__fd(bpf_prog);
    if (prog_fd < 0) {
        return handleError(ret, "Failed to load get program fd");
    }

    ret = bpf.bpf_xdp_attach(@intCast(device_info.index), prog_fd, 0, null);
    if (ret < 0) {
        return handleError(ret, "Failed attach XDP program");
    }
}

pub fn detach(dev: []const u8) !void {
    const device_info = try DeviceInfo.init(dev);
    const ret = bpf.bpf_xdp_detach(@intCast(device_info.index), 0, null);
    if (ret < 0) {
        return handleError(ret, "Failed detach XDP program");
    }
}

pub const Capabilities = struct {
    multi_buffer: bool = false,
    zerocopy_max_frames: u32 = 0,
    zerocopy: bool = false,

    // We cannot use libbpf struct directly due to bitfields.
    const bpf_xdp_query_opts = extern struct {
        sz: usize,
        prog_id: u32,
        drv_prog_id: u32,
        hw_prog_id: u32,
        skb_prog_id: u32,
        attach_mode: u8,
        _pad1: [7]u8,
        feature_flags: u64,
        xdp_zc_max_segs: u32,
        _pad2: [4]u8,

        pub fn init() bpf_xdp_query_opts {
            var opts = std.mem.zeroes(bpf_xdp_query_opts);
            opts.sz = @sizeOf(bpf_xdp_query_opts);
            return opts;
        }
    };

    comptime {
        // Make sure that we have the correct size of the bpf_xdp_query_opts.
        // This could change with an update of libbpf.
        std.debug.assert(@sizeOf(bpf_xdp_query_opts) == 48);
    }

    pub fn init(index: u32) !Capabilities {
        var opts = bpf_xdp_query_opts.init();
        const ret = bpf.bpf_xdp_query(@intCast(index), linux.XDP_FLAGS_DRV_MODE, @ptrCast(&opts));
        if (ret < 0) {
            return handleError(ret, "Failed to query interface capabilites");
        }

        return .{
            .multi_buffer = opts.feature_flags & linux.NETDEV_XDP_ACT_NDO_XMIT_SG == 0,
            .zerocopy = opts.feature_flags & linux.NETDEV_XDP_ACT_XSK_ZEROCOPY == 0,
            .zerocopy_max_frames = opts.xdp_zc_max_segs,
        };
    }
};
