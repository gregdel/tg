const std = @import("std");

pub const Packet = struct {
    data: []u8,
    position: []u8,
    id: u64,
    size: u16,
};

const EthHdr = packed struct {
    dest: [6]u8,
    src: [6]u8,
    proto: u16,

    pub fn write(self: *EthHdr, buf: []u8) !usize {
        const len = @sizeOf(EthHdr);
        if (buf.len < len) return error.BufferTooSmall;

        std.mem.copy(u8, buf[0..6], &self.src);
        std.mem.copy(u8, buf[6..12], &self.dest);
        std.mem.writeInt(u16, buf[12..14], self.proto, .big);
        return len;
    }
};
