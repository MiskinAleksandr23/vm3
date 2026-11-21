const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vm3",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const disassembler = b.addTranslateC(.{
        .root_source_file = b.path("src/lama/disassembler.h"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("lama_disassembler", disassembler.createModule());
    exe.root_module.addCSourceFile(.{
        .file = b.path("src/lama/byterun.c"),
        .flags = &.{"-std=c11"},
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run the analyzer").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run tests").dependOn(&run_tests.step);
}
