const std = @import("std");

pub var running = std.atomic.Value(bool).init(true);

fn handleSignal(sig: i32) callconv(.c) void {
    _ = sig;
    running.store(false, .release);
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
