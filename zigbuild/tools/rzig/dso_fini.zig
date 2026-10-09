//! Linux shared libraries: what crtbeginS.o does in a gcc link, which a
//! zig link lacks (stress round 1, Z9). zig links linux-gnu shared
//! libraries without crtbeginS.o: no .fini_array entry, and lld's stand-in
//! for __dso_handle is the image base. So the handlers a library registers
//! with __cxa_atexit (C++ static destructors) or atexit stay registered
//! after dlclose, and glibc calls them at exit, after the library's code
//! is gone: R segfaults at exit after unloadNamespace() of lme4 or
//! fstcore, or after a Stan model was compiled and sampled. A two-file
//! repro (lib.cpp, main.c) crashes with a zig library and not with a gcc
//! one.
//!
//! The fix is crtbeginS.o's part: `source` below, compiled once with the
//! zig that links, for the target it links, into rzig's cache
//! (cache.compiled): <cache>/dso-fini-<key>/dso_fini.o. compiler.zig
//! passes it on every linux shared link, first among the inputs, where gcc
//! puts crtbeginS.o: its .fini_array entry is then the first, which runs
//! last, after the library's own destructors.
//!
//! Links that choose their own startup files (-nostartfiles, -nostdlib, as
//! gcc leaves crtbeginS.o out then) get none. A crtbeginS.o a link names
//! itself still links: __dso_handle is weak here, so its strong one wins,
//! and its own __cxa_finalize call makes ours find nothing left to run
//! (glibc runs each handler once). Executables are never unloaded (their
//! handlers run at exit, with their code still there), static archives
//! are made by ar, not linked, and macOS and Windows are left as they
//! are: dyld never unloads an image with thread-local variables (zig's
//! static libc++abi has one; all 76 compiled packages unloaded and exited
//! 0 on omicron), and no Windows package crashed (stress round 2 on kappa:
//! 108 packages loaded, unloaded and exited 0).
//!
//! No object when it cannot be made (no writable cache, zig failed): the
//! link goes on without it, as before, with a warning.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const cache = @import("cache.zig");
const Args = cmdline.Args;

/// round 1's fini2.c, with __dso_handle weak.
pub const source =
    \\/* rzig (zigbuild/tools/rzig/dso_fini.zig): crtbeginS.o's part that a
    \\   zig link of a linux shared library lacks. __dso_handle holds its own
    \\   address (lld's stand-in is the image base), and a .fini_array entry
    \\   runs and forgets the handlers this library registered with
    \\   __cxa_atexit or atexit when it is unloaded. */
    \\void *__dso_handle __attribute__((visibility("hidden"), weak)) = &__dso_handle;
    \\extern void __cxa_finalize(void *) __attribute__((weak));
    \\static void r_zig_fini(void) { if (__cxa_finalize) __cxa_finalize(__dso_handle); }
    \\__attribute__((section(".fini_array"), used)) static void (*r_zig_fini_p)(void) = r_zig_fini;
    \\
;

/// Whether a link gets the object: a shared library (`-shared` as a word,
/// no compile-only flag) whose startup files are not the caller's.
pub fn wanted(args: Args) bool {
    return cmdline.anyWord(args, "-shared") and !cmdline.compileOnly(args) and
        !cmdline.anyWord(args, "-nostartfiles") and !cmdline.anyWord(args, "-nostdlib");
}

/// The object for `target` (a zig target triple), made if it is not there
/// yet; null when ctx.zig is unset or it cannot be made.
pub fn object(ctx: *Ctx, target: []const u8) !?[]const u8 {
    return cache.compiled(ctx, .{
        .name = "dso-fini",
        .file = "dso_fini.c",
        .source = source,
        .target = target,
        .flags = &.{"-fPIC"},
        .consequence = "this library's static destructors may run after it is unloaded",
    });
}

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");

test wanted {
    try testing.expect(wanted(&.{ "-shared", "-o", "p.so", "a.o" }));
    try testing.expect(wanted(&.{ "-DX=a -shared b", "-o", "libq.so" }));
    for ([_]Args{
        &.{ "-o", "prog", "a.o" },
        &.{ "-shared", "-c", "a.c" },
        &.{ "-shared", "-nostartfiles", "-o", "p.so", "crtbeginS.o", "a.o" },
        &.{ "-shared", "-nostdlib", "-o", "p.so", "a.o" },
        &.{ "-Wl,-shared", "-o", "p.so", "a.o" },
    }) |args| try testing.expect(!wanted(args));
}

