//! The helper a tier-2 package's build.zig receives as `rpkg`: R's C API
//! as a zig module, and a shared library linked by rzig exactly as a
//! tier-1 package's is. A package's `src/build.zig`:
//!
//!   pub fn build(b: *std.Build) void { _ = b; } // R drives rbuild
//!   pub fn rbuild(comptime rpkg: type, b: *std.Build, opts: rpkg.Options) std.Build.LazyPath {
//!       return rpkg.addLibrary(b, opts, .{ .root_source_file = b.path("hello.zig") });
//!   }
//!
//! and its zig root exports `R_init_<pkg>(dll: *R.DllInfo)`, registering
//! routines with `R.R_registerRoutines` (`const R = @import("R");`).
//! The zig object is zig build's; the C and C++ sources and the link are
//! rzig's, one step (`rzig t1`, zigbuild/tools/rzig/tier1.zig), as for a
//! tier-1 package.
const std = @import("std");

/// The fields of rzig's plan (zigbuild/tools/rzig/pkgplan.zig's `Plan`)
/// this file reads; the others are rzig's own. A package's rbuild sees
/// only these in `opts.plan`. Before feat-tier1-engine it saw
/// build_t1.zig's whole plan, the compile and link words (cc, cxx, fc,
/// link, libs, toolchain, sources, env) included: `rzig t1` reads those
/// itself now.
pub const Plan = struct {
    name: []const u8,
    srcdir: []const u8,
    output: []const u8,
    /// "libs", or "libs/x64" on Windows (R_ARCH); "" = the prefix itself
    libs_dir: []const u8 = "libs",
    /// rzig itself, which compiles the C and C++ sources and links
    rzig: []const u8 = "",
    target: []const u8 = "", // R's zig target, e.g. x86_64-linux-gnu.2.17
    r_include: []const u8 = "", // R_HOME/include
    /// plan.zon's own path (readPlan), for `rzig t1 --plan`
    path: []const u8 = "",
    /// The build root, plan.zon's directory (readPlan).
    root: []const u8 = "",
    /// -j for `rzig t1`, as rzig build's zig build got it (readPlan, from
    /// -Djobs); 0: rzig t1's own default, the CPU count.
    jobs: usize = 0,
};

pub fn readPlan(b: *std.Build) *const Plan {
    const plan_path = b.option([]const u8, "plan", "plan.zon") orelse @panic("-Dplan=<file> is required");
    const raw = std.Io.Dir.cwd().readFileAlloc(b.graph.io, plan_path, b.allocator, .limited(16 * 1024 * 1024)) catch @panic("cannot read the plan");
    const z = b.allocator.dupeSentinel(u8, raw, 0) catch @panic("OOM");
    const plan = b.allocator.create(Plan) catch @panic("OOM");
    var diag: std.zon.parse.Diagnostics = undefined; // the callee initializes it
    plan.* = std.zon.parse.fromSlice(Plan, .{ .gpa = b.allocator, .arena = b.allocator, .source = z, .diagnostics = &diag, .ignore_unknown_fields = true }) catch @panic("cannot parse the plan");
    // absolute: rzig passes it so, with `/` (pkgbuild.zig)
    plan.path = if (std.fs.path.isAbsolute(plan_path)) plan_path else b.pathResolve(&.{ std.process.currentPathAlloc(b.graph.io, b.allocator) catch @panic("cwd"), plan_path });
    plan.root = std.fs.path.dirname(plan.path) orelse ".";
    plan.jobs = b.option(usize, "jobs", "-j for rzig t1 (rzig build's -j)") orelse 0;
    return plan;
}

/// "libs" or "libs/x64" under the prefix.
pub fn installDir(libs_dir: []const u8) std.Build.InstallDir {
    return if (libs_dir.len == 0) .prefix else .{ .custom = libs_dir };
}

pub const Options = struct {
    /// the package's plan (readPlan), which `rzig t1` builds from
    plan: *const Plan,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    /// R_HOME/include
    r_include: []const u8,
};

pub const LibraryOptions = struct {
    /// The zig root (exports R_init_<pkg>); null for C-only.
    root_source_file: ?std.Build.LazyPath = null,
    /// C sources relative to the package's src/, compiled by rzig with the
    /// plan's flags: Makeconf's, with the site and user Makevars, what a
    /// tier-1 package with an empty Makevars gets. Tier 2 does not read
    /// the package's own src/Makevars, so its PKG_CPPFLAGS and PKG_CFLAGS
    /// do not apply (`#include "x.h"` still finds a header beside the
    /// source) [code-4].
    c_sources: []const []const u8 = &.{},
    /// C++ sources likewise.
    cxx_sources: []const []const u8 = &.{},
    /// More imports for the zig root.
    imports: []const std.Build.Module.Import = &.{},
};

/// R's C API as a module: `@import("R")`. R_NO_REMAP so Rf_* keep their
/// names; STRICT_R_HEADERS drops the legacy macros.
pub fn rModule(b: *std.Build, opts: Options) *std.Build.Module {
    const wf = b.addWriteFiles();
    const hdr = wf.add("r_zig.h",
        \\#define R_NO_REMAP 1
        \\#define STRICT_R_HEADERS 1
        \\#include <Rinternals.h>
        \\#include <R_ext/Rdynload.h>
        \\
    );
    const tc = b.addTranslateC(.{ .root_source_file = hdr, .target = opts.target, .optimize = opts.optimize });
    tc.addIncludePath(.{ .cwd_relative = opts.r_include });
    return tc.createModule();
}

/// The zig root's object (zig), then the C/C++ sources and the link
/// (`rzig t1`): the LazyPath of <pkg>.so (.dll).
pub fn addLibrary(b: *std.Build, opts: Options, lo: LibraryOptions) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ opts.plan.rzig, "t1", "--plan", opts.plan.path, "--root", b.fmt("{s}/t1", .{opts.plan.root}) });
    run.setName(b.fmt("rzig t1 {s}", .{opts.plan.output}));
    run.has_side_effects = true; // its objects and the link are in the build root, not zig build's cache
    // its compiles run beside each other: as many as zig build's -j, which
    // held them when each was a step of its own
    if (opts.plan.jobs > 0) run.addArgs(&.{ "-j", b.fmt("{d}", .{opts.plan.jobs}) });
    if (lo.root_source_file) |root| {
        var imports = std.ArrayList(std.Build.Module.Import).empty;
        imports.append(b.allocator, .{ .name = "R", .module = rModule(b, opts) }) catch @panic("OOM");
        imports.appendSlice(b.allocator, lo.imports) catch @panic("OOM");
        const mod = b.createModule(.{
            .root_source_file = root,
            .target = opts.target,
            .optimize = opts.optimize,
            .link_libc = true,
            .pic = true,
            .imports = imports.items,
        });
        const obj = b.addObject(.{ .name = opts.plan.name, .root_module = mod });
        run.addArg("--object");
        run.addFileArg(obj.getEmittedBin());
    }
    for (lo.c_sources) |c| run.addArgs(&.{ "--c", c });
    for (lo.cxx_sources) |c| run.addArgs(&.{ "--cxx", c });
    run.addArg("--out");
    return run.addOutputFileArg(opts.plan.output);
}
