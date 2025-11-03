const std = @import("std");

const Ip = @import("../layers/Ip.zig");
const checksum = @import("../net/checksum.zig");
const IpProto = @import("../net/IpProto.zig");
const Ipv6Addr = @import("../net/Ipv6Addr.zig");
const Range = @import("../range.zig").Range;

pub const Ipv6 = @This();

version: u4 = 6,
ds: u6 = 0,
ecn: u2 = 0,
flow_label: u20 = 0,
payload_len: u16 = 0,
next_header: IpProto,
hop_limit: u8 = 64,
saddr: Range(Ipv6Addr),
daddr: Range(Ipv6Addr),

pub fn setLen(self: *Ipv6, len: u16) void {
    self.payload_len = len - self.size();
}

pub fn size(_: *const Ipv6) u16 {
    return 40;
}

pub fn setNextProto(self: *Ipv6, next_proto: u16) !void {
    try self.next_header.set(next_proto);
}

pub fn getProto(_: *const Ipv6) ?u16 {
    return std.os.linux.ETH.P.IPV6;
}

pub fn format(self: *const Ipv6, writer: anytype) !void {
    try writer.print("ip src:{f} dst:{f} payload_len:{d} next_header:{f}", .{
        self.saddr, self.daddr, self.payload_len, self.next_header,
    });
}

pub fn pseudoHeaderCksum(self: *const Ipv6, data: []const u8) !u16 {
    const header = data[0..self.size()];
    var pseudo_header: [40]u8 = undefined;
    @memcpy(pseudo_header[0..16], header[8..24]);
    @memcpy(pseudo_header[16..32], header[24..40]);
    std.mem.writeInt(u32, pseudo_header[32..36], self.payload_len, .big);
    pseudo_header[36..40].* = .{ 0, 0, 0, self.next_header.proto };
    return checksum.cksum(&pseudo_header, 0);
}

pub fn write(self: *const Ipv6, writer: anytype, seed: u64) !usize {
    const saddr = self.saddr.get(seed);
    const daddr = self.daddr.get(seed);

    try writer.writeInt(u32, @as(u32, self.version) << 28 |
        @as(u32, self.ds) << 22 |
        @as(u32, self.ecn) << 20 |
        @as(u32, self.flow_label), .big);
    try writer.writeInt(u16, self.payload_len, .big);
    try self.next_header.write(writer);
    try writer.writeInt(u8, self.hop_limit, .big);
    _ = try saddr.write(writer);
    _ = try daddr.write(writer);
    return self.size();
}
