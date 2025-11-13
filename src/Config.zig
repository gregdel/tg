const std = @import("std");

const Yaml = @import("yaml").Yaml;

const EthProto = @import("net/proto.zig").Eth;
const IpAddr = @import("net/IpAddr.zig");
const IpProto = @import("net/proto.zig").Ip;
const Ipv6Addr = @import("net/Ipv6Addr.zig");
const MacAddr = @import("net/MacAddr.zig");
const Range = @import("range.zig").Range;
const DeviceInfo = @import("DeviceInfo.zig");
const SocketConfig = @import("Socket.zig").SocketConfig;
const CliArgs = @import("CliArgs.zig");
const pretty = @import("pretty.zig");

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
const default_umem_entries = @import("Socket.zig").ring_size;

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
        getStringValue(map, "dev") catch return error.ConfigMissingDev;

    const dev = try allocator.dupe(u8, tmp_dev);
    errdefer allocator.free(dev);

    const device_info = if (probe) try DeviceInfo.init(dev) else DeviceInfo{
        .name = dev,
        .capabilities = .{},
    };

    const layers_raw = map.get("layers") orelse return error.ConfigMissingLayers;
    const layer_list = layers_raw.asList() orelse return error.ConfigMissingLayers;

    var layers = try Layers.init(allocator, layer_list.len);
    errdefer layers.deinit();
    for (layer_list) |layer_value| {
        const layer = layer_value.asMap() orelse return error.InvalidYaml;
        const layer_type = std.meta.stringToEnum(
            std.meta.Tag(Layer),
            try getStringValue(layer, "type"),
        ) orelse return error.InvalidYaml;

        switch (layer_type) {
            .eth => try layers.addLayer(.{ .eth = .{
                .src = try Range(MacAddr).parse(try getStringValue(layer, "src")),
                .dst = try Range(MacAddr).parse(try getStringValue(layer, "dst")),
                .proto = try EthProto.init(try getOptionalStringValue(layer, "proto")),
            } }),
            .gre => try layers.addLayer(.{ .gre = .{
                .proto = try EthProto.init(try getOptionalStringValue(layer, "proto")),
            } }),
            .vlan => try layers.addLayer(.{ .vlan = .{
                .vlan = try Range(u12).parse(try getStringValue(layer, "vlan")),
                .proto = try EthProto.init(try getOptionalStringValue(layer, "proto")),
            } }),
            .vxlan => try layers.addLayer(.{ .vxlan = .{
                .vni = try Range(u24).parse(try getStringValue(layer, "vni")),
            } }),
            .ip => try layers.addLayer(.{ .ip = .{
                .saddr = try Range(IpAddr).parse(try getStringValue(layer, "src")),
                .daddr = try Range(IpAddr).parse(try getStringValue(layer, "dst")),
                .protocol = try IpProto.init(try getOptionalStringValue(layer, "proto")),
            } }),
            .udp => try layers.addLayer(.{ .udp = .{
                .source = try getIntRangeValue(u16, layer, "src"),
                .dest = try getIntRangeValue(u16, layer, "dst"),
            } }),
            .ipv6 => try layers.addLayer(.{ .ipv6 = .{
                .saddr = try Range(Ipv6Addr).parse(try getStringValue(layer, "src")),
                .daddr = try Range(Ipv6Addr).parse(try getStringValue(layer, "dst")),
                .next_header = try IpProto.init(try getOptionalStringValue(layer, "next_header")),
            } }),
        }
    }

    const pkt_min_size = layers.minSize();
    var pkt_size = try getValue(?u16, map, "pkt_size") orelse pkt_min_size;
    if (pkt_size < pkt_min_size) {
        pkt_size = pkt_min_size;
        std.log.debug("Adjusting packet size to fit the layers: {d}", .{pkt_size});
    }
    layers.fixSize(pkt_size);
    try layers.fixMissingNextHeader();

    const frames_per_packet: u8 = @truncate(pkt_size / std.heap.pageSize() + 1);

    // Adjust the umem entries to be a multiple of frames_per_packet
    var umem_entries: u32 = try getValue(?u32, map, "umem_entries") orelse default_umem_entries;
    umem_entries -= umem_entries % frames_per_packet;

    var batch = try getValue(?u16, map, "batch") orelse default_batch;
    // Adjust the batch size to be a multiple of frames_per_packet
    batch -= batch % frames_per_packet;
    // Batches should not be smaller than the number of umem entries
    batch = @min(batch, umem_entries);

    const pkt_count = if (cli_args.count) |count| count else try getValue(?u64, map, "count");

    // The number of threads might be limited by the number of queues
    var threads = if (cli_args.threads) |threads|
        threads
    else
        try getValue(?u32, map, "threads") orelse device_info.queue_count;
    threads = @min(threads, device_info.queue_count);
    if (pkt_count) |count| {
        // Don't use more threads than packets to send
        threads = @min(threads, count);
    }

    const rate_limit = if (cli_args.rate) |rate| rate else try getValue(?u64, map, "rate");
    const rate_limit_pps = if (cli_args.pps) |pps| pps else try getValue(?u64, map, "pps");

    if (rate_limit_pps != null and rate_limit != null) {
        return error.PPSAndRate;
    }

    const prefill = if (cli_args.prefill) |pre_fill|
        pre_fill
    else
        try getValue(?bool, map, "pre_fill") orelse false;

    return .{
        .allocator = allocator,
        .threads = threads,
        .device_info = device_info,
        .layers = layers,
        .socket_config = .{
            .dev = dev,
            .pkt_size = pkt_size,
            .umem_entries = umem_entries,
            .frames_per_packet = frames_per_packet,
            .prefill = prefill,
            .rate_limit_pps = if (rate_limit_pps) |pps|
                pps
            else if (rate_limit) |rate|
                rate / (pkt_size * 8)
            else
                null,
            .pkt_count = pkt_count,
            .pkt_batch = batch,
            .layers = layers,
        },
    };
}

