const Udp = @import("udp.zig");
const Ip = @import("ip.zig");
const Eth = @import("eth.zig");

pub const Layer = union(enum) {
    eth: Eth,
    udp: Udp,
    ip: Ip,

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

    pub fn format(self: *const Layer, writer: anytype) !void {
        return switch (self.*) {
            inline else => |layer| try layer.format(writer),
        };
    }

    pub fn write(self: *const Layer, writer: anytype) !usize {
        return switch (self.*) {
            inline else => |layer| layer.write(writer),
        };
    }
};
