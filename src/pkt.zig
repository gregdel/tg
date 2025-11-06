const std = @import("std");

const Layers = @import("layers/Layers.zig");

pub fn build(layers: Layers, buf: []u8, seed: u64) !void {
    var writer = std.Io.Writer.fixed(buf);
    var pos: usize = 0;
    for (layers.entries.items) |layer| {
        pos += try layer.write(&writer, seed);
    }
    try writer.flush();

    // For now don't write anything at the end of the packet, it's all zeroes
    // so we don't need to do the checksum on it.
    const end_of_packet = pos + 1;

    var i = layers.entries.items.len;
    while (i > 0) {
        i -= 1;
        var current = layers.entries.items[i];
        pos -= current.size();

        const pseudo_header: u16 = if (i > 0) blk: {
            const prev = layers.entries.items[i - 1];
            const start = pos - prev.size();
            break :blk try prev.pseudoHeaderCksum(buf[start..end_of_packet]);
        } else 0;

        try current.updateCksum(buf[pos..end_of_packet], pseudo_header);
    }
}
