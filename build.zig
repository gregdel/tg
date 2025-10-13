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

    // Main module
    const mod = b.addModule("tg", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yaml", .module = yaml.module("yaml") },
        },
    });
    mod.linkLibrary(libxdp);
    mod.linkLibrary(libbpf);

    const exe = b.addExecutable(.{
        .name = "tg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "tg", .module = mod },
            },
        }),
    });
    exe.root_module.linkLibrary(libxdp);
    b.installArtifact(exe);

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
