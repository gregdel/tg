const std = @import("std");
const MacAddr = @import("../macaddr.zig");

const Udp = @import("udp.zig");
const Ip = @import("ip.zig");
const Eth = @import("eth.zig");

const MAX_LAYERS = 8;

pub const Layers = struct {
    layers: [MAX_LAYERS]Layer = undefined,
    count: u8 = 0,

    const Iterator = struct {
        i: usize = 0,
        layers: []Layer,

        pub fn next(self: *Iterator) ?*Layer {
            if (self.i == self.layers.len) return null;
            defer self.i += 1;
            return &self.layers[self.i];
        }

        pub fn reset(self: *Iterator) void {
            self.i = 0;
        }
    };

    pub fn iterator(self: *Layers) Iterator {
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
    eth: Eth,
    udp: Udp,
    ip: Ip,

    pub fn name(self: Layer) []const u8 {
        return @tagName(self);
    }

    pub fn size(self: *const Layer) u16 {
        return switch (self.*) {
            inline else => |layer| layer.size(),
        };
    }

    pub fn cksum(self: *const Layer, data: []u8, seed: u16) !u16 {
        return switch (self.*) {
            inline else => |layer| try layer.cksum(data, seed),
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
