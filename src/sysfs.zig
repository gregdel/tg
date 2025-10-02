const std = @import("std");

const DeviceInfo = struct {
    index: u32,
};

pub fn getDeviceInfo(allocator: std.mem.Allocator, dev: []const u8) !DeviceInfo {
    var device_info: DeviceInfo = .{ .index = 0 };
    const device_path = try std.fmt.allocPrint(allocator, "/sys/class/net/{s}/", .{dev});
    const dir = try std.fs.openDirAbsolute(device_path, .{});
    const uevent = try dir.openFile("uevent", .{});
    defer uevent.close();
    const address = try dir.openFile("address", .{});
    defer address.close();

    var buf: [256]u8 = undefined;
    var file_reader = uevent.reader(&buf);

    var reader: *std.Io.Reader = &file_reader.interface;
    while (true) {
        if (reader.takeDelimiterExclusive('\n')) |line| {
            if (!std.mem.startsWith(u8, line, "IFINDEX=")) {
                continue;
            }

            const value_str = line["IFINDEX=".len..];
            const ifindex: u32 = try std.fmt.parseInt(u32, value_str, 10);
            device_info.index = ifindex;
            break;
        } else |err| {
            if (err == error.EndOfStream) break;
            return err;
        }
    }

    std.log.debug("file: {any}, {any}", .{ uevent, address });
    return device_info;
}
