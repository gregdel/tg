const std = @import("std");

const Vlan = @This();

const Range = @import("../range.zig").Range;
const EthProto = @import("../net/EthProto.zig");

vlan: Range(u12),
proto: EthProto,

pub fn size(_: *const Vlan) u16 {
    return 4;
}

pub inline fn write(self: *const Vlan, writer: anytype, seed: u64) !usize {
    const vlan = self.vlan.get(seed);
    try writer.writeInt(u16, vlan, .big);
    try self.proto.write(writer);
    return self.size();
}

pub fn setNextProto(self: *Vlan, next_proto: u16) !void {
    return self.proto.set(next_proto);
}

pub fn getProto(_: *const Vlan) ?u16 {
    return std.os.linux.ETH.P.P_8021Q;
}

pub fn format(self: *const Vlan, writer: anytype) !void {
    try writer.print("vlan:{f} next_proto:{f}", .{
        self.vlan, self.proto,
    });
}
