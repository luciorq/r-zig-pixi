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
//! The fix is guard_dispatch.S's part, cfguard.S. R's build assembles it
//! into R_HOME/bin/toolchain/cfguard.o, beside rzig (build.zig's
//! linkObject), as dso_fini.zig's object; rzig assembled it into its cache
//! at link time before (feat-r-home-link-objects). compiler.zig passes it
//! on every Windows link (an -o, no compile-only flag and no -r: a partial
//! link makes no image, and zig's COFF -r takes one object). Nothing uses it
//! unless libmingw32's mingw_cfguard_support.obj is pulled in; other links
//! carry its 16 bytes of code. A zig whose libmingw32 has guard_dispatch.S's
//! member never pulls that member, as the symbol is already defined. R on
//! Windows is x86_64 here (win-64), and the code is x86_64's: R's build
//! makes no cfguard.o for another architecture, and an rzig built for one
//! (Windows on ARM, cross-built only) adds none (compiler.zig).
//!
//! The symbol is excluded from lld's MinGW auto-export (a DLL with no .def
//! file and no dllexport exports every global symbol), with the
//! `-exclude-symbols:` directive clang writes for a hidden symbol: a DLL
//! exports what it exported before. A link that defines the symbol itself
//! in an object stops at a duplicate symbol; none is known. An archive
//! member, pulled only when needed, would avoid both, but takes a second
//! tool (zig ar) and step to make.
//!
//! No object when the file is missing: the link goes on without it, with
//! a warning.
const std = @import("std");
const cmdline = @import("cmdline.zig");
const Args = cmdline.Args;

/// The file in rzig's directory (compiler.zig's linkObject).
pub const file = "cfguard.o";
pub const consequence = "code compiled with Control Flow Guard cannot link";

/// Whether a command links an image: an -o, no compile-only flag and no
/// -r (`--version`, `-E` for windres, `-c` and a partial link get nothing).
pub fn wanted(args: Args) bool {
    return !cmdline.compileOnly(args) and cmdline.anyWord(args, "-o") and !cmdline.anyWord(args, "-r");
}

// ---------------------------------------------------------------------------

const testing = std.testing;

test wanted {
    try testing.expect(wanted(&.{ "-shared", "-o", "p.dll", "a.o" }));
    try testing.expect(wanted(&.{ "-o", "prog.exe", "a.o" }));
    for ([_]Args{
        &.{"--version"},
        &.{ "-E", "-xc", "-DRC_INVOKED", "r.rc" },
        &.{ "-c", "a.c", "-o", "a.o" },
        &.{ "-shared", "a.o" },
        &.{ "-r", "a.o", "-o", "part.o" },
    }) |args| try testing.expect(!wanted(args));
}
