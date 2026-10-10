//! Unit-test fixtures: a Ctx over a private environment, and a temporary
//! directory to put libraries and programs in.
const std = @import("std");
const testing = std.testing;
const Ctx = @import("Ctx.zig");
const Args = @import("cmdline.zig").Args;

pub const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    env: std.process.Environ.Map,
    tmp: testing.TmpDir,
    ctx: Ctx,
    /// The temporary directory's absolute path, with `/` separators as
    /// rzig's own paths have (main.zig's selfExe, environment.zig).
    root: []const u8,
    /// What the code under test warned about (Ctx.warn), one line each.
    warnings: std.ArrayList(u8),

    /// In place, since `ctx` points into the fixture.
    pub fn init(f: *Fixture, os: Ctx.Os) !void {
        f.arena = .init(testing.allocator);
        f.env = .init(f.arena.allocator());
        f.tmp = testing.tmpDir(.{});
        f.warnings = .empty;
        f.ctx = .{ .io = testing.io, .arena = f.arena.allocator(), .env = &f.env, .os = os, .name = "rzig-test", .warnings = &f.warnings };
        f.root = try f.tmp.dir.realPathFileAlloc(testing.io, ".", f.arena.allocator());
        if (@import("builtin").os.tag == .windows) f.root = try std.mem.replaceOwned(u8, f.arena.allocator(), f.root, "\\", "/");
        // hermetic: no SDK unless a test provides an xcrun
        f.ctx.xcrun = f.path("no-xcrun");
    }

    /// The warnings so far, then forgets them.
    pub fn takeWarnings(f: *Fixture) []const u8 {
        const w = f.warnings.items;
        f.warnings = .empty;
        return w;
    }

    pub fn deinit(f: *Fixture) void {
        f.tmp.cleanup();
        f.arena.deinit();
    }

    /// <root>/<sub>
    pub fn path(f: *Fixture, sub: []const u8) []const u8 {
        return f.ctx.fmt("{s}/{s}", .{ f.root, sub }) catch @panic("OOM");
    }

    pub fn fmt(f: *Fixture, comptime format: []const u8, args: anytype) []const u8 {
        return f.ctx.fmt(format, args) catch @panic("OOM");
    }

    /// An empty file at <root>/<sub>, parents made.
    pub fn touch(f: *Fixture, sub: []const u8) !void {
        return f.write(sub, "", .default_file);
    }

    pub fn touchExe(f: *Fixture, sub: []const u8) !void {
        return f.write(sub, "", .fromMode(0o755));
    }

    /// A program rzig's lookups find as <dir>/<name> (find_zig.inDir): an
    /// empty executable file, or on a Windows host an empty <name>.exe (a
    /// file is what counts there). Its path, as rzig finds it.
    pub fn touchProgram(f: *Fixture, sub: []const u8) ![]const u8 {
        const windows = @import("builtin").os.tag == .windows;
        const exe = if (windows) f.fmt("{s}.exe", .{sub}) else sub;
        if (windows) try f.touch(exe) else try f.touchExe(exe);
        const dir = std.fs.path.dirname(sub) orelse ".";
        return f.fmt("{s}{s}{s}", .{ f.path(dir), if (windows) "\\" else "/", std.fs.path.basename(exe) });
    }

    pub fn write(f: *Fixture, sub: []const u8, data: []const u8, permissions: std.Io.File.Permissions) !void {
        if (std.fs.path.dirname(sub)) |d| try f.tmp.dir.createDirPath(testing.io, d);
        try f.tmp.dir.writeFile(testing.io, .{ .sub_path = sub, .data = data, .flags = .{ .permissions = permissions } });
    }
};

pub fn expectArgs(expected: Args, actual: Args) !void {
    errdefer std.debug.print("expected: {f}\nactual:   {f}\n", .{ fmtArgs(expected), fmtArgs(actual) });
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, x| try testing.expectEqualStrings(e, x);
}

fn fmtArgs(args: Args) std.fmt.Alt(Args, struct {
    fn f(xs: Args, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (xs) |x| try w.print("[{s}] ", .{x});
    }
}.f) {
    return .{ .data = args };
}
