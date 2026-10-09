//! Tier-1 root: builds one R package's shared library from a plan.
//! Every compile and the link are Run steps that call rzig (the
//! toolchain's zig-cc / zig-cxx / zig-fc); no flag is derived here.
//! Usage: zig build --build-file build_t1.zig -Dplan=plan.zon --prefix <dir>
//! writes <dir>/libs/<output>.
const std = @import("std");

pub const Source = struct { lang: []const u8, path: []const u8, obj: []const u8 };

pub const Plan = struct {
    name: []const u8,
    srcdir: []const u8,
    output: []const u8,
    toolchain: []const u8,
    link_driver: []const u8,
    sources: []const Source,
    // tool file names under `toolchain`; rzig installs as zig-cc/zig-cxx/zig-fc
    // on unix and as gcc.exe/g++.exe/zig-fc.exe on Windows (Makeconf's names)
    cc_tool: []const u8 = "zig-cc",
    cxx_tool: []const u8 = "zig-cxx",
    fc_tool: []const u8 = "zig-fc",
    cc: []const []const u8 = &.{},
    cxx: []const []const u8 = &.{},
    fc: []const []const u8 = &.{},
    f9x: []const []const u8 = &.{},
    link: []const []const u8 = &.{},
    libs: []const []const u8 = &.{},
    env: []const []const u8 = &.{}, // NAME=value pairs for the compiler
    target: []const u8 = "", // tier 2: zig target of R, e.g. x86_64-linux-gnu.2.17
    r_include: []const u8 = "", // tier 2: R_HOME/include
};

pub fn readPlan(b: *std.Build) *const Plan {
    const plan_path = b.option([]const u8, "plan", "plan.zon") orelse @panic("-Dplan=<file> is required");
    const raw = std.Io.Dir.cwd().readFileAlloc(b.graph.io, plan_path, b.allocator, .limited(4 * 1024 * 1024)) catch @panic("cannot read the plan");
    const z = b.allocator.dupeZ(u8, raw) catch @panic("OOM");
    const plan = b.allocator.create(Plan) catch @panic("OOM");
    @setEvalBranchQuota(20_000); // std.zon.parse's per-field inline switch grows with Plan's fields
    plan.* = std.zon.parse.fromSliceAlloc(Plan, b.allocator, z, null, .{}) catch @panic("cannot parse the plan");
    return plan;
}

fn driverFor(plan: *const Plan, lang: []const u8) struct { tool: []const u8, flags: []const []const u8 } {
    if (std.mem.eql(u8, lang, "c")) return .{ .tool = plan.cc_tool, .flags = plan.cc };
    if (std.mem.eql(u8, lang, "cxx")) return .{ .tool = plan.cxx_tool, .flags = plan.cxx };
    if (std.mem.eql(u8, lang, "f")) return .{ .tool = plan.fc_tool, .flags = plan.fc };
    if (std.mem.eql(u8, lang, "f9x")) return .{ .tool = plan.fc_tool, .flags = plan.f9x };
    @panic("unknown language in the plan");
}

fn applyEnv(run: *std.Build.Step.Run, plan: *const Plan) void {
    for (plan.env) |kv| {
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        run.setEnvironmentVariable(kv[0..eq], kv[eq + 1 ..]);
    }
}

/// One object per source, in the plan's order.
pub fn compileAll(b: *std.Build, plan: *const Plan) []std.Build.LazyPath {
    var objs = std.ArrayList(std.Build.LazyPath).empty;
    for (plan.sources) |s| {
        const d = driverFor(plan, s.lang);
        const run = b.addSystemCommand(&.{b.pathJoin(&.{ plan.toolchain, d.tool })});
        run.setName(b.fmt("{s} {s}", .{ d.tool, s.path }));
        run.setCwd(.{ .cwd_relative = plan.srcdir });
        applyEnv(run, plan);
        run.addArgs(d.flags);
        run.addArg("-c");
        run.addFileArg(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, s.path }) });
        run.addArg("-o");
        objs.append(b.allocator, run.addOutputFileArg(std.fs.path.basename(s.obj))) catch @panic("OOM");
    }
    return objs.items;
}

/// The one link: SHLIB_LINK -o out objects ALL_LIBS, as shlib.mk writes it.
pub fn link(b: *std.Build, plan: *const Plan, objs: []const std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{b.pathJoin(&.{ plan.toolchain, plan.link_driver })});
    run.setName(b.fmt("link {s}", .{plan.output}));
    run.setCwd(.{ .cwd_relative = plan.srcdir });
    applyEnv(run, plan);
    run.addArgs(plan.link);
    run.addArg("-o");
    const out = run.addOutputFileArg(plan.output);
    for (objs) |o| run.addFileArg(o);
    run.addArgs(plan.libs);
    return out;
}

pub fn build(b: *std.Build) void {
    const plan = readPlan(b);
    const lib = link(b, plan, compileAll(b, plan));
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib, .{ .custom = "libs" }, plan.output).step);
}
