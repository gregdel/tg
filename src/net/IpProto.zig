const std = @import("std");
const linux = std.os.linux;

const IpProto = @This();

const unset: u8 = linux.IPPROTO.RAW;

proto: u8 = unset,

pub fn set(self: *IpProto, value: u16) !void {
    if (self.proto != unset) return error.AlreadySet;
    if (value >= std.os.linux.IPPROTO.MAX) return error.InvalidIpProto;
    self.proto = @truncate(value);
}

pub fn init(input: ?[]const u8) !IpProto {
    const str = input orelse return .{};

    inline for (@typeInfo(linux.IPPROTO).@"struct".decls) |field| {
        const value = @field(linux.IPPROTO, field.name);
        if (value == linux.IPPROTO.MAX) continue;

        if (std.ascii.eqlIgnoreCase(str, field.name)) {
            return .{ .proto = value };
        }
    }

    return .{
        .proto = try std.fmt.parseInt(u8, str, 10),
    };
}

pub fn toString(self: *const IpProto) ?[]const u8 {
    inline for (@typeInfo(linux.IPPROTO).@"struct".decls) |field| {
        if (@field(linux.IPPROTO, field.name) == self.proto) {
            return field.name;
        }
    }
    return null;
}

pub fn write(self: *const IpProto, writer: anytype) !void {
    return writer.writeInt(u8, self.proto, .big);
}

pub fn format(self: *const IpProto, writer: anytype) !void {
    if (self.toString()) |proto| {
        var buf: [16]u8 = undefined;
        const lower_proto = std.ascii.lowerString(&buf, proto);
        try writer.print("{s}({d})", .{ lower_proto, self.proto });
    } else {
        try writer.print("{d}", .{self.proto});
    }
}

test "init" {
    const test_cases = [_]struct {
        proto: u8,
        input: ?[]const u8,
    }{
        .{ .proto = unset, .input = null },
        .{ .proto = linux.IPPROTO.UDP, .input = "udp" },
        .{ .proto = linux.IPPROTO.TCP, .input = "tcp" },
    };

    for (test_cases) |case| {
        try std.testing.expectEqual(
            IpProto{ .proto = case.proto },
            IpProto.init(case.input),
        );
    }
}
