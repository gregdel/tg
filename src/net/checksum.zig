const std = @import("std");

pub fn cksum(data: []const u8, seed: u16) !u16 {
    var sum: u32 = @intCast(seed);
    var pos: usize = 0;

    while (pos < data.len) : (pos += 2) {
        const remaining = data.len - pos;
        if (remaining == 1) {
            sum += @as(u32, data[pos]) << 8;
        } else {
            sum += std.mem.readInt(u16, data[pos..][0..2], .big);
        }
    }

    while (sum > 0xffff) {
        sum = (sum & 0xffff) + (sum >> 16);
    }

    return ~@as(u16, @truncate(sum));
}

test "cksum wikipedia" {
    const data = [_]u8{
        0x45, 0x00, 0x00, 0x73, 0x00,
        0x00, 0x40, 0x00, 0x40, 0x11,
        0x00, 0x00, 0xc0, 0xa8, 0x00,
        0x01, 0xc0, 0xa8, 0x00, 0xc7,
    };

    const sum = cksum(&data, 0);
    try std.testing.expectEqual(0xb861, sum);
}

test "cksum ip pseudo header" {
    const data = [_]u8{
        0xC0, 0xA8, 0x01, 0x01,
        0xC0, 0xA8, 0x01, 0x02,
        0x00, 0x11, 0x05, 0xB2,
    };

    const sum = cksum(&data, 0);
    try std.testing.expectEqual(0x76E8, sum);
}
