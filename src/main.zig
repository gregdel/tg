const std = @import("std");
const tg = @import("tg");

pub fn main() !void {
    const Tg = tg.Tg;
    // Prints to stderr, ignoring potential errors.
    std.debug.print("Tg: {any}\n", .{Tg});
}
