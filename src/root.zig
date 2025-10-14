pub const Tg = @import("tg.zig").Tg;
pub const Config = @import("config.zig");

test {
    _ = @import("device_info.zig");
    _ = @import("config.zig");
    _ = @import("layers/checksum.zig");
    _ = @import("layers/ip.zig");
}
