const std = @import("std");

const Layer = @import("layer.zig").Layer;

// TODO: should we keep a maximum ?
pub const max_layers = 12;

const alignement = @import("../CpuSet.zig").alignement;

const Layers = @This();

allocator: std.mem.Allocator,
entries: std.ArrayListAligned(Layer, alignement),

pub fn init(allocator: std.mem.Allocator, num: usize) !Layers {
    if (num > max_layers) return error.TooManyLayers;
    return .{
        .allocator = allocator,
        .entries = try std.ArrayListAligned(Layer, alignement).initCapacity(allocator, num),
    };
}

pub fn deinit(self: *Layers) void {
    self.entries.deinit(self.allocator);
}

pub fn minSize(self: *Layers) u16 {
    var size: u16 = 0;
    for (self.entries.items) |layer| {
        size += layer.size();
    }
    return size;
}

pub fn fixSize(self: *Layers, total: u16) void {
    var remaining = total;
    for (self.entries.items) |*layer| {
        layer.setLen(remaining);
        remaining -= layer.size();
    }
}

pub fn fixMissingNextHeader(self: *Layers) !void {
    if (self.entries.items.len < 2) return;
    const end = self.entries.items.len - 1;
    for (0..end) |i| {
        const j = i + 1;
        const next_proto = self.entries.items[j].getProto() orelse continue;
        self.entries.items[i].setNextProto(next_proto) catch |err| {
            switch (err) {
                error.AlreadySet => continue,
                else => return err,
            }
        };
    }
}

pub fn addLayer(self: *Layers, layer: Layer) !void {
    if (self.entries.items.len == max_layers) return error.TooManyLayers;
    try self.entries.append(self.allocator, layer);
}

pub fn format(self: *const Layers, writer: anytype) !void {
    for (self.entries.items) |layer| {
        try writer.print("{s: >6} : {f}\n", .{ layer.name(), layer });
    }
}

test "addLayer too many layers" {
    const Range = @import("../range.zig").Range;

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var layers = try Layers.init(allocator, max_layers);
    defer layers.deinit();

    const udpLayer = Layer{ .udp = .{
        .source = try Range(u16).init(1234, null),
        .dest = try Range(u16).init(1234, null),
    } };
    for (0..max_layers) |_| {
        try layers.addLayer(udpLayer);
    }

    // Check that we stopped with correctly at the max numbers of layers
    try std.testing.expectEqual(max_layers, layers.entries.items.len);
    // Check that adding another layer returns an error
    try std.testing.expectError(error.TooManyLayers, layers.addLayer(udpLayer));
}
