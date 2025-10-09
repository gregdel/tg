dev: []const u8,
pkt_size: u32 = 64,
batch: u32 = 64,
ring_size: u32 = 2048,
entries: u32 = 2048 * 2, // XSK_RING_PROD__DEFAULT_NUM_DESCS;

const Self = @This();

pub fn init(dev: []const u8) Self {
    return .{ .dev = dev };
}
