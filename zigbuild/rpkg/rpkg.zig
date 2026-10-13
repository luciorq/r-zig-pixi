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
const std = @import("std");
const t1 = @import("build_t1.zig");

pub const Options = struct {
    /// link, libs and cc as rzig computed them for this package
    plan: *const t1.Plan,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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

/// Objects from the zig root (zig) and the C/C++ sources (rzig), linked by
/// rzig as tier 1 links: the LazyPath of <pkg>.so (.dll).
pub fn addLibrary(b: *std.Build, opts: Options, lo: LibraryOptions) std.Build.LazyPath {
    var objs = std.ArrayList(std.Build.LazyPath).empty;
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
        objs.append(b.allocator, obj.getEmittedBin()) catch @panic("OOM");
    }
    if (lo.c_sources.len > 0 or lo.cxx_sources.len > 0) {
        var srcs = std.ArrayList(t1.Source).empty;
        for (lo.c_sources) |c| srcs.append(b.allocator, .{ .lang = "c", .path = c, .obj = b.fmt("{s}.o", .{std.fs.path.stem(c)}) }) catch @panic("OOM");
        for (lo.cxx_sources) |c| srcs.append(b.allocator, .{ .lang = "cxx", .path = c, .obj = b.fmt("{s}.o", .{std.fs.path.stem(c)}) }) catch @panic("OOM");
        var sub = opts.plan.*;
        sub.sources = srcs.items;
        for (t1.compileAll(b, &sub)) |o| objs.append(b.allocator, o) catch @panic("OOM");
    }
    return t1.link(b, opts.plan, objs.items);
}
