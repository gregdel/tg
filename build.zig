const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        // .default_target = try std.Target.Query.parse(.{
        //     .arch_os_abi = "x86_64-linux-musl",
        // }),
        .default_target = .{},
    });
    const optimize = b.standardOptimizeOption(.{});

    // Main module
    const mod = b.addModule("tg", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // const xdp_tools = b.dependency("xdp_tools", .{});
    // const xdp_tools_src = xdp_tools.path("");

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
    exe.root_module.linkSystemLibrary("xdp", .{});
    // exe.root_module.addIncludePath(b.path("xdp-tools/headers"));
    // exe.root_module.addLibraryPath(b.path("xdp-tools/lib"));
    b.installArtifact(exe);

    // Run command with arguments
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
