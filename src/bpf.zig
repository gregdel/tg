const std = @import("std");
const DeviceInfo = @import("DeviceInfo.zig");

const bpf = @cImport({
    @cInclude("bpf/libbpf.h");
});

const tg_xdp = @embedFile("tg_xdp");

const programs = std.StaticStringMap(void).initComptime(.{
    .{ "tg_pass", .{} },
    .{ "tg_drop", .{} },
});

pub fn attach(dev: []const u8, prog: []const u8) !void {
    programs.get(prog) orelse return error.InvalidXdpProgram;

    const device_info = try DeviceInfo.init(dev);

    var ret = bpf.libbpf_set_strict_mode(bpf.LIBBPF_STRICT_DIRECT_ERRS | bpf.LIBBPF_STRICT_CLEAN_PTRS);
    if (ret < 0) {
        return error.LibBpf;
    }

    const obj = bpf.bpf_object__open_mem(@ptrCast(tg_xdp.ptr), tg_xdp.len, null) orelse {
        return error.BpfObjectOpen;
    };

    ret = bpf.bpf_object__load(obj);
    if (ret < 0) {
        return error.LibBpf;
    }
    errdefer bpf.bpf_object__close(obj);
    defer bpf.bpf_object__close(obj);

    const bpf_prog = bpf.bpf_object__find_program_by_name(obj, @ptrCast(prog)) orelse {
        return error.BpfFindByName;
    };

    const prog_fd = bpf.bpf_program__fd(bpf_prog);
    if (prog_fd < 0) {
        return error.LibBpf;
    }

    ret = bpf.bpf_xdp_attach(@intCast(device_info.index), prog_fd, 0, null);
    if (prog_fd < 0) {
        return error.LibBpf;
    }
}
