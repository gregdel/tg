const std = @import("std");

const pretty = @import("pretty.zig");
const MacAddr = @import("net/MacAddr.zig");
const CpuSet = @import("CpuSet.zig");
const Capabilities = @import("bpf.zig").Capabilities;
const DeviceInfo = @This();

pub const max_queues = 128;

name: []const u8,
index: u32 = 0,
mtu: u16 = 1500,
speed: ?u64 = 0,
addr: MacAddr = MacAddr.zero(),
queue_count: u16 = 0,
queues: [max_queues]?CpuSet = .{null} ** max_queues,
capabilities: Capabilities,

const sysfs_path = "/sys/class/net/{s}";

pub fn init(name: []const u8) !DeviceInfo {
    var info = parseFiles(name) catch |err| {
        return switch (err) {
            error.FileNotFound => error.DeviceNotFound,
            error.Overflow, error.InvalidCharacter => error.DeviceParse,
            MacAddr.ParseError => error.DeviceMacAddrParse,
            else => err,
        };
    };

    try info.parseQueues();
    info.capabilities = try Capabilities.init(info.index);

    return info;
}

fn parseFiles(name: []const u8) !DeviceInfo {
    var buf: [64]u8 = undefined;

    var speed: ?u64 = parse(u64, name, "speed", &buf) catch null;
    if (speed) |*s| s.* *= 1_000_000;

    return .{
        .name = name,
        .index = try parse(u32, name, "ifindex", &buf),
        .addr = try parse(MacAddr, name, "address", &buf),
        .mtu = try parse(u16, name, "mtu", &buf),
        .speed = speed,
        .capabilities = .{},
    };
}

pub fn format(self: DeviceInfo, writer: anytype) std.Io.Writer.Error!void {
    var speed_buf: [64]u8 = undefined;
    const speed_str: []const u8 = if (self.speed) |speed|
        pretty.printNumber(&speed_buf, speed, "bit/s") catch "Unknown"
    else
        "Unknown";

    try writer.print(
        \\Device:
        \\  Name: {s} (index:{d})
        \\  MTU: {d}
        \\  Address: {f}
        \\  Queues: {d}
        \\  Speed: {s}
        \\  Capabilities:
        \\    Zerocopy: {} (max frames:{d})
        \\    Multi buffer: {}
    ,
        .{
            self.name,
            self.index,
            self.mtu,
            self.addr,
            self.queue_count,
            speed_str,
            self.capabilities.zerocopy,
            self.capabilities.zerocopy_max_frames,
            self.capabilities.multi_buffer,
        },
    );
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
