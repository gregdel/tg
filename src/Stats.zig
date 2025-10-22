const std = @import("std");

const Stats = @This();

pending: u32 = 0,
sent: u64 = 0,

// AF_XDP socket stats
rx_dropped: u64 = 0,
rx_invalid_descs: u64 = 0,
tx_invalid_descs: u64 = 0,
rx_ring_full: u64 = 0,
rx_fill_ring_empty_descs: u64 = 0,
tx_ring_empty_descs: u64 = 0,

pub fn add(self: *Stats, other: *const Stats) void {
    self.pending += other.pending;
    self.sent += other.sent;
    self.rx_dropped += other.rx_dropped;
    self.rx_invalid_descs += other.rx_invalid_descs;
    self.tx_invalid_descs += other.tx_invalid_descs;
    self.rx_ring_full += other.rx_ring_full;
    self.rx_fill_ring_empty_descs += other.rx_fill_ring_empty_descs;
    self.tx_ring_empty_descs += other.tx_ring_empty_descs;
}

pub fn format(self: *const Stats, writer: anytype) !void {
    const fmt = "{s: >25}: {d}\n";
    try writer.print(fmt, .{ "pending", self.pending });
    try writer.print(fmt, .{ "frames_sent", self.sent });
    try writer.print(fmt, .{ "rx_dropped", self.rx_dropped });
    try writer.print(fmt, .{ "rx_invalid_descs", self.rx_invalid_descs });
    try writer.print(fmt, .{ "tx_invalid_descs", self.tx_invalid_descs });
    try writer.print(fmt, .{ "rx_ring_full", self.rx_ring_full });
    try writer.print(fmt, .{ "rx_fill_ring_empty_descs", self.rx_fill_ring_empty_descs });
    try writer.print(fmt, .{ "tx_ring_empty_descs", self.tx_ring_empty_descs });
}
