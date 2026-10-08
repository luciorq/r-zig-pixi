//! zig-cc and zig-cxx (gcc.exe and g++.exe on Windows), and zig-fc's
//! shared links (fortran.zig): what the bash shims did to the caller's
//! arguments, in their order, and the flags of the environments a package
//! compiles against (environment.zig), which Makeconf's CPPFLAGS and
//! LDFLAGS carried before F3b. The steps every OS shares are here; the
//! macOS and Windows ones are darwin.zig and windows.zig, the Fortran
//! runtime flang_rt.zig. Every other step works around a zig or
//! conda-forge quirk; the comments say which.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const darwin = @import("darwin.zig");
const windows = @import("windows.zig");
const flang_rt = @import("flang_rt.zig");
const environment = @import("environment.zig");
const floors = @import("floors.zig");
const Args = cmdline.Args;

pub const Lang = enum { c, cxx };

/// zig's arguments after its own path:
///   cc|c++ -fno-sanitize=undefined -mcpu=baseline [<target>]
///          [-F<SDK frameworks>] [<soname>]
///          <caller's, rewritten, no -mtune=, with the environments'
///          -L/-rpath before the first -o> <environments' headers> [-lomp]
///          [-L<SDK>/usr/lib]
pub fn argv(ctx: *Ctx, lang: Lang, caller: Args) !Args {
    const a = ctx.arena;
    var before: Args = &.{};
    var link_last: Args = &.{};
    switch (ctx.os) {
        // The glibc floor build.zig uses for R itself: packages are often
        // compiled on a newer login node than the compute nodes that load
        // them, and glibc is backward compatible, so a floor, not a
        // restriction. Not a native target, so zig adds no rpaths either.
        .linux => before = &.{ "-target", linux_target },
        .macos => {
            const t = try darwin.target(ctx);
            before = t.before;
            link_last = t.link_last;
        },
        // No target: zig cc's native Windows OS and ABI are already
        // x86_64-windows-gnu, R's own. Its native CPU is the compiling
        // machine's, which -mcpu=baseline (below) replaces.
        .windows, .other => {},
    }

    var args = try flang_rt.resolve(ctx, try dropTune(ctx, caller));
    // the caller's arguments decide it, not a directory's name
    const soname = try sonameFlag(ctx, args);
    args = try envFlags(ctx, args);
    // after envFlags: an -l, -lomp included, resolves in its directories
    if (ctx.os == .windows) {
        args = try windows.libs(ctx, args);
        args = try windows.exeSuffix(ctx, args);
    }
    if (ctx.os == .macos) {
        args = try darwin.dedupLibs(ctx, args);
        if (cmdline.compileOnly(args)) link_last = &.{};
    }

    var out: std.ArrayList([]const u8) = .empty;
    try out.append(a, switch (lang) {
        .c => "cc",
        .cxx => "c++",
    });
    // zig cc enables UBSan in trap mode by default; R's numeric code has
    // benign UB that would SIGILL at run time.
    try out.append(a, "-fno-sanitize=undefined");
    try out.append(a, cpu_flag);
    try out.appendSlice(a, before);
    if (soname) |s| try out.append(a, s);
    try out.appendSlice(a, args);
    try out.appendSlice(a, link_last);
    return out.items;
}

/// The CPU packages are compiled for, on every OS: the baseline of the
/// target's architecture (x86-64 on linux and Windows x86_64, generic on
/// linux aarch64, apple-m1 on macOS arm64, core2 on macOS x86_64), as
/// build.zig compiles R itself (cpu_model = .baseline). A package
/// compiled on one machine is loaded on others: CI-built binary packages,
/// a shared library on a cluster's compute nodes, so no instruction may
/// depend on the compiling machine's CPU (AVX2, AVX-512). zig resolves a
/// target that names its architecture to that baseline already (linux's
/// and macOS's above), and no target to the machine's own CPU (Windows:
/// target-cpu "skylake" on kappa, 2026-10-06); one explicit rule, the
/// same flag everywhere.
/// Before the caller's arguments: zig takes the last -mcpu or -march, so
/// a package's own -march=native still wins. zig reads -mtune as one of
/// them too, which is why dropTune drops it.
const cpu_flag = "-mcpu=baseline";

