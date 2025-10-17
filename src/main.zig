const std = @import("std");

const Tg = @import("Tg.zig");
const Config = @import("Config.zig");

// Disable YAML parsing logs
pub const std_options: std.Options = .{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .parser, .level = .err },
        .{ .scope = .tokenizer, .level = .err },
    },
};

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try Config.init(allocator, "config.yaml");
    defer config.deinit();
    try stdout.print("{f}", .{config});
    try stdout.flush();

    var tg = try Tg.init(&config);
    defer tg.deinit();
    try tg.run();

    try stdout.print("\n{f}", .{tg});
    try stdout.flush();
}

test {
    _ = @import("DeviceInfo.zig");
    _ = @import("Config.zig");
    _ = @import("net/checksum.zig");
    _ = @import("net/IpAddr.zig");
    _ = @import("layers/Ip.zig");
    _ = @import("range.zig");
}
