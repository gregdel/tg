const Stats = @This();

frames_pending: u32 = 0,
frames_sent: u64 = 0,

// AF_XDP socket stats
tx_invalid_descs: u64 = 0,
tx_ring_empty_descs: u64 = 0,

pub fn add(self: *Stats, other: *const Stats) void {
    self.frames_pending += other.frames_pending;
    self.frames_sent += other.frames_sent;
    self.tx_invalid_descs += other.tx_invalid_descs;
    self.tx_ring_empty_descs += other.tx_ring_empty_descs;
}

pub fn format(self: *const Stats, writer: anytype) !void {
    try writer.print(
        \\  Frames pending:{d} sent:{d}
        \\  Tx desc_invalid:{d} ring_empty:{d}
    , .{
        self.frames_pending,   self.frames_sent,
        self.tx_invalid_descs, self.tx_ring_empty_descs,
    });
}
