const std = @import("std");

const Tg = @import("Tg.zig");
const Config = @import("Config.zig");
const CliArgs = @import("CliArgs.zig");
const CmdCtx = @import("CliArgs.zig").CmdCtx;

pub const max_layers = @import("layers/Layers.zig").max_layers;

// Disable YAML parsing logs
pub const std_options: std.Options = .{
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .parser, .level = .err },
        .{ .scope = .tokenizer, .level = .err },
    },
};

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

const cmds = std.StaticStringMap(CmdCtx).initComptime(.{
    .{ "help", CmdCtx{ .cmd = .help, .func = help } },
    .{ "send", CmdCtx{ .cmd = .send, .func = send } },
    .{ "attach", CmdCtx{ .cmd = .attach, .func = attach } },
    .{ "detach", CmdCtx{ .cmd = .detach, .func = detach } },
});

pub fn main() !void {
    run() catch |err| return exitError(err);
}

fn run() !void {
    const cmd = try CliArgs.parse(cmds);
    try cmd.ctx.func(&cmd.args);
}

fn detach(cli_args: *const CliArgs) !void {
    try Tg.detach(cli_args);
    try stdout.print("Program detached\n", .{});
    try stdout.flush();
}

fn attach(cli_args: *const CliArgs) !void {
    try Tg.attach(cli_args);
    try stdout.print("Program attached\n", .{});
    try stdout.flush();
}

fn send(cli_args: *const CliArgs) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try Config.init(allocator, cli_args);
    defer config.deinit();
    try stdout.print("{f}", .{config});
    try stdout.flush();

    var tg = try Tg.init(&config);
    try tg.run();

    try stdout.print("\n{f}", .{tg});
    try stdout.flush();
}

fn help(_: *const CliArgs) !void {}

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
        error.MissingConfigFile => "Missing config file",
        error.ConfigMissingDev => "Missing dev in config",
        error.ConfigMissingLayers => "Missing layers in config",
        error.InvalidXdpProgram => "Invalid xdp program name",
        error.CliUsage => @import("CliArgs.zig").usage,
        else => {
            try stderr.print("Err: {t}\n", .{err});
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
    _ = @import("Config.zig");
    _ = @import("CpuSet.zig");
    _ = @import("DeviceInfo.zig");
    _ = @import("Tg.zig");
    _ = @import("layers/Ip.zig");
    _ = @import("net/IpAddr.zig");
    _ = @import("net/Ipv6Addr.zig");
    _ = @import("net/checksum.zig");
    _ = @import("pretty.zig");
    _ = @import("range.zig");
}
