const std = @import("std");

pub const CpuSet = @This();

value: std.os.linux.cpu_set_t,

const cpu_set_group_size = @bitSizeOf(usize);

pub fn zero() CpuSet {
    return std.mem.zeroes(CpuSet);
}

pub fn isEmpty(self: *const CpuSet) bool {
    return std.os.linux.CPU_COUNT(self.value) == 0;
}

pub fn apply(self: *const CpuSet) !void {
    if (self.isEmpty()) {
        return error.EmptyCpuSet;
    }
    try std.os.linux.sched_setaffinity(0, &self.value);
}

pub fn setFallback(self: *CpuSet, cpu: usize) void {
    const group = cpu / cpu_set_group_size;
    const bit = cpu % cpu_set_group_size;
    self.value[group] = @as(usize, 1) << @truncate(bit);
    return;
}

pub fn parse(mask: []const u8) !CpuSet {
    var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);

    var bit_index: usize = 0;
    var group_index: usize = 0;
    // Each group is a u32 representing the mask for the cores.
    // The right most bit is the least significant.
    var iter = std.mem.splitBackwardsScalar(u8, mask, ',');
    while (iter.next()) |group| {
        const trimmed = std.mem.trim(u8, group, "\n");
        const value = try std.fmt.parseInt(u32, trimmed, 16);

        cpu_set[group_index] |= @as(usize, value) << @truncate(bit_index);
        bit_index += @bitSizeOf(u32);
        if (bit_index == cpu_set_group_size) {
            bit_index = 0;
            group_index += 1;
        }
    }

    return CpuSet{ .value = cpu_set };
}

test "parse cpu affinity 128 cores" {
    const affinity = try CpuSet.parse("ffffffff,ffffffff,ffffffff,ffffffff\n");
    var expected = CpuSet.zero().value;
    expected[0] = std.math.maxInt(usize);
    expected[1] = std.math.maxInt(usize);
    try std.testing.expectEqual(CpuSet{ .value = expected }, affinity);
}

test "parse cpu affinity 2 of 4 cores" {
    const affinity = try CpuSet.parse("a");
    var expected = CpuSet.zero().value;
    expected[0] = 0b1010;
    try std.testing.expectEqual(CpuSet{ .value = expected }, affinity);
}