/// The caller's -mtune=<cpu>, dropped. zig cc reads it as the CPU to
/// compile for, as it reads -mcpu and -march, never as tuning alone:
/// after -mcpu=baseline, -mtune=native gives target-cpu "skylake-avx512"
/// and -mtune=haswell "haswell", with tune-cpu "generic" either way (zig
/// 0.16.0, 2026-10-06); a gcc spelling zig has no CPU for fails the
/// compile (-mtune=generic: "unknown target CPU 'generic'"; aarch64's
/// -mtune=cortex-a76). gcc, clang and flang only schedule for that CPU,
/// so a Makevars, a package's or ~/.R/Makevars, may well pass
/// -mtune=native as a portable flag; through zig it would make a package
/// that needs the compiling machine's CPU. Nothing is lost: zig tunes
/// for "generic" anyway. zig-fc's flang commands keep it (flang:
/// target-cpu "x86-64", tune-cpu the named one).
fn dropTune(ctx: *Ctx, caller: Args) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    for (caller) |x| {
        if (!mem.startsWith(u8, x, "-mtune=")) try out.append(ctx.arena, x);
    }
    return out.items;
}

/// zig's name for this binary's own architecture. The shim asked `uname
/// -m`, which agrees on x86_64 and aarch64, the two linux arches shipped.
const linux_target = @tagName(builtin.cpu.arch) ++ "-linux-gnu." ++ floors.majorMinor(floors.glibc);

/// GNU ld records a bare "libR.so" as DT_NEEDED when a library has no
/// SONAME; zig's lld records the path it resolved (e.g.
/// "../../lib/libR.so"), which breaks at run time. So a shared library
/// named lib*.so* without an explicit -soname gets one, on every OS as the
/// shims did. Only the first `-o`'s argument counts.
fn sonameFlag(ctx: *Ctx, args: Args) !?[]const u8 {
    if (!cmdline.anyWord(args, "-shared") or cmdline.anyContains(args, "-soname")) return null;
    if (args.len < 2) return null;
    for (args[0 .. args.len - 1], args[1..]) |x, next| {
        if (!mem.eql(u8, x, "-o")) continue;
        const base = if (mem.findScalarLast(u8, next, '/')) |i| next[i + 1 ..] else next;
        // the glob lib*.so*
        if (mem.startsWith(u8, base, "lib") and mem.find(u8, base[3..], ".so") != null) {
            return try ctx.fmt("-Wl,-soname,{s}", .{base});
        }
        return null;
    }
    return null;
}

/// Windows: the environments' headers on every compile, searched after
/// zig's own MinGW and libc++ headers (-idirafter), so a conda-forge
/// header cannot shadow one of theirs (an env stdint.h or pthread.h would,
/// with -I). false: only on -fopenmp calls, which need omp.h, as before
/// F3b; the fallback should a Library/include header still break a
/// compile through an #include_next chain.
const windows_headers_always = true;

/// The environments' flags (environment.zig), each only when its directory
/// exists, R's own environment first:
///   -I<dir>/include (Windows: -idirafter <dir>/include) on every call,
///     after the caller's arguments: a package's own and its LinkingTo
///     headers come first, and the environment's still before the C
///     library's and the SDK's;
///   -L<dir>/lib, and -Wl,-rpath,<dir>/lib for a conda env, on links,
///     just before the first -o: where Makeconf's LDFLAGS sat on R CMD
///     SHLIB's link line, ahead of a package's own -L directories, so the
///     environment's libraries keep winning as they did. At the end when
///     the line has no -o;
///   -lomp on a -fopenmp link: zig cc does -fopenmp codegen but bundles
///     neither omp.h nor libomp and won't link it, so llvm-openmp's, when
///     an environment has omp.h and the caller does not link libomp
///     itself. Some packages (data.table) probe OpenMP themselves and put
///     -lomp in PKG_LIBS on top of R's SHLIB_OPENMP_CFLAGS; a second
///     libomp would be a duplicate LC_LOAD_DYLIB, which newer macOS dyld
///     refuses to load. On Windows windows.libs resolves it to libomp.lib.
fn envFlags(ctx: *Ctx, args: Args) !Args {
    const a = ctx.arena;
    const envs = try environment.list(ctx);
    const link = !cmdline.compileOnly(args);
    const headers = ctx.os != .windows or windows_headers_always or cmdline.anyContains(args, "-fopenmp");
    var inc: std.ArrayList([]const u8) = .empty;
    var lib: std.ArrayList([]const u8) = .empty;
    for (envs) |e| {
        const include = try ctx.fmt("{s}/include", .{e.dir});
        if (headers and ctx.isDir(include)) {
            if (ctx.os == .windows) {
                try inc.appendSlice(a, &.{ "-idirafter", include });
            } else {
                try inc.append(a, try ctx.fmt("-I{s}", .{include}));
            }
        }
        const dir = try ctx.fmt("{s}/lib", .{e.dir});
        if (!link or !ctx.isDir(dir)) continue;
        try lib.append(a, try ctx.fmt("-L{s}", .{dir}));
        if (e.conda) try lib.append(a, try ctx.fmt("-Wl,-rpath,{s}", .{dir}));
    }
    var omp: Args = &.{};
    if (link and cmdline.anyContains(args, "-fopenmp") and !linksLibomp(args) and try environment.openmp(ctx, envs) != null) {
        omp = &.{"-lomp"};
    }
    const at = cmdline.outputIndex(args) orelse args.len;
    return mem.concat(a, []const u8, &.{ args[0..at], lib.items, args[at..], inc.items, omp });
}

