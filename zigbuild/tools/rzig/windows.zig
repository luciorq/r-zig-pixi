//! Windows: what the shims did to a compiler command line under MSYS
//! (`uname -s` MINGW*/MSYS*), in gcc.exe/g++.exe's place.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const Args = cmdline.Args;

/// zig's MinGW `-l` search tries only <n>.dll, <n>.lib and lib<n>.a. It
/// misses lib<n>.dll.a (MinGW import libraries, what GNU ld tries first)
/// and lib<n>.lib (conda-forge's MSVC naming: libbz2.lib, libcurl.lib), so
/// name the file when only a missed name exists. MinGW's library names
/// zig has no import library for under that name are renamed first
/// (mingw_names). Also the -mwindows libraries. (-lgfortran and
/// -lquadmath are flang's runtime by now: flang_rt.zig.)
pub fn libs(ctx: *Ctx, args: Args) !Args {
    const a = ctx.arena;
    const dirs = try cmdline.libDirs(a, args);
    var out: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        var name = cmdline.flagValue(x, "-l") orelse {
            try out.append(a, x);
            continue;
        };
        var l = x;
        if (mingw_names.get(name)) |n| {
            name = n;
            l = try ctx.fmt("-l{s}", .{n});
        }
        try out.append(a, (try importLib(ctx, dirs.items, name)) orelse l);
    }
    // GNU gcc's -mwindows also links the GDI/shell set; zig only sets the
    // subsystem. gnuwin32's makefiles rely on the implicit libraries.
    if (cmdline.anyWord(args, "-mwindows")) {
        try out.appendSlice(a, &.{ "-lgdi32", "-lcomdlg32", "-lwinspool", "-ladvapi32", "-lshell32" });
    }
    return out.items;
}

/// MinGW library names upstream zig has no import library for, and the
/// name it has one under. zig makes the import library for -l<n> from
/// <n>.def in its lib/libc/mingw, and upstream zig ships no .def under
/// these names; conda-forge's zig ships prebuilt MinGW import libraries
/// as well, so it links either name. One rule for both zigs: the name
/// both have a .def for, which imports the same functions from the same
/// DLL.
///   synchronization: WaitOnAddress, WakeByAddressSingle and
///     WakeByAddressAll, which Rust's standard library calls on
///     windows-gnu (rustc's native-static-libs list -lsynchronization, so
///     Rust-based packages' Makevars.win name it, and rustc passes it on
///     its own links). They live in the API set api-ms-win-core-synch-l1-2-0;
///     conda-forge's synchronization.def is that API set's .def (LIBRARY
///     api-ms-win-core-synch-l1-2-0.dll, the same 17 exports). Upstream
///     zig 0.16.0: "unable to find dynamic system library
///     'synchronization'"; with the API set's name both zigs link it
///     (cross-compiled from linux-64, and natively on kappa with this
///     rule, 2026-10-08: the same import table).
const mingw_names = std.StaticStringMap([]const u8).initComptime(.{
    .{ "synchronization", "api-ms-win-core-synch-l1-2-0" },
});

/// MinGW gcc names an executable link's output `<name>.exe` when `-o`
/// gives a name without an extension (`gcc px.c -o px` writes px.exe);
/// zig writes exactly the name given. Packages build helper programs that
/// way and then look for the .exe (ps and processx: px.exe,
/// interrupt.exe, which no r-zig build had before 2026-10-02). Shared
/// libraries and compile-only calls keep their names.
pub fn exeSuffix(ctx: *Ctx, args: Args) !Args {
    if (cmdline.compileOnly(args) or cmdline.anyWord(args, "-shared") or cmdline.anyWord(args, "-r")) return args;
    const i = cmdline.outputIndex(args) orelse return args;
    if (i + 1 >= args.len) return args;
    const name = args[i + 1];
    const base = if (mem.lastIndexOfAny(u8, name, "/\\")) |sep| name[sep + 1 ..] else name;
    if (base.len == 0 or mem.indexOfScalar(u8, base, '.') != null) return args;
    const out = try ctx.arena.dupe([]const u8, args);
    out[i + 1] = try ctx.fmt("{s}.exe", .{name});
    return out;
}

/// An image link's -flto and -flto=<x> (Makeconf.win's LTO_OPT, what R
/// CMD INSTALL --use-LTO sets), dropped. With it zig 0.16 (conda-forge's
/// and upstream's) builds its MinGW runtime for LTO as well, and every
/// x86_64-windows-gnu link of objects compiled with -flto stops at
/// symbols that runtime then lacks: "lld-link: error: undefined symbol:
/// wmemchr ... frexpf", from zig cc alone (phase 3's LTO record on
/// kappa, 2026-10-11; -flto=thin too). Without it zig hands those objects
/// (LLVM bitcode) to lld all the same, and lld optimizes them together:
/// the package's code still gets LTO, and zig's runtime is linked as it
/// is, as GCC's LTO leaves MinGW's runtime alone. Compiles keep -flto; a
/// command that compiles and links at once compiles without it.
pub fn noLtoLink(ctx: *Ctx, args: Args) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        if (mem.eql(u8, x, "-flto") or mem.startsWith(u8, x, "-flto=")) continue;
        try out.append(ctx.arena, x);
    }
    return out.items;
}

