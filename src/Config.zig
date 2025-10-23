const std = @import("std");

const Yaml = @import("yaml").Yaml;

const IpAddr = @import("net/IpAddr.zig");
const MacAddr = @import("net/MacAddr.zig");
const Range = @import("range.zig").Range;
const DeviceInfo = @import("DeviceInfo.zig");
const SocketConfig = @import("Socket.zig").SocketConfig;
const CliArgs = @import("CliArgs.zig");

const Ip = @import("layers/Ip.zig");
const Eth = @import("layers/Eth.zig");
const Layers = @import("layers/Layers.zig");
const Layer = @import("layers/layer.zig").Layer;

allocator: std.mem.Allocator,
layers: Layers,
socket_config: SocketConfig,
device_info: DeviceInfo,
threads: u32,

const Config = @This();

const default_batch = 64;
const max_file_size = 100_000; // ~100ko
const default_entries = @import("Socket.zig").ring_size;

pub fn init(allocator: std.mem.Allocator, cli_args: *const CliArgs) !Config {
    if (cli_args.config == null) return error.MissingConfigFile;
    const file_content = try std.fs.cwd().readFileAlloc(allocator, cli_args.config.?, max_file_size);
    defer allocator.free(file_content);
    return initRaw(allocator, cli_args, file_content, true);
}

fn initRaw(allocator: std.mem.Allocator, cli_args: *const CliArgs, source: []const u8, probe: bool) !Config {
    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(allocator);
    try yaml.load(allocator);

    if (yaml.docs.items.len != 1) return error.InvalidYaml;
    const map = yaml.docs.items[0].map;

    const tmp_dev = if (cli_args.dev) |dev|
        dev
    else
        getValue([]const u8, map.get("dev")) catch return error.ConfigMissingDev;

    const dev = try allocator.dupe(u8, tmp_dev);
    errdefer allocator.free(dev);

    const device_info = if (probe) try DeviceInfo.init(dev) else DeviceInfo{
        .name = dev,
    };

    const layers_raw = map.get("layers") orelse return error.ConfigMissingLayers;
    const layer_list = layers_raw.asList() orelse return error.ConfigMissingLayers;

    var layers = Layers{};

    for (layer_list) |layer_value| {
        const layer = layer_value.asMap() orelse return error.InvalidYaml;
        const layer_type = try getValue([]const u8, layer.get("type"));

        if (std.mem.eql(u8, layer_type, "eth")) {
            try layers.addLayer(.{ .eth = .{
                .src = try Range(MacAddr).parse(try getValue([]const u8, layer.get("src"))),
                .dst = try Range(MacAddr).parse(try getValue([]const u8, layer.get("dst"))),
                .proto = try Eth.parseEthProto(
                    try getValue(?[]const u8, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "vlan")) {
            try layers.addLayer(.{ .vlan = .{
                .vlan = try Range(u12).parse(try getValue([]const u8, layer.get("vlan"))),
                .proto = try Eth.parseEthProto(
                    try getValue(?[]const u8, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "vxlan")) {
            try layers.addLayer(.{ .vxlan = .{
                .vni = try Range(u24).parse(try getValue([]const u8, layer.get("vni"))),
            } });
        }

        if (std.mem.eql(u8, layer_type, "ip")) {
            try layers.addLayer(.{ .ip = .{
                .saddr = try Range(IpAddr).parse(try getValue([]const u8, layer.get("src"))),
                .daddr = try Range(IpAddr).parse(try getValue([]const u8, layer.get("dst"))),
                .protocol = try Ip.parseIpProto(
                    try getValue(?[]const u8, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "udp")) {
            try layers.addLayer(.{ .udp = .{
                .source = try getIntRangeValue(u16, layer.get("src")),
                .dest = try getIntRangeValue(u16, layer.get("dst")),
            } });
        }
    }

    const pkt_size = try getValue(?u16, map.get("pkt_size")) orelse layers.minSize();
    layers.fixSize(pkt_size);
    try layers.fixMissingNextHeader();

    const frames_per_packet: u8 = @truncate(pkt_size / std.heap.pageSize() + 1);
    var batch = try getValue(?u16, map.get("batch")) orelse default_batch;
    // Adjust the batch size to be a multiple of frames_per_packet
    batch -= batch % frames_per_packet;

    // Adjust the umem entries to be a multiple of frames_per_packet
    var entries: u32 = default_entries;
    entries -= entries % frames_per_packet;

    // The number of threads might be limited by the number of queues
    var threads = try getValue(?u32, map.get("threads")) orelse device_info.queue_count;
    threads = @min(threads, device_info.queue_count);

    return .{
        .allocator = allocator,
        .threads = threads,
        .device_info = device_info,
        .layers = layers,
        .socket_config = .{
            .dev = dev,
            .pkt_size = pkt_size,
            .entries = entries,
            .frames_per_packet = frames_per_packet,
            .pre_fill = try getValue(?bool, map.get("pre_fill")) orelse false,
            .pkt_count = try getValue(?u64, map.get("count")),
            .pkt_batch = batch,
            .layers = layers,
        },
    };
}

pub fn deinit(self: *const Config) void {
    self.allocator.free(self.socket_config.dev);
}

pub fn format(self: *const Config, writer: anytype) !void {
    const fmt = "{s: <18}";
    const fmtTitle = fmt ++ ":\n";
    const fmtNumber = fmt ++ ": {d}\n";
    try writer.print("{f}", .{self.device_info});
    try writer.print("{f}", .{self.socket_config});
    try writer.print(fmtNumber, .{ "Threads", self.threads });
    try writer.print(fmtTitle, .{"Layers"});
    try writer.print("{f}", .{self.layers});
}

fn parseBool(str: []const u8) !bool {
    if (std.mem.eql(u8, str, "true")) return true;
    if (std.mem.eql(u8, str, "false")) return false;
    return error.YamlInvalid;
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
        .bool => try parseBool(value),
        .pointer => |info| switch (info.size) {
            .slice => return value,
            else => @compileError("Unsupported pointer type " ++ @tagName(info.size)),
        },
        else => @compileError("Unsupported type:" ++ @typeName(T)),
    };
}

fn getIntRangeValue(comptime T: type, maybe_value: ?Yaml.Value) !Range(T) {
    if (@typeInfo(T) != .int) {
        @compileError("This function only handles intergers");
    }

    // First try to parse the value as type T. If this fails, parse it as a
    // range from a string.
    if (getValue(T, maybe_value)) |value| {
        return try Range(T).init(value, null);
    } else |_| {
        return try Range(T).parse(try getValue([]const u8, maybe_value));
    }
}

test "parse yaml" {
    const source =
        \\dev: tg0
        \\pkt_size: 1500
        \\batch: 256
        \\count: 1024
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
    const cli_args = CliArgs{ .cmd = .send };
    var config = try initRaw(std.testing.allocator, &cli_args, source, false);
    defer config.deinit();

    try std.testing.expectEqualStrings("tg0", config.socket_config.dev);
    try std.testing.expectEqual(1500, config.socket_config.pkt_size);
    try std.testing.expectEqual(256, config.socket_config.pkt_batch);
    try std.testing.expectEqual(1024, config.socket_config.pkt_count);
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
    const cli_args = CliArgs{ .cmd = .send };
    var config = try initRaw(std.testing.allocator, &cli_args, source, false);
    defer config.deinit();
    try std.testing.expectEqual(config.layers.minSize(), config.socket_config.pkt_size);
    try std.testing.expectEqual(default_batch, config.socket_config.pkt_batch);
}
