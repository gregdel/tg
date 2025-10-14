const std = @import("std");
const Yaml = @import("yaml").Yaml;

const IpAddr = @import("ip.zig");
const MacAddr = @import("macaddr.zig");

const layers_import = @import("layers/layers.zig");
const Layer = layers_import.Layer;
const Layers = layers_import.Layers;
const Ip = @import("layers/ip.zig");
const Eth = @import("layers/eth.zig");

allocator: std.mem.Allocator,

layers: Layers,
dev: []const u8,
threads: u32,
pkt_size: u16,
batch: u32 = 64,
ring_size: u32 = 2048,
entries: u32 = 2048 * 2, // XSK_RING_PROD__DEFAULT_NUM_DESCS;

const Config = @This();

const default_pkt_size = 64;
const max_file_size = 100_000; // ~100ko

pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Config {
    const file_content = try std.fs.cwd().readFileAlloc(allocator, filename, max_file_size);
    defer allocator.free(file_content);
    return initRaw(allocator, file_content);
}

fn initRaw(allocator: std.mem.Allocator, source: []const u8) !Config {
    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(allocator);
    try yaml.load(allocator);

    if (yaml.docs.items.len != 1) return error.InvalidYaml;
    const map = yaml.docs.items[0].map;

    const layers_raw = map.get("layers") orelse return error.InvalidYaml;
    const layer_list = layers_raw.asList() orelse return error.InvalidYaml;

    var layers = Layers{};

    for (layer_list) |layer_value| {
        const layer = layer_value.asMap() orelse return error.InvalidYaml;
        const layer_type = try getValue(.string, layer.get("type"));

        if (std.mem.eql(u8, layer_type, "eth")) {
            try layers.addLayer(.{ .eth = .{
                .src = try MacAddr.parse(try getValue(.string, layer.get("src"))),
                .dst = try MacAddr.parse(try getValue(.string, layer.get("dst"))),
                .proto = try Eth.parseEthProto(
                    try getValue(.string, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "ip")) {
            try layers.addLayer(.{ .ip = .{
                .saddr = try IpAddr.parse(try getValue(.string, layer.get("src"))),
                .daddr = try IpAddr.parse(try getValue(.string, layer.get("dst"))),
                .protocol = try Ip.parseIpProto(
                    try getValue(.string, layer.get("proto")),
                ),
            } });
        }

        if (std.mem.eql(u8, layer_type, "udp")) {
            try layers.addLayer(.{ .udp = .{
                .source = try getValue(.u16, layer.get("src")),
                .dest = try getValue(.u16, layer.get("dst")),
            } });
        }
    }

    const pkt_size = try getValue(.optional_u16, map.get("pkt_size")) orelse default_pkt_size;
    layers.fixSize(pkt_size);

    return .{
        .allocator = allocator,
        .dev = try allocator.dupe(u8, try getValue(.string, map.get("dev"))),
        .pkt_size = pkt_size,
        .threads = 1,
        .layers = layers,
    };
}

pub fn deinit(self: *const Config) void {
    self.allocator.free(self.dev);
}

pub fn format(self: *const Config, writer: anytype) !void {
    try writer.print("dev:{s}\n", .{self.dev});
    try writer.print("layers:\n{f}\n", .{self.layers});
}

const valueType = enum {
    string,
    optional_u16,
    u16,
};

fn getValue(
    comptime v: valueType,
    maybe_value: ?Yaml.Value,
) !switch (v) {
    .string => []const u8,
    .optional_u16 => ?u16,
    .u16 => u16,
} {
    const value = maybe_value orelse return error.YamlInvalid;
    switch (v) {
        .string => {
            return value.asScalar() orelse return error.YamlInvalid;
        },
        .optional_u16 => {
            const scalar = value.asScalar() orelse return null;
            return try std.fmt.parseInt(u16, scalar, 10);
        },
        .u16 => {
            const scalar = value.asScalar() orelse return error.YamlInvalid;
            return try std.fmt.parseInt(u16, scalar, 10);
        },
    }
}

test "parse yaml" {
    const source =
        \\dev: tg0
        \\pkt_size: 1500
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
    var config = try initRaw(std.testing.allocator, source);
    defer config.deinit();

    try std.testing.expectEqualStrings("tg0", config.dev);
    try std.testing.expect(config.pkt_size == 1500);
    try std.testing.expect(config.layers.count == 3);
}
