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

    pub fn fixSize(self: *Layers, total: u16) void {
        var remaining = total;
        for (self.layers[0..self.count]) |*layer| {
            layer.setLen(remaining);
            remaining -= layer.size();
        }
    }

    pub fn addLayer(self: *Layers, layer: Layer) !void {
        if (self.count + 1 >= MAX_LAYERS) return error.TooManyLayers;
        self.layers[self.count] = layer;
        self.count += 1;
    }

    pub fn format(self: *const Layers, writer: anytype) !void {
        for (self.layers[0..self.count]) |*layer| {
            try writer.print("{s}:{f}\n", .{ layer.name(), layer });
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

    pub fn size(self: Layer) u16 {
        return switch (self) {
            .ethernet => 14,
            .ip => @as(u16, self.ip.ihl) * 4,
            .udp => 8,
        };
    }

    pub fn setLen(self: *Layer, len: u16) void {
        return switch (self.*) {
            inline else => |*layer| layer.setLen(len),
        };
    }

    pub fn format(self: *const Layer, writer: anytype) !void {
        return switch (self.*) {
            inline else => |layer| try layer.format(writer),
        };
    }

    pub fn write(self: *const Layer, writer: anytype) !usize {
        return switch (self.*) {
            inline else => |layer| layer.write(writer),
        };
    }
};

pub const Ethernet = struct {
    src: MacAddr,
    dst: MacAddr,
    proto: u16,

    pub inline fn write(self: *const Ethernet, writer: anytype) !usize {
        const len = @sizeOf(@This());
        var ret: usize = 0;
        ret += try self.src.write(writer);
        ret += try self.dst.write(writer);
        try writer.writeInt(u16, self.proto, .big);
        ret += 2;
        if (ret != len) return error.EthHdrWrite;
        return len;
    }

    pub fn setLen(_: *Ethernet, _: u16) void {}

    pub fn format(self: *const Ethernet, writer: anytype) !void {
        try writer.print("src:{f} dst:{f} proto:{d}", .{
            self.src, self.dst, self.proto,
        });
    }
};

const ethProto = enum(u16) {
    arp = std.os.linux.ETH.P.ARP,
    ip = std.os.linux.ETH.P.IP,
    ipv6 = std.os.linux.ETH.P.IPV6,
};

pub fn parseEthProto(input: []const u8) !u16 {
    return if (std.meta.stringToEnum(ethProto, input)) |proto|
        @intFromEnum(proto)
    else
        std.fmt.parseInt(u16, input, 10);
}

const IpHdr = struct {
    version: u4 = 4,
    ihl: u4 = 5,
    tos: u8 = 0x4,
    tot_len: u16 = 0,
    id: u16 = 0,
    frag_off: u16 = 0,
    ttl: u8 = 64,
    protocol: u8,
    check: u16 = 0,
    saddr: Ip,
    daddr: Ip,

    pub fn setLen(self: *IpHdr, len: u16) void {
        self.tot_len = len;
    }

    pub inline fn write(self: *const IpHdr, writer: anytype) !usize {
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

    pub fn format(self: *const IpHdr, writer: anytype) !void {
        try writer.print("ip src:{f} dst:{f} tot_len:{d} proto:{d}", .{
            self.saddr, self.daddr, self.tot_len, self.protocol,
        });
    }
};

const ipProto = enum(u8) {
    ip = std.os.linux.IPPROTO.IP,
    icmp = std.os.linux.IPPROTO.ICMP,
    ipip = std.os.linux.IPPROTO.IPIP,
    tcp = std.os.linux.IPPROTO.TCP,
    udp = std.os.linux.IPPROTO.UDP,
    ipv6 = std.os.linux.IPPROTO.IPV6,
    gre = std.os.linux.IPPROTO.GRE,
    icmpv6 = std.os.linux.IPPROTO.ICMPV6,
};

pub fn parseIpProto(input: []const u8) !u8 {
    return if (std.meta.stringToEnum(ipProto, input)) |proto|
        @intFromEnum(proto)
    else
        std.fmt.parseInt(u8, input, 10);
}

const Udp = struct {
    source: u16,
    dest: u16,
    len: u16 = 0,
    check: u16 = 0,

    pub fn setLen(self: *Udp, len: u16) void {
        self.len = len;
    }

    pub inline fn write(self: *const Udp, writer: anytype) !usize {
        try writer.writeInt(u16, self.source, .big);
        try writer.writeInt(u16, self.dest, .big);
        try writer.writeInt(u16, self.len, .big);
        try writer.writeInt(u16, self.check, .big);
        return 2 + 2 + 2 + 2;
    }

    pub fn format(self: *const Udp, writer: anytype) !void {
        try writer.print("src:{d} dst:{d} len:{d}", .{
            self.source, self.dest, self.len,
        });
    }
};
