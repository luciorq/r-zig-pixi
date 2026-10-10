//! Tier-2 root: the package's own `src/build.zig` is a path dependency
//! named `pkg` in this root's build.zig.zon (rzig writes both into the
//! build root); it exports `rbuild(rpkg, b, opts)` and never imports
//! anything outside its own tree. `rzig build` copies this file as
//! build.zig beside build_t1.zig and rpkg.zig.
const std = @import("std");
const t1 = @import("build_t1.zig");
const rpkg = @import("rpkg.zig");
const pkg = @import("pkg");

pub fn build(b: *std.Build) void {
    const plan = t1.readPlan(b);
    // R's target with the baseline CPU, as rzig compiles C (-mcpu=baseline)
    const query = std.Target.Query.parse(.{ .arch_os_abi = plan.target, .cpu_features = "baseline" }) catch @panic("bad target in the plan");
    const opts: rpkg.Options = .{
        .plan = plan,
        .target = b.resolveTargetQuery(query),
        .optimize = .ReleaseFast,
        .r_include = plan.r_include,
    };
    const dep = b.dependency("pkg", .{});
    const lib = pkg.rbuild(rpkg, dep.builder, opts);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib, .{ .custom = plan.libs_dir }, plan.output).step);
}
