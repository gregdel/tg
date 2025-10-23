const std = @import("std");

const Stats = @This();

frames_pending: u32 = 0,
frames_sent: u64 = 0,

// AF_XDP socket stats
rx_dropped: u64 = 0,
rx_invalid_descs: u64 = 0,
tx_invalid_descs: u64 = 0,
rx_ring_full: u64 = 0,
rx_fill_ring_empty_descs: u64 = 0,
tx_ring_empty_descs: u64 = 0,

pub fn add(self: *Stats, other: *const Stats) void {
    self.frames_pending += other.frames_pending;
    self.frames_sent += other.frames_sent;
    self.rx_dropped += other.rx_dropped;
    self.rx_invalid_descs += other.rx_invalid_descs;
    self.tx_invalid_descs += other.tx_invalid_descs;
    self.rx_ring_full += other.rx_ring_full;
    self.rx_fill_ring_empty_descs += other.rx_fill_ring_empty_descs;
    self.tx_ring_empty_descs += other.tx_ring_empty_descs;
}

pub fn format(self: *const Stats, writer: anytype) !void {
    const fmt = "{s: >25}: {d}\n";
    try writer.print(fmt, .{ "frames pending", self.frames_pending });
    try writer.print(fmt, .{ "frames sent", self.frames_sent });
    try writer.print(fmt, .{ "rx_dropped", self.rx_dropped });
    try writer.print(fmt, .{ "rx_invalid_descs", self.rx_invalid_descs });
    try writer.print(fmt, .{ "tx_invalid_descs", self.tx_invalid_descs });
    try writer.print(fmt, .{ "rx_ring_full", self.rx_ring_full });
    try writer.print(fmt, .{ "rx_fill_ring_empty_descs", self.rx_fill_ring_empty_descs });
    try writer.print(fmt, .{ "tx_ring_empty_descs", self.tx_ring_empty_descs });
}
