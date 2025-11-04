const std = @import("std");

const RateLimiter = @This();

tokens: f64,
max_tokens: f64,
tokens_per_ns: f64,
timer: std.time.Timer,

pub fn init(packets_per_second: u64) !RateLimiter {
    const pps: f64 = @floatFromInt(packets_per_second);
    return .{
        .tokens = 0,
        .max_tokens = pps * 2,
        .tokens_per_ns = pps / std.time.ns_per_s,
        .timer = try std.time.Timer.start(),
    };
}

pub fn refill(self: *RateLimiter) void {
    // Get the number of ns since last lap
    const elapsed: f64 = @floatFromInt(self.timer.lap());

    // Refill tokens
    self.tokens = @min(
        self.tokens + elapsed * self.tokens_per_ns,
        self.max_tokens,
    );
}

pub fn tryTake(self: *RateLimiter, n: u64) bool {
    self.refill();

    const requested: f64 = @floatFromInt(n);
    if (self.tokens >= requested) {
        self.tokens -= requested;
        return true;
    }

    const missing = requested - self.tokens;
    const sleep_time: u64 = @intFromFloat(@round(missing / self.tokens_per_ns));
    std.Thread.sleep(sleep_time);
    return false;
}
