const std = @import("std");
const Tg = @import("tg").Tg;

const c = @cImport({
    @cInclude("net/if.h");
});

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    const ifname = "tg0";
    const index = c.if_nametoindex(ifname);
    if (index == 0) {
        std.debug.print("Failed to find ifindex for {s}\n", .{ifname});
        return;
    }
    std.debug.print("Got index for {s}: {d}\n", .{ ifname, index });

    var tg = try Tg.init(allocator, ifname);
    defer tg.deinit();

    tg.print();
    tg.run();
}