fn linksLibomp(args: Args) bool {
    for (args) |x| {
        if (mem.eql(u8, x, "-lomp") or mem.endsWith(u8, x, "/libomp.lib")) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;
const pre: Args = &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-target", linux_target };

test "linux: glibc floor pinned, UBSan off, the caller's arguments kept" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try testing.expect(mem.endsWith(u8, linux_target, "-linux-gnu.2.17"));
    try expectArgs(pre ++ &[_][]const u8{ "-std=gnu23", "-c", "a.c", "-o", "a.o" }, try argv(&f.ctx, .c, &.{ "-std=gnu23", "-c", "a.c", "-o", "a.o" }));
    try expectArgs(&.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-target", linux_target, "-c", "a.cpp" }, try argv(&f.ctx, .cxx, &.{ "-c", "a.cpp" }));
    // nothing is de-duplicated off macOS
    try expectArgs(pre ++ &[_][]const u8{ "-lm", "-lm" }, try argv(&f.ctx, .c, &.{ "-lm", "-lm" }));
}

test "every OS: the baseline CPU, once, before the target and the caller's own -march/-mcpu; -mtune dropped" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // no SDK (the fixture's xcrun runs nothing): macOS's target alone
    const mac: Args = &.{ "-target", (if (builtin.cpu.arch == .aarch64) "aarch64" else "x86_64") ++ "-native.13.0" };
    const targets = [_]struct { os: Ctx.Os, target: Args }{
        .{ .os = .linux, .target = &.{ "-target", linux_target } },
        .{ .os = .macos, .target = mac },
        // Windows: no target, so without the flag zig would compile for
        // the machine's own CPU
        .{ .os = .windows, .target = &.{} },
    };
    for (targets) |t| {
        c.os = t.os;
        for ([_]Lang{ .c, .cxx }) |lang| {
            const head: Args = &.{ if (lang == .c) "cc" else "c++", "-fno-sanitize=undefined", "-mcpu=baseline" };
            try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-O2", "-c", "a.c", "-o", "a.o" } }), try argv(c, lang, &.{ "-O2", "-c", "a.c", "-o", "a.o" }));
            // a package's own CPU choice comes later, so zig takes it
            try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-march=native", "-mcpu=haswell", "-c", "a.c" } }), try argv(c, lang, &.{ "-march=native", "-mcpu=haswell", "-c", "a.c" }));
            // -mtune=, which zig would take as the CPU, goes; the rest stays
            try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-O2", "-march=x86-64", "-mtune", "-c", "a.c" } }), try argv(c, lang, &.{ "-mtune=native", "-O2", "-march=x86-64", "-mtune=haswell", "-mtune", "-c", "a.c" }));
            // links too: a shared library carries the objects' code
            const link = try argv(c, lang, &.{ "-shared", "-mtune=native", "-o", "pkg.so", "a.o" });
            try expectArgs(head, link[0..3]);
            var n: usize = 0;
            for (link) |x| {
                n += @intFromBool(mem.startsWith(u8, x, "-mcpu="));
                try testing.expect(!mem.startsWith(u8, x, "-mtune"));
            }
            try testing.expectEqual(1, n);
        }
    }
}

test "SONAME for lib*.so* only, first -o only, never over an explicit one" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,libR.so", "-shared", "-o", "../lib/libR.so", "x.o" }, try argv(c, .c, &.{ "-shared", "-o", "../lib/libR.so", "x.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,libfoo.something", "-shared", "-o", "libfoo.something" }, try argv(c, .c, &.{ "-shared", "-o", "libfoo.something" }));
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,lib.so", "-shared", "-o", "lib.so" }, try argv(c, .c, &.{ "-shared", "-o", "lib.so" }));
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-o", "pkg.so", "-o", "libx.so" }, try argv(c, .c, &.{ "-shared", "-o", "pkg.so", "-o", "libx.so" }));
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-Wl,-soname,x", "-o", "libx.so" }, try argv(c, .c, &.{ "-shared", "-Wl,-soname,x", "-o", "libx.so" }));
    try expectArgs(pre ++ &[_][]const u8{ "-o", "libx.so" }, try argv(c, .c, &.{ "-o", "libx.so" }));
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-o" }, try argv(c, .c, &.{ "-shared", "-o" }));
    try expectArgs(pre ++ &[_][]const u8{"-shared"}, try argv(c, .c, &.{"-shared"}));
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-olibx.so" }, try argv(c, .c, &.{ "-shared", "-olibx.so" }));
    // a word inside one argument counts, as it did in " $* "
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,liby.so", "-DX=a -shared b", "-o", "liby.so" }, try argv(c, .c, &.{ "-DX=a -shared b", "-o", "liby.so" }));
}

