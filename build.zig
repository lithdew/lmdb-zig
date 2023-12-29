const std = @import("std");

pub fn build(b: *std.Build) void {
    var target = b.standardTargetOptions(.{});
    if (target.isGnuLibC()) target.abi = .musl;

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "lmdb",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.addCSourceFiles(.{ .files = &.{ "lmdb/libraries/liblmdb/mdb.c", "lmdb/libraries/liblmdb/midl.c" }, .flags = &.{"-fno-sanitize=undefined"} });

    b.installArtifact(lib);

    const pkg = b.addModule("lmdb", .{
        .source_file = .{ .path = "lmdb.zig" },
    });

    const tests = b.addTest(.{
        .name = "test",
        .root_source_file = pkg.source_file,
        .target = target,
        .optimize = optimize,
    });
    tests.addIncludePath(.{ .path = "lmdb/libraries/liblmdb" });
    tests.linkLibrary(lib);

    b.installArtifact(tests);

    const test_step = b.step("test", "Run libary tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
