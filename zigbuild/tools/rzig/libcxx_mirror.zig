//! libc++ is linked statically, everywhere (decided 2026-09-30). Upstream
//! zig always does; conda-forge's zig (feedstock patch Lld.zig-prefer-
//! shared-libcxx) links a shared libc++ instead whenever one sits in
//! <zig lib dir>/../../lib, which is always the case in a macOS conda env
//! and in any env with the `libcxx` package. The probe is relative to the
//! lib dir, so point ZIG_LIB_DIR at a mirror of it: a directory of
//! symlinks, nested as <mirror>/lib/zig so that <mirror>/lib has no
//! libc++. Kept in the user's cache, one per zig lib dir, made once:
//! creating the directory is the lock for parallel make jobs, `.complete`
//! the marker. Not on Windows (no win-64 env has libc++.dll.a). Retires
//! with F4 (one zig).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");

/// Sets ZIG_LIB_DIR in `ctx.env` when the zig found at `zig0` (the first
/// word of its command) would link a shared libc++. Returns whether it did.
pub fn apply(ctx: *Ctx, zig0: []const u8) !bool {
    const lib_dir = (try zigLibDir(ctx, zig0)) orelse return false;
    if (!ctx.isDir(lib_dir)) return false;
    for ([_][]const u8{ "libc++.1.dylib", "libc++.dylib", "libc++.so.1", "libc++.so" }) |name| {
        if (ctx.exists(try ctx.fmt("{s}/../../lib/{s}", .{ lib_dir, name }))) break;
    } else return false;

    const real = Io.Dir.cwd().realPathFileAlloc(ctx.io, lib_dir, ctx.arena) catch return false;
    const names = try listing(ctx, real);
    const m = try ctx.fmt("{s}/r-zig/zig-lib-{d}", .{ try cacheHome(ctx), try key(ctx, real, names) });
    const complete = try ctx.fmt("{s}/.complete", .{m});
    if (!ctx.exists(complete)) {
        if (lock(ctx, m)) {
            populate(ctx, real, names, m) catch {};
        } else {
            // another job is making it
            var i: usize = 0;
            while (!ctx.exists(complete) and i < 100) : (i += 1) {
                try ctx.io.sleep(.fromMilliseconds(100), .awake);
            }
        }
    }
    if (!ctx.exists(complete)) {
        ctx.warn("could not prepare {s}; this link may use a shared libc++", .{m});
        return false;
    }
    try ctx.env.put("ZIG_LIB_DIR", try ctx.fmt("{s}/lib/zig", .{m}));
    return true;
}

/// ZIG_LIB_DIR when set, else <dir of zig>/../lib/zig when it holds
/// std/std.zig (conda's layout). `python3 -m ziglang` has none.
fn zigLibDir(ctx: *Ctx, zig0: []const u8) !?[]const u8 {
    if (ctx.getenv("ZIG_LIB_DIR")) |d| return d;
    if (mem.eql(u8, zig0, "python3")) return null;
    const bin = if (mem.findScalarLast(u8, zig0, '/')) |i| zig0[0..i] else ".";
    if (!ctx.isFile(try ctx.fmt("{s}/../lib/zig/std/std.zig", .{bin}))) return null;
    return try ctx.fmt("{s}/../lib/zig", .{bin});
}

/// What `ls` prints for the directory: its non-hidden names, sorted. In
/// byte order, which the bash shim's `ls` used only under LC_ALL=C (its
/// order, and so the key, followed the locale).
fn listing(ctx: *Ctx, dir_path: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var dir = Io.Dir.cwd().openDir(ctx.io, dir_path, .{ .iterate = true }) catch return names.items;
    defer dir.close(ctx.io);
    var it = dir.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        try names.append(ctx.arena, try ctx.arena.dupe(u8, entry.name));
    }
    mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return mem.lessThan(u8, a, b);
        }
    }.lt);
    return names.items;
}

/// The bash shim's `{ echo "$zl"; ls "$zl"; } | cksum`, so both name the
/// same mirror: the lib dir changes when zig is updated in place.
fn key(ctx: *Ctx, real: []const u8, names: []const []const u8) !u32 {
    var text: std.ArrayList(u8) = .empty;
    try text.print(ctx.arena, "{s}\n", .{real});
    for (names) |n| try text.print(ctx.arena, "{s}\n", .{n});
    return cksum(text.items);
}

/// POSIX `cksum`: CRC-32 (polynomial 0x04C11DB7, unreflected) over the
/// data, then over its length in as few bytes as it takes, low first.
fn cksum(data: []const u8) u32 {
    var crc = std.hash.crc.Crc32Cksum.init();
    crc.update(data);
    var n = data.len;
    while (n != 0) : (n >>= 8) crc.update(&.{@as(u8, @truncate(n))});
    return crc.final();
}

/// `${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}`
fn cacheHome(ctx: *Ctx) ![]const u8 {
    if (ctx.getenv("XDG_CACHE_HOME")) |d| return d;
    return ctx.fmt("{s}/.cache", .{ctx.getenv("HOME") orelse "/tmp"});
}