/// zig writes an import library for every DLL it links (and for a
/// program that exports symbols), beside it, named after the link's
/// first input: rzig's CFG stub comes first (cfguard.zig), so every
/// package link left src/guard_dispatch.lib, which R CMD build packs and
/// R CMD check warns about ("These are unlikely file names for src
/// files"; kappa, 2026-10-11). GNU ld writes none unless asked, and zig
/// cc has no flag for none. So an image link that names none
/// (--out-implib, -implib) names <output>.rzig.lib, which main.zig's run
/// deletes when zig is done (ctx.discard): no link leaves one, and the
/// next link of the same output replaces one a killed link left. Through
/// -Xlinker, as a comma in the output's path would split a -Wl, flag.
pub fn implib(ctx: *Ctx, args: Args) !Args {
    if (cmdline.anyContains(args, "-implib")) return &.{};
    const i = cmdline.outputIndex(args) orelse return &.{};
    if (i + 1 >= args.len) return &.{};
    const lib = try ctx.fmt("{s}.rzig.lib", .{args[i + 1]});
    try ctx.discard.append(ctx.arena, lib);
    return ctx.arena.dupe([]const u8, &.{ "-Xlinker", try ctx.fmt("--out-implib={s}", .{lib}) });
}

/// MinGW gcc writes `-c a.c` without `-o` to a.o; zig writes a.obj, its
/// COFF default. Packages compile that way and then name the .o (stress
/// round 1, Z7: QuickJSR runs `$(R_CC) ... -c libquickjs.c`, then `ar -rs
/// ... libquickjs.o`, which failed on kappa and skipped rstan). With `-c`,
/// no -S, -E, -M or -MM, no output named (`-o <file>`, `-o<file>`) and one
/// source file, name the output as gcc does: the source's base name with
/// .o, in the current directory. Several sources keep zig's names (one -o
/// cannot name them); autoconf's object-suffix probe then finds .o, as
/// with gcc.
pub fn objSuffix(ctx: *Ctx, args: Args) !Args {
    var compile = false;
    for (args) |x| {
        if (mem.eql(u8, x, "-c")) compile = true;
        for ([_][]const u8{ "-S", "-E", "-M", "-MM" }) |f| if (mem.eql(u8, x, f)) return args;
        if (x.len > 2 and mem.startsWith(u8, x, "-o")) return args; // a joined -o<file>
    }
    if (!compile or cmdline.outputIndex(args) != null) return args;
    var src: ?[]const u8 = null;
    var it = cmdline.inputs(args);
    while (it.next()) |i| {
        if (!cmdline.isSource(args[i])) continue;
        if (src != null) return args;
        src = args[i];
    }
    const base = cmdline.baseName(src orelse return args);
    const stem = base[0 .. mem.findScalarLast(u8, base, '.') orelse base.len];
    return mem.concat(ctx.arena, []const u8, &.{ args, &.{ "-o", try ctx.fmt("{s}.o", .{stem}) } });
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

// ---------------------------------------------------------------------------

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

test "-lsynchronization: the API set's name, which both zigs have an import library for" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const l1 = f.fmt("-L{s}", .{f.path("d1")});
    // Rust's libraries on a package's link line
    try expectArgs(
        &.{ "a.o", l1, "-lrustpkg", "-lws2_32", "-lapi-ms-win-core-synch-l1-2-0", "-lntdll" },
        try libs(&f.ctx, &.{ "a.o", l1, "-lrustpkg", "-lws2_32", "-lsynchronization", "-lntdll" }),
    );
    // looked up under the new name, as any other -l
    try f.touch("d1/libapi-ms-win-core-synch-l1-2-0.dll.a");
    try expectArgs(&.{ l1, f.path("d1/libapi-ms-win-core-synch-l1-2-0.dll.a") }, try libs(&f.ctx, &.{ l1, "-lsynchronization" }));
    // only that name, as a one-argument -l
    const others: Args = &.{ "-lsynchronizationx", "-lsynch", "-l", "synchronization", "-Wl,-lsynchronization" };
    try expectArgs(others, try libs(&f.ctx, others));
}

