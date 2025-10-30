const std = @import("std");

const units = [_]?u8{ null, 'k', 'M', 'G', 'T', 'P', 'E' };

pub fn parseNumber(comptime T: type, input: []const u8) !T {
    if (input.len == 0) return error.InvalidCharacter;

    const last_i = input.len - 1;
    const last = input[last_i];
    if (std.ascii.isDigit(last)) {
        return std.fmt.parseInt(T, input, 10);
    }

    const number_part = input[0..last_i];
    if (number_part.len == 0) return error.InvalidCharacter;

    const base_value = try std.fmt.parseInt(T, number_part, 10);

    var factor: T = 1;
    var found = false;
    for (units[1..]) |unit| {
        factor *= 1000;
        if (std.ascii.toLower(last) == std.ascii.toLower(unit.?)) {
            found = true;
            break;
        }
    }
    if (!found) return error.ParseError;

    // Check for overflow
    const result = @mulWithOverflow(base_value, factor);
    if (result[1] != 0) return error.Overflow;

    return result[0];
}

pub fn printNumber(buf: []u8, value: u64, suffix: []const u8) ![]u8 {
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

test "parse number" {
    try std.testing.expectEqual(1_000, try parseNumber(u16, "1k"));
    try std.testing.expectEqual(1_000, try parseNumber(u16, "1K"));
    try std.testing.expectEqual(10_000, try parseNumber(u32, "10k"));
    try std.testing.expectEqual(1_000_000, try parseNumber(u64, "1M"));
    try std.testing.expectEqual(3_000_000_000, try parseNumber(u64, "3G"));
    try std.testing.expectEqual(123, try parseNumber(u64, "123"));
    try std.testing.expectEqual(error.InvalidCharacter, parseNumber(u16, ""));
    try std.testing.expectEqual(error.InvalidCharacter, parseNumber(u16, "k"));
}
