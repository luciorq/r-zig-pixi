//! The Fortran runtime. Makeconf's FLIBS says -lflang_rt.runtime
//! (feat-no-host-paths F1.5); link the static archive of the flang on
//! PATH, the compiler FC runs, wherever its LLVM keeps it (<resource
//! dir>/lib/<triple>/): never a shared runtime, which would need an rpath
//! into the environment at load time (conda-forge's linux-64 flang-rt
//! ships one next to the archive), and not tied to the LLVM major R was
//! built with. Once: R CMD SHLIB repeats $(FLIBS). No flang on PATH:
//! nothing this link has was compiled by it, so the flag goes (CRAN's
//! usual `PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)` puts it on C and
//! C++ links too). A flang without the archive: dropped with a warning, so
//! only a Fortran package fails, at its load test.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const find_zig = @import("find_zig.zig");
const Args = cmdline.Args;

const flag = "-lflang_rt.runtime";
const archive = "libflang_rt.runtime.a";

/// `args` with the first -lflang_rt.runtime replaced by the archive (or
/// dropped) and every later one dropped. Unchanged, and flang not asked,
/// when no argument has the flag as a word (the shims' `" $* "` test).
pub fn resolve(ctx: *Ctx, args: Args) !Args {
    if (!cmdline.anyWord(args, flag)) return args;
    var found = try find(ctx);
    var out: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        if (!mem.eql(u8, x, flag)) {
            try out.append(ctx.arena, x);
            continue;
        }
        if (found) |a| try out.append(ctx.arena, a);
        found = null;
    }
    return out.items;
}

/// <flang -print-resource-dir>/lib/*/libflang_rt.runtime.a, the first in
/// glob order that is a file.
fn find(ctx: *Ctx) !?[]const u8 {
    const flang = (try find_zig.onPath(ctx, "flang")) orelse return null;
    const res = ctx.capture(&.{ flang, "-print-resource-dir" });
    if (!res.ok or res.stdout.len == 0) return null;
    // a Windows flang's answer: CRLF and backslashes
    var dir = res.stdout;
    if (mem.endsWith(u8, dir, "\r")) dir = dir[0 .. dir.len - 1];
    dir = try mem.replaceOwned(u8, ctx.arena, dir, "\\", "/");

    for (try globDirs(ctx, try ctx.fmt("{s}/lib", .{dir}))) |sub| {
        const a = try ctx.fmt("{s}/lib/{s}/" ++ archive, .{ dir, sub });
        if (ctx.isFile(a)) return a;
    }
    ctx.warn("warning: no " ++ archive ++ " under {s}/lib/*/; dropping " ++ flag, .{dir});
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
    try testing.expectEqualStrings(f.fmt("rzig-test: warning: no libflang_rt.runtime.a under {s}/lib/*/; dropping -lflang_rt.runtime\n", .{rd}), f.takeWarnings());
    // the first triple directory in byte order that has it; a directory of that name is no archive
    try f.tmp.dir.createDirPath(testing.io, "llvm/lib/clang/23/lib/.hidden/libflang_rt.runtime.a");
    try f.tmp.dir.createDirPath(testing.io, "llvm/lib/clang/23/lib/a-dir/libflang_rt.runtime.a");
    try f.touch("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    try f.touch("llvm/lib/clang/23/lib/zz/libflang_rt.runtime.a");
    const a = f.path("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    try expectArgs(&.{ "a.o", a, "-lm" }, try resolve(&f.ctx, &.{ "a.o", "-lflang_rt.runtime", "-lm", "-lflang_rt.runtime" }));
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
