//! rzig's cache, ${XDG_CACHE_HOME:-$HOME/.cache}/r-zig (`root`), the place
//! the shims kept the libc++ mirror in (libcxx_mirror.zig). rzig also
//! keeps there the archives it passes under an .a name (archives.zig).
//! Each entry is made once, in a directory named by a key of what it is
//! made from, and is safe under parallel make: a file appears complete or
//! not at all (written under a temporary name, then renamed into place),
//! and two jobs making the same entry write the same bytes. rzig removes
//! none. The objects rzig adds to links (dso_fini.zig, cfguard.zig) were
//! compiled into it too, at link time; R's build installs them beside
//! rzig now (feat-r-home-link-objects).
const std = @import("std");
const builtin = @import("builtin");
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

/// A file name no other job uses: <prefix>.<16 random hex digits><suffix>.
pub fn tempName(ctx: *const Ctx, prefix: []const u8, suffix: []const u8) ![]const u8 {
    var r: [8]u8 = undefined;
    ctx.io.random(&r);
    return ctx.fmt("{s}.{s}{s}", .{ prefix, std.fmt.bytesToHex(r, .lower), suffix });
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

test tempName {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const t1 = try tempName(&f.ctx, "x", ".o");
    const t2 = try tempName(&f.ctx, "x", ".o");
    try testing.expectEqual(@as(usize, 1 + 1 + 16 + 2), t1.len);
    try testing.expect(!std.mem.eql(u8, t1, t2));
}
