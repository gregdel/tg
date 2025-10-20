const std = @import("std");

const cksum = @import("net/checksum.zig");

const MacAddr = @import("net/MacAddr.zig");
const IpAddr = @import("net/IpAddr.zig");

const Layer = @import("layers/layer.zig").Layer;

pub fn build(layers: []const Layer, buf: []u8, seed: u64) !usize {
    var writer = std.Io.Writer.fixed(buf);
    var ret: usize = 0;
    for (layers) |layer| {
        ret += try layer.write(&writer, seed);
    }
    try writer.flush();

    var pseudo_header: u16 = 0;
    var pos: usize = 0;
    for (layers) |layer| {
        pseudo_header = try layer.cksum(buf[pos..], pseudo_header);
        pos += layer.size();
    }

    return ret;
}
