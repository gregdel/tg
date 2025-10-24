const std = @import("std");

const CliArgs = @This();

dev: ?[]const u8 = null,
config: ?[]const u8 = null,
prog: ?[]const u8 = null,

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
    \\  help
    \\  send [dev DEV] [config PATH]
    \\  attach dev DEV prog [tg_drop|tg_pass]
    \\  detach dev DEV
    \\Arguments:
    \\  DEV    device to use
    \\  PATH   config file path
;
const Cmd = enum {
    help,
    send,
    attach,
    detach,

    pub fn args(self: Cmd) !std.StaticStringMap(ArgType) {
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
            .help => return error.CliUsage,
        };
    }
};

pub const CmdCtx = struct {
    cmd: Cmd,
    func: *const fn (*const CliArgs) anyerror!void,
};

pub const CliCmd = struct {
    ctx: CmdCtx,
    args: CliArgs = .{},
};

pub fn parse(commands: std.StaticStringMap(CmdCtx)) !CliCmd {
    var args = std.process.args();
    _ = args.skip();

    const cmd_str = args.next() orelse {
        std.log.err("Missing command", .{});
        return error.CliUsage;
    };

    const ctx = commands.get(cmd_str) orelse {
        std.log.err("Invalid command: {s}", .{cmd_str});
        return error.CliUsage;
    };

    var cmd: CliCmd = .{ .ctx = ctx };

    const cmd_args = try ctx.cmd.args();
    while (args.next()) |arg| {
        const arg_type = cmd_args.get(arg) orelse {
            std.log.err("Invalid argument: {s}", .{arg});
            return error.CliUsage;
        };

        switch (arg_type) {
            .dev => {
                cmd.args.dev = args.next() orelse return error.CliUsage;
            },
            .config => {
                cmd.args.config = args.next() orelse return error.CliUsage;
            },
            .prog => {
                cmd.args.prog = args.next() orelse return error.CliUsage;
            },
            .help => {
                return error.CliUsage;
            },
        }
    }

    return cmd;
}
