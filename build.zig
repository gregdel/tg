const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .linux,
            .abi = .musl,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const libxdp = b.dependency("libxdp", .{
        .target = target,
        .optimize = optimize,
    }).artifact("xdp");

    const libbpf = b.dependency("libbpf", .{
        .target = target,
        .optimize = optimize,
    }).artifact("bpf");

    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "yaml", .module = yaml.module("yaml") },
        },
    });
    root_module.linkLibrary(libbpf);
    root_module.linkLibrary(libxdp);

    const xdp_programs = b.addObject(.{
        .name = "tg_xdp",
        .root_module = b.createModule(.{
            .strip = false,
            .root_source_file = b.path("src/kern/tg.zig"),
            .optimize = .ReleaseFast,
            .target = b.resolveTargetQuery(.{
                .cpu_arch = switch (target.result.cpu.arch.endian()) {
                    .big => .bpfeb,
                    .little => .bpfel,
                },
                .os_tag = .freestanding,
            }),
        }),
    });

    const install_xdp = b.addInstallFileWithDir(
        xdp_programs.getEmittedBin(),
        .prefix,
        "tg.xdp",
    );

    // Binary
    const exe = b.addExecutable(.{
        .name = "tg",
        .root_module = root_module,
    });
    exe.step.dependOn(&install_xdp.step);
    b.installArtifact(exe);

    // Tests
    const exe_tests = b.addTest(.{
        .root_module = root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
