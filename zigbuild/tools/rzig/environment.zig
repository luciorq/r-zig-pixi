//! Where the environment R lives in is: the directory an installed
//! Makeconf calls $(R_HOME)/../.. (feat-no-host-paths F1.5) — a conda
//! env, the standalone prefix, the wheel's r_zig/R; on Windows
//! <prefix>/Library. rzig is installed in R_HOME/bin/toolchain, so that is
//! four levels above its own directory, whatever the tree was moved to.
//! CONDA_PREFIX is the fallback, for an rzig that runs from anywhere else.
//!
//! The one place rzig decides it. Today only OpenMP asks (compiler.zig);
//! phase F3b moves the rest of Makeconf's environment flags (-I/-L, the
//! flang runtime, the conda-only rpath) here too.
const std = @import("std");
const builtin = @import("builtin");
const Ctx = @import("Ctx.zig");

/// <dir of this binary>/../../../.., without the dots: null when rzig does
/// not know where it is, or sits fewer than four levels deep.
pub fn selfLocated(ctx: *const Ctx) ?[]const u8 {
    var p = ctx.self_exe orelse return null;
    for (0..5) |_| p = std.fs.path.dirname(p) orelse return null;
    return p;
}

/// CONDA_PREFIX (CONDA_PREFIX/Library on Windows, conda-forge's place for
/// everything that is not Python), null when unset or empty.
pub fn conda(ctx: *const Ctx) !?[]const u8 {
    const p = ctx.getenv("CONDA_PREFIX") orelse return null;
    return if (ctx.os == .windows) try ctx.fmt("{s}/Library", .{p}) else p;
}

/// The environment whose llvm-openmp a -fopenmp compile uses: this tree's
/// own when it has omp.h (a conda env, or a standalone tree that build.zig
/// installed the headers into), else CONDA_PREFIX's whether or not it has.
pub fn forOpenmp(ctx: *const Ctx) !?[]const u8 {
    if (selfLocated(ctx)) |p| {
        if (ctx.isFile(try ctx.fmt("{s}/include/omp.h", .{p}))) return p;
    }
    return conda(ctx);
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

test "four levels above R_HOME/bin/toolchain, else CONDA_PREFIX(/Library)" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const ctx = &f.ctx;
    ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    try testing.expectEqualStrings(f.path("tree"), selfLocated(ctx).?);
    try testing.expect(try forOpenmp(ctx) == null);
    try f.env.put("CONDA_PREFIX", "/env");
    try testing.expectEqualStrings("/env", (try forOpenmp(ctx)).?);
    try f.touch("tree/include/omp.h");
    try testing.expectEqualStrings(f.path("tree"), (try forOpenmp(ctx)).?);
    // omp.h is the test, not the directory
    ctx.self_exe = f.path("elsewhere/lib/R/bin/toolchain/zig-cc");
    try testing.expectEqualStrings("/env", (try forOpenmp(ctx)).?);
    ctx.os = .windows;
    try testing.expectEqualStrings("/env/Library", (try forOpenmp(ctx)).?);
    try f.env.put("CONDA_PREFIX", "");
    try testing.expect(try forOpenmp(ctx) == null);
    // too shallow, or unknown
    ctx.self_exe = "/a/b/zig-cc";
    try testing.expect(selfLocated(ctx) == null);
    ctx.self_exe = null;
    try testing.expect(selfLocated(ctx) == null);
}
