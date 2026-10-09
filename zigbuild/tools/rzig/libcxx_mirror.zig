//! libc++ is linked statically, everywhere (decided 2026-09-30). Upstream
//! zig always does; conda-forge's zig (feedstock patch Lld.zig-prefer-
//! shared-libcxx) links a shared libc++ instead whenever one sits in
//! <zig lib dir>/../../lib, which is always the case in a macOS conda env
//! and in any env with the `libcxx` package. The probe is relative to the
//! lib dir, so zig gets a mirror of it as its lib dir: a directory of
//! symlinks, nested as <mirror>/lib/zig so that <mirror>/lib has no
//! libc++. One per zig lib dir under a cache root, made once: creating
//! the directory is the lock for parallel jobs, `.complete` the marker.
//!
//! One implementation for packages and for R itself (feat-no-host-paths
//! F4): rzig (`apply`) points the zig it runs at the mirror through
//! ZIG_LIB_DIR, the mirror in the user's cache; build.zig (`prepare`)
//! gives it to R's own Compile steps as their zig lib dir, the mirror in
//! zig build's local cache. A no-op with upstream zig (the ziglang.org
//! release, PyPI's ziglang), which has nothing beside its lib dir; it
//! stays as long as conda-forge's patch does. Not on Windows: symlinks
//! need a privilege there, and no win-64 env has libc++.dll.a (build.zig
//! stops if one appears, `sharedLibcxx(.., .windows)`).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Allocator = mem.Allocator;
const Ctx = @import("Ctx.zig");
const cache = @import("cache.zig");

/// Sets ZIG_LIB_DIR in `ctx.env` when the zig found at `zig0` (the first
/// word of its command) would link a shared libc++. Returns whether it did.
pub fn apply(ctx: *Ctx, zig0: []const u8) !bool {
    const lib_dir = (try zigLibDir(ctx, zig0)) orelse return false;
    switch (try prepare(ctx.io, ctx.arena, lib_dir, try cache.root(ctx))) {
        .none => return false,
        .failed => |m| {
            ctx.warn("could not prepare {s}; this link may use a shared libc++", .{m});
            return false;
        },
        .ready => |mirror| {
            try ctx.env.put("ZIG_LIB_DIR", mirror);
            return true;
        },
    }
}

/// Which names conda-forge's patch probes for (its src/link/
/// libcxx_shared.zig, by target OS); unix: macOS's and linux's together,
/// either would be linked.
pub const Target = enum { unix, windows };

/// The shared libc++ conda-forge's zig with lib dir `lib_dir` would link
/// in place of its own static one, or null.
pub fn sharedLibcxx(io: Io, arena: Allocator, lib_dir: []const u8, target: Target) !?[]const u8 {
    const names: []const []const u8 = switch (target) {
        .unix => &.{ "libc++.1.dylib", "libc++.dylib", "libc++.so.1", "libc++.so" },
        .windows => &.{"libc++.dll.a"},
    };
    for (names) |name| {
        const p = try std.fmt.allocPrint(arena, "{s}/../../lib/{s}", .{ lib_dir, name });
        if (kind(io, p) != null) return p;
    }
    return null;
}

pub const Mirror = union(enum) {
    /// nothing beside the lib dir: zig links its own static libc++
    none,
    /// the lib dir to give zig instead, <mirror>/lib/zig
    ready: []const u8,
    /// a shared libc++ is there, and this mirror could not be made
    failed: []const u8,
};

/// The mirror of `lib_dir` (unix) under `cache_root`, made if it is not
/// there yet, when the zig with that lib dir would link a shared libc++.
pub fn prepare(io: Io, arena: Allocator, lib_dir: []const u8, cache_root: []const u8) !Mirror {
    if (kind(io, lib_dir) != .directory) return .none;
    if (try sharedLibcxx(io, arena, lib_dir, .unix) == null) return .none;

    const real = Io.Dir.cwd().realPathFileAlloc(io, lib_dir, arena) catch return .none;
    const names = try listing(io, arena, real);
    const m = try std.fmt.allocPrint(arena, "{s}/zig-lib-{d}", .{ cache_root, try key(arena, real, names) });
    const complete = try std.fmt.allocPrint(arena, "{s}/.complete", .{m});
    if (kind(io, complete) == null) {
        if (lock(io, m)) {
            populate(io, arena, real, names, m) catch {};
        } else {
            // another job is making it
            var i: usize = 0;
            while (kind(io, complete) == null and i < 100) : (i += 1) {
                try io.sleep(.fromMilliseconds(100), .awake);
            }
        }
    }
    if (kind(io, complete) == null) return .{ .failed = m };
    return .{ .ready = try std.fmt.allocPrint(arena, "{s}/lib/zig", .{m}) };
}

