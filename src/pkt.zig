const std = @import("std");

const MacAddr = @import("macaddr.zig").MacAddr;
const IpAddr = @import("ip.zig").IpAddr;

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
        var ret = try (EthHdr{
            .src = try MacAddr.parse("de:ad:be:ef:00:00"),
            .dst = try MacAddr.parse("de:ad:be:ef:00:01"),
            .proto = std.os.linux.ETH.P.IP,
        }).write(&w);

        const ip_len: u16 = @intCast(self.data.len - ret);
        var ip = IpHdr.init();
        ip.tot_len = ip_len;
        ip.saddr = try IpAddr.parse("192.168.1.1");
        ip.daddr = try IpAddr.parse("192.168.1.2");
        ip.protocol = std.os.linux.IPPROTO.UDP;
        ret += try ip.write(&w);

        const udp_len: u16 = @intCast(self.data.len - ret);
        ret += try (UdpHdr{
            .source = 1234,
            .dest = 5678,
            .len = udp_len,
            .check = 0,
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

const IpHdr = struct {
    version: u4,
    ihl: u4,
    tos: u8,
    tot_len: u16,
    id: u16,
    frag_off: u16,
    ttl: u8,
    protocol: u8,
    check: u16,
    saddr: IpAddr,
    daddr: IpAddr,

    pub fn init() IpHdr {
        return .{
            .ihl = 5,
            .version = 4,
            .tos = 0x4,
            .tot_len = 0,
            .id = 0,
            .frag_off = 0,
            .ttl = 64,
            .protocol = 0,
            .check = 0,
            .saddr = IpAddr.zero(),
            .daddr = IpAddr.zero(),
        };
    }

    pub inline fn write(self: IpHdr, writer: *std.Io.Writer) !usize {
        try writer.writeInt(u8, @as(u8, self.version) << 4 | self.ihl, .big);
        try writer.writeInt(u8, self.tos, .big);
        try writer.writeInt(u16, self.tot_len, .big);
        try writer.writeInt(u16, self.id, .big);
        try writer.writeInt(u16, self.frag_off, .big);
        try writer.writeInt(u8, self.ttl, .big);
        try writer.writeInt(u8, self.protocol, .big);
        try writer.writeInt(u16, self.check, .big);
        _ = try self.saddr.write(writer);
        _ = try self.daddr.write(writer);
        return @as(usize, self.ihl) * 4;
    }
};

const UdpHdr = struct {
    source: u16,
    dest: u16,
    len: u16,
    check: u16,

    pub inline fn write(self: UdpHdr, writer: *std.Io.Writer) !usize {
        try writer.writeInt(u16, self.source, .big);
        try writer.writeInt(u16, self.dest, .big);
        try writer.writeInt(u16, self.len, .big);
        try writer.writeInt(u16, self.check, .big);
        return 2 + 2 + 2 + 2;
    }
};
