const std = @import("std");

const Ipv6Addr = @This();

bytes: [16]u8,

pub fn parse(s: []const u8) !Ipv6Addr {
    const addr: std.net.Address = try std.net.Address.parseIp6(s, 0);
    return Ipv6Addr{ .bytes = addr.in6.sa.addr };
}

pub fn zero() Ipv6Addr {
    return .{ .bytes = .{0} ** 16 };
}

pub inline fn write(self: *const Ipv6Addr, writer: *std.Io.Writer) !usize {
    return writer.write(&self.bytes);
}

pub fn format(self: *const Ipv6Addr, writer: anytype) !void {
    try writer.print(
        "{x}:{x}:{x}:{x}::",
        .{ self.bytes[0..2], self.bytes[2..4], self.bytes[4..6], self.bytes[6..8] },
    );
}

pub fn fromInt(value: u64) Ipv6Addr {
    var ip = Ipv6Addr.zero();
    std.mem.writeInt(u64, ip.bytes[0..8], value, .big);
    return ip;
}

pub fn toInt(self: *const Ipv6Addr) u64 {
    return std.mem.readInt(u64, self.bytes[0..8], .big);
}

test "parse ipv6" {
    const test_cases = [_][]const u8{
        "2001::",
        "2001:0db8:85a3:a87e:0:0:0:0",
        "fe80::",
        "ffff:ffff:ffff:ffff::",
    };
    for (test_cases) |ip_str| {
        const ip = try Ipv6Addr.parse(ip_str);
        const value = ip.toInt();
        const other = Ipv6Addr.fromInt(value);
        try std.testing.expectEqual(ip, other);
    }
}