pub fn deinit(self: *Config) void {
    self.allocator.free(self.socket_config.dev);
    self.socket_config.layers.deinit();
}

pub fn format(self: *const Config, writer: anytype) !void {
    try writer.print(
        \\{f}
        \\{f}
        \\Threads: {d}
        \\Layers:
        \\{f}
    ,
        .{
            self.device_info,
            self.socket_config,
            self.threads,
            self.layers,
        },
    );
}

fn parseBool(str: []const u8) !bool {
    if (std.mem.eql(u8, str, "true")) return true;
    if (std.mem.eql(u8, str, "false")) return false;
    return error.YamlInvalid;
}

fn getStringValue(map: Yaml.Map, name: []const u8) ![]const u8 {
    return getValue([]const u8, map, name);
}

fn getOptionalStringValue(map: Yaml.Map, name: []const u8) !?[]const u8 {
    return getValue(?[]const u8, map, name);
}

fn getValue(comptime ValueT: type, map: Yaml.Map, name: []const u8) !ValueT {
    const maybe_value = map.get(name);

    const optional = @typeInfo(ValueT) == .optional;
    if (maybe_value == null) {
        return if (optional) null else error.YamlInvalid;
    }

    const value = maybe_value.?.asScalar() orelse return error.YamlInvalid;
    const T = if (optional) @typeInfo(ValueT).optional.child else ValueT;

    return switch (@typeInfo(T)) {
        .int => try pretty.parseNumber(T, value),
        .bool => try parseBool(value),
        .pointer => |info| switch (info.size) {
            .slice => return value,
            else => @compileError("Unsupported pointer type " ++ @tagName(info.size)),
        },
        else => @compileError("Unsupported type:" ++ @typeName(T)),
    };
}

fn getIntRangeValue(comptime T: type, map: Yaml.Map, name: []const u8) !Range(T) {
    if (@typeInfo(T) != .int) {
        @compileError("This function only handles integers");
    }

    // First try to parse the value as type T. If this fails, parse it as a
    // range from a string.
    if (getValue(T, map, name)) |value| {
        return try Range(T).init(value, null);
    } else |_| {
        return try Range(T).parse(try getStringValue(map, name));
    }
}

test "parse yaml" {
    const source =
        \\dev: tg0
        \\pkt_size: 1500
        \\batch: 256
        \\count: 1024
        \\rate: 12k
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
    const cli_args: CliArgs = .{};
    var config = try initRaw(std.testing.allocator, &cli_args, source, false);
    defer config.deinit();

    try std.testing.expectEqualStrings("tg0", config.socket_config.dev);
    try std.testing.expectEqual(1500, config.socket_config.pkt_size);
    try std.testing.expectEqual(256, config.socket_config.pkt_batch);
    try std.testing.expectEqual(1024, config.socket_config.pkt_count);
    try std.testing.expectEqual(1, config.socket_config.rate_limit_pps);
    try std.testing.expectEqual(3, config.layers.entries.items.len);
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
    const cli_args: CliArgs = .{};
    var config = try initRaw(std.testing.allocator, &cli_args, source, false);
    defer config.deinit();
    try std.testing.expectEqual(config.layers.minSize(), config.socket_config.pkt_size);
    try std.testing.expectEqual(default_batch, config.socket_config.pkt_batch);
}

test "cli supersede yaml" {
    const source =
        \\dev: tg0
        \\pps: 2k
        \\layers:
        \\  - type: eth
        \\    src: de:ad:be:ef:00:00
        \\    dst: de:ad:be:ef:00:01
        \\    proto: ip
    ;
    const cli_args: CliArgs = .{
        .pps = 42,
    };
    var config = try initRaw(std.testing.allocator, &cli_args, source, false);
    defer config.deinit();

    try std.testing.expectEqual(42, config.socket_config.rate_limit_pps);
}

test "parse yaml error Missing dev" {
    const source =
        \\layers:
        \\  - type: eth
        \\    src: de:ad:be:ef:00:00
        \\    dst: de:ad:be:ef:00:01
        \\    proto: ip
    ;
    const cli_args: CliArgs = .{};
    try std.testing.expectError(error.ConfigMissingDev, initRaw(std.testing.allocator, &cli_args, source, false));
}

test "parse yaml error Missing layers" {
    const source =
        \\dev: tg0
    ;
    const cli_args: CliArgs = .{};
    try std.testing.expectError(error.ConfigMissingLayers, initRaw(std.testing.allocator, &cli_args, source, false));
}

test "parse yaml error Rate and PPS" {
    const source =
        \\dev: tg0
        \\rate: 1k
        \\pps: 2k
        \\layers:
        \\  - type: eth
        \\    src: de:ad:be:ef:00:00
        \\    dst: de:ad:be:ef:00:01
        \\    proto: ip
    ;
    const cli_args: CliArgs = .{};
    try std.testing.expectError(error.PPSAndRate, initRaw(std.testing.allocator, &cli_args, source, false));
}
