//! rzig's cache, ${XDG_CACHE_HOME:-$HOME/.cache}/r-zig (`root`), the place
//! the shims kept the libc++ mirror in (libcxx_mirror.zig). rzig also
//! keeps there what it makes for links: the objects it compiles from its
//! own sources (`compiled`: linux shared libraries' finalization object,
//! dso_fini.zig; Windows' Control Flow Guard stub, cfguard.zig) and
//! archives under an .a name (archives.zig). Each entry is made once, in a
//! directory named by a key of what it is made from, and is safe under
//! parallel make: a file appears complete or not at all (written under a
//! temporary name, then renamed into place), and two jobs making the same
//! entry write the same bytes. rzig removes none.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// <cache home>/r-zig. On a Windows host %LOCALAPPDATA%, where zig keeps
/// its own cache, before HOME: R sets HOME to the Documents folder (R_USER)
/// when it is unset, so under R CMD there is always one. With none of
/// these, zig's own global cache, $ZIG_GLOBAL_CACHE_DIR/r-zig; else
/// error.NoCacheHome, and each caller makes nothing in a cache (it warns
/// and goes on). zig itself stops there ("unable to resolve zig cache
/// directory: AppDataDirUnavailable"), so a zig that runs always has one
/// of these. The shims' /tmp/.cache/r-zig is gone: anyone can make that
/// directory, and rzig links and runs what its cache holds, so the cache
/// is never in a place more open than zig's own global cache (cr27 D1 A).
pub fn root(ctx: *const Ctx) ![]const u8 {
    if (ctx.getenv("XDG_CACHE_HOME")) |d| return ctx.fmt("{s}/r-zig", .{d});
    if (builtin.os.tag == .windows) {
        if (ctx.getenv("LOCALAPPDATA")) |d| return ctx.fmt("{s}/r-zig", .{d});
    }
    if (ctx.getenv("HOME")) |d| return ctx.fmt("{s}/.cache/r-zig", .{d});
    if (ctx.getenv("ZIG_GLOBAL_CACHE_DIR")) |d| return ctx.fmt("{s}/r-zig", .{d});
    return error.NoCacheHome;
}

/// An entry's key: the first 16 bytes of a SHA-256, in hex.
pub const Key = [32]u8;

pub fn hexKey(digest: [Sha256.digest_length]u8) Key {
    return std.fmt.bytesToHex(digest[0..16].*, .lower);
}

/// The key of `parts`, each ended by a 0 byte.
pub fn key(parts: []const []const u8) Key {
    var h: Sha256 = .init(.{});
    for (parts) |p| {
        h.update(p);
        h.update(&.{0});
    }
    return hexKey(h.finalResult());
}

/// A file name no other job uses: <prefix>.<16 random hex digits><suffix>.
pub fn tempName(ctx: *const Ctx, prefix: []const u8, suffix: []const u8) ![]const u8 {
    var r: [8]u8 = undefined;
    ctx.io.random(&r);
    return ctx.fmt("{s}.{s}{s}", .{ prefix, std.fmt.bytesToHex(r, .lower), suffix });
}

/// The zig command as a key part (`compiled`): as spelled, but with `/`
/// only on Windows, where one zig is found as `C:\...\zig.exe` (PATH's
/// entries, find_zig's joins) and as `C:/.../zig.exe` (ZIG_BIN through
/// MSYS). Keyed as spelled, kappa got two build-runner directories and
/// two cfguard entries for one conda-forge zig (feat-shared-build-runner
/// open decision 1 b, folded into feat-standalone-toolchain phase 4).
/// Elsewhere `\` is a file name's character.
pub fn command(ctx: *const Ctx, zig: []const []const u8) ![]const u8 {
    const spelled = try mem.join(ctx.arena, " ", zig);
    return if (ctx.os == .windows) try mem.replaceOwned(u8, ctx.arena, spelled, "\\", "/") else spelled;
}

/// An object rzig compiles from a source of its own, with the zig that
/// links, for the target it links.
pub const Compiled = struct {
    /// The entry's directory: <cache>/<name>-<key>.
    name: []const u8,
    /// The source's file name there; the object is its stem plus .o.
    file: []const u8,
    source: []const u8,
    target: []const u8,
    /// zig cc's flags after the common ones, before -c.
    flags: []const []const u8 = &.{},
    /// What goes wrong without it, for the warning.
    consequence: []const u8,
};

/// <cache>/<name>-<key>/<stem>.o, compiled once, the key made of the
/// source, the target, the zig command (`command`) and what `zig version`
/// says. Made under a temporary name and renamed into place, so parallel
/// jobs see it whole or not at all. null when ctx.zig is unset, or with a
/// warning when it cannot be made (no writable cache, zig failed).
pub fn compiled(ctx: *Ctx, c: Compiled) !?[]const u8 {
    const zig = ctx.zig orelse return null;
    const cache_root = root(ctx) catch |err| switch (err) {
        error.NoCacheHome => {
            ctx.warn("cannot make {s}.o ({t}): {s}", .{ std.fs.path.stem(c.file), err, c.consequence });
            return null;
        },
        else => |e| return e,
    };
    const version = ctx.capture(try mem.concat(ctx.arena, []const u8, &.{ zig, &.{"version"} }));
    const k = key(&.{ c.source, c.target, try command(ctx, zig), version.stdout });
    const dir = try ctx.fmt("{s}/{s}-{s}", .{ cache_root, c.name, &k });
    const obj = try ctx.fmt("{s}/{s}.o", .{ dir, std.fs.path.stem(c.file) });
    if (ctx.isFile(obj)) return obj;
    make(ctx, zig, c, dir, obj) catch |err| {
        ctx.warn("cannot make {s} ({t}): {s}", .{ obj, err, c.consequence });
        return null;
    };
    return obj;
}

