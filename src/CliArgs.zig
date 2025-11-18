const std = @import("std");

const pretty = @import("pretty.zig");

const CliArgs = @This();

dev: ?[]const u8 = null,
config: ?[]const u8 = null,
prog: ?[]const u8 = null,
threads: ?u32 = null,
pps: ?u64 = null,
rate: ?u64 = null,
count: ?u64 = null,
prefill: ?bool = null,
size: ?u16 = null,

const ArgType = enum {
    help,
    dev,
    config,
    prog,
    threads,
    pps,
    rate,
    count,
    prefill,
    size,
};

pub const usage =
    \\Usage:
    \\  tg [command] [args]
    \\Commands:
    \\  help
    \\  send [dev DEV] [config PATH] [pps PPS] [rate RATE] [count COUNT]
    \\       [threads THREADS] [size SIZE] [prefill]
    \\  attach dev DEV prog [tg_drop|tg_pass]
    \\  detach dev DEV
    \\Arguments:
    \\  DEV      device to use
    \\  PATH     config file path
    \\  PPS      number of packet per second (e.g 1k)
    \\  RATE     number of bits per second (e.g 1M)
    \\  COUNT    total number of packets to send (e.g 1M)
    \\  SIZE     size of the packet (e.g 9000)
    \\  prefill  prefill the umem with packets only once
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
                .{ "pps", .pps },
                .{ "rate", .rate },
                .{ "count", .count },
                .{ "threads", .threads },
                .{ "size", .size },
                .{ "prefill", .prefill },
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

pub fn getNext(args: *std.process.ArgIterator) ![:0]const u8 {
    return args.next() orelse return error.CliUsage;
}

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
                cmd.args.dev = try getNext(&args);
            },
            .config => {
                cmd.args.config = try getNext(&args);
            },
            .prog => {
                cmd.args.prog = try getNext(&args);
            },
            .pps => {
                cmd.args.pps = try pretty.parseNumber(u64, try getNext(&args));
            },
            .rate => {
                cmd.args.rate = try pretty.parseNumber(u64, try getNext(&args));
            },
            .count => {
                cmd.args.count = try pretty.parseNumber(u64, try getNext(&args));
            },
            .threads => {
                cmd.args.threads = try pretty.parseNumber(u32, try getNext(&args));
            },
            .size => {
                cmd.args.size = try pretty.parseNumber(u16, try getNext(&args));
            },
            .prefill => {
                cmd.args.prefill = true;
            },
            .help => {
                return error.CliUsage;
            },
        }
    }

    return cmd;
}
