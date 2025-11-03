const std = @import("std");

const checksum = @import("../net/checksum.zig");
const IpAddr = @import("../net/IpAddr.zig");
const IpProto = @import("../net/IpProto.zig");
const Range = @import("../range.zig").Range;

const Ip = @This();

version: u4 = 4,
ihl: u4 = 5,
tos: u8 = 0x4,
tot_len: u16 = 0,
id: u16 = 0,
frag_off: u16 = 0,
ttl: u8 = 64,
protocol: IpProto,
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
    pseudo_header[8..10].* = .{ 0, self.protocol.proto };
    std.mem.writeInt(u16, pseudo_header[10..12], self.tot_len - self.size(), .big);
    return checksum.cksum(&pseudo_header, 0);
}

pub fn updateCksum(self: *const Ip, data: []u8, _: u16) !void {
    const header = data[0..self.size()];
    const sum = try checksum.cksum(header, 0);
    std.mem.writeInt(u16, data[10..12], sum, .big);
}

pub fn setNextProto(self: *Ip, next_proto: u16) !void {
    try self.protocol.set(next_proto);
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
    try self.protocol.write(writer);
    try writer.writeInt(u16, self.check, .big);
    _ = try saddr.write(writer);
    _ = try daddr.write(writer);
    return self.size();
}

pub fn size(self: *const Ip) u16 {
    return @as(u16, self.ihl) * 4;
}

pub fn format(self: *const Ip, writer: anytype) !void {
    try writer.print("ip src:{f} dst:{f} tot_len:{d} next_proto:{f}", .{
        self.saddr, self.daddr, self.tot_len, self.protocol,
    });
}

test "pseudo header checksum" {
    const hdr = Ip{
        .saddr = try Range(IpAddr).parse("192.168.1.1"),
        .daddr = try Range(IpAddr).parse("192.168.1.2"),
        .tot_len = 1458,
        .protocol = try IpProto.init("udp"),
    };
    var buffer: [20]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const written = try hdr.write(&writer, 0);
    try writer.flush();
    try std.testing.expectEqual(0x76FC, try hdr.pseudoHeaderCksum(&buffer));
    try std.testing.expectEqual(hdr.size(), written);
}
