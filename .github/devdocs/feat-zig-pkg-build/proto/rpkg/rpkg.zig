//! The helper a tier-2 package's build.zig receives as `rpkg`: R's
//! headers as a zig module, and a shared library linked by rzig.
const std = @import("std");
const t1 = @import("build_t1.zig");

pub const Options = struct {
    plan: *const t1.Plan, // link, libs and cc as rzig computed them
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    r_include: []const u8,
};

pub const LibraryOptions = struct {
    root_source_file: ?std.Build.LazyPath = null, // zig root (exports R_init_<pkg>)
    c_sources: []const []const u8 = &.{}, // relative to the package's src/
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

/// Objects from the zig root (native) and the C sources (rzig), linked by
/// rzig exactly as tier 1 links: the LazyPath of <pkg>.so.
pub fn addLibrary(b: *std.Build, opts: Options, lo: LibraryOptions) std.Build.LazyPath {
    var objs = std.ArrayList(std.Build.LazyPath).empty;
    if (lo.root_source_file) |root| {
        const mod = b.createModule(.{
            .root_source_file = root,
            .target = opts.target,
            .optimize = opts.optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{.{ .name = "R", .module = rModule(b, opts) }},
        });
        const obj = b.addObject(.{ .name = opts.plan.name, .root_module = mod });
        objs.append(b.allocator, obj.getEmittedBin()) catch @panic("OOM");
    }
    if (lo.c_sources.len > 0) {
        var srcs = std.ArrayList(t1.Source).empty;
        for (lo.c_sources) |c| srcs.append(b.allocator, .{ .lang = "c", .path = c, .obj = b.fmt("{s}.o", .{std.fs.path.stem(c)}) }) catch @panic("OOM");
        var sub = opts.plan.*;
        sub.sources = srcs.items;
        for (t1.compileAll(b, &sub)) |o| objs.append(b.allocator, o) catch @panic("OOM");
    }
    return t1.link(b, opts.plan, objs.items);
}