/// A decoy every environment test sets: an activated conda env with
/// OpenMP and zlib, which R is not installed in. Nothing may come from it.
fn decoy(f: *testutil.Fixture) !void {
    try f.tmp.dir.createDirPath(testing.io, "decoy/conda-meta");
    for ([_][]const u8{ "include/omp.h", "include/zlib.h", "lib/libomp.so", "lib/libz.so", "Library/include/omp.h", "Library/lib/libomp.lib", "Library/lib/libz.dll.a" }) |p| {
        try f.touch(f.fmt("decoy/{s}", .{p}));
    }
    try f.env.put("CONDA_PREFIX", f.path("decoy"));
}

fn expectNoDecoy(args: Args) !void {
    for (args) |x| try testing.expect(mem.find(u8, x, "decoy") == null);
}

/// rzig's path in an installed tree <name> (so <name>/lib exists), with
/// include/omp.h when `omp` and a conda-meta/ directory when `conda`.
fn tree(f: *testutil.Fixture, name: []const u8, conda: bool, omp: bool) ![]const u8 {
    try f.tmp.dir.createDirPath(testing.io, f.fmt("{s}/lib/R/bin/toolchain", .{name}));
    if (omp) try f.touch(f.fmt("{s}/include/omp.h", .{name}));
    if (conda) try f.tmp.dir.createDirPath(testing.io, f.fmt("{s}/conda-meta", .{name}));
    return f.path(f.fmt("{s}/lib/R/bin/toolchain/zig-cc", .{name}));
}

