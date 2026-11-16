//! A link input zig cannot classify (stress round 1, Z6; chore-release-11
//! finding 31). zig cc takes an input by its name's extension and stops
//! at a name it does not know ("error: unrecognized file extension",
//! every target), where GNU ld, lld and ld64 read the file and find an
//! archive or an object. V8 on macOS: its autobrew script renames
//! libv8_monolith.a to .deps/v8_monolith and links that path. Rhtslib's
//! bundled htslib links libhts.so from objects named kfunc.pico, ... So
//! an input named without one of zig's library or object extensions, and
//! not a source, goes to zig as a copy in rzig's cache (cache.zig) when
//! its first bytes say what it is:
//!   - an ar archive (`!<arch>\n`, or a macOS universal file of ar
//!     archives, as V8's bundle is): <cache>/archive-<key>/<name>.a
//!   - a relocatable object: <cache>/object-<key>/<name>.o. ELF of type
//!     ET_REL; Mach-O of type MH_OBJECT, also in a universal file; COFF
//!     for x86, x64 or arm64 with no optional header (an import library
//!     member, a bigobj or a .res starts with machine 0); LLVM bitcode
//!     (-flto's objects).
//! <key> is a key of its bytes. Every other input passes unchanged: an
//! input with a name zig takes, and a shared library or an executable
//! under any name. A shared library linked by its path without a SONAME
//! is recorded by that path, which must not be the cache's.
//!
//! A copy, keyed by its content, because that works on every OS and file
//! system and is never stale. A symlink needs a privilege on Windows. A
//! hard link fails across file systems (the cache is in $HOME, a build is
//! often in /tmp), and shares later in-place writes to the original, so a
//! content key could come to name other bytes. Keyed by its path, a copy
//! would go stale when the archive changes; keyed by its content, a
//! changed archive is another entry. The price: reading the input once
//! per link, and one copy per distinct input. Such inputs are rare (two
//! packages in the stress suite).
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const cache = @import("cache.zig");
const Args = cmdline.Args;

const Sha256 = std.crypto.hash.sha2.Sha256;

