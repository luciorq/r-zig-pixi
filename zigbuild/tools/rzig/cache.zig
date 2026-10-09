//! rzig's cache, ${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/r-zig, the place
//! the shims kept the libc++ mirror in (libcxx_mirror.zig). rzig also
//! keeps there what it makes for links: the objects it compiles from its
//! own sources (`compiled`: linux shared libraries' finalization object,
//! dso_fini.zig; Windows' Control Flow Guard stub, cfguard.zig) and
//! archives under an .a name (archives.zig). Each entry is made once, in a
//! directory named by a key of what it is made from, and is safe under
//! parallel make: a file appears complete or not at all (written under a
//! temporary name, then renamed into place), and two jobs making the same
//! entry write the same bytes.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// <cache home>/r-zig. On a Windows host %LOCALAPPDATA%, where zig keeps
/// its own cache, before HOME: R sets HOME to the Documents folder (R_USER)
/// when it is unset, so under R CMD there is always one.
pub fn root(ctx: *const Ctx) ![]const u8 {
    if (ctx.getenv("XDG_CACHE_HOME")) |d| return ctx.fmt("{s}/r-zig", .{d});
    if (builtin.os.tag == .windows) {
        if (ctx.getenv("LOCALAPPDATA")) |d| return ctx.fmt("{s}/r-zig", .{d});
    }
    if (ctx.getenv("HOME")) |d| return ctx.fmt("{s}/.cache/r-zig", .{d});
    return "/tmp/.cache/r-zig";
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
/// source, the target, the zig command and what `zig version` says. Made
/// under a temporary name and renamed into place, so parallel jobs see it
/// whole or not at all. null when ctx.zig is unset, or with a warning when
/// it cannot be made (no writable cache, zig failed).
pub fn compiled(ctx: *Ctx, c: Compiled) !?[]const u8 {
    const zig = ctx.zig orelse return null;
    const version = ctx.capture(try mem.concat(ctx.arena, []const u8, &.{ zig, &.{"version"} }));
    const k = key(&.{ c.source, c.target, try mem.join(ctx.arena, " ", zig), version.stdout });
    const dir = try ctx.fmt("{s}/{s}-{s}", .{ try root(ctx), c.name, &k });
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
    try af.replace(ctx.io);
    const tmp = try tempName(ctx, obj, ".o");
    defer cwd.deleteFile(ctx.io, tmp) catch {};
    const cc = try mem.concat(ctx.arena, []const u8, &.{
        zig,
        &.{ "cc", "-target", c.target, "-mcpu=baseline", "-fno-sanitize=undefined", "-O2", "-g0" },
        c.flags,
        &.{ "-c", src, "-o", tmp },
    });
    if (!ctx.succeeds(cc) or !ctx.isFile(tmp)) return error.CompileFailed;
    try cwd.rename(tmp, cwd, obj, ctx.io);
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

test root {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // nothing set: the shims' /tmp, except on a Windows host
    if (builtin.os.tag != .windows) try testing.expectEqualStrings("/tmp/.cache/r-zig", try root(c));
    try f.env.put("LOCALAPPDATA", "C:/Users/u/AppData/Local");
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
