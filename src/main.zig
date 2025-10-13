const std = @import("std");

const Tg = @import("tg").Tg;
const Config = @import("tg").Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try Config.init(allocator, "config.yaml");
    defer config.deinit();
    std.log.debug("{f}", .{config});

    var tg = try Tg.init(&config);
    defer tg.deinit();

    tg.print();
    try tg.run();
}
