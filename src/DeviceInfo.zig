const std = @import("std");

const MacAddr = @import("net/MacAddr.zig");
const DeviceInfo = @This();

name: []const u8,
index: u32 = 0,
mtu: u32 = 1500,
addr: MacAddr = MacAddr.zero(),

pub fn init(name: []const u8) !DeviceInfo {
    var buf: [64]u8 = undefined;
    const info: anyerror!DeviceInfo = .{
        .name = name,
        .index = try parse(u32, name, "ifindex", &buf),
        .addr = try parse(MacAddr, name, "address", &buf),
        .mtu = try parse(u32, name, "mtu", &buf),
    };

    if (info) |value| {
        return value;
    } else |err| return switch (err) {
        error.FileNotFound => error.DeviceNotFound,
        error.Overflow, error.InvalidCharacter => error.DeviceParse,
        MacAddr.ParseError => error.DeciceMacAddrParse,
        else => err,
    };
}

pub fn format(self: DeviceInfo, writer: anytype) std.Io.Writer.Error!void {
    try writer.print("{s: <13}: {s}\n", .{ "Name", self.name });
    try writer.print("{s: <13}: {d}\n", .{ "Index", self.index });
    try writer.print("{s: <13}: {d}\n", .{ "MTU", self.mtu });
    try writer.print("{s: <13}: {f}\n", .{ "Address", self.addr });
}

fn open(dev: []const u8, path: []const u8, buf: []u8) !usize {
    const device_path = try std.fmt.bufPrint(buf, "/sys/class/net/{s}/", .{dev});
    var dir = try std.fs.openDirAbsolute(device_path, .{});
    defer dir.close();

    const file = try dir.openFile(path, .{});
    defer file.close();

    return file.read(buf);
}

fn parse(comptime T: type, dev: []const u8, name: []const u8, buf: []u8) !T {
    const read = try open(dev, name, buf);
    if (read < 2) return error.DeviceParse;
    const end = read - 1;
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(u32, buf[0..end], 10),
        else => switch (T) {
            MacAddr => MacAddr.parse(buf[0..end]),
            else => @compileError("Unsupported type:" ++ @typeName(T)),
        },
    };
}

test "get device info on loopback" {
    const device_info = try DeviceInfo.init("lo");
    // Index should be positive
    try std.testing.expect(device_info.index > 0);
    // MTU should be positive
    try std.testing.expect(device_info.mtu > 0);
    // Loopback typically has a zero MAC address
    try std.testing.expectEqual(MacAddr.zero(), device_info.addr);
}
