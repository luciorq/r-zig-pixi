//! A link input zig cannot classify (stress round 1, Z6). zig cc takes an
//! input by its name's extension and stops at a name it does not know
//! ("error: unrecognized file extension", every target), where GNU ld,
//! lld and ld64 read the file and find an archive. V8 on macOS: its
//! autobrew script renames libv8_monolith.a to .deps/v8_monolith and
//! links that path. So an ar archive (it starts with `!<arch>\n`, or it
//! is a macOS universal file of ar archives, as V8's bundle is) named
//! without one of zig's library or object extensions goes to zig as a
//! copy named <name>.a, in rzig's cache (cache.zig):
//! <cache>/archive-<key of its bytes>/<name>.a. Every other input passes
//! unchanged, an archive with a name zig takes as well.
//!
//! A copy, keyed by its content, because that works on every OS and file
//! system and is never stale. A symlink needs a privilege on Windows. A
//! hard link fails across file systems (the cache is in $HOME, a build is
//! often in /tmp), and shares later in-place writes to the original, so a
//! content key could come to name other bytes. Keyed by its path, a copy
//! would go stale when the archive changes; keyed by its content, a
//! changed archive is another entry. The price: reading the archive once
//! per link, and one copy per distinct archive. Such inputs are rare (one
//! package in the stress suite).
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const cache = @import("cache.zig");
const Args = cmdline.Args;

const Sha256 = std.crypto.hash.sha2.Sha256;

/// `args` with each such archive input replaced by its copy. Links only.
pub fn rename(ctx: *Ctx, args: Args) !Args {
    if (cmdline.compileOnly(args)) return args;
    var out: ?[][]const u8 = null;
    var it = cmdline.inputs(args);
    while (it.next()) |i| {
        const x = args[i];
        if (zigTakes(x) or !isArchive(ctx, x)) continue;
        const copy = (try cached(ctx, x)) orelse continue;
        if (out == null) out = try ctx.arena.dupe([]const u8, args);
        out.?[i] = copy;
    }
    return out orelse args;
}

/// zig's extensions for libraries and objects, the names zig 0.16's cc
/// took an archive under (each tried, 2026-10-08): .a .lib .o .obj .lo
/// .so .so.<N>[.<M>...] .dylib .tbd .dll.
fn zigTakes(x: []const u8) bool {
    const base = cmdline.baseName(x);
    for ([_][]const u8{ ".a", ".lib", ".o", ".obj", ".lo", ".so", ".dylib", ".tbd", ".dll" }) |e| {
        if (mem.endsWith(u8, base, e)) return true;
    }
    // a versioned shared library: .so. then digits and dots
    const so = mem.find(u8, base, ".so.") orelse return false;
    const v = base[so + ".so.".len ..];
    if (v.len == 0) return false;
    for (v) |c| if (!std.ascii.isDigit(c) and c != '.') return false;
    return true;
}

const magic = "!<arch>\n";

/// A file that starts with an ar archive's magic, or a macOS universal
/// (fat) file whose first slice does, as lipo makes them: V8's autobrew
/// bundle holds one for x86_64 and arm64 (omicron, 2026-10-08). zig's
/// linker takes both under an .a name. The fat header (all big-endian):
/// magic, the number of slices, then each slice's cputype, cpusubtype
/// and offset (32 bits, 64 in the fat_arch_64 form), ... A Java class
/// file starts with the same magic; its bytes at that offset do not.
fn isArchive(ctx: *Ctx, path: []const u8) bool {
    var buf: [24]u8 = undefined;
    const head = Io.Dir.cwd().readFile(ctx.io, path, &buf) catch return false;
    if (mem.startsWith(u8, head, magic)) return true;
    if (head.len < buf.len) return false;
    const offset: u64 = switch (mem.readInt(u32, buf[0..4], .big)) {
        0xcafebabe => mem.readInt(u32, buf[16..20], .big),
        0xcafebabf => mem.readInt(u64, buf[16..24], .big),
        else => return false,
    };
    var file = Io.Dir.cwd().openFile(ctx.io, path, .{}) catch return false;
    defer file.close(ctx.io);
    var slice: [magic.len]u8 = undefined;
    const n = file.readPositionalAll(ctx.io, &slice, offset) catch return false;
    return n == magic.len and mem.eql(u8, &slice, magic);
}

/// The copy of `path` in the cache, made if it is not there yet; null,
/// with a warning, when it cannot be made (zig then names the input).
fn cached(ctx: *Ctx, path: []const u8) !?[]const u8 {
    const k = (try contentKey(ctx, path)) orelse return null;
    const dest = try ctx.fmt("{s}/archive-{s}/{s}.a", .{ try cache.root(ctx), &k, cmdline.baseName(path) });
    if (ctx.isFile(dest)) return dest;
    Io.Dir.cwd().copyFile(path, Io.Dir.cwd(), dest, ctx.io, .{ .make_path = true, .replace = true }) catch |err| {
        ctx.warn("cannot copy {s} to {s}: {t}", .{ path, dest, err });
        return null;
    };
    return dest;
}

