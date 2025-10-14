const std = @import("std");

const cksum = @import("net/checksum.zig");

const MacAddr = @import("net/MacAddr.zig");
const IpAddr = @import("net/IpAddr.zig");

const Layers = @import("layers/Layers.zig");

pub fn build(layers: *const Layers, buf: []u8) !usize {
    var writer = std.Io.Writer.fixed(buf);
    var ret: usize = 0;
    for (layers.entries[0..layers.count]) |layer| {
        ret += try layer.write(&writer);
    }
    try writer.flush();

    var pseudo_header: u16 = 0;
    var pos: usize = 0;
    for (layers.entries[0..layers.count]) |layer| {
        pseudo_header = try layer.cksum(buf[pos..], pseudo_header);
        pos += layer.size();
    }

    return ret;
}
