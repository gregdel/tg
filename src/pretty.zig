const std = @import("std");

pub fn printNumber(buf: []u8, value: u64, suffix: []const u8) ![]u8 {
    const units = [_]?u8{ null, 'k', 'M', 'G', 'T', 'P', 'E' };

    var index: usize = 0;
    var current: f64 = @floatFromInt(value);
    for (units, 0..) |_, i| {
        index = i;
        if (current < 1000) break;
        current /= 1000;
    }

    const no_decimals = (current * 100 == @round(current) * 100);

    var value_buf: [6]u8 = undefined; // xxx.xx
    const value_str: []u8 = if (no_decimals)
        try std.fmt.bufPrint(&value_buf, "{d}", .{current})
    else
        try std.fmt.bufPrint(&value_buf, "{d:.2}", .{current});

    return if (units[index]) |unit|
        try std.fmt.bufPrint(buf, "{s}{c}{s}", .{ value_str, unit, suffix })
    else
        try std.fmt.bufPrint(buf, "{s}{s}", .{ value_str, suffix });
}

test "print number" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("1bit/s", try printNumber(&buf, 1, "bit/s"));
    try std.testing.expectEqualStrings("1kbit/s", try printNumber(&buf, 1_000, "bit/s"));
    try std.testing.expectEqualStrings("10Gbit/s", try printNumber(&buf, 10_000_000_000, "bit/s"));
    try std.testing.expectEqualStrings("1.23kbit/s", try printNumber(&buf, 1_234, "bit/s"));
    try std.testing.expectEqualStrings("1.23Mbit/s", try printNumber(&buf, 1_234_456, "bit/s"));
}
