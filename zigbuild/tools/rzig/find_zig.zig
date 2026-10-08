//! Which zig to run: $ZIG_BIN when it names an executable (the r-zig wheel
//! points it at the PyPI `ziglang` package's binary), else zig on PATH
//! (the conda env's; on win-64 conda-forge installs the real binary only
//! as x86_64-w64-mingw32-zig, `zig` being a .bat), else `python3 -m
//! ziglang` (the wheel with ziglang outside R's own site-packages).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");

const windows = builtin.os.tag == .windows;

/// The command that runs zig: one path, or python3 -m ziglang.
pub fn find(ctx: *Ctx) ![]const []const u8 {
    if (ctx.getenv("ZIG_BIN")) |bin| {
        if (try executable(ctx, bin)) |p| return try ctx.arena.dupe([]const u8, &.{p});
    }
    for ([_][]const u8{ "zig", "x86_64-w64-mingw32-zig" }) |name| {
        if (try onPath(ctx, name)) |p| return try ctx.arena.dupe([]const u8, &.{p});
    }
    return &.{ "python3", "-m", "ziglang" };
}

/// `[ -x path ]`. On Windows also path.exe: MSYS completed the extension,
/// and the wheel's ZIG_BIN names ziglang/zig without one.
fn executable(ctx: *Ctx, path: []const u8) !?[]const u8 {
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

/// `command -v name`: the first PATH entry holding an executable file of
/// that name (name.exe on Windows; a .bat is no use to CreateProcess with
/// arguments like ours). An empty entry is the current directory. Also how
/// the applets find flang, in `ctx.env`'s PATH.
pub fn onPath(ctx: *Ctx, name: []const u8) !?[]const u8 {
    const path = ctx.getenv("PATH") orelse return null;
    var it = mem.splitScalar(u8, path, if (windows) ';' else ':');
    while (it.next()) |entry| {
        const dir = if (entry.len == 0) "." else entry;
        const sep = if (mem.endsWith(u8, dir, "/") or (windows and mem.endsWith(u8, dir, "\\"))) "" else if (windows) "\\" else "/";
        const cand = try ctx.fmt("{s}{s}{s}{s}", .{ dir, sep, name, if (windows) ".exe" else "" });
        if (ctx.isFile(cand) and canRun(ctx, cand)) return cand;
    }
    return null;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

test "ZIG_BIN, then PATH (zig before the mingw name), then python3 -m ziglang" {
    if (windows) return error.SkipZigTest;
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const ctx = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "b/zig"); // a directory named zig is skipped
    try f.touchExe("a/x86_64-w64-mingw32-zig");
    try f.touch("a/plain");
    try f.touchExe("zigbin");

    try testutil.expectArgs(&.{ "python3", "-m", "ziglang" }, try find(ctx));
    try f.env.put("PATH", f.fmt("{s}:{s}/", .{ f.path("b"), f.path("a") }));
    try testing.expectEqualStrings(f.path("a/x86_64-w64-mingw32-zig"), (try find(ctx))[0]);
    try f.touchExe("a/zig");
    try testing.expectEqualStrings(f.path("a/zig"), (try find(ctx))[0]);
    // not executable: ignored
    try f.env.put("ZIG_BIN", f.path("a/plain"));
    try testing.expectEqualStrings(f.path("a/zig"), (try find(ctx))[0]);
    try f.env.put("ZIG_BIN", f.path("zigbin"));
    try testing.expectEqualStrings(f.path("zigbin"), (try find(ctx))[0]);
}
