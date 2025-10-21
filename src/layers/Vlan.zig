const std = @import("std");

const Vlan = @This();

const Range = @import("../range.zig").Range;
const ethProto = @import("Eth.zig").ethProto;

const unset: u16 = @import("Eth.zig").unset;

vlan: Range(u12),
proto: u16 = unset,

pub fn size(_: *const Vlan) u16 {
    return 4;
}

pub inline fn write(self: *const Vlan, writer: anytype, seed: u64) !usize {
    const vlan = self.vlan.get(seed);
    try writer.writeInt(u16, vlan, .big);
    try writer.writeInt(u16, self.proto, .big);
    return self.size();
}

pub fn setNextProto(self: *Vlan, next_proto: u16) !void {
    if (self.proto != unset) return error.AlreadySet;
    self.proto = next_proto;
}

pub fn getProto(_: *const Vlan) ?u16 {
    return std.os.linux.ETH.P.P_8021Q;
}

pub fn format(self: *const Vlan, writer: anytype) !void {
    if (std.meta.intToEnum(ethProto, self.proto)) |proto| {
        try writer.print("vlan:{f} next_proto:{s}(0x{x:0>4})", .{
            self.vlan, @tagName(proto), self.proto,
        });
    } else |_| {
        try writer.print("vlan:{f} next_proto:0x{x:0>4}", .{
            self.vlan, self.proto,
        });
    }
}
