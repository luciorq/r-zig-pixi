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
//! The fix is crtbeginS.o's part, dso_fini.c. R's build compiles it for
//! R's target into R_HOME/bin/toolchain/dso_fini.o, beside rzig
//! (build.zig's linkObject), and compiler.zig passes that file on every
//! linux shared link, first among the inputs, where gcc puts crtbeginS.o:
//! its .fini_array entry is then the first, which runs last, after the
//! library's own destructors. Until feat-r-home-link-objects rzig compiled
//! it at link time into its cache, keyed by what `zig version` said, so
//! every such link spawned that: the object is the same for zig 0.16.0,
//! conda-forge's and upstream's, the two measured (the bytes differ in
//! .comment's clang version alone), and a file in a cache is code every
//! package then runs (cr27 g1 probe 6: a planted dso_fini.o's constructor
//! ran).
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
//! No object when the file is missing (a broken install, rzig copied
//! alone): the link goes on without it, with a warning.
const std = @import("std");
const cmdline = @import("cmdline.zig");
const Args = cmdline.Args;

/// The file in rzig's directory (compiler.zig's linkObject).
pub const file = "dso_fini.o";
pub const consequence = "this library's static destructors may run after it is unloaded";

/// Whether a link gets the object: a shared library (`-shared` as a word,
/// no compile-only flag) whose startup files are not the caller's.
pub fn wanted(args: Args) bool {
    return cmdline.anyWord(args, "-shared") and !cmdline.compileOnly(args) and
        !cmdline.anyWord(args, "-nostartfiles") and !cmdline.anyWord(args, "-nostdlib");
}

// ---------------------------------------------------------------------------

const testing = std.testing;

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
