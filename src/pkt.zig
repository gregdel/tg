const std = @import("std");

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

    pub fn build(self: PacketBuilder, buf: []u8) !usize {
        var writer = std.Io.Writer.fixed(buf);
        var it = self.layers.iterator();
        var ret: usize = 0;
        while (it.next()) |layer| {
            ret += try layer.write(&writer);
        }
        try writer.flush();
        return ret;
    }

    // TODO
    pub fn show(self: *const PacketBuilder) void {
        std.log.debug("{f}", .{self.layers});
    }
};
