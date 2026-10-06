//! The environments a package compiles against (feat-no-host-paths F3b):
//! the one R is installed in, and at most one more, named on purpose. The
//! one place rzig decides them; compiler.zig turns them into flags, the
//! ones Makeconf's CPPFLAGS and LDFLAGS carried before (both are empty
//! now, in every distribution).
//!
//! 1. R's own. rzig is installed in <root>/lib/R/bin/toolchain
//!    (<root>/Library/lib/R/bin/toolchain on Windows), so its own path,
//!    symlinks resolved (main.zig's selfExe), names the root: a conda env,
//!    the standalone prefix, the wheel's r_zig/R. Anywhere else
//!    (zig-out/bin, a bare copy) rzig has no environment of its own.
//! 2. R_ZIG_EXTRA_ENV, when set: one more environment root, for a
//!    standalone R compiling against an environment of libraries, and for
//!    the dev tree under pixi (pixi.toml sets it to the pixi env). It
//!    counts whether or not rzig found an environment of its own. Made
//!    absolute and resolved to its real path, so that it is dropped when it
//!    names R's own (a symlinked or differently spelled path included). Set
//!    it to an absolute path: a relative one resolves against the
//!    directory each compile runs in (R CMD INSTALL compiles in the
//!    package's src/), not the one it was set in.
//!
//! An environment's directory is its root on unix and <root>/Library on
//! Windows (conda-forge's place for everything that is not Python): its
//! include/ and lib/ are what the flags name. It is a conda environment
//! when <root>/conda-meta is a directory, on unix only: links then get an
//! rpath into its lib/, so a library of the env loads in any process that
//! loads the package (glibc applies only the executable's own DT_RPATH to
//! a dlopened library's dependencies). Windows has no rpath.
//!
//! CONDA_PREFIX is never read, nor PIXI_* or R_HOME, and the current
//! directory names no environment: an activated environment R is not
//! installed in must not change what a package compiles against.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");

pub const Env = struct {
    /// Holds include/ and lib/: the root, or <root>/Library on Windows.
    dir: []const u8,
    /// <root>/conda-meta is a directory (never on Windows): links get an
    /// rpath into <dir>/lib.
    conda: bool,
};

/// Where rzig is installed, below the environment's directory.
const toolchain_dir = "/lib/R/bin/toolchain";
const library = "/Library";

/// R's own environment, from the directory this binary is installed in:
/// <dir>/lib/R/bin/toolchain, with <dir> ending in /Library on Windows
/// (compared ignoring case there). null anywhere else.
pub fn own(ctx: *const Ctx) !?Env {
    const exe = ctx.self_exe orelse return null;
    const bin = exe[0 .. mem.findScalarLast(u8, exe, '/') orelse return null];
    if (!endsWith(ctx, bin, toolchain_dir)) return null;
    const dir = bin[0 .. bin.len - toolchain_dir.len];
    if (ctx.os == .windows) {
        if (!endsWith(ctx, dir, library)) return null;
        return .{ .dir = dir, .conda = false };
    }
    return .{ .dir = dir, .conda = try isConda(ctx, dir) };
}

/// The environment R_ZIG_EXTRA_ENV names (unset or empty: none), at its
/// real path; none, with a warning, when that path does not resolve.
pub fn extra(ctx: *const Ctx) !?Env {
    const v = ctx.getenv("R_ZIG_EXTRA_ENV") orelse return null;
    var root: []const u8 = Io.Dir.cwd().realPathFileAlloc(ctx.io, v, ctx.arena) catch |err| {
        ctx.warn("warning: R_ZIG_EXTRA_ENV={s}: {t}; ignored", .{ v, err });
        return null;
    };
    if (builtin.os.tag == .windows) root = try mem.replaceOwned(u8, ctx.arena, root, "\\", "/");
    if (ctx.os == .windows) return .{ .dir = try ctx.fmt("{s}" ++ library, .{root}), .conda = false };
    return .{ .dir = root, .conda = try isConda(ctx, root) };
}

/// R's own environment, then the extra one unless it is the same.
pub fn list(ctx: *const Ctx) ![]const Env {
    var out: std.ArrayList(Env) = .empty;
    const o = try own(ctx);
    if (o) |e| try out.append(ctx.arena, e);
    if (try extra(ctx)) |e| {
        const same = if (o) |oe| (if (ctx.os == .windows) std.ascii.eqlIgnoreCase(oe.dir, e.dir) else mem.eql(u8, oe.dir, e.dir)) else false;
        if (!same) try out.append(ctx.arena, e);
    }
    return out.items;
}

/// The environment whose llvm-openmp a -fopenmp link uses: the first with
/// include/omp.h (a conda env with llvm-openmp, a standalone tree build.zig
/// installed the headers into).
pub fn openmp(ctx: *const Ctx, envs: []const Env) !?Env {
    for (envs) |e| {
        if (ctx.isFile(try ctx.fmt("{s}/include/omp.h", .{e.dir}))) return e;
    }
    return null;
}

fn isConda(ctx: *const Ctx, root: []const u8) !bool {
    if (ctx.os == .windows) return false;
    return ctx.isDir(try ctx.fmt("{s}/conda-meta", .{root}));
}

