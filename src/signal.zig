const std = @import("std");

pub var running = true;

fn handleSignal(sig: i32) callconv(.c) void {
    _ = sig;
    running = false;
}

pub fn setup() !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
}
