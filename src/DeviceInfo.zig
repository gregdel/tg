const std = @import("std");

const pretty = @import("pretty.zig");
const MacAddr = @import("net/MacAddr.zig");
const CpuSet = @import("CpuSet.zig");
const DeviceInfo = @This();

pub const max_queues = 128;

name: []const u8,
index: u32 = 0,
mtu: u32 = 1500,
speed: u64 = 0,
addr: MacAddr = MacAddr.zero(),
queue_count: u16 = 0,
queues: [max_queues]?CpuSet = .{null} ** max_queues,

const sysfs_path = "/sys/class/net/{s}";

pub fn init(name: []const u8) !DeviceInfo {
    var info: DeviceInfo = undefined;
    if (parseFiles(name)) |value| {
        info = value;
    } else |err| return switch (err) {
        error.FileNotFound => error.DeviceNotFound,
        error.Overflow, error.InvalidCharacter => error.DeviceParse,
        MacAddr.ParseError => error.DeciceMacAddrParse,
        else => err,
    };

    try info.parseQueues();

    return info;
}

fn parseFiles(name: []const u8) !DeviceInfo {
    var buf: [64]u8 = undefined;
    return .{
        .name = name,
        .index = try parse(u32, name, "ifindex", &buf),
        .addr = try parse(MacAddr, name, "address", &buf),
        .mtu = try parse(u32, name, "mtu", &buf),
        .speed = try parse(u64, name, "speed", &buf) * 1_000_000,
    };
}

pub fn format(self: DeviceInfo, writer: anytype) std.Io.Writer.Error!void {
    var buf: [64]u8 = undefined;
    const fmt = "{s: <13}: ";
    try writer.print(fmt ++ "{s}\n", .{ "Name", self.name });
    try writer.print(fmt ++ "{d}\n", .{ "Index", self.index });
    try writer.print(fmt ++ "{d}\n", .{ "MTU", self.mtu });
    if (pretty.printNumber(&buf, self.speed, "bit/s")) |speed| {
        try writer.print(fmt ++ "{s}\n", .{ "Speed", speed });
    } else |_| {}
    try writer.print(fmt ++ "{f}\n", .{ "Address", self.addr });
    try writer.print(fmt ++ "{d}\n", .{ "Queues", self.queue_count });
}

fn open(dev: []const u8, path: []const u8, buf: []u8) !usize {
    const device_path = try std.fmt.bufPrint(buf, sysfs_path, .{dev});
    var dir = try std.fs.openDirAbsolute(device_path, .{});
    defer dir.close();

    const file = try dir.openFile(path, .{});
    defer file.close();

    return file.read(buf);
}

pub fn parseQueues(self: *DeviceInfo) !void {
    var buf: [64]u8 = undefined;
    const base_path = sysfs_path ++ "/queues/";
    const device_path = try std.fmt.bufPrint(&buf, base_path, .{self.name});
    var dir = try std.fs.openDirAbsolute(device_path, .{ .iterate = true });

    var iter = dir.iterate();

    const xps_cpus_fmt = base_path ++ "tx-{d}/xps_cpus";
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "tx-")) continue;
        const queue = try std.fmt.parseInt(u16, entry.name[3..], 10);

        const xps_cpus_path = try std.fmt.bufPrint(
            &buf,
            xps_cpus_fmt,
            .{ self.name, queue },
        );
        var file = std.fs.openFileAbsolute(xps_cpus_path, .{}) catch continue;
        errdefer file.close();

        const read = file.read(&buf) catch continue;
        const end = read - 1;
        self.queues[queue] = try CpuSet.parse(buf[0..end]);
        self.queue_count += 1;

        file.close();
    }

    return;
}

fn parse(comptime T: type, dev: []const u8, name: []const u8, buf: []u8) !T {
    const read = try open(dev, name, buf);
    if (read < 2) return error.DeviceParse;
    const end = read - 1;
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, buf[0..end], 10),
        else => switch (T) {
            MacAddr => MacAddr.parse(buf[0..end]),
            else => @compileError("Unsupported type:" ++ @typeName(T)),
        },
    };
}
