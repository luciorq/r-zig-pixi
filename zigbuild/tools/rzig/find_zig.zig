//! Which zig to run (feat-standalone-toolchain B2 a, B34 a), the first
//! that is there:
//! 1. $ZIG_BIN, when it names an executable (the r-zig wheel points it at
//!    the PyPI `ziglang` package's binary);
//! 2. the compilers group's zig, <rzig dir>/zig/zig (R_HOME/bin/toolchain/
//!    zig/zig in the standalone tree);
//! 3. zig in the bin/ of the environment R is installed in
//!    (environment.zig): a conda env used without activation, such as an
//!    IDE pointed at <env>/bin/R. On win-64 conda-forge installs the real
//!    binary only as x86_64-w64-mingw32-zig (`zig` is a .bat), so that
//!    name too, after zig;
//! 4. zig on PATH, then x86_64-w64-mingw32-zig;
//! 5. `python3 -m ziglang`, when the python3 on PATH has ziglang (the
//!    wheel with ziglang outside R's own site-packages).
//! None: null, and the compile names the compilers group (groups.zig).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const environment = @import("environment.zig");

const windows = builtin.os.tag == .windows;

/// zig's names in a bin/ directory and on PATH, in this order.
const names = [_][]const u8{ "zig", "x86_64-w64-mingw32-zig" };

pub const Zig = struct {
    /// The command that runs zig: one path, or python3 -m ziglang.
    argv: []const []const u8,
    /// The file found: zig, or the python3 that has ziglang.
    file: []const u8,
};

/// The zig to run, or null when there is none.
pub fn find(ctx: *Ctx) !?Zig {
    if (ctx.getenv("ZIG_BIN")) |bin| {
        if (try executable(ctx, bin)) |p| return try one(ctx, p);
    }
    if (environment.toolchain(ctx)) |tc| {
        if (try inDir(ctx, try ctx.fmt("{s}/zig", .{tc}), "zig")) |p| return try one(ctx, p);
    }
    if (try environment.own(ctx)) |e| {
        const bin = try ctx.fmt("{s}/bin", .{e.dir});
        for (names) |n| if (try inDir(ctx, bin, n)) |p| return try one(ctx, p);
    }
    for (names) |n| if (try onPath(ctx, n)) |p| return try one(ctx, p);
    // `python3 -m ziglang` fails with a traceback when python3 has no
    // ziglang: ask first, quietly. Run by name, as before; in a real run
    // ctx.env's PATH is rzig's own.
    const py = (try onPath(ctx, "python3")) orelse return null;
    if (!ctx.capture(&.{ py, "-c", "import ziglang" }).ok) return null;
    return .{ .argv = &.{ "python3", "-m", "ziglang" }, .file = py };
}

fn one(ctx: *Ctx, p: []const u8) !Zig {
    return .{ .argv = try ctx.arena.dupe([]const u8, &.{p}), .file = p };
}

/// `[ -x path ]`. On Windows also path.exe: MSYS completed the extension,
/// and the wheel's ZIG_BIN names ziglang/zig without one.
pub fn executable(ctx: *Ctx, path: []const u8) !?[]const u8 {
    if (canRun(ctx, path)) return path;
    if (windows and !mem.endsWith(u8, path, ".exe")) {
        const exe = try ctx.fmt("{s}.exe", .{path});
        if (canRun(ctx, exe)) return exe;
    }
    return null;
}

fn canRun(ctx: *Ctx, path: []const u8) bool {
    if (path.len == 0) return false;
    if (windows) return ctx.isFile(path);
    Io.Dir.cwd().access(ctx.io, path, .{ .execute = true }) catch return false;
    return true;
}

/// <dir>/<name> (name.exe on Windows: a .bat is no use to CreateProcess
/// with arguments like ours) when it is an executable file.
pub fn inDir(ctx: *Ctx, dir: []const u8, name: []const u8) !?[]const u8 {
    const sep = if (mem.endsWith(u8, dir, "/") or (windows and mem.endsWith(u8, dir, "\\"))) "" else if (windows) "\\" else "/";
    const cand = try ctx.fmt("{s}{s}{s}{s}", .{ dir, sep, name, if (windows) ".exe" else "" });
    if (ctx.isFile(cand) and canRun(ctx, cand)) return cand;
    return null;
}

