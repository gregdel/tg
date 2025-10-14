const std = @import("std");

const Layer = @import("layer.zig").Layer;

const max_layers = 8;

pub const Layers = @This();

entries: [max_layers]Layer = undefined,
count: u8 = 0,

const Iterator = struct {
    i: usize = 0,
    layers: []const Layer,

    pub fn next(self: *Iterator) ?*const Layer {
        if (self.i == self.layers.len) return null;
        defer self.i += 1;
        return &self.layers[self.i];
    }

    pub fn reset(self: *Iterator) void {
        self.i = 0;
    }
};

pub fn iterator(self: *const Layers) Iterator {
    return .{ .layers = self.entries[0..self.count] };
}

pub fn fixSize(self: *Layers, total: u16) void {
    var remaining = total;
    for (self.entries[0..self.count]) |*layer| {
        layer.setLen(remaining);
        remaining -= layer.size();
    }
}

pub fn addLayer(self: *Layers, layer: Layer) !void {
    if (self.count + 1 >= max_layers) return error.TooManyLayers;
    self.entries[self.count] = layer;
    self.count += 1;
}

pub fn format(self: *const Layers, writer: anytype) !void {
    for (self.entries[0..self.count]) |*layer| {
        try writer.print("{s: >6} : {f}\n", .{ layer.name(), layer });
    }
}
