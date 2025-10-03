const std = @import("std");

const MacAddr = @import("macaddr.zig").MacAddr;

pub const Packet = struct {
    id: u64,
    data: []u8,

    pub fn init(id: u64, data: []u8) Packet {
        return .{ .id = id, .data = data };
    }

    pub fn writer(self: *Packet) std.Io.Writer {
        return std.Io.Writer.fixed(self.data);
    }

    pub fn write_stuff(self: *Packet) !usize {
        var w = self.writer();
        const ret = try (EthHdr{
            .src = try MacAddr.parse("de:ad:be:ef:00:00"),
            .dst = try MacAddr.parse("de:ad:be:ef:00:01"),
            .proto = std.os.linux.ETH.P.IP,
        }).write(&w);
        try w.flush();

        return ret;
    }
};

const EthHdr = struct {
    src: MacAddr,
    dst: MacAddr,
    proto: u16,

    pub inline fn write(self: EthHdr, writer: *std.Io.Writer) !usize {
        const len = @sizeOf(EthHdr);
        var ret: usize = 0;
        ret += try self.src.write(writer);
        ret += try self.dst.write(writer);
        try writer.writeInt(u16, self.proto, .big);
        ret += 2;
        if (ret != len) return error.EthHdrWrite;
        return len;
    }
};