test "R's environment: -I after the caller's, -L before -o, -lomp on -fopenmp links (standalone tree)" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try decoy(&f);
    const c = &f.ctx;
    c.self_exe = try tree(&f, "tree", false, true);
    const rh = f.path("tree/lib/R");
    const inc = f.fmt("-I{s}", .{f.path("tree/include")});
    const l = f.fmt("-L{s}", .{f.path("tree/lib")});
    const rinc = f.fmt("-I{s}/include", .{rh});
    const rlib = f.fmt("-L{s}/lib", .{rh});
    // R CMD SHLIB's compile and link lines with $(SHLIB_OPENMP_CFLAGS)
    // (Makeconf's CPPFLAGS and LDFLAGS empty)
    try expectArgs(
        pre ++ &[_][]const u8{ "-std=gnu23", rinc, "-DNDEBUG", "-fopenmp", "-fpic", "-O2", "-c", "a.c", "-o", "a.o", inc },
        try argv(c, .c, &.{ "-std=gnu23", rinc, "-DNDEBUG", "-fopenmp", "-fpic", "-O2", "-c", "a.c", "-o", "a.o" }),
    );
    try expectArgs(
        pre ++ &[_][]const u8{ "-std=gnu23", "-shared", rlib, l, "-o", "pkg.so", "a.o", "-fopenmp", rlib, "-lR", inc, "-lomp" },
        try argv(c, .c, &.{ "-std=gnu23", "-shared", rlib, "-o", "pkg.so", "a.o", "-fopenmp", rlib, "-lR" }),
    );
    // a package's own -L comes after the environment's, as after LDFLAGS
    try expectArgs(
        pre ++ &[_][]const u8{ "-shared", rlib, l, "-o", "pkg.so", "a.o", "-L/opt/foo/lib", "-lfoo", "-lz", rlib, "-lR", inc },
        try argv(c, .c, &.{ "-shared", rlib, "-o", "pkg.so", "a.o", "-L/opt/foo/lib", "-lfoo", "-lz", rlib, "-lR" }),
    );
    // configure's ac_link: -o first, so the -L goes first
    try expectArgs(
        pre ++ &[_][]const u8{ "-std=gnu23", l, "-o", "conftest", "-O2", "conftest.c", "-lz", inc },
        try argv(c, .c, &.{ "-std=gnu23", "-o", "conftest", "-O2", "conftest.c", "-lz" }),
    );
    // no -o (a.out): after the caller's arguments; -lomp last
    try expectArgs(pre ++ &[_][]const u8{ "-O2", "-fopenmp", "test-omp.c", l, inc, "-lomp" }, try argv(c, .c, &.{ "-O2", "-fopenmp", "test-omp.c" }));
    // the caller's own -lomp: none added; -fopenmp-simd counts (a substring, as in the shims)
    try expectArgs(pre ++ &[_][]const u8{ "-shared", l, "-o", "dt.so", "a.o", "-fopenmp", "-lomp", inc }, try argv(c, .c, &.{ "-shared", "-o", "dt.so", "a.o", "-fopenmp", "-lomp" }));
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp-simd", l, "-o", "p", "a.o", inc, "-lomp" }, try argv(c, .c, &.{ "-fopenmp-simd", "-o", "p", "a.o" }));
    // an -o inside -Xlinker is not the output
    try expectArgs(pre ++ &[_][]const u8{ "-Xlinker", "-o", "-Xlinker", "x", "a.o", l, inc }, try argv(c, .c, &.{ "-Xlinker", "-o", "-Xlinker", "x", "a.o" }));
    // compile only (-c -S -E -M -MM): headers, no -L, no -lomp
    for ([_][]const u8{ "-c", "-S", "-E", "-M", "-MM" }) |only| {
        try expectArgs(pre ++ &[_][]const u8{ only, "-fopenmp", "a.c", inc }, try argv(c, .c, &.{ only, "-fopenmp", "a.c" }));
    }
}

test "conda env: rpath into its lib after its -L; missing directories add nothing" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try decoy(&f);
    const c = &f.ctx;
    c.self_exe = try tree(&f, "env", true, true);
    const inc = f.fmt("-I{s}", .{f.path("env/include")});
    const l = f.fmt("-L{s}", .{f.path("env/lib")});
    const rp = f.fmt("-Wl,-rpath,{s}", .{f.path("env/lib")});
    try expectArgs(pre ++ &[_][]const u8{ "-shared", l, rp, "-o", "z.so", "z.o", "-lz", inc }, try argv(c, .c, &.{ "-shared", "-o", "z.so", "z.o", "-lz" }));
    try expectArgs(pre ++ &[_][]const u8{ "-c", "z.c", inc }, try argv(c, .c, &.{ "-c", "z.c" }));
    // no include/ (the wheel's r_zig/R): -L only; no omp.h: no -lomp
    c.self_exe = try tree(&f, "wheel", false, false);
    const wl = f.fmt("-L{s}", .{f.path("wheel/lib")});
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-fopenmp", wl, "-o", "p.so", "a.o" }, try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp", "-c", "a.c" }, try argv(c, .c, &.{ "-fopenmp", "-c", "a.c" }));
}

