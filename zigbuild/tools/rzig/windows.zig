//! Windows: what the shims did to a compiler command line under MSYS
//! (`uname -s` MINGW*/MSYS*), in gcc.exe/g++.exe's place.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const find_zig = @import("find_zig.zig");
const Args = cmdline.Args;

/// zig's MinGW `-l` search tries only <n>.dll, <n>.lib and lib<n>.a. It
/// misses lib<n>.dll.a (MinGW import libraries, what GNU ld tries first)
/// and lib<n>.lib (conda-forge's MSVC naming: libbz2.lib, libcurl.lib), so
/// name the file when only a missed name exists. Also the -mwindows
/// libraries, and gfortran's runtime directory.
pub fn libs(ctx: *Ctx, args: Args) !Args {
    const a = ctx.arena;
    var dirs = try cmdline.libDirs(a, args);
    // gfortran's runtime lives in GCC's private libdir, which the real gcc
    // driver searches implicitly and zig cannot know about.
    var gfortran_l: ?[]const u8 = null;
    if (cmdline.anyContains(args, "-lgfortran") or cmdline.anyContains(args, "-lquadmath")) {
        if (try gfortranLibDir(ctx)) |d| {
            try dirs.append(a, d);
            gfortran_l = try ctx.fmt("-L{s}", .{d});
        }
    }
    var out: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        const name = cmdline.flagValue(x, "-l") orelse {
            try out.append(a, x);
            continue;
        };
        try out.append(a, (try importLib(ctx, dirs.items, name)) orelse x);
    }
    // GNU gcc's -mwindows also links the GDI/shell set; zig only sets the
    // subsystem. gnuwin32's makefiles rely on the implicit libraries.
    if (cmdline.anyWord(args, "-mwindows")) {
        try out.appendSlice(a, &.{ "-lgdi32", "-lcomdlg32", "-lwinspool", "-ladvapi32", "-lshell32" });
    }
    if (gfortran_l) |l| try out.append(a, l);
    return out.items;
}

/// GNU ld's order in each directory, against what zig finds by itself.
fn importLib(ctx: *Ctx, dirs: Args, name: []const u8) !?[]const u8 {
    for (dirs) |d| {
        const dll_a = try ctx.fmt("{s}/lib{s}.dll.a", .{ d, name });
        if (ctx.isFile(dll_a)) return dll_a;
        // zig will find these itself
        if (ctx.isFile(try ctx.fmt("{s}/{s}.dll", .{ d, name })) or
            ctx.isFile(try ctx.fmt("{s}/{s}.lib", .{ d, name })) or
            ctx.isFile(try ctx.fmt("{s}/lib{s}.a", .{ d, name }))) return null;
        const lib_lib = try ctx.fmt("{s}/lib{s}.lib", .{ d, name });
        if (ctx.isFile(lib_lib)) return lib_lib;
    }
    return null;
}

/// The directory of `gfortran -print-file-name=libgfortran.dll.a`, when
/// gfortran answers with one that exists. (The shim's `dirname` turned a
/// missing gfortran, or an answer without a directory, into `.`, which
/// added `-L.`; that is dropped here. No platform uses gfortran since
/// Phase 2, so this only matters to a package naming -lgfortran.)
fn gfortranLibDir(ctx: *Ctx) !?[]const u8 {
    const gfortran = (try find_zig.onPath(ctx, "gfortran")) orelse return null;
    const res = ctx.capture(&.{ gfortran, "-print-file-name=libgfortran.dll.a" });
    const dir = std.fs.path.dirname(mem.trimEnd(u8, res.stdout, "\r")) orelse return null;
    return if (ctx.isDir(dir)) dir else null;
}

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "import libraries GNU ld would find; zig's own names left to zig; -mwindows" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    for ([_][]const u8{ "d1/libdlla.dll.a", "d1/ziglib.lib", "d1/libmsvc.lib", "d1/stop.dll", "d2/libstop.dll.a", "d2/libdlla.lib", "d2/libonly2.dll.a" }) |p| try f.touch(p);
    const l1 = f.fmt("-L{s}", .{f.path("d1")});
    const l2 = f.fmt("-L{s}", .{f.path("d2")});
    try expectArgs(&.{
        l1,          l2,                          f.path("d1/libdlla.dll.a"), "-lziglib",   f.path("d1/libmsvc.lib"), "-lstop",
        "-lnowhere", f.path("d2/libonly2.dll.a"), "-L",                       "/x",         "-l",                     "x",
        "-mwindows", "-lgdi32",                   "-lcomdlg32",               "-lwinspool", "-ladvapi32",             "-lshell32",
    }, try libs(&f.ctx, &.{ l1, l2, "-ldlla", "-lziglib", "-lmsvc", "-lstop", "-lnowhere", "-lonly2", "-L", "/x", "-l", "x", "-mwindows" }));
    // -mwindows as a word only
    try expectArgs(&.{"-mwindowsx"}, try libs(&f.ctx, &.{"-mwindowsx"}));
}

test "gfortran's libdir for -lgfortran/-lquadmath, nothing without gfortran" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for gfortran
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.env.put("PATH", f.path("bin"));
    try expectArgs(&.{ "a.o", "-lgfortran" }, try libs(&f.ctx, &.{ "a.o", "-lgfortran" }));
    for ([_][]const u8{ "gcc/libgfortran.dll.a", "gcc/libquadmath.dll.a" }) |p| try f.touch(p);
    try f.write("bin/gfortran", f.fmt("#!/bin/sh\nprintf '%s\\r\\n' '{s}'\n", .{f.path("gcc/libgfortran.dll.a")}), .fromMode(0o755));
    const l = f.fmt("-L{s}", .{f.path("gcc")});
    try expectArgs(
        &.{ "a.o", f.path("gcc/libgfortran.dll.a"), f.path("gcc/libquadmath.dll.a"), "-lm", l },
        try libs(&f.ctx, &.{ "a.o", "-lgfortran", "-lquadmath", "-lm" }),
    );
    // an answer without a directory (gcc's when it does not know the file)
    try f.write("bin/gfortran", "#!/bin/sh\necho libgfortran.dll.a\n", .fromMode(0o755));
    try expectArgs(&.{"-lquadmath"}, try libs(&f.ctx, &.{"-lquadmath"}));
}
