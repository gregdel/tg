const std = @import("std");
const linux = std.os.linux;

const EthProto = @This();

pub const unset: u16 = 0xffff;

proto: u16 = unset,

pub fn set(self: *EthProto, value: u16) !void {
    if (self.proto != unset) return error.AlreadySet;
    self.proto = value;
}

pub fn init(input: ?[]const u8) !EthProto {
    const str = input orelse return .{};

    inline for (@typeInfo(linux.ETH.P).@"struct".decls) |field| {
        if (std.ascii.eqlIgnoreCase(str, field.name)) {
            return .{
                .proto = @field(linux.ETH.P, field.name),
            };
        }
    }

    return .{
        .proto = try std.fmt.parseInt(u16, str, 10),
    };
}

pub fn toString(self: *const EthProto) ?[]const u8 {
    inline for (@typeInfo(linux.ETH.P).@"struct".decls) |field| {
        if (@field(linux.ETH.P, field.name) == self.proto) {
            return field.name;
        }
    }
    return null;
}

pub fn write(self: *const EthProto, writer: anytype) !void {
    return writer.writeInt(u16, self.proto, .big);
}

pub fn format(self: *const EthProto, writer: anytype) !void {
    if (self.toString()) |proto| {
        var buf: [16]u8 = undefined;
        const lower_proto = std.ascii.lowerString(&buf, proto);
        try writer.print("{s}(0x{x:0>4})", .{ lower_proto, self.proto });
    } else {
        try writer.print("0x{x:0>4}", .{self.proto});
    }
}

test "init" {
    const test_cases = [_]struct {
        proto: u16,
        input: ?[]const u8,
    }{
        .{ .proto = unset, .input = null },
        .{ .proto = linux.ETH.P.IP, .input = "ip" },
        .{ .proto = linux.ETH.P.IP, .input = "IP" },
        .{ .proto = 0x2a, .input = "42" },
    };

    for (test_cases) |case| {
        try std.testing.expectEqual(
            EthProto{ .proto = case.proto },
            EthProto.init(case.input),
        );
    }
}
