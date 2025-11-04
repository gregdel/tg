const Eth = @This();

const MacAddr = @import("../net/MacAddr.zig");
const EthProto = @import("../net/proto.zig").Eth;
const Range = @import("../range.zig").Range;

src: Range(MacAddr),
dst: Range(MacAddr),
proto: EthProto,

pub fn write(self: *const Eth, writer: anytype, seed: u64) !usize {
    const src = self.src.get(seed);
    const dst = self.dst.get(seed);
    _ = try dst.write(writer);
    _ = try src.write(writer);
    try self.proto.write(writer);
    return self.size();
}

pub fn size(_: *const Eth) u16 {
    return 14;
}

pub fn setNextProto(self: *Eth, next_proto: u16) !void {
    return self.proto.set(next_proto);
}

pub fn format(self: *const Eth, writer: anytype) !void {
    try writer.print("src:{f} dst:{f} next_proto:{f}", .{
        self.src, self.dst, self.proto,
    });
}
