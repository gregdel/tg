const std = @import("std");

const Layer = @import("layer.zig").Layer;

pub const max_layers = 12;

pub const Layers = @This();

entries: [max_layers]Layer = undefined,
count: u8 = 0,

pub fn asSlice(self: *const Layers) []const Layer {
    return self.entries[0..self.count];
}

pub fn minSize(self: *Layers) u16 {
    var size: u16 = 0;
    for (self.asSlice()) |layer| {
        size += layer.size();
    }
    return size;
}

pub fn fixSize(self: *Layers, total: u16) void {
    var remaining = total;
    for (self.entries[0..self.count]) |*layer| {
        layer.setLen(remaining);
        remaining -= layer.size();
    }
}

pub fn fixMissingNextHeader(self: *Layers) !void {
    for (0..self.count - 1) |i| {
        const j = i + 1;
        const next_proto = self.entries[j].getProto() orelse continue;
        self.entries[i].setNextProto(next_proto) catch |err| {
            switch (err) {
                error.AlreadySet => continue,
                else => return err,
            }
        };
    }
}

pub fn addLayer(self: *Layers, layer: Layer) !void {
    if (self.count >= max_layers) return error.TooManyLayers;
    self.entries[self.count] = layer;
    self.count += 1;
}

pub fn format(self: *const Layers, writer: anytype) !void {
    for (self.asSlice()) |layer| {
        try writer.print("{s: >6} : {f}\n", .{ layer.name(), layer });
    }
}

test "addLayer too many layers" {
    const Range = @import("../range.zig").Range;

    var layers = Layers{};
    const udpLayer = Layer{ .udp = .{
        .source = try Range(u16).init(1234, null),
        .dest = try Range(u16).init(1234, null),
    } };
    for (0..max_layers) |_| {
        try layers.addLayer(udpLayer);
    }

    // Check that we stopped with correctly at the max numbers of layers
    try std.testing.expectEqual(max_layers, layers.count);
    // Check that adding another layer returns an error
    try std.testing.expectError(error.TooManyLayers, layers.addLayer(udpLayer));
}
