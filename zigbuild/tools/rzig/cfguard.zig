//! Windows links: the Control Flow Guard symbol zig's MinGW runtime lacks
//! (stress round 2, Z11). Code compiled with CFG (clang -mguard=cf, MSVC
//! /guard:cf, Rust's windows-gnullvm std) calls through
//! __guard_dispatch_icall_fptr. mingw-w64 defines that pointer in
//! cfguard/mingw_cfguard_support.c and its target,
//! __guard_dispatch_icall_dummy (a `jmp *%rax`), in cfguard/guard_dispatch.S.
//! zig 0.16 (conda-forge's and upstream's) builds libmingw32 from the .c
//! file without the .S file, so such a link stops: "lld-link: error:
//! undefined symbol: __guard_dispatch_icall_dummy, referenced by
//! libmingw32.lib(mingw_cfguard_support.obj)". On kappa, magick's link
//! (its clang-x86_64 r-windows bundle: librsvg-2.a holds Rust's std,
//! compiled with CFG) and a one-file repro (`zig cc -mguard=cf`) fail so.
//!
//! The fix is guard_dispatch.S's part: `source` below, assembled once with
//! the zig that links into rzig's cache (cache.zig), as dso_fini.zig's
//! object: <cache>/cfguard-<key>/guard_dispatch.o. compiler.zig passes it
//! on every Windows link (an -o and no compile-only flag). Nothing uses it
//! unless libmingw32's mingw_cfguard_support.obj is pulled in; other links
//! carry its 16 bytes of code. A zig whose libmingw32 has guard_dispatch.S's
//! member never pulls that member, as the symbol is already defined. R on
//! Windows is x86_64 here (win-64), and the code is x86_64's.
//!
//! The symbol is excluded from lld's MinGW auto-export (a DLL with no .def
//! file and no dllexport exports every global symbol), with the
//! `-exclude-symbols:` directive clang writes for a hidden symbol: a DLL
//! exports what it exported before. A link that defines the symbol itself
//! in an object stops at a duplicate symbol; none is known. An archive
//! member, pulled only when needed, would avoid both, but takes a second
//! tool (zig ar) and step to make.
//!
//! No object when it cannot be made: the link goes on without it, as
//! before, with a warning.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const cache = @import("cache.zig");
const Args = cmdline.Args;

/// mingw-w64-crt's cfguard/guard_dispatch.S, x86_64, kept out of
/// auto-export.
pub const source =
    \\/* rzig (zigbuild/tools/rzig/cfguard.zig): mingw-w64-crt's
    \\   cfguard/guard_dispatch.S, which zig's MinGW runtime leaves out. The
    \\   target of __guard_dispatch_icall_fptr when CFG is off: jump to the
    \\   address the caller put in %rax. Not auto-exported from a DLL. */
    \\    .text
    \\    .globl __guard_dispatch_icall_dummy
    \\__guard_dispatch_icall_dummy:
    \\    jmp *%rax
    \\    .section .drectve,"yni"
    \\    .ascii " -exclude-symbols:__guard_dispatch_icall_dummy"
    \\
;

pub const target = "x86_64-windows-gnu";

/// Whether a command links: an -o, and no compile-only flag (`--version`,
/// `-E` for windres and `-c` get nothing).
pub fn wanted(args: Args) bool {
    return !cmdline.compileOnly(args) and cmdline.anyWord(args, "-o");
}

/// The object, made if it is not there yet; null when ctx.zig is unset or
/// it cannot be made.
pub fn object(ctx: *Ctx) !?[]const u8 {
    return cache.compiled(ctx, .{
        .name = "cfguard",
        .file = "guard_dispatch.S",
        .source = source,
        .target = target,
        .consequence = "code compiled with Control Flow Guard cannot link",
    });
}

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");

test wanted {
    try testing.expect(wanted(&.{ "-shared", "-o", "p.dll", "a.o" }));
    try testing.expect(wanted(&.{ "-o", "prog.exe", "a.o" }));
    for ([_]Args{
        &.{"--version"},
        &.{ "-E", "-xc", "-DRC_INVOKED", "r.rc" },
        &.{ "-c", "a.c", "-o", "a.o" },
        &.{ "-shared", "a.o" },
    }) |args| try testing.expect(!wanted(args));
}

test "made once into the cache, from guard_dispatch.S" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for zig
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    try testing.expect(try object(c) == null);
    try f.write("bin/zig", "#!/bin/sh\n[ \"$1\" = version ] && { echo 0.16.0; exit 0; }\no=; p=; for a in \"$@\"; do [ \"$p\" = -o ] && o=$a; p=$a; done\necho \"$*\" > \"$o\"\n", .fromMode(0o755));
    c.zig = &.{f.path("bin/zig")};
    const o = (try object(c)).?;
    try testing.expect(mem.startsWith(u8, o, f.path("cache/r-zig/cfguard-")));
    try testing.expect(mem.endsWith(u8, o, "/guard_dispatch.o"));
    const dir = o[0 .. o.len - "/guard_dispatch.o".len];
    var buf: [4096]u8 = undefined;
    const asked = try std.Io.Dir.cwd().readFile(testing.io, o, &buf);
    try testing.expect(mem.startsWith(u8, asked, f.fmt("cc -target x86_64-windows-gnu -mcpu=baseline -fno-sanitize=undefined -O2 -g0 -c {s}/guard_dispatch.S -o {s}/guard_dispatch.o.", .{ dir, dir })));
    var sbuf: [4096]u8 = undefined;
    try testing.expectEqualStrings(source, try std.Io.Dir.cwd().readFile(testing.io, f.fmt("{s}/guard_dispatch.S", .{dir}), &sbuf));
    try testing.expectEqualStrings("", f.takeWarnings());
}