fn endsWith(ctx: *const Ctx, s: []const u8, suffix: []const u8) bool {
    return if (ctx.os == .windows) std.ascii.endsWithIgnoreCase(s, suffix) else mem.endsWith(u8, s, suffix);
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

/// A decoy every test sets: a conda env with OpenMP, as an activated env
/// R is not installed in looks. Nothing may come from it.
fn decoy(f: *testutil.Fixture) !void {
    try f.tmp.dir.createDirPath(testing.io, "decoy/conda-meta");
    try f.touch("decoy/include/omp.h");
    try f.touch("decoy/lib/libomp.so");
    try f.touch("decoy/Library/include/omp.h");
    try f.touch("decoy/Library/lib/libomp.lib");
    try f.env.put("CONDA_PREFIX", f.path("decoy"));
}

fn expectEnvs(f: *testutil.Fixture, expected: []const Env) !void {
    const got = try list(&f.ctx);
    errdefer for (got) |e| std.debug.print("got: {s} conda={}\n", .{ e.dir, e.conda });
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try testing.expectEqualStrings(e.dir, g.dir);
        try testing.expectEqual(e.conda, g.conda);
        try testing.expect(mem.find(u8, g.dir, "decoy") == null);
    }
}

test "own: <dir>/lib/R/bin/toolchain, else none; never CONDA_PREFIX" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try decoy(&f);
    f.ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    try expectEnvs(&f, &.{.{ .dir = f.path("tree"), .conda = false }});
    // a conda env: conda-meta a directory, not a file
    try f.touch("tree/conda-meta");
    try expectEnvs(&f, &.{.{ .dir = f.path("tree"), .conda = false }});
    try f.tmp.dir.createDirPath(testing.io, "env/conda-meta");
    f.ctx.self_exe = f.path("env/lib/R/bin/toolchain/zig-cxx");
    try expectEnvs(&f, &.{.{ .dir = f.path("env"), .conda = true }});
    // anywhere else: nothing, the decoy included
    for ([_][]const u8{ "/x/zig-out/bin/rzig", "/x/lib/R/bin/zig-cc", "/x/xlib/R/bin/toolchain/zig-cc", "zig-cc" }) |p| {
        f.ctx.self_exe = p;
        try expectEnvs(&f, &.{});
    }
    f.ctx.self_exe = null;
    try expectEnvs(&f, &.{});
    try testing.expect(try openmp(&f.ctx, try list(&f.ctx)) == null);
    // R installed at /
    f.ctx.self_exe = "/lib/R/bin/toolchain/zig-cc";
    try expectEnvs(&f, &.{.{ .dir = "", .conda = false }});
}

test "Windows: <root>/Library, ignoring case; no conda rpath" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try decoy(&f);
    try f.tmp.dir.createDirPath(testing.io, "env/conda-meta");
    f.ctx.self_exe = "C:/env/Library/lib/R/bin/toolchain/gcc.exe";
    try expectEnvs(&f, &.{.{ .dir = "C:/env/Library", .conda = false }});
    f.ctx.self_exe = "C:/env/library/LIB/r/bin/Toolchain/g++.exe";
    try expectEnvs(&f, &.{.{ .dir = "C:/env/library", .conda = false }});
    f.ctx.self_exe = f.fmt("{s}/Library/lib/R/bin/toolchain/gcc.exe", .{f.path("env")});
    try expectEnvs(&f, &.{.{ .dir = f.fmt("{s}/Library", .{f.path("env")}), .conda = false }});
    // no Library: not an installed tree on Windows
    f.ctx.self_exe = "C:/env/lib/R/bin/toolchain/gcc.exe";
    try expectEnvs(&f, &.{});
}

test "R_ZIG_EXTRA_ENV: resolved, after R's own, dropped when the same" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try decoy(&f);
    try f.tmp.dir.createDirPath(testing.io, "env/conda-meta");
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    // with no R tree of its own too
    try f.env.put("R_ZIG_EXTRA_ENV", f.fmt("{s}/", .{f.path("env")}));
    try expectEnvs(&f, &.{.{ .dir = f.path("env"), .conda = true }});
    f.ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    try expectEnvs(&f, &.{ .{ .dir = f.path("tree"), .conda = false }, .{ .dir = f.path("env"), .conda = true } });
    // a symlink or a path with dots names the same place (symlinks need
    // privileges on Windows)
    if (builtin.os.tag != .windows) {
        try f.tmp.dir.symLink(testing.io, f.path("tree"), "link", .{ .is_directory = true });
        try f.env.put("R_ZIG_EXTRA_ENV", f.path("link"));
        try expectEnvs(&f, &.{.{ .dir = f.path("tree"), .conda = false }});
    }
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("tree/lib/.."));
    try expectEnvs(&f, &.{.{ .dir = f.path("tree"), .conda = false }});
    // a missing one: ignored, with a warning
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("nowhere"));
    try expectEnvs(&f, &.{.{ .dir = f.path("tree"), .conda = false }});
    try testing.expect(mem.find(u8, f.takeWarnings(), "R_ZIG_EXTRA_ENV=") != null);
    try f.env.put("R_ZIG_EXTRA_ENV", "");
    try expectEnvs(&f, &.{.{ .dir = f.path("tree"), .conda = false }});
    try testing.expectEqualStrings("", f.takeWarnings());
    // Windows: <root>/Library, no rpath
    f.ctx.os = .windows;
    f.ctx.self_exe = null;
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("env"));
    try expectEnvs(&f, &.{.{ .dir = f.fmt("{s}/Library", .{f.path("env")}), .conda = false }});
}

test "OpenMP: the first environment with include/omp.h" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try decoy(&f);
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    try f.tmp.dir.createDirPath(testing.io, "env/include/omp.h"); // a directory is no header
    f.ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("env"));
    try testing.expect(try openmp(&f.ctx, try list(&f.ctx)) == null);
    try f.touch("env2/include/omp.h");
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("env2"));
    try testing.expectEqualStrings(f.path("env2"), (try openmp(&f.ctx, try list(&f.ctx))).?.dir);
    try f.touch("tree/include/omp.h");
    try testing.expectEqualStrings(f.path("tree"), (try openmp(&f.ctx, try list(&f.ctx))).?.dir);
}
