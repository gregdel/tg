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

fn handleError(err: c_int, msg: []const u8) !void {
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
