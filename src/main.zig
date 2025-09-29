const std = @import("std");
const tg = @import("tg");

const LibXdp = @cImport({
    @cInclude("xdp/libxdp.h");
});

const c = @cImport({
    @cInclude("net/if.h");
});

pub fn main() !void {
    const ifname = "tg0";
    const index = c.if_nametoindex(ifname);
    if (index == 0) {
        std.debug.print("Failed to find ifindex for {s}\n", .{ifname});
        return;
    }

    std.debug.print("Got index for {s}: {d}\n", .{ ifname, index });

    // LibXdp.bpf_xdp_query(ifindex: c_int, flags: c_int, opts: ?*struct_bpf_xdp_query_opts)
    std.debug.print("Tg: {any}\n", .{LibXdp.XDP_ABORTED});
}
