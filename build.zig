const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(
        bool,
        "tracy",
        "Enable Tracy profiling",
    ) orelse false;

    const tracy = b.dependency("tracy", .{ .enable = enable_tracy });

    const scripty = b.addModule("scripty", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    scripty.addImport("tracy", tracy.module("tracy"));

    const unit_tests = b.addTest(.{
        .root_module = scripty,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
