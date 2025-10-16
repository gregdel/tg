const std = @import("std");

const IpAddr = @This();

bytes: [4]u8,

pub fn parse(s: []const u8) !IpAddr {
    var parts = std.mem.splitScalar(u8, s, '.');
    var bytes: [4]u8 = undefined;
    var i: usize = 0;

    while (parts.next()) |part| {
        if (i >= bytes.len) return error.TooManyParts;
        bytes[i] = try std.fmt.parseInt(u8, part, 10);
        i += 1;
    }
    if (i != bytes.len) return error.TooFewParts;
    return IpAddr{ .bytes = bytes };
}

pub fn zero() IpAddr {
    return .{ .bytes = .{0} ** 4 };
}

pub inline fn write(self: *const IpAddr, writer: *std.Io.Writer) !usize {
    return writer.write(&self.bytes);
}

pub fn format(self: *const IpAddr, writer: anytype) !void {
    try writer.print(
        "{d}.{d}.{d}.{d}",
        .{ self.bytes[0], self.bytes[1], self.bytes[2], self.bytes[3] },
    );
}

pub fn fromInt(value: u64) IpAddr {
    var ip = IpAddr.zero();
    std.mem.writeInt(u32, &ip.bytes, @truncate(value), .big);
    return ip;
}

pub fn toInt(self: *const IpAddr) u64 {
    return @as(u64, std.mem.readInt(u32, &self.bytes, .big));
}

test "parse ip" {
    const ip = try IpAddr.parse("192.168.1.1");
    const value = ip.toInt();
    const other = IpAddr.fromInt(value);
    try std.testing.expectEqual(ip, other);
}
