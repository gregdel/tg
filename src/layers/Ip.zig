const std = @import("std");

const IpAddr = @import("../net/IpAddr.zig");

const checksum = @import("../net/checksum.zig");

pub const Ip = @This();

version: u4 = 4,
ihl: u4 = 5,
tos: u8 = 0x4,
tot_len: u16 = 0,
id: u16 = 0,
frag_off: u16 = 0,
ttl: u8 = 64,
protocol: u8,
check: u16 = 0,
saddr: IpAddr,
daddr: IpAddr,

pub fn setLen(self: *Ip, len: u16) void {
    self.tot_len = len;
}

pub fn pseudoHeaderCksum(self: *const Ip) !u16 {
    var pseudo_header = [12]u8{
        self.saddr.bytes[0], self.saddr.bytes[1],
        self.saddr.bytes[2], self.saddr.bytes[3],
        self.daddr.bytes[0], self.daddr.bytes[1],
        self.daddr.bytes[2], self.daddr.bytes[3],
        0,                   self.protocol,
        0,                   0,
    };
    std.mem.writeInt(u16, pseudo_header[10..12], self.tot_len - self.size(), .big);
    return checksum.cksum(&pseudo_header, 0);
}

pub fn cksum(self: *const Ip, data: []u8, _: u16) !u16 {
    const sum = try checksum.cksum(data[0..self.size()], 0);
    std.mem.writeInt(u16, data[10..12], sum, .big);
    return self.pseudoHeaderCksum();
}

pub inline fn write(self: *const Ip, writer: anytype) !usize {
    try writer.writeInt(u8, @as(u8, self.version) << 4 | self.ihl, .big);
    try writer.writeInt(u8, self.tos, .big);
    try writer.writeInt(u16, self.tot_len, .big);
    try writer.writeInt(u16, self.id, .big);
    try writer.writeInt(u16, self.frag_off, .big);
    try writer.writeInt(u8, self.ttl, .big);
    try writer.writeInt(u8, self.protocol, .big);
    try writer.writeInt(u16, self.check, .big);
    _ = try self.saddr.write(writer);
    _ = try self.daddr.write(writer);
    return @as(usize, self.ihl) * 4;
}

pub inline fn size(self: *const Ip) u16 {
    return @as(u16, self.ihl) * 4;
}

pub fn format(self: *const Ip, writer: anytype) !void {
    try writer.print("ip src:{f} dst:{f} tot_len:{d} proto:{d}", .{
        self.saddr, self.daddr, self.tot_len, self.protocol,
    });
}

const ipProto = enum(u8) {
    ip = std.os.linux.IPPROTO.IP,
    icmp = std.os.linux.IPPROTO.ICMP,
    ipip = std.os.linux.IPPROTO.IPIP,
    tcp = std.os.linux.IPPROTO.TCP,
    udp = std.os.linux.IPPROTO.UDP,
    ipv6 = std.os.linux.IPPROTO.IPV6,
    gre = std.os.linux.IPPROTO.GRE,
    icmpv6 = std.os.linux.IPPROTO.ICMPV6,
};

pub fn parseIpProto(input: []const u8) !u8 {
    return if (std.meta.stringToEnum(ipProto, input)) |proto|
        @intFromEnum(proto)
    else
        std.fmt.parseInt(u8, input, 10);
}

test "pseudo header checksum" {
    const hdr = Ip{
        .saddr = try IpAddr.parse("192.168.1.1"),
        .daddr = try IpAddr.parse("192.168.1.2"),
        .tot_len = 1458,
        .protocol = 17,
    };
    try std.testing.expectEqual(try hdr.pseudoHeaderCksum(), 0x76FC);
}
