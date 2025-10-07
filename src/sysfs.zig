const std = @import("std");

const MacAddr = @import("macaddr.zig");

const DeviceInfo = struct {
    index: u32,
    addr: MacAddr,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print(
            "ifindex:{d} macaddr:{f}",
            .{ self.index, self.addr },
        );
    }
};

fn open(dev: []const u8, path: []const u8, buf: []u8) !usize {
    const device_path = try std.fmt.bufPrint(buf, "/sys/class/net/{s}/", .{dev});
    var dir = try std.fs.openDirAbsolute(device_path, .{});
    defer dir.close();

    const file = try dir.openFile(path, .{});
    defer file.close();
    var reader = file.reader(buf);

    return try reader.read(buf);
}

fn ifindex(dev: []const u8, buf: []u8) !u32 {
    const read = try open(dev, "ifindex", buf);
    if (read < 2) return error.IfindexParseError;
    return std.fmt.parseInt(u32, buf[0 .. read - 1], 10);
}

fn macaddr(dev: []const u8, buf: []u8) !MacAddr {
    const read = try open(dev, "address", buf);
    if (read != 18) return error.MacAddrParseError;
    return MacAddr.parse(buf[0 .. read - 1]);
}

pub fn getDeviceInfo(dev: []const u8) !DeviceInfo {
    var buf: [64]u8 = undefined;
    return .{
        .index = try ifindex(dev, buf[0..]),
        .addr = try macaddr(dev, buf[0..]),
    };
}

test "get device info on loopback" {
    const device_info = try getDeviceInfo("lo");
    // Index should be positive
    try std.testing.expect(device_info.index > 0);
    // Loopback typically has a zero MAC address
    try std.testing.expectEqual(MacAddr.zero(), device_info.addr);
}
