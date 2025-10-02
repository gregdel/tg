const std = @import("std");

pub const MacAddr = struct {
    bytes: [6]u8,

    pub fn parse(s: []const u8) !MacAddr {
        var parts = std.mem.splitScalar(u8, s, ':');
        var out: [6]u8 = undefined;
        var i: usize = 0;

        while (parts.next()) |part| {
            if (i >= out.len) return error.TooManyParts;
            if (part.len != 2) return error.InvalidPart;
            out[i] = try std.fmt.parseInt(u8, part, 16);
            i += 1;
        }
        if (i != out.len) return error.TooFewParts;
        return MacAddr{ .bytes = out };
    }

    pub fn zero() MacAddr {
        var addr: MacAddr = undefined;
        @memset(&addr.bytes, 0);
        return addr;
    }

    pub fn format(self: MacAddr, writer: anytype) !void {
        try writer.print(
            "{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}",
            .{ self.bytes[0], self.bytes[1], self.bytes[2], self.bytes[3], self.bytes[4], self.bytes[5] },
        );
    }
};
