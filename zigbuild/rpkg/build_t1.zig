//! Tier-1 root: one R package's shared library from a plan (plan.zon,
//! written by `rzig build`: zigbuild/tools/rzig/pkgplan.zig). Every
//! compile and the link are Run steps that call rzig (the toolchain's
//! zig-cc / zig-cxx / zig-fc; gcc.exe, g++.exe, zig-fc.exe on Windows) with
//! the words make would have passed; no flag is derived here. Installed
//! to R_HOME/share/zig/rpkg by the repo's build.zig; rzig runs
//!   zig build --build-file <this file> -Dplan=<plan.zon> --prefix <dir> --cache-dir <cache>
//! and finds <dir>/<libs_dir>/<output>.
const std = @import("std");
const builtin = @import("builtin");
const windows = builtin.os.tag == .windows;

pub const Source = struct { lang: []const u8, path: []const u8, obj: []const u8 };

/// Field names and defaults as pkgplan.zig's `Plan` writes them.
pub const Plan = struct {
    name: []const u8,
    srcdir: []const u8,
    output: []const u8,
    /// "libs", or "libs/x64" on Windows (R_ARCH); "" = the prefix itself
    libs_dir: []const u8 = "libs",
    toolchain: []const u8,
    /// rzig itself, for `rzig def` (Windows); "" when not needed
    rzig: []const u8 = "",
    link_driver: []const u8,
    // the plan always names them (pkgplan.zig, from Makeconf); the defaults
    // are the names installRzig (build.zig) uses on this OS
    cc_tool: []const u8 = if (windows) "gcc.exe" else "zig-cc",
    cxx_tool: []const u8 = if (windows) "g++.exe" else "zig-cxx",
    fc_tool: []const u8 = if (windows) "zig-fc.exe" else "zig-fc",
    sources: []const Source,
    cc: []const []const u8 = &.{},
    cxx: []const []const u8 = &.{},
    fc: []const []const u8 = &.{},
    f9x: []const []const u8 = &.{},
    link: []const []const u8 = &.{},
    libs: []const []const u8 = &.{},
    env: []const []const u8 = &.{}, // NAME=value pairs for the compiler
    target: []const u8 = "", // tier 2: zig target of R, e.g. x86_64-linux-gnu.2.17
    r_include: []const u8 = "", // tier 2: R_HOME/include
    /// Windows: write the .def from the objects (rzig def) and link with it
    def: bool = false,
    /// Windows: the package's own <pkg>-win.def in srcdir, linked instead
    win_def: []const u8 = "",
};

pub fn readPlan(b: *std.Build) *const Plan {
    const plan_path = b.option([]const u8, "plan", "plan.zon") orelse @panic("-Dplan=<file> is required");
    const raw = std.Io.Dir.cwd().readFileAlloc(b.graph.io, plan_path, b.allocator, .limited(16 * 1024 * 1024)) catch @panic("cannot read the plan");
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

/// The one link: `SHLIB_LINK -o out [def] objects ALL_LIBS`, as shlib.mk
/// and winshlib.mk write it.
pub fn link(b: *std.Build, plan: *const Plan, objs: []const std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{b.pathJoin(&.{ plan.toolchain, plan.link_driver })});
    run.setName(b.fmt("link {s}", .{plan.output}));
    run.setCwd(.{ .cwd_relative = plan.srcdir });
    applyEnv(run, plan);
    run.addArgs(plan.link);
    run.addArg("-o");
    const out = run.addOutputFileArg(plan.output);
    if (plan.win_def.len > 0) {
        run.addFileArg(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, plan.win_def }) });
    } else if (plan.def) {
        // winshlib.mk's tmp.def, from the objects' symbol tables
        const def = b.addSystemCommand(&.{ plan.rzig, "def", "-o" });
        def.setName(b.fmt("def {s}", .{plan.output}));
        const def_file = def.addOutputFileArg(b.fmt("{s}.def", .{std.fs.path.stem(plan.output)}));
        for (objs) |o| def.addFileArg(o);
        run.addFileArg(def_file);
    }
    for (objs) |o| run.addFileArg(o);
    run.addArgs(plan.libs);
    return out;
}

/// "libs" or "libs/x64" under the prefix; "" (rzig build --flat) the
/// prefix itself, where make leaves the library in src/.
pub fn installDir(libs_dir: []const u8) std.Build.InstallDir {
    return if (libs_dir.len == 0) .prefix else .{ .custom = libs_dir };
}

pub fn build(b: *std.Build) void {
    const plan = readPlan(b);
    if (plan.sources.len == 0) return; // make: `if test "z$(OBJECTS)" != "z"`
    const lib = link(b, plan, compileAll(b, plan));
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib, installDir(plan.libs_dir), plan.output).step);
}
