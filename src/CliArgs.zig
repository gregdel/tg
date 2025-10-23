const std = @import("std");

const CliArgs = @This();

dev: ?[]const u8 = null,
config: ?[]const u8 = null,
cmd: Cmd,

const ArgType = enum {
    dev,
    config,
};

pub const usage =
    \\Usage:
    \\  tg [command] [args]
    \\Commands:
    \\  send - send packets
    \\    Args:
    \\      dev [DEV]     - device to use
    \\      config [PATH] - config file path
;
const Cmd = enum {
    send,

    pub fn args(self: Cmd) std.StaticStringMap(ArgType) {
        return switch (self) {
            .send => std.StaticStringMap(ArgType).initComptime(.{
                .{ "dev", .dev },
                .{ "config", .config },
            }),
        };
    }
};
const cmd_map = std.StaticStringMap(Cmd).initComptime(.{
    .{ "send", .send },
});

pub fn parse() !CliArgs {
    var args = std.process.args();
    _ = args.skip();

    const cmd_str = args.next() orelse {
        std.log.debug("Missing command", .{});
        return error.CliUsage;
    };

    var cli: CliArgs = .{
        .cmd = cmd_map.get(cmd_str) orelse {
            std.log.debug("Invalid command: {s}", .{cmd_str});
            return error.CliUsage;
        },
    };

    const cmd_args = cli.cmd.args();
    while (args.next()) |arg| {
        const arg_type = cmd_args.get(arg) orelse {
            std.log.debug("Invalid argument: {s}", .{arg});
            return error.CliUsage;
        };

        switch (arg_type) {
            .dev => {
                cli.dev = args.next() orelse return error.CliUsage;
            },
            .config => {
                cli.config = args.next() orelse return error.CliUsage;
            },
        }
    }

    return cli;
}
