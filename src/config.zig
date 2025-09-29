const Config = struct {
    dev: []u8,
    pkt_size: usize,
    batch: usize,
    ring_size: usize,

    fn init() Config {
        return .{
            .pkt_size = 1500,
            .batch = 64,
            .ring_size = 1024,
        };
    }
};
