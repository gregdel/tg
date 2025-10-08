pub const Config = struct {
    dev: []const u8,
    pkt_size: u32,
    batch: u32,
    ring_size: u32,
    entries: u32,

    pub fn init(dev: []const u8) !Config {
        return .{
            .dev = dev,
            .pkt_size = 64,
            .batch = 64,
            .ring_size = 2048, // XSK_RING_PROD__DEFAULT_NUM_DESCS;
            .entries = 2048 * 2,
        };
    }
};
