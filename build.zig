// TODO min version is Windows11 22000
pub fn build(b: *@import("std").Build) void {
    const exe = b.addExecutable(.{
        .name = "laid",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = .{ .os_tag = .windows },
        .optimize = b.standardOptimizeOption(.{}),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Copy build artifacts to prefix path and run them.").dependOn(&run.step);
}
