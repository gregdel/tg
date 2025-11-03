const std = @import("std");

const MacAddr = @This();

bytes: [6]u8,

pub const ParseError = error.ParseError;

pub fn parse(s: []const u8) !MacAddr {
    var parts = std.mem.splitScalar(u8, s, ':');
    var out: [6]u8 = undefined;
    var i: usize = 0;

    while (parts.next()) |part| {
        if (i >= out.len) return ParseError;
        if (part.len != 2) return ParseError;
        out[i] = try std.fmt.parseInt(u8, part, 16);
        i += 1;
    }
    if (i != out.len) return ParseError;
    return MacAddr{ .bytes = out };
}

pub fn zero() MacAddr {
    return .{ .bytes = .{0} ** 6 };
}

pub fn write(self: *const MacAddr, writer: *std.Io.Writer) !usize {
    return writer.write(&self.bytes);
}

pub fn format(self: *const MacAddr, writer: anytype) !void {
    try writer.print(
        "{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}",
        .{
            self.bytes[0],
            self.bytes[1],
            self.bytes[2],
            self.bytes[3],
            self.bytes[4],
            self.bytes[5],
        },
    );
}

pub fn fromInt(value: u64) MacAddr {
    var mac = MacAddr.zero();
    std.mem.writeInt(u48, &mac.bytes, @truncate(value), .big);
    return mac;
}

pub fn toInt(self: *const MacAddr) u64 {
    return @as(u64, std.mem.readInt(u48, &self.bytes, .big));
}
