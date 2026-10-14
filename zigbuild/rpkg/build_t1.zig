//! Tier-1 root: one R package's shared library from a plan (plan.zon,
//! written by `rzig build`: zigbuild/tools/rzig/pkgplan.zig). Every
//! compile and the link are Run steps that call rzig (the toolchain's
//! zig-cc / zig-cxx / zig-fc; gcc.exe, g++.exe, zig-fc.exe on Windows) with
//! the words make would have passed; no flag is derived here. Installed
//! to R_HOME/share/zig/rpkg by the repo's build.zig; rzig runs
//!   zig build --build-file <this file> -Dplan=<plan.zon> --prefix <dir> --cache-dir <cache>
//! and finds <dir>/<libs_dir>/<output>; by default <cache> is a directory
//! of rzig's cache, and <this file> its copy there. The steps write their
//! objects and the library into the build root, the plan's directory,
//! never into <cache>: it then holds this file's build runner alone, one
//! per content of this file and zig, which every tier-1 install shares
//! (zigbuild/tools/rzig/pkgbuild.zig's sharedRunner).
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
    /// The build root, the plan's own directory, where the steps write
    /// (outputFile). Not in plan.zon: readPlan sets it.
    root: []const u8 = "",
};

pub fn readPlan(b: *std.Build) *const Plan {
    const plan_path = b.option([]const u8, "plan", "plan.zon") orelse @panic("-Dplan=<file> is required");
    const raw = std.Io.Dir.cwd().readFileAlloc(b.graph.io, plan_path, b.allocator, .limited(16 * 1024 * 1024)) catch @panic("cannot read the plan");
    const z = b.allocator.dupeZ(u8, raw) catch @panic("OOM");
    const plan = b.allocator.create(Plan) catch @panic("OOM");
    @setEvalBranchQuota(20_000); // std.zon.parse's per-field inline switch grows with Plan's fields
    plan.* = std.zon.parse.fromSliceAlloc(Plan, b.allocator, z, null, .{}) catch @panic("cannot parse the plan");
    // absolute: the steps run in srcdir and name their outputs on their
    // command lines. rzig passes it so, with `/` (pkgbuild.zig).
    const root = std.fs.path.dirname(plan_path) orelse ".";
    plan.root = if (std.fs.path.isAbsolute(root)) root else b.pathResolve(&.{ b.graph.cache.cwd, root });
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

/// The file `run` writes at `path`, in the build root, named on its
/// command line where addOutputFileArg would name one in zig build's
/// cache, o/<hash of the step's inputs>/, with a manifest in h/: the
/// inputs hash the whole environment, R_SESSION_TMPDIR included, so a
/// cache shared across installs gained an entry per step per install,
/// never reused (feat-zig-pkg-build N3, fact 9). The step always runs, as
/// it did with a cache of its own per install, and writes nothing into
/// the cache. expectExitCode gives it the stdio a step with an output
/// file has: stdin and stdout ignored, stderr piped and shown as the
/// step's diagnostic. Without it a step with no output file inherits
/// stdio and holds zig build's stderr lock while it runs, one compile at
/// a time whatever -j says.
fn outputFile(b: *std.Build, run: *std.Build.Step.Run, path: []const u8) std.Build.LazyPath {
    run.has_side_effects = true;
    run.expectExitCode(0);
    run.addArg(path);
    const file = b.allocator.create(std.Build.GeneratedFile) catch @panic("OOM");
    file.* = .{ .step = &run.step, .path = path };
    return .{ .generated = .{ .file = file } };
}

/// One object per source, in the plan's order. Each compile runs in
/// srcdir and names its source relative to it, `-c one.c`, as make does
/// from src/: zig cc keys its object cache (zig's global cache) on the
/// source path as given, so the absolute path under install.R's new
/// R.INSTALL directory added one entry per source on every tarball
/// install, never reused, where make's entries are [tests-T1]. The file
/// stays an input of the step (addFileInput). The object goes to
/// <root>/obj/<n>/<its file name>, a directory per source as zig build's
/// cache had one per step: OBJECTS may name two files of one name
/// (util.o, sub/util.o) or one outside src/ (../x.o), and rpkg names a
/// tier-2 source's object by its stem.
pub fn compileAll(b: *std.Build, plan: *const Plan) []std.Build.LazyPath {
    var objs = std.ArrayList(std.Build.LazyPath).empty;
    for (plan.sources, 0..) |s, n| {
        const d = driverFor(plan, s.lang);
        const run = b.addSystemCommand(&.{b.pathJoin(&.{ plan.toolchain, d.tool })});
        run.setName(b.fmt("{s} {s}", .{ d.tool, s.path }));
        run.setCwd(.{ .cwd_relative = plan.srcdir });
        applyEnv(run, plan);
        run.addArgs(d.flags);
        run.addArg("-c");
        run.addArg(s.path);
        run.addFileInput(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, s.path }) });
        run.addArg("-o");
        const dir = b.fmt("{s}/obj/{d}", .{ plan.root, n });
        std.Io.Dir.cwd().createDirPath(b.graph.io, dir) catch @panic("cannot create the build root's obj/");
        objs.append(b.allocator, outputFile(b, run, b.fmt("{s}/{s}", .{ dir, std.fs.path.basename(s.obj) }))) catch @panic("OOM");
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
    const out = outputFile(b, run, b.fmt("{s}/{s}", .{ plan.root, plan.output }));
    if (plan.win_def.len > 0) {
        // relative to srcdir too, as winshlib.mk names it (compileAll)
        run.addArg(plan.win_def);
        run.addFileInput(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, plan.win_def }) });
    } else if (plan.def) {
        // winshlib.mk's tmp.def, from the objects' symbol tables
        const def = b.addSystemCommand(&.{ plan.rzig, "def", "-o" });
        def.setName(b.fmt("def {s}", .{plan.output}));
        const def_file = outputFile(b, def, b.fmt("{s}/{s}.def", .{ plan.root, std.fs.path.stem(plan.output) }));
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
