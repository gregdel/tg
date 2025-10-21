const Eth = @import("Eth.zig");
const Ip = @import("Ip.zig");
const Udp = @import("Udp.zig");
const Vlan = @import("Vlan.zig");

pub const Layer = union(enum) {
    eth: Eth,
    ip: Ip,
    udp: Udp,
    vlan: Vlan,

    pub fn name(self: Layer) []const u8 {
        return @tagName(self);
    }

    pub fn size(self: *const Layer) u16 {
        return switch (self.*) {
            inline else => |layer| layer.size(),
        };
    }

    pub fn cksum(self: *const Layer, data: []u8, seed: u16) !u16 {
        return switch (self.*) {
            inline else => |layer| try layer.cksum(data, seed),
        };
    }

    pub fn setLen(self: *Layer, len: u16) void {
        return switch (self.*) {
            inline else => |*layer| layer.setLen(len),
        };
    }

    pub fn setNextProto(self: *Layer, next_proto: ?u16) !void {
        if (next_proto == null) return;
        return switch (self.*) {
            inline else => |*layer| layer.setNextProto(next_proto.?),
        };
    }

    pub fn getProto(self: *const Layer) ?u16 {
        return switch (self.*) {
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