test "R_ZIG_EXTRA_ENV: after R's own; with no R tree; the decoy never" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try decoy(&f);
    const c = &f.ctx;
    _ = try tree(&f, "env", true, true);
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("env"));
    const einc = f.fmt("-I{s}", .{f.path("env/include")});
    const el = f.fmt("-L{s}", .{f.path("env/lib")});
    const erp = f.fmt("-Wl,-rpath,{s}", .{f.path("env/lib")});
    // the dev tree under pixi: the tree's own, then the pixi env's
    c.self_exe = try tree(&f, "tree", false, true);
    const inc = f.fmt("-I{s}", .{f.path("tree/include")});
    const l = f.fmt("-L{s}", .{f.path("tree/lib")});
    try expectArgs(
        pre ++ &[_][]const u8{ "-shared", "-fopenmp", l, el, erp, "-o", "p.so", "a.o", inc, einc, "-lomp" },
        try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }),
    );
    // a bare copy of rzig: the extra environment alone
    c.self_exe = "/x/zig-out/bin/zig-cc";
    try expectArgs(pre ++ &[_][]const u8{ "-shared", el, erp, "-o", "p.so", "a.o", einc }, try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o" }));
    // and none at all: the caller's arguments only, CONDA_PREFIX or not
    _ = f.env.swapRemove("R_ZIG_EXTRA_ENV");
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }, try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp", "-c", "a.c" }, try argv(c, .c, &.{ "-fopenmp", "-c", "a.c" }));
    for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
        c.os = os;
        c.self_exe = null;
        try expectNoDecoy(try argv(c, .cxx, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o", "-lz" }));
        c.self_exe = try tree(&f, "tree2", false, false);
        try expectNoDecoy(try argv(c, .cxx, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o", "-lz" }));
        try expectNoDecoy(try argv(c, .cxx, &.{ "-fopenmp", "-c", "a.cpp" }));
    }
}

test "Windows: -idirafter, no rpath, -lz and -lomp through the environment's -L" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try decoy(&f);
    const c = &f.ctx;
    try f.env.put("PATH", f.path("nothing"));
    try f.tmp.dir.createDirPath(testing.io, "env/conda-meta");
    for ([_][]const u8{ "env/Library/include/omp.h", "env/Library/include/zlib.h", "env/Library/lib/libomp.lib", "env/Library/lib/libz.dll.a", "env/Library/lib/R/bin/toolchain/gcc.exe" }) |p| try f.touch(p);
    // installed: <prefix>/Library/lib/R/bin/toolchain/gcc.exe
    c.self_exe = f.path("env/Library/lib/R/bin/toolchain/gcc.exe");
    const inc = f.path("env/Library/include");
    const l = f.fmt("-L{s}", .{f.path("env/Library/lib")});
    const omp = f.path("env/Library/lib/libomp.lib");
    const z = f.path("env/Library/lib/libz.dll.a");
    try expectArgs(&.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-c", "z.c", "-o", "z.o", "-idirafter", inc }, try argv(c, .c, &.{ "-c", "z.c", "-o", "z.o" }));
    try expectArgs(
        &.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-shared", "-fopenmp", l, "-o", "pkg.dll", "a.o", z, "-idirafter", inc, omp },
        try argv(c, .cxx, &.{ "-shared", "-fopenmp", "-o", "pkg.dll", "a.o", "-lz" }),
    );
    // the caller's -lomp, resolved the same way; none added
    try expectArgs(
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-shared", "-fopenmp", l, "-o", "pkg.dll", "a.o", omp, "-idirafter", inc },
        try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "pkg.dll", "a.o", "-lomp" }),
    );
}

test "Windows: no target, the Fortran runtime before the -l lookup" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.env.put("PATH", f.path("nothing"));
    try f.touch("d/libz.dll.a");
    const l = f.fmt("-L{s}", .{f.path("d")});
    try expectArgs(
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-shared", "-o", "pkg.dll", "a.o", l, f.path("d/libz.dll.a"), "-lc++" },
        try argv(&f.ctx, .c, &.{ "-shared", "-o", "pkg.dll", "a.o", l, "-lz", "-lflang_rt.runtime", "-lc++" }),
    );
}

