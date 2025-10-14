const std = @import("std");

const cksum = @import("layers/checksum.zig");

const MacAddr = @import("macaddr.zig");
const Ip = @import("ip.zig");

const Layers = @import("layers/layers.zig").Layers;

pub const PacketBuilder = struct {
    layers: Layers,

    pub fn init(layers: Layers) !PacketBuilder {
        return .{
            .layers = layers,
        };
    }

    pub fn build(self: *PacketBuilder, buf: []u8) !usize {
        var writer = std.Io.Writer.fixed(buf);
        var it = self.layers.iterator();
        var ret: usize = 0;
        while (it.next()) |layer| {
            ret += try layer.write(&writer);
        }
        try writer.flush();

        it.reset();
        var pseudo_header: u16 = 0;
        var pos: usize = 0;
        while (it.next()) |layer| {
            pseudo_header = try layer.cksum(buf[pos..], pseudo_header);
            pos += layer.size();
        }

        return ret;
    }

    // TODO
    pub fn show(self: *const PacketBuilder) void {
        std.log.debug("{f}", .{self.layers});
    }
};