/// What `path` is, symlinks followed (`[ -e ]`, `[ -d ]`); null when
/// nothing is there.
fn kind(io: Io, path: []const u8) ?Io.File.Kind {
    if (path.len == 0) return null;
    const st = Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    return st.kind;
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
fn listing(io: Io, arena: Allocator, dir_path: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var dir = Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return names.items;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        try names.append(arena, try arena.dupe(u8, entry.name));
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
fn key(arena: Allocator, real: []const u8, names: []const []const u8) !u32 {
    var text: std.ArrayList(u8) = .empty;
    try text.print(arena, "{s}\n", .{real});
    for (names) |n| try text.print(arena, "{s}\n", .{n});
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

/// Whether this process gets to make the mirror.
fn lock(io: Io, m: []const u8) bool {
    const cwd = Io.Dir.cwd();
    cwd.createDirPath(io, std.fs.path.dirname(m).?) catch return false;
    cwd.createDir(io, m, .default_dir) catch return false;
    return true;
}

/// A symlink per entry, then the marker, which is only written once all
/// links exist (the bash shim checked the last one only).
fn populate(io: Io, arena: Allocator, real: []const u8, names: []const []const u8, m: []const u8) !void {
    const cwd = Io.Dir.cwd();
    const zig_dir = try std.fmt.allocPrint(arena, "{s}/lib/zig", .{m});
    try cwd.createDirPath(io, zig_dir);
    for (names) |n| {
        try cwd.symLink(io, try std.fmt.allocPrint(arena, "{s}/{s}", .{ real, n }), try std.fmt.allocPrint(arena, "{s}/{s}", .{ zig_dir, n }), .{});
    }
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}/.complete", .{m}), .data = "" });
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

test "prepare: build.zig's use, any cache root; upstream's layout and Windows' name" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // as above
    var f: @import("testutil.zig").Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const arena = f.ctx.arena;
    const io = testing.io;
    for ([_][]const u8{ "env/lib/zig/std/std.zig", "env/lib/zig/libcxx/include/vector", "up/zig", "up/lib/std/std.zig" }) |p| try f.touch(p);
    const cache_root = f.path("build/zig-cache/local/r-zig");

    // upstream zig: <dir>/zig with <dir>/lib, nothing two levels above it
    try testing.expect(try prepare(io, arena, f.path("up/lib"), cache_root) == .none);
    // no lib dir there at all
    try testing.expect(try prepare(io, arena, f.path("nowhere/lib/zig"), cache_root) == .none);
    // conda-forge's zig, no libcxx package in the env
    try testing.expect(try prepare(io, arena, f.path("env/lib/zig"), cache_root) == .none);

    // with one: the mirror, under the given root, holding the lib dir's
    // entries and nothing beside it
    try f.touch("env/lib/libc++.so");
    try testing.expectEqualStrings(f.path("env/lib/zig/../../lib/libc++.so"), (try sharedLibcxx(io, arena, f.path("env/lib/zig"), .unix)).?);
    const ready = try prepare(io, arena, f.path("env/lib/zig"), cache_root);
    const mirror = ready.ready;
    try testing.expect(mem.startsWith(u8, mirror, f.fmt("{s}/zig-lib-", .{cache_root})));
    try testing.expect(mem.endsWith(u8, mirror, "/lib/zig"));
    try testing.expect(f.ctx.isFile(f.fmt("{s}/libcxx/include/vector", .{mirror})));
    try testing.expect(try sharedLibcxx(io, arena, mirror, .unix) == null);
    // made once: the same path again, also from a relative lib dir's
    // spelling of it (zig reports a relative one when it can)
    try testing.expectEqualStrings(mirror, (try prepare(io, arena, f.fmt("{s}/env/lib/../lib/zig", .{f.root}), cache_root)).ready);
    // a mirror left half made (no marker, the lock taken) fails, after
    // the wait, rather than handing out an incomplete lib dir
    try f.touch("env2/lib/zig/std/std.zig");
    try f.touch("env2/lib/libc++.1.dylib");
    const real2 = try Io.Dir.cwd().realPathFileAlloc(io, f.path("env2/lib/zig"), arena);
    const m2 = f.fmt("{s}/zig-lib-{d}", .{ cache_root, try key(arena, real2, try listing(io, arena, real2)) });
    try Io.Dir.cwd().createDirPath(io, m2);
    try testing.expectEqualStrings(m2, (try prepare(io, arena, f.path("env2/lib/zig"), cache_root)).failed);

    // Windows: conda-forge's patch looks for the import library only
    try testing.expect(try sharedLibcxx(io, arena, f.path("env/lib/zig"), .windows) == null);
    try f.touch("env/lib/libc++.dll.a");
    try testing.expectEqualStrings(f.path("env/lib/zig/../../lib/libc++.dll.a"), (try sharedLibcxx(io, arena, f.path("env/lib/zig"), .windows)).?);
}

test "key: the shim's `{ echo dir; ls dir; } | cksum`" {
    var f: @import("testutil.zig").Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    // printf '/z\na\nb\n' | cksum
    try testing.expectEqual(@as(u32, 970910982), try key(f.ctx.arena, "/z", &.{ "a", "b" }));
}
