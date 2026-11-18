//! rzig's finalization object for linux shared libraries
//! (../dso_fini.zig): crtbeginS.o's part that a zig link of a linux
//! shared library lacks. __dso_handle holds its own address (lld's
//! stand-in is the image base), and a .fini_array entry runs and forgets
//! the handlers this library registered with __cxa_atexit or atexit when
//! it is unloaded. R's build compiles this file alone, position
//! independent, into R_HOME/bin/toolchain/dso_fini.o (../build.zig's
//! linkObject), stripped. Its code is the C version's (dso_fini.c until
//! chore-release-11): __cxa_finalize's address tested through the GOT,
//! __dso_handle read through its symbol, so a strong one a link names
//! (crtbeginS.o) is the one passed.

/// __dso_handle's storage: weak, so a crtbeginS.o the link names itself
/// wins; hidden, so each library has its own.
var dso_handle: *const anyopaque = @ptrCast(&dso_handle);

/// __dso_handle by its symbol, whichever definition the link chose.
const handle = @extern(*const *const anyopaque, .{ .name = "__dso_handle", .visibility = .hidden });

/// glibc's, weak: its address, null when nothing defines it. A variable,
/// so the test is made at run time (zig takes an @extern's address for
/// non-null).
var cxa_finalize: ?*const fn (*const anyopaque) callconv(.c) void = @extern(?*const fn (*const anyopaque) callconv(.c) void, .{ .name = "__cxa_finalize", .linkage = .weak });

fn finalize() callconv(.c) void {
    if (cxa_finalize) |f| f(handle.*);
}

/// The .fini_array entry, the first of the library's when this object
/// is the first input, so it runs last. Exported to be kept (zig drops an
/// unreferenced declaration); hidden, so it is local in the library, as
/// a static one is; weak, so a link that has this object twice (named by
/// hand, or in a -r object) keeps one entry, not a duplicate symbol.
const finalize_p: *const fn () callconv(.c) void linksection(".fini_array") = &finalize;

comptime {
    @export(&dso_handle, .{ .name = "__dso_handle", .linkage = .weak, .visibility = .hidden });
    @export(&finalize_p, .{ .name = "r_zig_fini_p", .linkage = .weak, .visibility = .hidden });
}