/// `command -v name`: the first PATH entry holding an executable file of
/// that name (inDir). An empty entry is the current directory. Also how the
/// applets find flang and make, in `ctx.env`'s PATH.
pub fn onPath(ctx: *Ctx, name: []const u8) !?[]const u8 {
    const path = ctx.getenv("PATH") orelse return null;
    var it = mem.splitScalar(u8, path, if (windows) ';' else ':');
    while (it.next()) |entry| {
        if (try inDir(ctx, if (entry.len == 0) "." else entry, name)) |p| return p;
    }
    return null;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

fn expectZig(expected: []const u8, got: ?Zig) !void {
    const z = got orelse return error.TestExpectedZig;
    try testutil.expectArgs(&.{expected}, z.argv);
    try testing.expectEqualStrings(expected, z.file);
}

test "ZIG_BIN, then PATH (zig before the mingw name); no python3: none" {
    if (windows) return error.SkipZigTest;
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const ctx = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "b/zig"); // a directory named zig is skipped
    try f.touchExe("a/x86_64-w64-mingw32-zig");
    try f.touch("a/plain");
    try f.touchExe("zigbin");

    try testing.expect(try find(ctx) == null);
    try f.env.put("PATH", f.fmt("{s}:{s}/", .{ f.path("b"), f.path("a") }));
    try expectZig(f.path("a/x86_64-w64-mingw32-zig"), try find(ctx));
    try f.touchExe("a/zig");
    try expectZig(f.path("a/zig"), try find(ctx));
    // not executable: ignored
    try f.env.put("ZIG_BIN", f.path("a/plain"));
    try expectZig(f.path("a/zig"), try find(ctx));
    try f.env.put("ZIG_BIN", f.path("zigbin"));
    try expectZig(f.path("zigbin"), try find(ctx));
}

test "the toolchain's zig/ wins over the environment's bin and PATH; ZIG_BIN over all" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const ctx = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    const path_zig = try f.touchProgram("p/zig");
    const bin_zig = try f.touchProgram("tree/bin/zig");
    const tc_zig = try f.touchProgram("tree/lib/R/bin/toolchain/zig/zig");
    try f.env.put("PATH", f.path("p"));
    try expectZig(tc_zig, try find(ctx));
    try f.env.put("ZIG_BIN", path_zig);
    try expectZig(path_zig, try find(ctx));
    _ = f.env.swapRemove("ZIG_BIN");
    // a directory named zig in zig/ is no zig: the environment's bin next
    try f.tmp.dir.deleteFile(testing.io, if (windows) "tree/lib/R/bin/toolchain/zig/zig.exe" else "tree/lib/R/bin/toolchain/zig/zig");
    try f.tmp.dir.createDirPath(testing.io, if (windows) "tree/lib/R/bin/toolchain/zig/zig.exe" else "tree/lib/R/bin/toolchain/zig/zig");
    try expectZig(bin_zig, try find(ctx));
    // a bare copy of rzig: its own directory's zig/, no environment
    ctx.self_exe = f.path("bare/zig-cc");
    try expectZig(path_zig, try find(ctx));
    const bare_zig = try f.touchProgram("bare/zig/zig");
    try expectZig(bare_zig, try find(ctx));
}

test "the environment's bin: zig, then the mingw name, before PATH; R's own only" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const ctx = &f.ctx;
    // conda's win-64 layout: <prefix>/Library/bin/x86_64-w64-mingw32-zig.exe
    try f.tmp.dir.createDirPath(testing.io, "env/Library/lib/R/bin/toolchain");
    ctx.self_exe = f.path("env/Library/lib/R/bin/toolchain/gcc.exe");
    const path_zig = try f.touchProgram("p/zig");
    try f.env.put("PATH", f.path("p"));
    try expectZig(path_zig, try find(ctx));
    const mingw = try f.touchProgram("env/Library/bin/x86_64-w64-mingw32-zig");
    try expectZig(mingw, try find(ctx));
    const zig = try f.touchProgram("env/Library/bin/zig");
    try expectZig(zig, try find(ctx));
    // R_ZIG_EXTRA_ENV's bin is not looked in (B34: R's own environment)
    ctx.os = .linux;
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    _ = try f.touchProgram("extra/bin/zig");
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("extra"));
    try expectZig(path_zig, try find(ctx));
}

test "python3 -m ziglang only when the python3 on PATH has ziglang" {
    if (windows) return error.SkipZigTest; // shell-script stand-in for python3
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const ctx = &f.ctx;
    try f.env.put("PATH", f.path("py"));
    // it answers `-c 'import ziglang'` with an error, as a python3 without
    // ziglang does
    try f.write("py/python3", "#!/bin/sh\n[ \"$2\" = 'import ziglang' ] && { echo \"ModuleNotFoundError\" >&2; exit 1; }\nexit 0\n", .fromMode(0o755));
    try testing.expect(try find(ctx) == null);
    try f.write("py/python3", "#!/bin/sh\necho on stdout\n", .fromMode(0o755));
    const z = (try find(ctx)).?;
    try testutil.expectArgs(&.{ "python3", "-m", "ziglang" }, z.argv);
    try testing.expectEqualStrings(f.path("py/python3"), z.file);
}
