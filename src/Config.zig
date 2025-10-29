const std = @import("std");

const Yaml = @import("yaml").Yaml;

const IpAddr = @import("net/IpAddr.zig");
const Ipv6Addr = @import("net/Ipv6Addr.zig");
const MacAddr = @import("net/MacAddr.zig");
const Range = @import("range.zig").Range;
const DeviceInfo = @import("DeviceInfo.zig");
const SocketConfig = @import("Socket.zig").SocketConfig;
const CliArgs = @import("CliArgs.zig");
const bpf = @import("bpf.zig");

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

    var layers = Layers{};
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
                .proto = try Eth.parseEthProto(try getOptionalStringValue(layer, "proto")),
            } }),
            .vlan => try layers.addLayer(.{ .vlan = .{
                .vlan = try Range(u12).parse(try getStringValue(layer, "vlan")),
                .proto = try Eth.parseEthProto(try getOptionalStringValue(layer, "proto")),
            } }),
            .vxlan => try layers.addLayer(.{ .vxlan = .{
                .vni = try Range(u24).parse(try getStringValue(layer, "vni")),
            } }),
            .ip => try layers.addLayer(.{ .ip = .{
                .saddr = try Range(IpAddr).parse(try getStringValue(layer, "src")),
                .daddr = try Range(IpAddr).parse(try getStringValue(layer, "dst")),
                .protocol = try Ip.parseIpProto(try getOptionalStringValue(layer, "proto")),
            } }),
            .udp => try layers.addLayer(.{ .udp = .{
                .source = try getIntRangeValue(u16, layer, "src"),
                .dest = try getIntRangeValue(u16, layer, "dst"),
            } }),
            .ipv6 => try layers.addLayer(.{ .ipv6 = .{
                .saddr = try Range(Ipv6Addr).parse(try getStringValue(layer, "src")),
                .daddr = try Range(Ipv6Addr).parse(try getStringValue(layer, "dst")),
                .next_header = try Ip.parseIpProto(try getOptionalStringValue(layer, "next_header")),
            } }),
        }
    }

    const pkt_size = try getValue(?u16, map, "pkt_size") orelse layers.minSize();
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

    // The number of threads might be limited by the number of queues
    var threads = try getValue(?u32, map, "threads") orelse device_info.queue_count;
    threads = @min(threads, device_info.queue_count);

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
            .pre_fill = try getValue(?bool, map, "pre_fill") orelse false,
            .pkt_count = try getValue(?u64, map, "count"),
            .pkt_batch = batch,
            .layers = layers,
        },
    };
}

pub fn deinit(self: *const Config) void {
    self.allocator.free(self.socket_config.dev);
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
        .int => try std.fmt.parseInt(T, value, 10),
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
    const cli_args: CliArgs = .{};
    var config = try initRaw(std.testing.allocator, &cli_args, source, false);
    defer config.deinit();
    try std.testing.expectEqual(config.layers.minSize(), config.socket_config.pkt_size);
    try std.testing.expectEqual(default_batch, config.socket_config.pkt_batch);
}
