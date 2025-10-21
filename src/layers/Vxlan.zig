const std = @import("std");

const Range = @import("../range.zig").Range;

const Vxlan = @This();

vni: Range(u24),
flags: u32 = @shlExact(1, 27),

pub fn size(_: *const Vxlan) u16 {
    return 8;
}

pub inline fn write(self: *const Vxlan, writer: anytype, seed: u64) !usize {
    const vni: u32 = @shlExact(self.vni.get(seed), 8);
    try writer.writeInt(u32, self.flags, .big);
    try writer.writeInt(u32, vni, .big);
    return self.size();
}

pub fn format(self: *const Vxlan, writer: anytype) !void {
    try writer.print("vni:{f}", .{self.vni});
}
