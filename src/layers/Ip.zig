const std = @import("std");

const checksum = @import("../net/checksum.zig");
const IpAddr = @import("../net/IpAddr.zig");
const Range = @import("../range.zig").Range;

const unset: u8 = std.os.linux.IPPROTO.RAW;

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
saddr: Range(IpAddr),
daddr: Range(IpAddr),

pub fn setLen(self: *Ip, len: u16) void {
    self.tot_len = len;
}

pub fn pseudoHeaderCksum(self: *const Ip, data: []const u8) !u16 {
    const header = data[0..self.size()];
    var pseudo_header: [12]u8 = undefined;
    @memcpy(pseudo_header[0..4], header[12..16]);
    @memcpy(pseudo_header[4..8], header[16..20]);
    pseudo_header[8..10].* = .{ 0, self.protocol };
    std.mem.writeInt(u16, pseudo_header[10..12], self.tot_len - self.size(), .big);
    return checksum.cksum(&pseudo_header, 0);
}

pub fn updateCksum(self: *const Ip, data: []u8, _: u16) !void {
    const header = data[0..self.size()];
    const sum = try checksum.cksum(header, 0);
    std.mem.writeInt(u16, data[10..12], sum, .big);
}

pub fn setNextProto(self: *Ip, next_proto: u16) !void {
    if (self.protocol != unset) return error.AlreadySet;
    if (next_proto >= std.os.linux.IPPROTO.MAX) return error.InvalidIpProto;
    self.protocol = @truncate(next_proto);
}

pub fn getProto(_: *const Ip) ?u16 {
    return std.os.linux.ETH.P.IP;
}

pub fn write(self: *const Ip, writer: anytype, seed: u64) !usize {
    const saddr = self.saddr.get(seed);
    const daddr = self.daddr.get(seed);

    try writer.writeInt(u8, @as(u8, self.version) << 4 | self.ihl, .big);
    try writer.writeInt(u8, self.tos, .big);
    try writer.writeInt(u16, self.tot_len, .big);
    try writer.writeInt(u16, self.id, .big);
    try writer.writeInt(u16, self.frag_off, .big);
    try writer.writeInt(u8, self.ttl, .big);
    try writer.writeInt(u8, self.protocol, .big);
    try writer.writeInt(u16, self.check, .big);
    _ = try saddr.write(writer);
    _ = try daddr.write(writer);
    return self.size();
}

pub fn size(self: *const Ip) u16 {
    return @as(u16, self.ihl) * 4;
}

pub fn format(self: *const Ip, writer: anytype) !void {
    if (std.meta.intToEnum(ipProto, self.protocol)) |proto| {
        try writer.print("ip src:{f} dst:{f} tot_len:{d} next_proto:{s}({d})", .{
            self.saddr, self.daddr, self.tot_len, @tagName(proto), self.protocol,
        });
    } else |_| {
        try writer.print("ip src:{f} dst:{f} tot_len:{d} next_proto:{d}", .{
            self.saddr, self.daddr, self.tot_len, self.protocol,
        });
    }
}

pub const ipProto = enum(u8) {
    ip = std.os.linux.IPPROTO.IP,
    icmp = std.os.linux.IPPROTO.ICMP,
    ipip = std.os.linux.IPPROTO.IPIP,
    tcp = std.os.linux.IPPROTO.TCP,
    udp = std.os.linux.IPPROTO.UDP,
    ipv6 = std.os.linux.IPPROTO.IPV6,
    gre = std.os.linux.IPPROTO.GRE,
    icmpv6 = std.os.linux.IPPROTO.ICMPV6,
};

pub fn parseIpProto(input: ?[]const u8) !u8 {
    if (input == null) return unset;
    return if (std.meta.stringToEnum(ipProto, input.?)) |proto|
        @intFromEnum(proto)
    else
        std.fmt.parseInt(u8, input.?, 10);
}

test "pseudo header checksum" {
    const hdr = Ip{
        .saddr = try Range(IpAddr).parse("192.168.1.1"),
        .daddr = try Range(IpAddr).parse("192.168.1.2"),
        .tot_len = 1458,
        .protocol = 17,
    };
    var buffer: [20]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const written = try hdr.write(&writer, 0);
    try writer.flush();
    try std.testing.expectEqual(0x76FC, try hdr.pseudoHeaderCksum(&buffer));
    try std.testing.expectEqual(hdr.size(), written);
}
