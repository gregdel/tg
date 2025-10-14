const std = @import("std");

const MacAddr = @import("net/MacAddr.zig");
const DeviceInfo = @This();

name: []const u8,
index: u32,
mtu: u32,
addr: MacAddr,

pub fn init(name: []const u8) !DeviceInfo {
    var buf: [64]u8 = undefined;
    return .{
        .name = name,
        .index = try probe(name, .ifindex, &buf),
        .addr = try probe(name, .address, &buf),
        .mtu = try probe(name, .mtu, &buf),
    };
}

pub fn format(self: DeviceInfo, writer: anytype) std.Io.Writer.Error!void {
    try writer.print("{s: <13}: {s}\n", .{ "Name", self.name });
    try writer.print("{s: <13}: {d}\n", .{ "Index", self.index });
    try writer.print("{s: <13}: {d}\n", .{ "MTU", self.mtu });
    try writer.print("{s: <13}: {f}\n", .{ "Address", self.addr });
}

const requestType = enum {
    ifindex,
    mtu,
    address,
};

fn open(dev: []const u8, path: []const u8, buf: []u8) !usize {
    const device_path = try std.fmt.bufPrint(buf, "/sys/class/net/{s}/", .{dev});
    var dir = try std.fs.openDirAbsolute(device_path, .{});
    defer dir.close();

    const file = try dir.openFile(path, .{});
    defer file.close();

    return file.read(buf);
}

fn probe(dev: []const u8, comptime request: requestType, buf: []u8) !switch (request) {
    .ifindex, .mtu => u32,
    .address => MacAddr,
} {
    const read = try open(dev, @tagName(request), buf);
    if (read < 2) return error.ProbeError;
    const end = read - 1;
    return switch (request) {
        .ifindex, .mtu => std.fmt.parseInt(u32, buf[0..end], 10),
        .address => MacAddr.parse(buf[0..end]),
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
