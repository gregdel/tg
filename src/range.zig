const std = @import("std");

const MacAddr = @import("net/MacAddr.zig");
const IpAddr = @import("net/IpAddr.zig");

const RangeError = error{
    EndBeforeStart,
    ParseError,
};

pub fn Range(comptime T: type) type {
    return struct {
        start: T,
        end: ?T,

        pub fn init(start: T, end: ?T) RangeError!Range(T) {
            if (end) |end_value| {
                const start_64: u64 = toInt(start);
                const end_64: u64 = toInt(end_value);
                if (start_64 > end_64) return RangeError.EndBeforeStart;
            }

            return .{
                .start = start,
                .end = end,
            };
        }

        pub fn get(range: *const Range(T), seed: u64) T {
            if (range.end == null) return range.start;
            const start_64: u64 = toInt(range.start);
            const end_64: u64 = toInt(range.end.?);
            const entries: u64 = end_64 - start_64 + 1;
            return fromInt(start_64 + (seed % entries));
        }

        pub fn fromInt(value: u64) T {
            return switch (@typeInfo(T)) {
                .int => @truncate(value),
                else => switch (T) {
                    MacAddr => MacAddr.fromInt(value),
                    IpAddr => IpAddr.fromInt(value),
                    else => @compileError("Unsupported type:" ++ @typeName(T)),
                },
            };
        }

        pub fn toInt(value: T) u64 {
            return switch (@typeInfo(T)) {
                .int => @intCast(value),
                else => switch (T) {
                    MacAddr => value.toInt(),
                    IpAddr => value.toInt(),
                    else => @compileError("Unsupported type:" ++ @typeName(T)),
                },
            };
        }

        pub fn parse(input: []const u8) RangeError!Range(T) {
            var parts = std.mem.splitScalar(u8, input, '-');
            var from: T = undefined;
            var to: ?T = null;

            var i: usize = 0;
            while (parts.next()) |part| {
                if (i == 2) return error.ParseError;
                const value = switch (@typeInfo(T)) {
                    .int => std.fmt.parseInt(u8, part, 10),
                    else => switch (T) {
                        MacAddr => MacAddr.parse(part),
                        IpAddr => IpAddr.parse(part),
                        else => @compileError("Unsupported type:" ++ @typeName(T)),
                    },
                };

                if (value) |v| {
                    if (i == 0) from = v;
                    if (i == 1) to = v;
                } else |_| {
                    return error.ParseError;
                }
                i += 1;
            }
            if (i == 0) return error.ParseError;

            return Range(T).init(from, to);
        }
    };
}

test "range of u16" {
    const u16_range = try Range(u16).init(0, 16);
    try std.testing.expectEqual(u16_range.start, 0);
    try std.testing.expectEqual(u16_range.end, 16);
}

test "range end greater than start" {
    const result = Range(u16).init(16, 0);
    try std.testing.expectEqual(result, RangeError.EndBeforeStart);
}

test "range of MacAddr" {
    const macaddr_range = try Range(MacAddr).init(
        try MacAddr.parse("de:ad:be:ef:00:00"),
        try MacAddr.parse("de:ad:be:ef:00:ff"),
    );
    const result = macaddr_range.get(2);
    const expected = try MacAddr.parse("de:ad:be:ef:00:02");
    try std.testing.expectEqualSlices(u8, &expected.bytes, &result.bytes);
}

test "parse range of MacAddr" {
    const expected = try Range(MacAddr).init(
        try MacAddr.parse("de:ad:be:ef:00:00"),
        try MacAddr.parse("de:ad:be:ef:00:ff"),
    );

    const result = try Range(MacAddr).parse("de:ad:be:ef:00:00-de:ad:be:ef:00:ff");
    try std.testing.expectEqual(expected, result);
}

test "parse range with single value" {
    const u16_range = try Range(u16).parse("42");
    try std.testing.expectEqual(u16_range.start, 42);
    try std.testing.expectEqual(u16_range.end, null);
}

test "parse invalid range" {
    const inputs: []const []const u8 = &.{
        "0-1-1",
        "0-",
        "x",
        "",
    };
    for (inputs) |input| {
        const result = Range(u16).parse(input);
        try std.testing.expectEqual(result, RangeError.ParseError);
    }
}

test "range of ip" {
    const ipaddr_range = try Range(IpAddr).init(
        try IpAddr.parse("192.168.1.0"),
        try IpAddr.parse("192.168.1.255"),
    );
    const result = ipaddr_range.get(2);
    const expected = try IpAddr.parse("192.168.1.2");
    try std.testing.expectEqual(expected, result);
}