fn make(ctx: *Ctx, zig: []const []const u8, c: Compiled, dir: []const u8, obj: []const u8) !void {
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(ctx.io, dir);
    // the source, for zig to read and for anyone to see what was compiled
    const src = try ctx.fmt("{s}/{s}", .{ dir, c.file });
    var af = try cwd.createFileAtomic(ctx.io, src, .{ .replace = true });
    defer af.deinit(ctx.io);
    try af.file.writeStreamingAll(ctx.io, c.source);
    // a rename that fails while the file is there is no failure: another
    // job renamed its own (the same bytes) at the same moment, and
    // Windows refuses one of two such renames
    af.replace(ctx.io) catch |err| if (!ctx.isFile(src)) return err;
    const tmp = try tempName(ctx, obj, ".o");
    defer cwd.deleteFile(ctx.io, tmp) catch {};
    const cc = try mem.concat(ctx.arena, []const u8, &.{
        zig,
        &.{ "cc", "-target", c.target, "-mcpu=baseline", "-fno-sanitize=undefined", "-O2", "-g0" },
        c.flags,
        &.{ "-c", src, "-o", tmp },
    });
    if (!ctx.succeeds(cc) or !ctx.isFile(tmp)) return error.CompileFailed;
    cwd.rename(tmp, cwd, obj, ctx.io) catch |err| if (!ctx.isFile(obj)) return err;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

test root {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // nothing set: no cache, never the shims' /tmp/.cache/r-zig
    try testing.expectError(error.NoCacheHome, root(c));
    // zig's own global cache, the last one
    try f.env.put("ZIG_GLOBAL_CACHE_DIR", "/zgc");
    try testing.expectEqualStrings("/zgc/r-zig", try root(c));
    try f.env.put("ZIG_GLOBAL_CACHE_DIR", "");
    try testing.expectError(error.NoCacheHome, root(c));
    try f.env.put("ZIG_GLOBAL_CACHE_DIR", "/zgc");
    try f.env.put("LOCALAPPDATA", "C:/Users/u/AppData/Local");
    if (builtin.os.tag != .windows) try testing.expectEqualStrings("/zgc/r-zig", try root(c));
    if (builtin.os.tag == .windows) try testing.expectEqualStrings("C:/Users/u/AppData/Local/r-zig", try root(c));
    try f.env.put("HOME", "/home/u");
    const home = if (builtin.os.tag == .windows) "C:/Users/u/AppData/Local/r-zig" else "/home/u/.cache/r-zig";
    try testing.expectEqualStrings(home, try root(c));
    try f.env.put("XDG_CACHE_HOME", "/c");
    try testing.expectEqualStrings("/c/r-zig", try root(c));
    // empty is unset, as in the shims' ${VAR:-}
    try f.env.put("XDG_CACHE_HOME", "");
    try testing.expectEqualStrings(home, try root(c));
}

test "compiled: no cache home, no object and a warning; zig is not asked" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // a zig that would fail to run: never run, the cache home comes first
    c.zig = &.{f.path("no/zig")};
    try testing.expect(try compiled(c, .{ .name = "x", .file = "x.c", .source = "int x;\n", .target = "x86_64-linux-gnu", .consequence = "no x" }) == null);
    try testing.expectEqualStrings("rzig-test: cannot make x.o (NoCacheHome): no x\n", f.takeWarnings());
    try testing.expect(!c.exists(f.path("no")));
}

test command {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    const back = [_][]const u8{"C:\\env\\Library\\bin\\x86_64-w64-mingw32-zig.exe"};
    const fwd = [_][]const u8{"C:/env/Library/bin/x86_64-w64-mingw32-zig.exe"};
    try testing.expectEqualStrings(fwd[0], try command(c, &back));
    try testing.expectEqualStrings(fwd[0], try command(c, &fwd));
    try testing.expectEqualStrings("python3 -m ziglang", try command(c, &.{ "python3", "-m", "ziglang" }));
    c.os = .linux;
    try testing.expectEqualStrings(back[0], try command(c, &back));
}

test key {
    // `printf 'a\0bc\0' | sha256sum | cut -c1-32`
    try testing.expectEqualStrings("aa795aa4bbb6117911ef062e271bcb05", &key(&.{ "a", "bc" }));
    // the parts' boundaries count
    try testing.expect(!std.mem.eql(u8, &key(&.{ "a", "bc" }), &key(&.{ "ab", "c" })));
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const t1 = try tempName(&f.ctx, "x", ".o");
    const t2 = try tempName(&f.ctx, "x", ".o");
    try testing.expectEqual(@as(usize, 1 + 1 + 16 + 2), t1.len);
    try testing.expect(!std.mem.eql(u8, t1, t2));
}