/// Whether this process gets to make the mirror.
fn lock(ctx: *Ctx, m: []const u8) bool {
    const cwd = Io.Dir.cwd();
    cwd.createDirPath(ctx.io, std.fs.path.dirname(m).?) catch return false;
    cwd.createDir(ctx.io, m, .default_dir) catch return false;
    return true;
}

/// A symlink per entry, then the marker, which is only written once all
/// links exist (the bash shim checked the last one only).
fn populate(ctx: *Ctx, real: []const u8, names: []const []const u8, m: []const u8) !void {
    const cwd = Io.Dir.cwd();
    const zig_dir = try ctx.fmt("{s}/lib/zig", .{m});
    try cwd.createDirPath(ctx.io, zig_dir);
    for (names) |n| {
        try cwd.symLink(ctx.io, try ctx.fmt("{s}/{s}", .{ real, n }), try ctx.fmt("{s}/{s}", .{ zig_dir, n }), .{});
    }
    try cwd.writeFile(ctx.io, .{ .sub_path = try ctx.fmt("{s}/.complete", .{m}), .data = "" });
}

// ---------------------------------------------------------------------------

const testing = std.testing;

test cksum {
    // `printf '123456789' | cksum` and `printf '' | cksum`
    try testing.expectEqual(@as(u32, 930766865), cksum("123456789"));
    try testing.expectEqual(@as(u32, 4294967295), cksum(""));
}

test "mirror: made once, ZIG_LIB_DIR set, idempotent under the mirror itself" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // the mirror is unix-only (main.zig never applies it on Windows); its symlinks need SeCreateSymbolicLinkPrivilege
    var f: @import("testutil.zig").Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const ctx = &f.ctx;
    // <bin>/../lib needs <bin> to exist, as it did for the shim
    for ([_][]const u8{ "env/bin/zig", "env/lib/zig/std/std.zig", "env/lib/zig/zig.h", "env/lib/zig/.hidden" }) |p| try f.touch(p);
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    const zig0 = f.path("env/bin/zig");

    // no libc++ next to the lib dir: nothing to do
    try testing.expect(!try apply(ctx, zig0));
    try testing.expect(f.env.get("ZIG_LIB_DIR") == null);

    try f.touch("env/lib/libc++.so.1");
    try testing.expect(try apply(ctx, zig0));
    const mirror = f.env.get("ZIG_LIB_DIR").?;
    try testing.expect(mem.startsWith(u8, mirror, f.path("cache/r-zig/zig-lib-")));
    try testing.expect(ctx.isFile(f.fmt("{s}/std/std.zig", .{mirror})));
    try testing.expect(ctx.isFile(f.fmt("{s}/zig.h", .{mirror})));
    try testing.expect(!ctx.exists(f.fmt("{s}/.hidden", .{mirror})));
    try testing.expect(!ctx.exists(f.fmt("{s}/../../lib/libc++.so.1", .{mirror})));

    // under the mirror the probe finds nothing, so ZIG_LIB_DIR stays
    try testing.expect(!try apply(ctx, zig0));
    try testing.expectEqualStrings(mirror, f.env.get("ZIG_LIB_DIR").?);
}

test "mirror: ZIG_LIB_DIR given (also for python3 -m ziglang), macOS's libc++.1.dylib, $HOME/.cache" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // the mirror is unix-only (main.zig never applies it on Windows); its symlinks need SeCreateSymbolicLinkPrivilege
    var f: @import("testutil.zig").Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const ctx = &f.ctx;
    for ([_][]const u8{ "env/lib/zig/std/std.zig", "env/lib/libc++.1.dylib" }) |p| try f.touch(p);
    try f.env.put("HOME", f.path("home"));
    // python3 -m ziglang has no lib dir of its own to look beside
    try testing.expect(!try apply(ctx, "python3"));
    try f.env.put("ZIG_LIB_DIR", f.path("env/lib/zig"));
    try testing.expect(try apply(ctx, "python3"));
    const mirror = try ctx.arena.dupe(u8, f.env.get("ZIG_LIB_DIR").?); // the map's copy goes with the next put
    try testing.expect(mem.startsWith(u8, mirror, f.path("home/.cache/r-zig/zig-lib-")));
    try testing.expect(mem.endsWith(u8, mirror, "/lib/zig"));
    try testing.expect(ctx.isFile(f.fmt("{s}/std/std.zig", .{mirror})));
    // the same lib dir, the same mirror: made once
    try f.env.put("ZIG_LIB_DIR", f.path("env/lib/zig"));
    try testing.expect(try apply(ctx, f.path("anywhere/zig")));
    try testing.expectEqualStrings(mirror, f.env.get("ZIG_LIB_DIR").?);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "key: the shim's `{ echo dir; ls dir; } | cksum`" {
    var f: @import("testutil.zig").Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    // printf '/z\na\nb\n' | cksum
    try testing.expectEqual(@as(u32, 970910982), try key(&f.ctx, "/z", &.{ "a", "b" }));
}
