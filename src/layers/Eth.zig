const std = @import("std");

const Eth = @This();

const MacAddr = @import("../net/MacAddr.zig");
const Range = @import("../range.zig").Range;

pub const unset: u16 = 0xffff;

src: Range(MacAddr),
dst: Range(MacAddr),
proto: u16 = unset,

pub inline fn write(self: *const Eth, writer: anytype, seed: u64) !usize {
    const src = self.src.get(seed);
    const dst = self.dst.get(seed);
    _ = try dst.write(writer);
    _ = try src.write(writer);
    try writer.writeInt(u16, self.proto, .big);
    return self.size();
}

pub fn size(_: *const Eth) u16 {
    return 14;
}

pub fn setNextProto(self: *Eth, next_proto: u16) !void {
    if (self.proto != unset) return error.AlreadySet;
    self.proto = next_proto;
}

pub fn format(self: *const Eth, writer: anytype) !void {
    if (std.meta.intToEnum(ethProto, self.proto)) |proto| {
        try writer.print("src:{f} dst:{f} next_proto:{s}(0x{x:0>4})", .{
            self.src, self.dst, @tagName(proto), self.proto,
        });
    } else |_| {
        try writer.print("src:{f} dst:{f} next_proto:0x{x:0>4}", .{
            self.src, self.dst, self.proto,
        });
    }
}

pub const ethProto = enum(u16) {
    arp = std.os.linux.ETH.P.ARP,
    ip = std.os.linux.ETH.P.IP,
    ipv6 = std.os.linux.ETH.P.IPV6,
    vlan = std.os.linux.ETH.P.P_8021Q,
};

pub fn parseEthProto(input: ?[]const u8) !u16 {
    if (input == null) return unset;
    return if (std.meta.stringToEnum(ethProto, input.?)) |proto|
        @intFromEnum(proto)
    else
        std.fmt.parseInt(u16, input.?, 10);
}
