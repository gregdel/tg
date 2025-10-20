const std = @import("std");

const Tg = @import("Tg.zig");
const Config = @import("Config.zig");

pub const max_layers = @import("layers/Layers.zig").max_layers;

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

    var config = Config.init(allocator, "config.yaml") catch |err| return exitError(err);
    defer config.deinit();
    try stdout.print("{f}", .{config});
    try stdout.flush();

    var tg = try Tg.init(&config);
    defer tg.deinit();
    try tg.run();

    try stdout.print("\n{f}", .{tg});
    try stdout.flush();
}

fn exitError(err: anyerror) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stdout().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const msg: ?[]const u8 = sw: switch (err) {
        error.FileNotFound => "Config file not found",
        error.DeviceNotFound => "Network device not found",
        error.DeviceParse => "Failed to get device info",
        error.DeviceMacAddrParse => "Failed to parse device macaddr",
        error.InvalidYaml => "Invalid yaml configuration file",
        error.TooManyLayers => std.fmt.comptimePrint(
            "To many layers, max: {d}",
            .{max_layers},
        ),
        error.ConfigMissingDev => "Missing dev in config",
        error.ConfigMissingLayers => "Missing layers in config",
        else => {
            try stderr.print("Failed to parse config: {t}\n", .{err});
            break :sw null;
        },
    };
    if (msg) |m| {
        try stderr.writeAll(m);
        try stderr.writeAll("\n");
    }

    try stderr.flush();
    return std.posix.exit(1);
}

test {
    _ = @import("DeviceInfo.zig");
    _ = @import("Config.zig");
    _ = @import("net/checksum.zig");
    _ = @import("net/IpAddr.zig");
    _ = @import("layers/Ip.zig");
    _ = @import("range.zig");
    _ = @import("CpuSet.zig");
}
