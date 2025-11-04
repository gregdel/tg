const std = @import("std");

const EthProto = @import("../net/proto.zig").Eth;

const Gre = @This();

flags: u16 = 0,
proto: EthProto,

pub fn size(_: *const Gre) u16 {
    return 4;
}

pub fn write(self: *const Gre, writer: anytype, _: u64) !usize {
    try writer.writeInt(u16, self.flags, .big);
    try self.proto.write(writer);
    return self.size();
}

pub fn setNextProto(self: *Gre, next_proto: u16) !void {
    return self.proto.set(next_proto);
}

pub fn getProto(_: *const Gre) ?u16 {
    return std.os.linux.IPPROTO.GRE;
}

pub fn format(self: *const Gre, writer: anytype) !void {
    try writer.print("next_proto:{f}", .{self.proto});
}
