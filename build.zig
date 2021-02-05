const std = @import("std");
const deps = @import("deps.zig");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    var target = b.standardTargetOptions(.{});
    if (target.isGnuLibC()) target.abi = .musl;

    const mode = b.standardReleaseOptions();

    const tests = b.addTest("lmdb.zig");
    tests.setTarget(target);
    tests.setBuildMode(mode);
    deps.addAllTo(tests);

    const test_step = b.step("test", "Run libary tests");
    test_step.dependOn(&tests.step);
}
