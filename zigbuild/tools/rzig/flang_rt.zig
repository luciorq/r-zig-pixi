//! The Fortran runtime. Makeconf's FLIBS says -lflang_rt.runtime
//! (feat-no-host-paths F1.5), and zig-fc's shared links add it
//! (fortran.zig); link the static archive of the flang `flang` finds, the
//! compiler zig-fc runs, wherever its LLVM keeps it (<resource
//! dir>/lib/<triple>/): never a shared runtime, which would need an rpath
//! into the environment at load time (flang-rt-zig >= 9 ships none, but
//! conda-forge's flang-rt and older flang-rt-zig builds have one next to
//! the archive), and not tied to the LLVM major R was built with. Once:
//! R CMD SHLIB repeats $(FLIBS). No flang:
//! nothing this link has was compiled by it, so the flag goes (CRAN's
//! usual `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)` puts it on C and
//! C++ links too). A flang without the archive: dropped with a warning, so
//! only a Fortran package fails, at its load test.
//!
//! -lgfortran and -lquadmath, as a Makevars written for gcc names them
//! (`PKG_LIBS = -lgfortran -lquadmath`, Rtools' habit on Windows), are this
//! runtime too, on every OS: FC is flang, so the Fortran runtime a link
//! needs is flang's, and gfortran's defines no symbol flang's code calls.
//! The three flags count as one: the first becomes the archive, every
//! other goes. Before (linux-64, 2026-10-08): -lgfortran failed the link
//! ("unable to find dynamic system library 'gfortran'") wherever the
//! environment had no conda-forge libgfortran (all but the openblas
//! variants'), and where it had one zig dropped it as unneeded and the
//! package failed to load ("undefined symbol:
//! _FortranAioBeginExternalListOutput"); -lquadmath linked nothing (libgcc's
//! libquadmath, dropped as unneeded) or, with no environment, failed the
//! link. macOS (osx-arm64, the same day): both failed the link, as neither
//! the environment nor the SDK has either library. Windows looked for a
//! gfortran on PATH and linked Rtools' libgfortran, which has no flang
//! symbol either, and failed the link without one. C that calls
//! libquadmath itself needs GCC's quadmath.h, which zig does not ship and
//! GCC keeps in its own lib/gcc/<triple>/<version>/include, on no
//! environment's include path.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const find_zig = @import("find_zig.zig");
const environment = @import("environment.zig");
const Args = cmdline.Args;

pub const flag = "-lflang_rt.runtime";
const archive = "libflang_rt.runtime.a";

/// The flags that name the runtime: FLIBS's, then gfortran's runtime and
/// its quad-precision library.
const flags = [_][]const u8{ flag, "-lgfortran", "-lquadmath" };

/// `args` with the first of the runtime's flags replaced by the archive
/// (or dropped) and every later one dropped. Unchanged, and flang not
/// asked, when no argument has one of them as a word (the shims' `" $* "`
/// test).
pub fn resolve(ctx: *Ctx, args: Args) !Args {
    for (flags) |f| {
        if (cmdline.anyWord(args, f)) break;
    } else return args;
    var found = try find(ctx);
    var out: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        if (!isFlag(x)) {
            try out.append(ctx.arena, x);
            continue;
        }
        if (found) |a| try out.append(ctx.arena, a);
        found = null;
    }
    return out.items;
}

fn isFlag(x: []const u8) bool {
    for (flags) |f| if (mem.eql(u8, x, f)) return true;
    return false;
}

/// The flang zig-fc runs, and whose runtime every link resolved here uses,
/// so the compiler and its runtime stay paired (feat-standalone-toolchain
/// B2 a, B34 a), the first that is there: the compilers group's,
/// <rzig dir>/flang/bin/flang (flang.exe); the one in the bin/ of the
/// environment R is installed in (a conda env used without activation);
/// PATH's.
pub fn flang(ctx: *Ctx) !?[]const u8 {
    if (environment.toolchain(ctx)) |tc| {
        if (try find_zig.inDir(ctx, try ctx.fmt("{s}/flang/bin", .{tc}), "flang")) |p| return p;
    }
    if (try environment.own(ctx)) |e| {
        if (try find_zig.inDir(ctx, try ctx.fmt("{s}/bin", .{e.dir}), "flang")) |p| return p;
    }
    return find_zig.onPath(ctx, "flang");
}