/// A zig stand-in: answers `version`, and for a compile writes its -o file
/// with what it was given (or fails, when `fails` is in its directory).
fn fakeZig(f: *testutil.Fixture) ![]const u8 {
    try f.write("bin/zig",
        \\#!/bin/sh
        \\[ "$1" = version ] && { echo 0.16.0; exit 0; }
        \\[ -e "${0%/*}/fails" ] && exit 1
        \\o=; p=; for a in "$@"; do [ "$p" = -o ] && o=$a; p=$a; done
        \\echo "$*" > "$o"
        \\
    , .fromMode(0o755));
    return f.path("bin/zig");
}

test "made once into the cache, keyed by zig and the target; nothing left behind" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for zig
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    // no zig known (unit tests of the compiler lines): none
    try testing.expect(try object(c, "x86_64-linux-gnu.2.17") == null);
    c.zig = &.{try fakeZig(&f)};
    const o = (try object(c, "x86_64-linux-gnu.2.17")).?;
    try testing.expect(mem.startsWith(u8, o, f.path("cache/r-zig/dso-fini-")));
    try testing.expect(mem.endsWith(u8, o, "/dso_fini.o"));
    // what zig was asked, and the source it read
    var buf: [4096]u8 = undefined;
    const dir = o[0 .. o.len - "/dso_fini.o".len];
    const asked = try Io.Dir.cwd().readFile(testing.io, o, &buf);
    try testing.expect(mem.startsWith(u8, asked, f.fmt("cc -target x86_64-linux-gnu.2.17 -mcpu=baseline -fno-sanitize=undefined -O2 -g0 -fPIC -c {s}/dso_fini.c -o {s}/dso_fini.o.", .{ dir, dir })));
    var sbuf: [4096]u8 = undefined;
    try testing.expectEqualStrings(source, try Io.Dir.cwd().readFile(testing.io, f.fmt("{s}/dso_fini.c", .{dir}), &sbuf));
    // the directory holds the source and the object, no temporary file
    var d = try Io.Dir.cwd().openDir(testing.io, dir, .{ .iterate = true });
    defer d.close(testing.io);
    var it = d.iterate();
    var n: usize = 0;
    while (try it.next(testing.io)) |e| {
        n += 1;
        try testing.expect(mem.eql(u8, e.name, "dso_fini.c") or mem.eql(u8, e.name, "dso_fini.o"));
    }
    try testing.expectEqual(@as(usize, 2), n);
    // made once: zig is not asked to compile again
    try f.touch("bin/fails");
    try testing.expectEqualStrings(o, (try object(c, "x86_64-linux-gnu.2.17")).?);
    try f.tmp.dir.deleteFile(testing.io, "bin/fails");
    // another target, another zig: another object
    const o2 = (try object(c, "aarch64-linux-gnu.2.17")).?;
    try testing.expect(!mem.eql(u8, o, o2));
    try f.write("bin2/zig", "#!/bin/sh\n[ \"$1\" = version ] && { echo 0.17.0; exit 0; }\no=; p=; for a in \"$@\"; do [ \"$p\" = -o ] && o=$a; p=$a; done\n: > \"$o\"\n", .fromMode(0o755));
    c.zig = &.{f.path("bin2/zig")};
    const o3 = (try object(c, "x86_64-linux-gnu.2.17")).?;
    try testing.expect(!mem.eql(u8, o, o3) and !mem.eql(u8, o2, o3));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "zig fails, or no cache: no object, a warning, no temporary file" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for zig
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    c.zig = &.{try fakeZig(&f)};
    try f.touch("bin/fails");
    try testing.expect(try object(c, "x86_64-linux-gnu.2.17") == null);
    try testing.expect(mem.find(u8, f.takeWarnings(), "cannot make") != null);
    var d = try Io.Dir.cwd().openDir(testing.io, f.path("cache/r-zig"), .{ .iterate = true });
    defer d.close(testing.io);
    var w = try d.walk(testing.allocator);
    defer w.deinit();
    while (try w.next(testing.io)) |e| try testing.expect(e.kind == .directory or mem.eql(u8, e.basename, "dso_fini.c"));
    // a cache it cannot write
    try f.tmp.dir.deleteFile(testing.io, "bin/fails");
    try f.touch("cachefile");
    try f.env.put("XDG_CACHE_HOME", f.path("cachefile"));
    try testing.expect(try object(c, "x86_64-linux-gnu.2.17") == null);
    try testing.expect(mem.find(u8, f.takeWarnings(), "cannot make") != null);
}
