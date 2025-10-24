const std = @import("std");

const CliArgs = @This();

dev: ?[]const u8 = null,
config: ?[]const u8 = null,
prog: ?[]const u8 = null,
cmd: Cmd,

const ArgType = enum {
    help,
    dev,
    config,
    prog,
};

pub const usage =
    \\Usage:
    \\  tg [command] [args]
    \\Commands:
    \\  send [dev DEV] [config PATH]
    \\  attach dev DEV prog [tg_drop|tg_pass]
    \\  detach dev DEV
    \\Arguments:
    \\  DEV    device to use
    \\  PATH   config file path
;
const Cmd = enum {
    send,
    attach,
    detach,

    pub fn args(self: Cmd) std.StaticStringMap(ArgType) {
        return switch (self) {
            .send => std.StaticStringMap(ArgType).initComptime(.{
                .{ "dev", .dev },
                .{ "config", .config },
                .{ "help", .help },
            }),
            .attach => std.StaticStringMap(ArgType).initComptime(.{
                .{ "dev", .dev },
                .{ "prog", .prog },
                .{ "help", .help },
            }),
            .detach => std.StaticStringMap(ArgType).initComptime(.{
                .{ "dev", .dev },
                .{ "help", .help },
            }),
        };
    }
};
const cmd_map = std.StaticStringMap(Cmd).initComptime(.{
    .{ "send", .send },
    .{ "attach", .attach },
    .{ "detach", .detach },
});

pub fn parse() !CliArgs {
    var args = std.process.args();
    _ = args.skip();

    const cmd_str = args.next() orelse {
        std.log.err("Missing command", .{});
        return error.CliUsage;
    };

    var cli: CliArgs = .{
        .cmd = cmd_map.get(cmd_str) orelse {
            std.log.err("Invalid command: {s}", .{cmd_str});
            return error.CliUsage;
        },
    };

    const cmd_args = cli.cmd.args();
    while (args.next()) |arg| {
        const arg_type = cmd_args.get(arg) orelse {
            std.log.err("Invalid argument: {s}", .{arg});
            return error.CliUsage;
        };

        switch (arg_type) {
            .dev => {
                cli.dev = args.next() orelse return error.CliUsage;
            },
            .config => {
                cli.config = args.next() orelse return error.CliUsage;
            },
            .prog => {
                cli.prog = args.next() orelse return error.CliUsage;
            },
            .help => {
                return error.CliUsage;
            },
        }
    }

    return cli;
}
