const std = @import("std");

const Yaml = @import("yaml").Yaml;

const IpAddr = @import("net/IpAddr.zig");
const MacAddr = @import("net/MacAddr.zig");
const DeviceInfo = @import("DeviceInfo.zig");

const Ip = @import("layers/Ip.zig");
const Eth = @import("layers/Eth.zig");
const Layers = @import("layers/Layers.zig");
const Layer = @import("layers/layer.zig").Layer;

allocator: std.mem.Allocator,

layers: Layers,
dev: []const u8,
threads: u32,
pkt_size: u16,
batch: u32,
ring_size: u32 = 2048,
entries: u32 = 2048 * 2, // XSK_RING_PROD__DEFAULT_NUM_DESCS;
device_info: DeviceInfo,

const Config = @This();

const default_pkt_size = 64;
const default_batch = 64;
const max_file_size = 100_000; // ~100ko

pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Config {
    const file_content = try std.fs.cwd().readFileAlloc(allocator, filename, max_file_size);
    defer allocator.free(file_content);
    return initRaw(allocator, file_content, true);
}

fn initRaw(allocator: std.mem.Allocator, source: []const u8, probe: bool) !Config {
    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(allocator);
    try yaml.load(allocator);

    if (yaml.docs.items.len != 1) return error.InvalidYaml;
    const map = yaml.docs.items[0].map;

    const dev = try allocator.dupe(u8, try getValue([]const u8, map.get("dev")));
    const device_info = if (probe) try DeviceInfo.init(dev) else DeviceInfo{
        .name = dev,
        .index = 0,
        .addr = MacAddr.zero(),
        .mtu = 1500,
    };

    const layers_raw = map.get("layers") orelse return error.InvalidYaml;
    const layer_list = layers_raw.asList() orelse return error.InvalidYaml;

    var layers = Layers{};

    for (layer_list) |layer_value| {
        const layer = layer_value.asMap() orelse return error.InvalidYaml;
        const layer_type = try getValue([]const u8, layer.get("type"));

        if (std.mem.eql(u8, layer_type, "eth")) {
            try layers.addLayer(.{ .eth = .{
                .src = try MacAddr.parse(try getValue([]const u8, layer.get("src"))),
                .dst = try MacAddr.parse(try getValue([]const u8, layer.get("dst"))),
                .proto = try Eth.parseEthProto(
                    try getValue([]const u8, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "ip")) {
            try layers.addLayer(.{ .ip = .{
                .saddr = try IpAddr.parse(try getValue([]const u8, layer.get("src"))),
                .daddr = try IpAddr.parse(try getValue([]const u8, layer.get("dst"))),
                .protocol = try Ip.parseIpProto(
                    try getValue([]const u8, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "udp")) {
            try layers.addLayer(.{ .udp = .{
                .source = try getValue(u16, layer.get("src")),
                .dest = try getValue(u16, layer.get("dst")),
            } });
        }
    }

    const pkt_size = try getValue(?u16, map.get("pkt_size")) orelse default_pkt_size;
    layers.fixSize(pkt_size);

    return .{
        .allocator = allocator,
        .dev = dev,
        .device_info = device_info,
        .pkt_size = pkt_size,
        .threads = 1,
        .batch = try getValue(?u16, map.get("batch")) orelse default_batch,
        .layers = layers,
    };
}

pub fn deinit(self: *const Config) void {
    self.allocator.free(self.dev);
}

pub fn format(self: *const Config, writer: anytype) !void {
    try writer.print("{s: <13}: \n", .{"Device info"});
    try writer.print("{f}", .{self.device_info});
    try writer.print("{s: <13}: {d}\n", .{ "Threads", self.threads });
    try writer.print("{s: <13}: {d}\n", .{ "Batch", self.batch });
    try writer.print("{s: <13}: {d}\n", .{ "Ring size", self.ring_size });
    try writer.print("{s: <13}: {d}\n", .{ "Packet size", self.pkt_size });
    try writer.print("{s: <13}: {d}\n", .{ "Entries", self.entries });
    try writer.print("{s: <13}: \n", .{"Layers"});
    try writer.print("{f}", .{self.layers});
}

fn getValue(comptime MaybeT: type, maybe_value: ?Yaml.Value) !MaybeT {
    const optional = @typeInfo(MaybeT) == .optional;
    if (maybe_value == null) {
        return if (optional) null else error.YamlInvalid;
    }

    const value = maybe_value.?.asScalar() orelse return error.YamlInvalid;
    const T = if (optional) @typeInfo(MaybeT).optional.child else MaybeT;

    return switch (@typeInfo(T)) {
        .int => try std.fmt.parseInt(T, value, 10),
        .pointer => |info| switch (info.size) {
            .slice => return value,
            else => @compileError("Unsupported type for pointer"),
        },
        else => @compileError("Unsupported type:" ++ @typeName(T)),
    };
}

test "parse yaml" {
    const source =
        \\dev: tg0
        \\pkt_size: 1500
        \\batch: 256
        \\layers:
        \\  - type: eth
        \\    src: de:ad:be:ef:00:00
        \\    dst: de:ad:be:ef:00:01
        \\    proto: ip
        \\  - type: ip
        \\    src: 192.168.1.1
        \\    dst: 192.168.1.2
        \\    proto: udp
        \\  - type: udp
        \\    src: 1234
        \\    dst: 5678
    ;
    var config = try initRaw(std.testing.allocator, source, false);
    defer config.deinit();

    try std.testing.expectEqualStrings("tg0", config.dev);
    try std.testing.expectEqual(1500, config.pkt_size);
    try std.testing.expectEqual(256, config.batch);
    try std.testing.expectEqual(3, config.layers.count);
}

test "parse yaml optional" {
    const source =
        \\dev: tg0
        \\layers:
        \\  - type: eth
        \\    src: de:ad:be:ef:00:00
        \\    dst: de:ad:be:ef:00:01
        \\    proto: ip
    ;
    var config = try initRaw(std.testing.allocator, source, false);
    defer config.deinit();
    try std.testing.expectEqual(default_pkt_size, config.pkt_size);
    try std.testing.expectEqual(default_batch, config.batch);
}
