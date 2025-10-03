const std = @import("std");

pub const IpAddr = struct {
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

    pub inline fn write(self: IpAddr, writer: *std.Io.Writer) !usize {
        return writer.write(&self.bytes);
    }

    pub fn zero() IpAddr {
        var ip: IpAddr = undefined;
        @memset(&ip.bytes, 0);
        return ip;
    }

    pub fn format(self: IpAddr, writer: anytype) !void {
        try writer.print(
            "{d}.{d}.{d}.{d}",
            .{
                self.value.bytes[0],
                self.value.bytes[1],
                self.value.bytes[2],
                self.value.bytes[3],
            },
        );
    }
};
