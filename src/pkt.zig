const std = @import("std");

const MacAddr = @import("macaddr.zig");
const Ip = @import("ip.zig");

const Layers = @import("layers/layers.zig").Layers;

pub const PacketBuilder = struct {
    layers: Layers,

    pub fn init(size: u32) !PacketBuilder {
        const pkt_size: u16 = @intCast(size);
        var layers = Layers{};
        try layers.addLayer(.{
            .ethernet = .{
                .src = try MacAddr.parse("de:ad:be:ef:00:00"),
                .dst = try MacAddr.parse("de:ad:be:ef:00:01"),
                .proto = std.os.linux.ETH.P.IP,
            },
        });
        try layers.addLayer(.{
            .ip = .{
                .saddr = try Ip.parse("192.168.1.1"),
                .daddr = try Ip.parse("192.168.1.2"),
                .protocol = std.os.linux.IPPROTO.UDP,
                .tot_len = pkt_size - 14, // TODO
            },
        });
        try layers.addLayer(.{
            .udp = .{
                .source = 1234,
                .dest = 5678,
                .len = pkt_size - (14 + 20), // TODO
            },
        });
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
