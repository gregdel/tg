const std = @import("std");

const Tg = @import("tg").Tg;
const Config = @import("tg").Config;

pub fn main() !void {
    const config = Config.init("tg0");
    std.log.debug("Result: {any}", .{config});

    var tg = try Tg.init(&config);
    defer tg.deinit();

    tg.print();
    try tg.run();
}
