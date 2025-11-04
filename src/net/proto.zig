const std = @import("std");
const linux = std.os.linux;

pub const Eth = enum(u16) {
    _,

    const unset: Eth = @enumFromInt(0xffff);

    pub fn set(self: *Eth, value: u16) !void {
        if (self.* != unset) return error.AlreadySet;
        self.* = @enumFromInt(value);
    }

    pub fn init(input: ?[]const u8) !Eth {
        return enumInit(Eth, Eth.unset, linux.ETH.P, input);
    }

    pub fn write(self: Eth, writer: anytype) !void {
        return writer.writeInt(u16, @intFromEnum(self), .big);
    }

    pub fn format(self: Eth, writer: anytype) !void {
        return enumFormat(self, "{s}(0x{x:0>4})", writer);
    }

    pub fn toString(self: Eth) ?[]const u8 {
        return enumToString(self, linux.ETH.P);
    }
};

pub const Ip = enum(u8) {
    _,

    const unset: Ip = @enumFromInt(linux.IPPROTO.RAW);

    pub fn set(self: *Ip, value: u16) !void {
        if (self.* != unset) return error.AlreadySet;
        if (value >= std.os.linux.IPPROTO.MAX) return error.InvalidIpProto;
        self.* = @enumFromInt(value);
    }

    pub fn init(input: ?[]const u8) !Ip {
        return enumInit(Ip, Ip.unset, linux.IPPROTO, input);
    }

    pub fn write(self: Ip, writer: anytype) !void {
        return writer.writeInt(u8, @intFromEnum(self), .big);
    }

    pub fn asInt(self: Ip) u8 {
        return @intFromEnum(self);
    }

    pub fn format(self: Ip, writer: anytype) !void {
        return enumFormat(self, "{s}({d})", writer);
    }

    pub fn toString(self: Ip) ?[]const u8 {
        return enumToString(self, linux.IPPROTO);
    }
};

fn enumInit(comptime T: type, unset: T, comptime Proto: type, input: ?[]const u8) !T {
    const str = input orelse return unset;
    const TagType = @typeInfo(T).@"enum".tag_type;
    const max_value = std.math.maxInt(TagType);

    inline for (@typeInfo(Proto).@"struct".decls) |field| {
        const value = @field(Proto, field.name);
        if (std.ascii.eqlIgnoreCase(str, field.name)) {
            if (value >= max_value) return unset;
            return @enumFromInt(value);
        }
    }

    return @enumFromInt(try std.fmt.parseInt(TagType, str, 10));
}

fn enumToString(self: anytype, comptime T: type) ?[]const u8 {
    inline for (@typeInfo(T).@"struct".decls) |field| {
        if (@field(T, field.name) == @intFromEnum(self)) {
            return field.name;
        }
    }
    return null;
}

fn enumFormat(self: anytype, comptime fmt: []const u8, writer: anytype) !void {
    if (self.toString()) |proto| {
        var buf: [16]u8 = undefined;
        const lower_proto = std.ascii.lowerString(&buf, proto);
        try writer.print(fmt, .{ lower_proto, @intFromEnum(self) });
    } else {
        try writer.print("{d}", .{@intFromEnum(self)});
    }
}

test "ip init" {
    const test_cases = [_]struct {
        proto: u8,
        input: ?[]const u8,
    }{
        .{ .proto = @intFromEnum(Ip.unset), .input = null },
        .{ .proto = linux.IPPROTO.UDP, .input = "udp" },
        .{ .proto = linux.IPPROTO.TCP, .input = "tcp" },
    };

    for (test_cases) |case| {
        try std.testing.expectEqual(
            @as(Ip, @enumFromInt(case.proto)),
            Ip.init(case.input),
        );
    }
}

test "eth init" {
    const test_cases = [_]struct {
        proto: u16,
        input: ?[]const u8,
    }{
        .{ .proto = @intFromEnum(Eth.unset), .input = null },
        .{ .proto = linux.ETH.P.IP, .input = "ip" },
        .{ .proto = linux.ETH.P.IP, .input = "IP" },
        .{ .proto = 0x2a, .input = "42" },
    };

    for (test_cases) |case| {
        try std.testing.expectEqual(
            @as(Eth, @enumFromInt(case.proto)),
            Eth.init(case.input),
        );
    }
}
