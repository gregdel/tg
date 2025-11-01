const std = @import("std");

const Eth = @import("Eth.zig");

pub const Gre = @This();

flags: u16 = 0,
proto: u16 = Eth.unset,

pub fn size(_: *const Gre) u16 {
    return 4;
}

pub inline fn write(self: *const Gre, writer: anytype, _: u64) !usize {
    try writer.writeInt(u16, self.flags, .big);
    try writer.writeInt(u16, self.proto, .big);
    return self.size();
}

pub fn setNextProto(self: *Gre, next_proto: u16) !void {
    if (self.proto != Eth.unset) return error.AlreadySet;
    self.proto = next_proto;
}

pub fn getProto(_: *const Gre) ?u16 {
    return std.os.linux.IPPROTO.GRE;
}

pub fn format(self: *const Gre, writer: anytype) !void {
    if (std.meta.intToEnum(Eth.ethProto, self.proto)) |proto| {
        try writer.print("next_proto:{s}(0x{x:0>4})", .{
            @tagName(proto), self.proto,
        });
    } else |_| {
        try writer.print("next_proto:0x{x:0>4}", .{
            self.proto,
        });
    }
}
