const std = @import("std");

const cksum = @import("net/checksum.zig");

const MacAddr = @import("net/MacAddr.zig");
const IpAddr = @import("net/IpAddr.zig");

const Layer = @import("layers/layer.zig").Layer;

pub fn build(layers: []const Layer, buf: []u8, seed: u64) !void {
    var writer = std.Io.Writer.fixed(buf);
    var pos: usize = 0;
    for (layers) |layer| {
        pos += try layer.write(&writer, seed);
    }
    try writer.flush();

    var i = layers.len;
    while (i > 0) {
        i -= 1;

        var current = layers[i];
        pos -= current.size();

        const pseudo_header: u16 = if (i > 0) blk: {
            const prev = layers[i - 1];
            const start = pos - prev.size();
            if (start >= buf.len or pos >= buf.len) unreachable;
            break :blk try prev.pseudoHeaderCksum(buf[start..]);
        } else 0;

        try current.updateCksum(buf[pos..], pseudo_header);
    }
}