/// <flang -print-resource-dir>/lib/*/libflang_rt.runtime.a, the first in
/// glob order that is a file.
fn find(ctx: *Ctx) !?[]const u8 {
    const fc = (try flang(ctx)) orelse return null;
    const res = ctx.capture(&.{ fc, "-print-resource-dir" });
    if (!res.ok or res.stdout.len == 0) return null;
    // a Windows flang's answer: CRLF and backslashes
    var dir = res.stdout;
    if (mem.endsWith(u8, dir, "\r")) dir = dir[0 .. dir.len - 1];
    dir = try mem.replaceOwned(u8, ctx.arena, dir, "\\", "/");

    for (try globDirs(ctx, try ctx.fmt("{s}/lib", .{dir}))) |sub| {
        const a = try ctx.fmt("{s}/lib/{s}/" ++ archive, .{ dir, sub });
        if (ctx.isFile(a)) return a;
    }
    ctx.warn("warning: no " ++ archive ++ " under {s}/lib/*/; dropping " ++ flag ++ ", -lgfortran and -lquadmath", .{dir});
    return null;
}

/// What `<dir>/*` expands to, as names: not hidden, in byte order (the
/// shell's under LC_ALL=C; any order picks the same archive when there is
/// one triple directory, as every LLVM layout has).
fn globDirs(ctx: *Ctx, dir_path: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var dir = Io.Dir.cwd().openDir(ctx.io, dir_path, .{ .iterate = true }) catch return names.items;
    defer dir.close(ctx.io);
    var it = dir.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        try names.append(ctx.arena, try ctx.arena.dupe(u8, entry.name));
    }
    mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return mem.lessThan(u8, a, b);
        }
    }.lt);
    return names.items;
}

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "no flang on PATH: every -lflang_rt.runtime dropped; flang never asked without the flag" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try f.env.put("PATH", f.path("nothing"));
    try expectArgs(&.{ "-o", "q.so", "a.o", "-lm" }, try resolve(&f.ctx, &.{ "-o", "q.so", "a.o", "-lflang_rt.runtime", "-lm", "-lflang_rt.runtime" }));
    // the flag inside another argument triggers the lookup but is no flag
    try expectArgs(&.{"-DX=a -lflang_rt.runtime b"}, try resolve(&f.ctx, &.{"-DX=a -lflang_rt.runtime b"}));
    try expectArgs(&.{ "-lflang_rt", "x.o" }, try resolve(&f.ctx, &.{ "-lflang_rt", "x.o" }));
    // gfortran's runtime and libquadmath are this runtime: dropped too
    try expectArgs(&.{ "a.o", "-lm" }, try resolve(&f.ctx, &.{ "a.o", "-lgfortran", "-lm", "-lquadmath" }));
}

test "flang: the toolchain's flang/bin, then the environment's bin, then PATH" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-fc");
    try testing.expect(try flang(c) == null);
    const on_path = try f.touchProgram("p/flang");
    try f.env.put("PATH", f.path("p"));
    try testing.expectEqualStrings(on_path, (try flang(c)).?);
    const in_bin = try f.touchProgram("tree/bin/flang");
    try testing.expectEqualStrings(in_bin, (try flang(c)).?);
    // the compilers group's flang/bin/flang (not flang/flang)
    _ = try f.touchProgram("tree/lib/R/bin/toolchain/flang/flang");
    try testing.expectEqualStrings(in_bin, (try flang(c)).?);
    const in_tc = try f.touchProgram("tree/lib/R/bin/toolchain/flang/bin/flang");
    try testing.expectEqualStrings(in_tc, (try flang(c)).?);
    // R_ZIG_EXTRA_ENV's bin is not looked in; a bare copy: its own flang/bin
    _ = try f.touchProgram("extra/bin/flang");
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("extra"));
    c.self_exe = f.path("bare/zig-fc");
    try testing.expectEqualStrings(on_path, (try flang(c)).?);
    const bare = try f.touchProgram("bare/flang/bin/flang");
    try testing.expectEqualStrings(bare, (try flang(c)).?);
}

test "the runtime of the flang the lookup chose" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins for flang
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    f.ctx.self_exe = f.path("tree/lib/R/bin/toolchain/zig-fc");
    for ([_][]const u8{ "tc", "path" }) |w| {
        try f.touch(f.fmt("{s}/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a", .{w}));
    }
    try f.write("p/flang", f.fmt("#!/bin/sh\necho '{s}'\n", .{f.path("path/lib/clang/23")}), .fromMode(0o755));
    try f.write("tree/lib/R/bin/toolchain/flang/bin/flang", f.fmt("#!/bin/sh\necho '{s}'\n", .{f.path("tc/lib/clang/23")}), .fromMode(0o755));
    try f.env.put("PATH", f.path("p"));
    try expectArgs(&.{ "a.o", f.path("tc/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a") }, try resolve(&f.ctx, &.{ "a.o", "-lflang_rt.runtime" }));
}

