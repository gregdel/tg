const std = @import("std");
const MacAddr = @import("../macaddr.zig");
const Ip = @import("../ip.zig");

const MAX_LAYERS = 8;

pub const Layers = struct {
    layers: [MAX_LAYERS]Layer = undefined,
    count: u8 = 0,

    const Iterator = struct {
        i: usize = 0,
        layers: []const Layer,

        pub fn next(self: *Iterator) ?Layer {
            if (self.i == self.layers.len) return null;
            defer self.i += 1;
            return self.layers[self.i];
        }
    };

    pub fn iterator(self: *const Layers) Iterator {
        return .{ .layers = self.layers[0..self.count] };
    }

    pub fn addLayer(self: *Layers, layer: Layer) !void {
        if (self.count + 1 >= MAX_LAYERS) return error.TooManyLayers;
        self.layers[self.count] = layer;
        self.count += 1;
    }

    pub fn format(self: *const Layers, writer: anytype) !void {
        var i: u8 = 0;
        while (i < self.count) : (i += 1) {
            const layer = self.layers[i];
            try writer.print("{s} -> {d} bytes\n", .{
                layer.name(),
                layer.size(),
            });
        }
    }
};

pub const Layer = union(enum) {
    ethernet: Ethernet,
    udp: Udp,
    ip: IpHdr,

    pub fn name(self: Layer) []const u8 {
        return switch (self) {
            .ethernet => "ethernet",
            .udp => "udp",
            .ip => "ip",
        };
    }

    pub fn size(self: Layer) usize {
        return switch (self) {
            .ethernet => 14,
            .ip => @as(usize, self.ip.ihl) * 4,
            .udp => 8,
        };
    }

    pub fn write(self: Layer, writer: anytype) !usize {
        return switch (self) {
            inline else => |layer| layer.write(writer),
        };
    }
};

pub const Ethernet = struct {
    src: MacAddr,
    dst: MacAddr,
    proto: u16,

    pub inline fn write(self: Ethernet, writer: anytype) !usize {
        const len = @sizeOf(@This());
        var ret: usize = 0;
        ret += try self.src.write(writer);
        ret += try self.dst.write(writer);
        try writer.writeInt(u16, self.proto, .big);
        ret += 2;
        if (ret != len) return error.EthHdrWrite;
        return len;
    }
};

const IpHdr = struct {
    version: u4 = 5,
    ihl: u4 = 4,
    tos: u8 = 0x4,
    tot_len: u16,
    id: u16 = 0,
    frag_off: u16 = 0,
    ttl: u8 = 64,
    protocol: u8,
    check: u16 = 0,
    saddr: Ip,
    daddr: Ip,

    pub inline fn write(self: IpHdr, writer: anytype) !usize {
        try writer.writeInt(u8, @as(u8, self.version) << 4 | self.ihl, .big);
        try writer.writeInt(u8, self.tos, .big);
        try writer.writeInt(u16, self.tot_len, .big);
        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u16, self.frag_off, .big);
        try writer.writeInt(u8, self.ttl, .big);
        try writer.writeInt(u8, self.protocol, .big);
        try writer.writeInt(u16, self.check, .big);
        _ = try self.saddr.write(writer);
        _ = try self.daddr.write(writer);
        return @as(usize, self.ihl) * 4;
    }
};

const Udp = struct {
    source: u16,
    dest: u16,
    len: u16,
    check: u16 = 0,

    pub inline fn write(self: Udp, writer: anytype) !usize {
        try writer.writeInt(u16, self.source, .big);
        try writer.writeInt(u16, self.dest, .big);
        try writer.writeInt(u16, self.len, .big);
        try writer.writeInt(u16, self.check, .big);
        return 2 + 2 + 2 + 2;
    }
};