test "every OS: -lgfortran and -lquadmath link flang's runtime, once; no gfortran is asked" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins for flang and gfortran
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const rd = f.path("llvm/lib/clang/23");
    try f.touch("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    const rt = f.path("llvm/lib/clang/23/lib/x86_64-unknown-linux-gnu/libflang_rt.runtime.a");
    try f.write("bin/flang", f.fmt("#!/bin/sh\n[ \"$1\" = -print-resource-dir ] && printf '%s\\n' '{s}'\n", .{rd}), .fromMode(0o755));
    // an Rtools gfortran, which Windows asked for its libdir before
    try f.touch("gcc/libgfortran.dll.a");
    try f.write("bin/gfortran", f.fmt("#!/bin/sh\n: > '{s}'\necho '{s}'\n", .{ f.path("gfortran-ran"), f.path("gcc/libgfortran.dll.a") }), .fromMode(0o755));
    try f.env.put("PATH", f.path("bin"));
    const mac: Args = &.{ "-target", (if (builtin.cpu.arch == .aarch64) "aarch64" else "x86_64") ++ "-native.13.0" };
    const targets = [_]struct { os: Ctx.Os, target: Args }{
        .{ .os = .linux, .target = &.{ "-target", linux_target } },
        .{ .os = .macos, .target = mac },
        .{ .os = .windows, .target = &.{} },
    };
    for (targets) |t| {
        c.os = t.os;
        const head: Args = &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline" };
        // R CMD SHLIB's link of a package whose Makevars was written for
        // gcc (PKG_LIBS = -lgfortran -lquadmath), then $(FLIBS)
        try expectArgs(
            try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-shared", "-o", "p.so", "a.o", "-L/r/lib", rt, "-lm" } }),
            try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o", "-L/r/lib", "-lgfortran", "-lquadmath", "-lflang_rt.runtime", "-lm" }),
        );
        // either alone
        for ([_][]const u8{ "-lgfortran", "-lquadmath" }) |l| {
            try expectArgs(
                try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-shared", "-o", "p.so", "a.o", rt } }),
                try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o", l }),
            );
        }
    }
    try testing.expect(!f.ctx.exists(f.path("gfortran-ran")));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "macOS: target, SONAME, -l de-duplicated with the environment's, SDK -L last on links only" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for xcrun
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    try decoy(&f);
    const c = &f.ctx;
    try f.write("bin/xcrun", "#!/bin/sh\necho /SDK\n", .fromMode(0o755));
    c.xcrun = f.path("bin/xcrun");
    try f.env.put("PATH", f.path("nothing"));
    c.self_exe = try tree(&f, "env", true, true);
    const inc = f.fmt("-I{s}", .{f.path("env/include")});
    const l = f.fmt("-L{s}", .{f.path("env/lib")});
    const rp = f.fmt("-Wl,-rpath,{s}", .{f.path("env/lib")});
    const t: Args = &.{ "-target", (if (builtin.cpu.arch == .aarch64) "aarch64" else "x86_64") ++ "-native.13.0", "-F/SDK/System/Library/Frameworks" };
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline" } ++ t ++ &[_][]const u8{ "-Wl,-soname,libx.so", "-shared", "-fopenmp", l, rp, "-o", "libx.so", "-L/r", "-lR", "-lomp", inc, "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "libx.so", "-L/r", "-lR", "-lomp", "-lR", "-lflang_rt.runtime", "-lomp" }),
    );
    // data.table: -lomp added once, then no second from the caller's; compiles get no SDK -L
    try expectArgs(
        &[_][]const u8{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline" } ++ t ++ &[_][]const u8{ "-Xclang", "-fopenmp", "-c", "a.cpp", inc },
        try argv(c, .cxx, &.{ "-Xclang", "-fopenmp", "-c", "a.cpp" }),
    );
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline" } ++ t ++ &[_][]const u8{ "-dynamiclib", l, rp, "-o", "p.so", "a.o", "-L/env/lib", "-lomp", "-fopenmp", inc, "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-dynamiclib", "-o", "p.so", "a.o", "-L/env/lib", "-lomp", "-fopenmp", "-lomp" }),
    );
    // a standalone tree: its -L before the SDK's, so its libz wins
    c.self_exe = try tree(&f, "tree", false, false);
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline" } ++ t ++ &[_][]const u8{ "-dynamiclib", f.fmt("-L{s}", .{f.path("tree/lib")}), "-o", "z.so", "z.o", "-lz", "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-dynamiclib", "-o", "z.so", "z.o", "-lz", "-lz" }),
    );
}