test "noLtoLink: -flto and -flto=<x> off a link; the rest kept" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try expectArgs(
        &.{ "-shared", "-O2", "-o", "pkg.dll", "f.o", "-fno-lto" },
        try noLtoLink(&f.ctx, &.{ "-shared", "-flto", "-O2", "-o", "pkg.dll", "f.o", "-flto=thin", "-fno-lto", "-flto=auto" }),
    );
}

test "implib: <output>.rzig.lib through -Xlinker, to delete; none over the caller's own" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    // winshlib.mk's link, and a program in a directory with a comma
    try expectArgs(&.{ "-Xlinker", "--out-implib=pkg.dll.rzig.lib" }, try implib(c, &.{ "-shared", "-s", "-o", "pkg.dll", "tmp.def", "a.o" }));
    try expectArgs(&.{ "-Xlinker", "--out-implib=C:/a,b/px.exe.rzig.lib" }, try implib(c, &.{ "px.o", "-o", "C:/a,b/px.exe" }));
    // main.zig's run deletes them after the link
    try expectArgs(&.{ "pkg.dll.rzig.lib", "C:/a,b/px.exe.rzig.lib" }, c.discard.items);
    // the caller names one (CMake's -Wl,--out-implib,lib<name>.dll.a),
    // or there is no output to name it after: none, nothing to delete
    c.discard = .empty;
    for ([_]Args{
        &.{ "-shared", "-o", "libfoo.dll", "a.o", "-Wl,--out-implib,libfoo.dll.a" },
        &.{ "-shared", "-o", "foo.dll", "a.o", "-Xlinker", "--out-implib", "-Xlinker", "foo.lib" },
        &.{ "-shared", "-o", "foo.dll", "a.o", "-Wl,-implib,foo.lib" },
        &.{ "-shared", "-Xlinker", "-o", "a.o" },
        &.{ "-shared", "a.o", "-o" },
    }) |args| try expectArgs(&.{}, try implib(c, args));
    try testing.expectEqual(0, c.discard.items.len);
}

test "objSuffix: gcc's .o for -c without -o" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try expectArgs(&.{ "-O2", "-c", "libquickjs.c", "-o", "libquickjs.o" }, try objSuffix(&f.ctx, &.{ "-O2", "-c", "libquickjs.c" }));
    try expectArgs(&.{ "-c", "src\\sub/a.cpp", "-I", "x.c", "-include", "b.h", "-o", "a.o" }, try objSuffix(&f.ctx, &.{ "-c", "src\\sub/a.cpp", "-I", "x.c", "-include", "b.h" }));
    try expectArgs(&.{ "-c", "x.f90", "-o", "x.o" }, try objSuffix(&f.ctx, &.{ "-c", "x.f90" }));
    // an output named, several sources, no -c, -E, -S, -M, -MM: unchanged
    for ([_]Args{
        &.{ "-c", "a.c", "-o", "b.o" },
        &.{ "-c", "a.c", "-ob.o" },
        &.{ "-c", "a.c", "b.c" },
        &.{ "a.c", "-o", "a" },
        &.{ "-E", "-c", "a.c" },
        &.{ "-M", "-c", "a.c" },
        &.{ "-MM", "-c", "a.c" },
        &.{ "-S", "-c", "a.c" },
        &.{ "-c", "-" },
        &.{ "-c", "a.o" },
    }) |args| try expectArgs(args, try objSuffix(&f.ctx, args));
}

test "exeSuffix: gcc's .exe for an executable named without an extension" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try expectArgs(&.{ "-O2", "px.c", "-o", "px.exe" }, try exeSuffix(&f.ctx, &.{ "-O2", "px.c", "-o", "px" }));
    try expectArgs(&.{ "-o", "tools/cmdzip.exe", "a.c" }, try exeSuffix(&f.ctx, &.{ "-o", "tools/cmdzip", "a.c" }));
    try expectArgs(&.{ "-o", "C:\\x.y\\conftest.exe", "a.c" }, try exeSuffix(&f.ctx, &.{ "-o", "C:\\x.y\\conftest", "a.c" }));
    // already named, a DLL, a compile, an object: unchanged
    try expectArgs(&.{ "-o", "px.exe", "px.c" }, try exeSuffix(&f.ctx, &.{ "-o", "px.exe", "px.c" }));
    try expectArgs(&.{ "-shared", "-o", "ps", "a.o" }, try exeSuffix(&f.ctx, &.{ "-shared", "-o", "ps", "a.o" }));
    try expectArgs(&.{ "-c", "a.c", "-o", "a" }, try exeSuffix(&f.ctx, &.{ "-c", "a.c", "-o", "a" }));
    try expectArgs(&.{ "-Xlinker", "-o", "a.c" }, try exeSuffix(&f.ctx, &.{ "-Xlinker", "-o", "a.c" }));
}
