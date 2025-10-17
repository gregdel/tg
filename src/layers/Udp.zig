const std = @import("std");

const checksum = @import("../net/checksum.zig");
const PortRange = @import("../range.zig").Range(u16);

pub const Udp = @This();

source: PortRange,
dest: PortRange,
len: u16 = 0,
check: u16 = 0,

pub inline fn size(_: *const Udp) u16 {
    return 8;
}

pub fn setLen(self: *Udp, len: u16) void {
    self.len = len;
}

pub fn cksum(_: *const Udp, data: []u8, seed: u16) !u16 {
    const sum = try checksum.cksum(data, ~seed);
    std.mem.writeInt(u16, data[6..8], sum, .big);
    return 0;
}

pub inline fn write(self: *const Udp, writer: anytype, seed: u64) !usize {
    const source = self.source.get(seed);
    const dest = self.dest.get(seed);

    try writer.writeInt(u16, source, .big);
    try writer.writeInt(u16, dest, .big);
    try writer.writeInt(u16, self.len, .big);
    try writer.writeInt(u16, self.check, .big);
    return self.size();
}

pub fn format(self: *const Udp, writer: anytype) !void {
    try writer.print("src:{f} dst:{f} len:{d}", .{
        self.source, self.dest, self.len,
    });
}
