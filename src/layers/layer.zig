const Eth = @import("Eth.zig");
const Ip = @import("Ip.zig");
const Ipv6 = @import("Ipv6.zig");
const Udp = @import("Udp.zig");
const Vlan = @import("Vlan.zig");
const Vxlan = @import("Vxlan.zig");

pub const Layer = union(enum) {
    eth: Eth,
    ip: Ip,
    ipv6: Ipv6,
    udp: Udp,
    vlan: Vlan,
    vxlan: Vxlan,

    pub fn name(self: Layer) []const u8 {
        return @tagName(self);
    }

    pub fn size(self: *const Layer) u16 {
        return switch (self.*) {
            inline else => |layer| layer.size(),
        };
    }

    pub fn pseudoHeaderCksum(self: *const Layer, data: []const u8) !u16 {
        return switch (self.*) {
            .ip => |layer| layer.pseudoHeaderCksum(data),
            .ipv6 => |layer| layer.pseudoHeaderCksum(data),
            inline else => 0,
        };
    }

    pub fn updateCksum(self: *const Layer, data: []u8, pseudo_header_cksum: u16) !void {
        return switch (self.*) {
            .eth, .vlan, .vxlan, .ipv6 => {},
            inline else => |layer| try layer.updateCksum(data, pseudo_header_cksum),
        };
    }

    pub fn setLen(self: *Layer, len: u16) void {
        return switch (self.*) {
            .eth, .vlan, .vxlan => {},
            inline else => |*layer| layer.setLen(len),
        };
    }

    pub fn setNextProto(self: *Layer, next_proto: ?u16) !void {
        if (next_proto == null) return;
        return switch (self.*) {
            .udp, .vxlan => {},
            inline else => |*layer| layer.setNextProto(next_proto.?),
        };
    }

    pub fn getProto(self: *const Layer) ?u16 {
        return switch (self.*) {
            .eth, .vxlan => null,
            inline else => |layer| layer.getProto(),
        };
    }

    pub fn format(self: *const Layer, writer: anytype) !void {
        return switch (self.*) {
            inline else => |layer| try layer.format(writer),
        };
    }

    pub fn write(self: *const Layer, writer: anytype, seed: u64) !usize {
        return switch (self.*) {
            inline else => |layer| layer.write(writer, seed),
        };
    }
};