/// The cache key of a file's bytes.
fn contentKey(ctx: *Ctx, path: []const u8) !?cache.Key {
    var file = Io.Dir.cwd().openFile(ctx.io, path, .{}) catch return null;
    defer file.close(ctx.io);
    var rbuf: [64 * 1024]u8 = undefined;
    var r = file.readerStreaming(ctx.io, &rbuf);
    var hbuf: [64]u8 = undefined;
    var h: Io.Writer.Hashing(Sha256) = .init(&hbuf);
    _ = r.interface.streamRemaining(&h.writer) catch return null;
    h.writer.flush() catch return null;
    return cache.hexKey(h.hasher.finalResult());
}

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test zigTakes {
    for ([_][]const u8{ "a.a", "x/libz.lib", "a.o", "a.obj", "a.lo", "libx.so", "libx.so.1", "libx.so.1.2", "a.dylib", "a.tbd", "a.dll", "libz.dll.a" }) |x| try testing.expect(zigTakes(x));
    for ([_][]const u8{ "v8_monolith", "a.so.x", "libx.so.", "a.A", "a.la", "a.a.1", ".deps/v8.d/x", "a.ar" }) |x| try testing.expect(!zigTakes(x));
}

test "an archive without zig's extension: a copy named .a, keyed by its bytes; everything else unchanged" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    const bytes = "!<arch>\nmember data";
    try f.write("deps/v8_monolith", bytes, .default_file);
    try f.write("deps/notar", "!<thin>\nnot one of ours", .default_file);
    try f.write("deps/short", "!<ar", .default_file);
    try f.write("deps/libok.a", bytes, .default_file);
    // a universal file of two archives (the fat header, two slices at 0x30
    // and 0x38), and a Java class file, which starts with the same magic
    const fat = "\xca\xfe\xba\xbe\x00\x00\x00\x02" ++
        "\x01\x00\x00\x07\x00\x00\x00\x03\x00\x00\x00\x30\x00\x00\x00\x08\x00\x00\x00\x03" ++
        "\x01\x00\x00\x0c\x00\x00\x00\x00\x00\x00\x00\x38\x00\x00\x00\x08\x00\x00\x00\x03" ++
        magic ++ magic;
    try f.write("deps/fat_monolith", fat, .default_file);
    try f.write("deps/Main", "\xca\xfe\xba\xbe\x00\x00\x00\x34\x00\x0a\x00\x01\x07\x00\x02\x01\x00\x10java/lang/Object" ++ magic, .default_file);
    try f.tmp.dir.createDirPath(testing.io, "deps/dir");
    const v8 = f.path("deps/v8_monolith");
    // the key: `printf '!<arch>\nmember data' | sha256sum | cut -c1-32`
    const copy = f.path("cache/r-zig/archive-7c6d5f344466ae401a4452a2a4a40ec7/v8_monolith.a");
    try expectArgs(&.{ "-dynamiclib", "-o", "V8.so", "a.o", copy, "-lR" }, try rename(c, &.{ "-dynamiclib", "-o", "V8.so", "a.o", v8, "-lR" }));
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings(bytes, try Io.Dir.cwd().readFile(testing.io, copy, &buf));
    // made once: the same bytes, the same copy, also from another name's
    // directory; other bytes, another
    try testing.expectEqualStrings(copy, (try rename(c, &.{ "-o", "x", v8 }))[2]);
    try f.write("other/v8_monolith", bytes, .default_file);
    try testing.expectEqualStrings(copy, (try rename(c, &.{ "-o", "x", f.path("other/v8_monolith") }))[2]);
    try f.write("deps/v8_monolith", "!<arch>\nnew member", .default_file);
    const copy2 = (try rename(c, &.{ "-o", "x", v8 }))[2];
    try testing.expect(!mem.eql(u8, copy, copy2));
    try testing.expectEqualStrings("!<arch>\nnew member", try Io.Dir.cwd().readFile(testing.io, copy2, &buf));
    // the universal file: a copy too (`printf '<fat>' | sha256sum | cut -c1-32`)
    const fat_copy = f.path("cache/r-zig/archive-21dcb53fa94d6de2934191200760f807/fat_monolith.a");
    try expectArgs(&.{ "-dynamiclib", "-o", "V8.so", fat_copy }, try rename(c, &.{ "-dynamiclib", "-o", "V8.so", f.path("deps/fat_monolith") }));
    try testing.expectEqualStrings(fat, try Io.Dir.cwd().readFile(testing.io, fat_copy, &buf));
    // not archives, a name zig takes, no file, an option's value, a
    // compile: unchanged
    const same: Args = &.{ "-shared", "-o", f.path("deps/v8_monolith"), f.path("deps/notar"), f.path("deps/short"), f.path("deps/Main"), f.path("deps/libok.a"), f.path("deps/dir"), f.path("nowhere"), "-include", v8 };
    try expectArgs(same, try rename(c, same));
    const compile: Args = &.{ "-c", v8 };
    try expectArgs(compile, try rename(c, compile));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "a copy it cannot make: the input unchanged, with a warning" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // a file as the cache's parent directory
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try f.write("deps/v8_monolith", "!<arch>\n", .default_file);
    try f.touch("cachefile");
    try f.env.put("XDG_CACHE_HOME", f.path("cachefile"));
    const args: Args = &.{ "-shared", "-o", "x.so", f.path("deps/v8_monolith") };
    try expectArgs(args, try rename(&f.ctx, args));
    try testing.expect(mem.find(u8, f.takeWarnings(), "cannot copy") != null);
}