test "flang's resource dir: the archive once, in place of the first flag" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for flang
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const rd = f.path("llvm/lib/clang/23");
    try f.write("bin/flang", f.fmt("#!/bin/sh\n[ \"$1\" = -print-resource-dir ] && printf '%s\\n' '{s}'\n", .{rd}), .fromMode(0o755));
    try f.env.put("PATH", f.path("bin"));
    // no archive: dropped, with a warning
    try f.touch("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libother.a");
    try expectArgs(&.{ "a.o", "-lm" }, try resolve(&f.ctx, &.{ "a.o", "-lflang_rt.runtime", "-lm", "-lflang_rt.runtime" }));
    try testing.expectEqualStrings(f.fmt("rzig-test: warning: no libflang_rt.runtime.a under {s}/lib/*/; dropping -lflang_rt.runtime, -lgfortran and -lquadmath\n", .{rd}), f.takeWarnings());
    // the first triple directory in byte order that has it; a directory of that name is no archive
    try f.tmp.dir.createDirPath(testing.io, "llvm/lib/clang/23/lib/.hidden/libflang_rt.runtime.a");
    try f.tmp.dir.createDirPath(testing.io, "llvm/lib/clang/23/lib/a-dir/libflang_rt.runtime.a");
    try f.touch("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    try f.touch("llvm/lib/clang/23/lib/zz/libflang_rt.runtime.a");
    const a = f.path("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    try expectArgs(&.{ "a.o", a, "-lm" }, try resolve(&f.ctx, &.{ "a.o", "-lflang_rt.runtime", "-lm", "-lflang_rt.runtime" }));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "-lgfortran and -lquadmath: the same runtime, once, in place of the first of the three, on every OS" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for flang
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const rd = f.path("llvm/lib/clang/23");
    try f.write("bin/flang", f.fmt("#!/bin/sh\n[ \"$1\" = -print-resource-dir ] && printf '%s\\n' '{s}'\n", .{rd}), .fromMode(0o755));
    try f.env.put("PATH", f.path("bin"));
    try f.touch("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    const a = f.path("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
        f.ctx.os = os;
        // a Makevars written for gcc: PKG_LIBS = -lgfortran -lquadmath
        try expectArgs(&.{ "a.o", a, "-lm" }, try resolve(&f.ctx, &.{ "a.o", "-lgfortran", "-lquadmath", "-lm" }));
        try expectArgs(&.{a}, try resolve(&f.ctx, &.{"-lquadmath"}));
        // and $(FLIBS) after it: the archive where the first flag was
        try expectArgs(
            &.{ "a.o", a, "-lm", "-lm" },
            try resolve(&f.ctx, &.{ "a.o", "-lquadmath", "-lm", "-lflang_rt.runtime", "-lgfortran", "-lm" }),
        );
        try expectArgs(&.{ "a.o", a, "-lc++" }, try resolve(&f.ctx, &.{ "a.o", "-lflang_rt.runtime", "-lc++", "-lgfortran" }));
    }
    // other names, the two-argument form and a flag inside another
    // argument are no flags (the last asks flang, as before)
    const others: Args = &.{ "-lgfortran5", "-lquadmathx", "-l", "gfortran", "-DX=a -lgfortran b", "-Wl,-lquadmath" };
    try expectArgs(others, try resolve(&f.ctx, others));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "a Windows flang's answer: CRLF stripped, backslashes turned" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.touch("llvm/lib/x86_64-w64-windows-gnu/libflang_rt.runtime.a");
    // printf's %s prints its argument as is, backslashes included
    const back = try mem.replaceOwned(u8, f.ctx.arena, f.path("llvm"), "/", "\\");
    try f.write("bin/flang", f.fmt("#!/bin/sh\nprintf '%s\\r\\n' '{s}'\n", .{back}), .fromMode(0o755));
    try f.env.put("PATH", f.path("bin"));
    try expectArgs(&.{f.path("llvm/lib/x86_64-w64-windows-gnu/libflang_rt.runtime.a")}, try resolve(&f.ctx, &.{"-lflang_rt.runtime"}));
}

test "flang that fails or says nothing: dropped without looking further" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try f.env.put("PATH", f.path("bin"));
    try f.write("bin/flang", "#!/bin/sh\necho /somewhere\nexit 3\n", .fromMode(0o755));
    try expectArgs(&.{"x.o"}, try resolve(&f.ctx, &.{ "x.o", "-lflang_rt.runtime" }));
    try f.write("bin/flang", "#!/bin/sh\n", .fromMode(0o755));
    try expectArgs(&.{"x.o"}, try resolve(&f.ctx, &.{ "x.o", "-lflang_rt.runtime" }));
    try testing.expectEqualStrings("", f.takeWarnings());
}