/// `args` with each such archive or object input replaced by its copy.
/// Links only.
pub fn rename(ctx: *Ctx, args: Args) !Args {
    if (cmdline.compileOnly(args)) return args;
    var out: ?[][]const u8 = null;
    var it = cmdline.inputs(args);
    while (it.next()) |i| {
        const x = args[i];
        if (zigTakes(x) or cmdline.isSource(x)) continue;
        const k = kind(ctx, x) orelse continue;
        const copy = (try cached(ctx, x, k)) orelse continue;
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

/// What rzig passes under another name: an archive as <name>.a, an
/// object as <name>.o.
const Kind = enum { archive, object };

const magic = "!<arch>\n";

/// What the file's first bytes say it is, or null. A macOS universal
/// (fat) file is what its first slice is, as lipo makes them: V8's
/// autobrew bundle holds an archive for x86_64 and arm64 (omicron,
/// 2026-10-08). zig's linker takes both forms under an .a or .o name
/// (a universal object too: zig 0.17.1, aarch64-macos and x86_64-macos).
/// The fat header (all big-endian): magic, the number of slices, then
/// each slice's cputype, cpusubtype and offset (32 bits, 64 in the
/// fat_arch_64 form), ... A Java class file starts with the same magic;
/// its bytes at that offset are neither.
fn kind(ctx: *Ctx, path: []const u8) ?Kind {
    var buf: [24]u8 = undefined;
    const head = Io.Dir.cwd().readFile(ctx.io, path, &buf) catch return null;
    if (mem.startsWith(u8, head, magic)) return .archive;
    if (isObject(head)) return .object;
    if (head.len < buf.len) return null;
    const offset: u64 = switch (mem.readInt(u32, buf[0..4], .big)) {
        0xcafebabe => mem.readInt(u32, buf[16..20], .big),
        0xcafebabf => mem.readInt(u64, buf[16..24], .big),
        else => return null,
    };
    var file = Io.Dir.cwd().openFile(ctx.io, path, .{}) catch return null;
    defer file.close(ctx.io);
    var slice: [16]u8 = undefined;
    const n = file.readPositionalAll(ctx.io, &slice, offset) catch return null;
    if (mem.startsWith(u8, slice[0..n], magic)) return .archive;
    if (isMachObject(slice[0..n])) return .object;
    return null;
}

/// A relocatable object, by its header: ELF's e_type (at 16, in the
/// byte order of EI_DATA, at 5), Mach-O's filetype, COFF's machine (at
/// 0) and optional header size (at 16), LLVM bitcode's magic, bare or
/// in its wrapper.
fn isObject(head: []const u8) bool {
    if (head.len >= 18 and mem.startsWith(u8, head, "\x7fELF")) {
        const order: std.builtin.Endian = switch (head[5]) {
            1 => .little,
            2 => .big,
            else => return false,
        };
        return mem.readInt(u16, head[16..18], order) == 1; // ET_REL
    }
    if (isMachObject(head)) return true;
    if (mem.startsWith(u8, head, "BC\xc0\xde") or mem.startsWith(u8, head, "\xde\xc0\x17\x0b")) return true;
    if (head.len >= 20) {
        const machine = mem.readInt(u16, head[0..2], .little);
        const sections = mem.readInt(u16, head[2..4], .little);
        const opt_header = mem.readInt(u16, head[16..18], .little);
        // IMAGE_FILE_MACHINE_I386, _AMD64, _ARM64
        const known = machine == 0x14c or machine == 0x8664 or machine == 0xaa64;
        return known and sections > 0 and opt_header == 0;
    }
    return false;
}

/// A Mach-O object (MH_OBJECT), 32 or 64 bits, in either byte order.
fn isMachObject(head: []const u8) bool {
    if (head.len < 16) return false;
    for ([_]std.builtin.Endian{ .little, .big }) |order| {
        switch (mem.readInt(u32, head[0..4], order)) {
            0xfeedface, 0xfeedfacf => return mem.readInt(u32, head[12..16], order) == 1,
            else => {},
        }
    }
    return false;
}

/// The copy of `path` in the cache, made if it is not there yet; null,
/// with a warning, when it cannot be made (zig then names the input).
fn cached(ctx: *Ctx, path: []const u8, k: Kind) !?[]const u8 {
    const cache_root = cache.root(ctx) catch |err| switch (err) {
        error.NoCacheHome => {
            ctx.warn("cannot copy {s} into rzig's cache: {t}", .{ path, err });
            return null;
        },
        else => |e| return e,
    };
    const key = (try contentKey(ctx, path)) orelse return null;
    const dest = switch (k) {
        .archive => try ctx.fmt("{s}/archive-{s}/{s}.a", .{ cache_root, &key, cmdline.baseName(path) }),
        .object => try ctx.fmt("{s}/object-{s}/{s}.o", .{ cache_root, &key, cmdline.baseName(path) }),
    };
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
    // response file (rzig build's links name their objects so; `@` and
    // an archive's path is no file), a compile: unchanged
    const same: Args = &.{ "-shared", "-o", f.path("deps/v8_monolith"), f.path("deps/notar"), f.path("deps/short"), f.path("deps/Main"), f.path("deps/libok.a"), f.path("deps/dir"), f.path("nowhere"), "-include", v8, f.fmt("@{s}", .{v8}) };
    try expectArgs(same, try rename(c, same));
    const compile: Args = &.{ "-c", v8 };
    try expectArgs(compile, try rename(c, compile));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "an object without zig's extension: a copy named .o; a shared library, an executable, text, a name zig takes: unchanged" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    // ELF headers: e_ident (class, byte order, version), then e_type
    const zeros = "\x00\x00\x00\x00\x00\x00\x00\x00\x00";
    const elf_rel = "\x7fELF\x02\x01\x01" ++ zeros ++ "\x01\x00\x3e\x00htslib";
    try f.write("hts/kfunc.pico", elf_rel, .default_file);
    try f.write("hts/be.pico", "\x7fELF\x02\x02\x01" ++ zeros ++ "\x00\x01\x00\x16", .default_file);
    // Mach-O 64-bit MH_OBJECT for arm64, and in a universal file (one
    // slice at 0x1c)
    const macho = "\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x01\x00\x00\x00";
    try f.write("hts/m.pico", macho, .default_file);
    try f.write("hts/fat.pico", "\xca\xfe\xba\xbe\x00\x00\x00\x01" ++
        "\x01\x00\x00\x0c\x00\x00\x00\x00\x00\x00\x00\x1c\x00\x00\x00\x10\x00\x00\x00\x03" ++ macho, .default_file);
    // COFF for x64 (8 sections, no optional header), LLVM bitcode
    try f.write("hts/w.pico", "\x64\x86\x08\x00" ++ "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", .default_file);
    try f.write("hts/lto.pico", "BC\xc0\xde\x35\x14\x00\x00", .default_file);
    const objects = [_][]const u8{ "kfunc.pico", "be.pico", "m.pico", "fat.pico", "w.pico", "lto.pico" };
    var args: [objects.len + 3][]const u8 = undefined;
    args[0..3].* = .{ "-shared", "-o", "libhts.so" };
    for (objects, 0..) |o, i| args[3 + i] = f.path(f.fmt("hts/{s}", .{o}));
    const got = try rename(c, &args);
    try expectArgs(&.{ "-shared", "-o", "libhts.so" }, got[0..3]);
    var buf: [64]u8 = undefined;
    for (objects, got[3..], args[3..]) |o, copy, orig| {
        try testing.expect(mem.startsWith(u8, copy, f.path("cache/r-zig/object-")));
        try testing.expect(mem.endsWith(u8, copy, f.fmt("/{s}.o", .{o})));
        var obuf: [64]u8 = undefined;
        try testing.expectEqualStrings(try Io.Dir.cwd().readFile(testing.io, orig, &obuf), try Io.Dir.cwd().readFile(testing.io, copy, &buf));
    }
    // the key: `printf '<elf_rel>' | sha256sum | cut -c1-32`
    try testing.expectEqualStrings(f.path("cache/r-zig/object-63233f662f9f051b3fe3afd281c584cf/kfunc.pico.o"), got[3]);
    // ELF ET_DYN and ET_EXEC, a Mach-O dylib, a COFF import library
    // member (machine 0) and one with an optional header (an image),
    // text; an object under a name zig takes or a source's name; an
    // option's value: unchanged
    try f.write("hts/libx.so.3a", "\x7fELF\x02\x01\x01" ++ zeros ++ "\x03\x00\x3e\x00", .default_file);
    try f.write("hts/prog.bin", "\x7fELF\x02\x01\x01" ++ zeros ++ "\x02\x00\x3e\x00", .default_file);
    try f.write("hts/x.dylib1", "\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00", .default_file);
    try f.write("hts/imp.pico", "\x00\x00\xff\xff\x00\x00\x64\x86" ++ "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", .default_file);
    try f.write("hts/img.pico", "\x64\x86\x08\x00" ++ "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++ "\xf0\x00\x22\x00", .default_file);
    try f.write("hts/notes.pico", "kfunc.c: the special functions\n", .default_file);
    try f.write("hts/kfunc.o", elf_rel, .default_file);
    try f.write("hts/kfunc.c", elf_rel, .default_file);
    const same: Args = &.{ "-shared", "-o", f.path("hts/kfunc.pico"), f.path("hts/libx.so.3a"), f.path("hts/prog.bin"), f.path("hts/x.dylib1"), f.path("hts/imp.pico"), f.path("hts/img.pico"), f.path("hts/notes.pico"), f.path("hts/kfunc.o"), f.path("hts/kfunc.c"), "-include", f.path("hts/kfunc.pico") };
    try expectArgs(same, try rename(c, same));
    // a compile: unchanged
    const compile: Args = &.{ "-c", f.path("hts/kfunc.pico") };
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

test "no cache home: the input unchanged, with a warning" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try f.write("deps/v8_monolith", "!<arch>\n", .default_file);
    const args: Args = &.{ "-shared", "-o", "x.so", f.path("deps/v8_monolith") };
    try expectArgs(args, try rename(&f.ctx, args));
    try testing.expectEqualStrings(f.fmt("rzig-test: cannot copy {s} into rzig's cache: NoCacheHome\n", .{f.path("deps/v8_monolith")}), f.takeWarnings());
}
