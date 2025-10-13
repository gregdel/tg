const std = @import("std");

const Ip = @This();

bytes: [4]u8,

pub fn parse(s: []const u8) !Ip {
    var parts = std.mem.splitScalar(u8, s, '.');
    var bytes: [4]u8 = undefined;
    var i: usize = 0;

    while (parts.next()) |part| {
        if (i >= bytes.len) return error.TooManyParts;
        bytes[i] = try std.fmt.parseInt(u8, part, 10);
        i += 1;
    }
    if (i != bytes.len) return error.TooFewParts;
    return Ip{ .bytes = bytes };
}

pub fn zero() Ip {
    return .{ .bytes = .{0} ** 4 };
}

pub inline fn write(self: *const Ip, writer: *std.Io.Writer) !usize {
    return writer.write(&self.bytes);
}

pub fn format(self: *const Ip, writer: anytype) !void {
    try writer.print(
        "{d}.{d}.{d}.{d}",
        .{ self.bytes[0], self.bytes[1], self.bytes[2], self.bytes[3] },
    );
}
