const std = @import("std");

const Eth = @This();

const MacAddr = @import("../macaddr.zig");

src: MacAddr,
dst: MacAddr,
proto: u16,

pub inline fn write(self: *const Eth, writer: anytype) !usize {
    const len = @sizeOf(@This());
    var ret: usize = 0;
    ret += try self.src.write(writer);
    ret += try self.dst.write(writer);
    try writer.writeInt(u16, self.proto, .big);
    ret += 2;
    if (ret != len) return error.EthHdrWrite;
    return len;
}

pub inline fn size(_: *const Eth) u16 {
    return 14;
}

pub fn setLen(_: *Eth, _: u16) void {}

pub fn cksum(_: *const Eth, _: []u8, _: u16) !u16 {
    return 0;
}

pub fn format(self: *const Eth, writer: anytype) !void {
    try writer.print("src:{f} dst:{f} proto:{d}", .{
        self.src, self.dst, self.proto,
    });
}

const ethProto = enum(u16) {
    arp = std.os.linux.ETH.P.ARP,
    ip = std.os.linux.ETH.P.IP,
    ipv6 = std.os.linux.ETH.P.IPV6,
};

pub fn parseEthProto(input: []const u8) !u16 {
    return if (std.meta.stringToEnum(ethProto, input)) |proto|
        @intFromEnum(proto)
    else
        std.fmt.parseInt(u16, input, 10);
}
