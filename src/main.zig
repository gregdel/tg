const std = @import("std");
const Tg = @import("tg").Tg;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    const ifname = "tg0";
    var tg = try Tg.init(allocator, ifname);
    defer tg.deinit();

    tg.print();
    try tg.run();
}
