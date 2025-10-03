const std = @import("std");
const Tg = @import("tg").Tg;

pub fn main() !void {
    const ifname = "tg0";
    var tg = try Tg.init(ifname);
    defer tg.deinit();

    tg.print();
    try tg.run();
}
