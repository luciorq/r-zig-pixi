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
const linker_args = @import("linker_args.zig");
const archives = @import("archives.zig");
const dso_fini = @import("dso_fini.zig");
const cfguard = @import("cfguard.zig");
const strip = @import("strip.zig");
const Args = cmdline.Args;

pub const Lang = enum { c, cxx };

/// zig's arguments after its own path:
///   cc|c++ -fno-sanitize=undefined -mcpu=baseline -Wno-error=date-time
///          [-g0] [<target>] [-F<SDK frameworks>] [<soname>]
///          [-Wl,--undefined-version] [-Wl,--strip-debug] [<linux shared
///          library's finalization object | Windows link's CFG stub>]
///          <caller's, rewritten, no -mtune=>
///          [<environments' -L/-rpath>] <environments' headers> [-lomp]
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

    var args = try marchArgs(ctx, try dropTune(ctx, caller));
    args = try linker_args.rewrite(ctx, args);
    args = try flang_rt.resolve(ctx, args);
    args = try archives.rename(ctx, args);
    if (ctx.os == .windows) args = try windows.objSuffix(ctx, args);
    // the caller's arguments decide these, not a directory's name
    const soname = try sonameFlag(ctx, args);
    const undefined_version = ctx.os == .linux and !cmdline.compileOnly(args) and cmdline.anyContains(args, "-version-script");
    const fini = if (ctx.os == .linux and dso_fini.wanted(args)) try dso_fini.object(ctx, linux_target) else null;
    const cfg = if (ctx.os == .windows and cfguard.wanted(args)) try cfguard.object(ctx) else null;
    const g0 = !cmdline.debugOption(args);
    const strip_debug = ctx.os == .linux and strip.wanted(ctx, args);
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
    // zig cc adds -Werror=date-time at -O1 and above (reproducible
    // builds), so a __DATE__ or __TIME__ stops the compile (stress round
    // 1, Z1: duckdb's bundled pcg header, arrow's bundled mimalloc, on
    // every OS). gcc and clang only warn, and only with -Wdate-time. After
    // zig's own flag, before the caller's: a package's -Werror=date-time
    // still wins.
    try out.append(a, "-Wno-error=date-time");
    // zig cc emits DWARF without -g (-debug-info-kind=constructor at -O2),
    // and Makeconf's CFLAGS are -O2 alone: an installed linux .so kept it
    // (stress round 1, Z10: mlpack 304 MB, duckdb 426 MB, arrow 402 MB).
    // So no debug info unless the caller asks for some: any -g option
    // (-g, -g0 to -g3, -ggdb, -gdwarf-5, -gline-tables-only, ...) leaves
    // it to the caller. On a link line it changes nothing.
    if (g0) try out.append(a, "-g0");
    try out.appendSlice(a, before);
    if (soname) |s| try out.append(a, s);
    // ld.lld stops at a version script that names a symbol the link does
    // not define (--no-undefined-version, its default since LLVM 16); GNU
    // ld does not (stress round 1, Z4: oneTBB's tbbmalloc, bundled in
    // RcppParallel). Linux links with a version script (-version-script
    // in any argument, one dash or two) get GNU ld's behaviour, before
    // the caller's arguments, so its own --no-undefined-version wins. It
    // also lets a real mistake in a version script pass, as GNU ld does.
    if (undefined_version) try out.append(a, "-Wl,--undefined-version");
    // -g0 leaves the DWARF of zig's own libc++, libc++abi and libunwind,
    // which zig builds with debug info whatever the caller asks: 4 to 6 MB
    // in every linux C++ package (stress round 2, Z10's residual). So
    // linux links strip all debug info when nothing asks for it: no -g
    // option (-g0's test) and no input object with debug info (one
    // compiled with -g whose link line has none, as devtools::load_all()
    // builds); strip.zig. It changes nothing on a command that does not
    // link (--version, -print-*, a header's -o).
    if (strip_debug) try out.append(a, "-Wl,--strip-debug");
    if (fini) |o| try out.append(a, o);
    // zig's MinGW runtime lacks __guard_dispatch_icall_dummy (stress
    // round 2, Z11: magick's bundle); cfguard.zig
    if (cfg) |o| try out.append(a, o);
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
/// target-cpu "x86-64", tune-cpu the named one). The value of
/// `-Xarch_<arch>` stays: clang's driver reads it, as clang does.
fn dropTune(ctx: *Ctx, caller: Args) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    for (caller, 0..) |x, i| {
        if (!mem.startsWith(u8, x, "-mtune=") or cmdline.xarchValue(caller, i)) try out.append(ctx.arena, x);
    }
    return out.items;
}

/// clang's `-march=armv<N>[.<M>]-a[+<ext>...]`, an Arm architecture, in
/// zig's words: `-mcpu=generic+v<N>[_<M>]a[+<feature>...]` (stress round
/// 1, Z5). zig cc reads -march as a CPU name and stops: "unknown CPU:
/// 'armv8'", also with +crc (arrow's CMake probes and its bundled
/// aws-checksums on aarch64, macOS and linux alike). clang's extension
/// names in zig's spelling: the ones it names otherwise (simd neon, fp
/// fp_armv8, fp16 fullfp16, rdma rdm, rng rand, memtag mte, profile spe,
/// fcma complxnum, jscvt jsconv, pmuv3 perfmon, predres2 specres2),
/// `-` as `_` (sve2-aes), no<x> as -<x>. Other -march values (CPU names,
/// armv8-r) are kept. On every arch: it names an Arm architecture, which
/// zig refuses elsewhere in either spelling.
/// It stays where the caller put it, after -mcpu=baseline, so the
/// package's architecture wins, as its -march would: generic+v8a+crc
/// instead of the baseline (generic on linux aarch64, apple-m1 on macOS).
/// The value of `-Xarch_<arch>` stays clang's -march: zig hands it to
/// clang's driver, which refuses zig's -mcpu spelling ("unsupported
/// argument 'generic+v8a+crypto' to option '-mcpu='", s2's bundled
/// abseil on macOS, R2-4's --conda run).
fn marchArgs(ctx: *Ctx, args: Args) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    for (args, 0..) |x, i| {
        const v = (if (cmdline.xarchValue(args, i)) null else cmdline.flagValue(x, "-march=")) orelse {
            try out.append(ctx.arena, x);
            continue;
        };
        try out.append(ctx.arena, (try armMcpu(ctx.arena, v)) orelse x);
    }
    return out.items;
}

const arm_ext_names = std.StaticStringMap([]const u8).initComptime(.{
    .{ "simd", "neon" },    .{ "fp", "fp_armv8" },   .{ "fp16", "fullfp16" },     .{ "rdma", "rdm" },
    .{ "rng", "rand" },     .{ "memtag", "mte" },    .{ "profile", "spe" },       .{ "fcma", "complxnum" },
    .{ "jscvt", "jsconv" }, .{ "pmuv3", "perfmon" }, .{ "predres2", "specres2" },
});

/// `armv<N>[.<M>]-a[+ext...]` as zig's -mcpu, or null for any other value.
fn armMcpu(a: mem.Allocator, v: []const u8) !?[]const u8 {
    var it = mem.splitScalar(u8, v, '+');
    const arch = it.first();
    if (!mem.startsWith(u8, arch, "armv") or !mem.endsWith(u8, arch, "-a")) return null;
    const ver = arch["armv".len .. arch.len - "-a".len];
    if (ver.len == 0) return null;
    for (ver) |c| if (!std.ascii.isDigit(c) and c != '.') return null;
    var s: std.ArrayList(u8) = .empty;
    try s.appendSlice(a, "-mcpu=generic+v");
    for (ver) |c| try s.append(a, if (c == '.') '_' else c);
    try s.append(a, 'a');
    while (it.next()) |e| {
        if (e.len == 0) continue;
        const off = e.len > 2 and mem.startsWith(u8, e, "no");
        const name = if (off) e[2..] else e;
        try s.append(a, if (off) '-' else '+');
        for (arm_ext_names.get(name) orelse name) |c| try s.append(a, if (c == '-') '_' else c);
    }
    return s.items;
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
///     after the caller's arguments too: a package's own -L directories
///     are searched first, so a library it bundles wins over the
///     environment's of the same name, and its own rpath comes first.
///     Before (as Makeconf's LDFLAGS sat on R CMD SHLIB's link line) they
///     went before the first -o, and with tbb-devel in the environment
///     RcppParallel's -ltbb bound the environment's TBB, not its bundled
///     one (stress round 1, R2: on Windows conda's MSVC tbb.lib, which
///     does not link). Where an -L sits among -l's does not matter: zig
///     (and lld) search every -L directory for every -l;
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
    return mem.concat(a, []const u8, &.{ args, lib.items, inc.items, omp });
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
const pre: Args = &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-target", linux_target };
/// A linux link without a -g option: `pre` and -Wl,--strip-debug.
const pre_link: Args = pre ++ &[_][]const u8{"-Wl,--strip-debug"};

test "linux: glibc floor pinned, UBSan off, the caller's arguments kept" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try testing.expect(mem.endsWith(u8, linux_target, "-linux-gnu.2.17"));
    try expectArgs(pre ++ &[_][]const u8{ "-std=gnu23", "-c", "a.c", "-o", "a.o" }, try argv(&f.ctx, .c, &.{ "-std=gnu23", "-c", "a.c", "-o", "a.o" }));
    try expectArgs(&.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-target", linux_target, "-c", "a.cpp" }, try argv(&f.ctx, .cxx, &.{ "-c", "a.cpp" }));
    // nothing is de-duplicated off macOS
    try expectArgs(pre_link ++ &[_][]const u8{ "-lm", "-lm" }, try argv(&f.ctx, .c, &.{ "-lm", "-lm" }));
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
            const head: Args = &.{ if (lang == .c) "cc" else "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" };
            try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-O2", "-c", "a.c", "-o", "a.o" } }), try argv(c, lang, &.{ "-O2", "-c", "a.c", "-o", "a.o" }));
            // a package's own CPU choice comes later, so zig takes it
            try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-march=native", "-mcpu=haswell", "-c", "a.c", "-o", "a.o" } }), try argv(c, lang, &.{ "-march=native", "-mcpu=haswell", "-c", "a.c", "-o", "a.o" }));
            // -mtune=, which zig would take as the CPU, goes; the rest stays
            try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, t.target, &.{ "-O2", "-march=x86-64", "-mtune", "-c", "a.c", "-o", "a.o" } }), try argv(c, lang, &.{ "-mtune=native", "-O2", "-march=x86-64", "-mtune=haswell", "-mtune", "-c", "a.c", "-o", "a.o" }));
            // links too: a shared library carries the objects' code
            const link = try argv(c, lang, &.{ "-shared", "-mtune=native", "-o", "pkg.so", "a.o" });
            try expectArgs(head, link[0..5]);
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
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,libR.so", "-Wl,--strip-debug", "-shared", "-o", "../lib/libR.so", "x.o" }, try argv(c, .c, &.{ "-shared", "-o", "../lib/libR.so", "x.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,libfoo.something", "-Wl,--strip-debug", "-shared", "-o", "libfoo.something" }, try argv(c, .c, &.{ "-shared", "-o", "libfoo.something" }));
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,lib.so", "-Wl,--strip-debug", "-shared", "-o", "lib.so" }, try argv(c, .c, &.{ "-shared", "-o", "lib.so" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o", "pkg.so", "-o", "libx.so" }, try argv(c, .c, &.{ "-shared", "-o", "pkg.so", "-o", "libx.so" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-Wl,-soname,x", "-o", "libx.so" }, try argv(c, .c, &.{ "-shared", "-Wl,-soname,x", "-o", "libx.so" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-o", "libx.so" }, try argv(c, .c, &.{ "-o", "libx.so" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o" }, try argv(c, .c, &.{ "-shared", "-o" }));
    try expectArgs(pre_link ++ &[_][]const u8{"-shared"}, try argv(c, .c, &.{"-shared"}));
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-olibx.so" }, try argv(c, .c, &.{ "-shared", "-olibx.so" }));
    // a word inside one argument counts, as it did in " $* "
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,-soname,liby.so", "-Wl,--strip-debug", "-DX=a -shared b", "-o", "liby.so" }, try argv(c, .c, &.{ "-DX=a -shared b", "-o", "liby.so" }));
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

test "R's environment: -I, -L after the caller's, -lomp on -fopenmp links (standalone tree)" {
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
        pre_link ++ &[_][]const u8{ "-std=gnu23", "-shared", rlib, "-o", "pkg.so", "a.o", "-fopenmp", rlib, "-lR", l, inc, "-lomp" },
        try argv(c, .c, &.{ "-std=gnu23", "-shared", rlib, "-o", "pkg.so", "a.o", "-fopenmp", rlib, "-lR" }),
    );
    // a package's own -L comes before the environment's (R2): its bundled
    // libfoo wins over the environment's
    try expectArgs(
        pre_link ++ &[_][]const u8{ "-shared", rlib, "-o", "pkg.so", "a.o", "-L/opt/foo/lib", "-lfoo", "-lz", rlib, "-lR", l, inc },
        try argv(c, .c, &.{ "-shared", rlib, "-o", "pkg.so", "a.o", "-L/opt/foo/lib", "-lfoo", "-lz", rlib, "-lR" }),
    );
    // configure's ac_link
    try expectArgs(
        pre_link ++ &[_][]const u8{ "-std=gnu23", "-o", "conftest", "-O2", "conftest.c", "-lz", l, inc },
        try argv(c, .c, &.{ "-std=gnu23", "-o", "conftest", "-O2", "conftest.c", "-lz" }),
    );
    // no -o (a.out); -lomp last
    try expectArgs(pre_link ++ &[_][]const u8{ "-O2", "-fopenmp", "test-omp.c", l, inc, "-lomp" }, try argv(c, .c, &.{ "-O2", "-fopenmp", "test-omp.c" }));
    // the caller's own -lomp: none added; -fopenmp-simd counts (a substring, as in the shims)
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o", "dt.so", "a.o", "-fopenmp", "-lomp", l, inc }, try argv(c, .c, &.{ "-shared", "-o", "dt.so", "a.o", "-fopenmp", "-lomp" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-fopenmp-simd", "-o", "p", "a.o", l, inc, "-lomp" }, try argv(c, .c, &.{ "-fopenmp-simd", "-o", "p", "a.o" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-Xlinker", "-o", "-Xlinker", "x", "a.o", l, inc }, try argv(c, .c, &.{ "-Xlinker", "-o", "-Xlinker", "x", "a.o" }));
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
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o", "z.so", "z.o", "-lz", l, rp, inc }, try argv(c, .c, &.{ "-shared", "-o", "z.so", "z.o", "-lz" }));
    // a package's own rpath and -L first (R2): its bundled libtbb.so.2
    // is found, at link and at load time, before the environment's
    try expectArgs(
        pre_link ++ &[_][]const u8{ "-shared", "-Ltbb/lib", "-Wl,-rpath,$ORIGIN/../lib", "-o", "p.so", "a.o", "-ltbb", l, rp, inc },
        try argv(c, .c, &.{ "-shared", "-Wl,-Ltbb/lib", "-Wl,-rpath,$ORIGIN/../lib", "-o", "p.so", "a.o", "-ltbb" }),
    );
    try expectArgs(pre ++ &[_][]const u8{ "-c", "z.c", inc }, try argv(c, .c, &.{ "-c", "z.c" }));
    // no include/ (the wheel's r_zig/R): -L only; no omp.h: no -lomp
    c.self_exe = try tree(&f, "wheel", false, false);
    const wl = f.fmt("-L{s}", .{f.path("wheel/lib")});
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-fopenmp", "-o", "p.so", "a.o", wl }, try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }));
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
        pre_link ++ &[_][]const u8{ "-shared", "-fopenmp", "-o", "p.so", "a.o", l, el, erp, inc, einc, "-lomp" },
        try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }),
    );
    // a bare copy of rzig: the extra environment alone
    c.self_exe = "/x/zig-out/bin/zig-cc";
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o", "p.so", "a.o", el, erp, einc }, try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o" }));
    // and none at all: the caller's arguments only, CONDA_PREFIX or not
    _ = f.env.swapRemove("R_ZIG_EXTRA_ENV");
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }, try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }));
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
    try expectArgs(&.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-c", "z.c", "-o", "z.o", "-idirafter", inc }, try argv(c, .c, &.{ "-c", "z.c", "-o", "z.o" }));
    try expectArgs(
        &.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-shared", "-fopenmp", "-o", "pkg.dll", "a.o", z, l, "-idirafter", inc, omp },
        try argv(c, .cxx, &.{ "-shared", "-fopenmp", "-o", "pkg.dll", "a.o", "-lz" }),
    );
    // the caller's -lomp, resolved the same way; none added
    try expectArgs(
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-shared", "-fopenmp", "-o", "pkg.dll", "a.o", omp, l, "-idirafter", inc },
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
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-shared", "-o", "pkg.dll", "a.o", l, f.path("d/libz.dll.a"), "-lc++" },
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
    const targets = [_]struct { os: Ctx.Os, target: Args, strip: Args = &.{} }{
        .{ .os = .linux, .target = &.{ "-target", linux_target }, .strip = &.{"-Wl,--strip-debug"} },
        .{ .os = .macos, .target = mac },
        .{ .os = .windows, .target = &.{} },
    };
    for (targets) |t| {
        c.os = t.os;
        const head: Args = &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" };
        // R CMD SHLIB's link of a package whose Makevars was written for
        // gcc (PKG_LIBS = -lgfortran -lquadmath), then $(FLIBS)
        try expectArgs(
            try mem.concat(c.arena, []const u8, &.{ head, t.target, t.strip, &.{ "-shared", "-o", "p.so", "a.o", "-L/r/lib", rt, "-lm" } }),
            try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o", "-L/r/lib", "-lgfortran", "-lquadmath", "-lflang_rt.runtime", "-lm" }),
        );
        // either alone
        for ([_][]const u8{ "-lgfortran", "-lquadmath" }) |l| {
            try expectArgs(
                try mem.concat(c.arena, []const u8, &.{ head, t.target, t.strip, &.{ "-shared", "-o", "p.so", "a.o", rt } }),
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
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" } ++ t ++ &[_][]const u8{ "-Wl,-soname,libx.so", "-shared", "-fopenmp", "-o", "libx.so", "-L/r", "-lR", "-lomp", l, rp, inc, "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "libx.so", "-L/r", "-lR", "-lomp", "-lR", "-lflang_rt.runtime", "-lomp" }),
    );
    // data.table: -lomp added once, then no second from the caller's; compiles get no SDK -L
    try expectArgs(
        &[_][]const u8{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" } ++ t ++ &[_][]const u8{ "-Xclang", "-fopenmp", "-c", "a.cpp", inc },
        try argv(c, .cxx, &.{ "-Xclang", "-fopenmp", "-c", "a.cpp" }),
    );
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-o", "p.so", "a.o", "-L/env/lib", "-lomp", "-fopenmp", l, rp, inc, "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-dynamiclib", "-o", "p.so", "a.o", "-L/env/lib", "-lomp", "-fopenmp", "-lomp" }),
    );
    // a standalone tree: its -L before the SDK's, so its libz wins
    c.self_exe = try tree(&f, "tree", false, false);
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-o", "z.so", "z.o", "-lz", f.fmt("-L{s}", .{f.path("tree/lib")}), "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-dynamiclib", "-o", "z.so", "z.o", "-lz", "-lz" }),
    );
}

test "every OS: -Wno-error=date-time always; -g0 unless the caller passes a -g option" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
        c.os = os;
        const plain = try argv(c, .c, &.{ "-O2", "-c", "a.c", "-o", "a.o" });
        try expectArgs(&.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" }, plain[0..5]);
        // links too: the same flags (a link's output does not change)
        try expectArgs(&.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" }, (try argv(c, .cxx, &.{ "-shared", "-o", "p.so", "a.o" }))[0..5]);
        for ([_][]const u8{ "-g", "-g0", "-g1", "-g3", "-ggdb", "-ggdb3", "-gdwarf-4", "-gdwarf", "-gline-tables-only", "-gsplit-dwarf", "-gz" }) |g| {
            const got = try argv(c, .c, &.{ "-O2", g, "-c", "a.c", "-o", "a.o" });
            try expectArgs(&.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time" }, got[0..4]);
            var n: usize = 0;
            for (got) |x| n += @intFromBool(mem.eql(u8, x, "-g0"));
            try testing.expectEqual(@as(usize, @intFromBool(mem.eql(u8, g, "-g0"))), n);
        }
    }
    // a caller's -Werror=date-time comes after ours, so it wins
    c.os = .linux;
    try expectArgs(pre ++ &[_][]const u8{ "-Werror=date-time", "-c", "a.c" }, try argv(c, .c, &.{ "-Werror=date-time", "-c", "a.c" }));
}

test "linux links without a -g option or an object with debug info: --strip-debug, after the SONAME and --undefined-version" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // a package's library and an executable (configure's, CMake's), C and C++
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o", "pkg.so", "a.o" }, try argv(c, .c, &.{ "-shared", "-o", "pkg.so", "a.o" }));
    try expectArgs(pre_link ++ &[_][]const u8{ "-o", "conftest", "conftest.c" }, try argv(c, .c, &.{ "-o", "conftest", "conftest.c" }));
    try testing.expectEqualStrings("-Wl,--strip-debug", (try argv(c, .cxx, &.{ "-shared", "-o", "p.so", "a.o" }))[pre.len]);
    // before the caller's arguments
    try expectArgs(
        pre ++ &[_][]const u8{ "-Wl,-soname,libx.so", "-Wl,--undefined-version", "-Wl,--strip-debug", "-shared", "-Wl,--version-script=v", "-o", "libx.so", "a.o" },
        try argv(c, .c, &.{ "-shared", "-Wl,--version-script=v", "-o", "libx.so", "a.o" }),
    );
    // any -g option on the link line keeps the debug info, -g0 included
    for ([_][]const u8{ "-g", "-g0", "-g3", "-ggdb", "-gdwarf-4", "-gline-tables-only", "-gsplit-dwarf" }) |g| {
        try expectArgs(
            &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-target", linux_target, "-shared", g, "-o", "p.so", "a.o" },
            try argv(c, .c, &.{ "-shared", g, "-o", "p.so", "a.o" }),
        );
    }
    // an input object with debug info keeps it: -g on the compile lines
    // only (pkgbuild's compile_dll(debug = TRUE)); strip.zig
    try f.write("dbg.o", @embedFile("testdata/f-g.o"), .default_file);
    const dbg = f.path("dbg.o");
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-o", "p.so", "a.o", dbg, "-lR" }, try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o", dbg, "-lR" }));
    // compiles: none
    for ([_][]const u8{ "-c", "-S", "-E", "-M", "-MM" }) |only| {
        try expectArgs(pre ++ &[_][]const u8{ only, "a.c" }, try argv(c, .c, &.{ only, "a.c" }));
    }
    // a command that links nothing gets it too; zig ignores it there
    try expectArgs(pre_link ++ &[_][]const u8{"--version"}, try argv(c, .c, &.{"--version"}));
    // macOS and Windows: none
    for ([_]Ctx.Os{ .macos, .windows }) |os| {
        c.os = os;
        for ([_]Args{ &.{ "-shared", "-o", "p.so", "a.o" }, &.{ "-o", "prog", "a.o" } }) |args| {
            for (try argv(c, .cxx, args)) |x| try testing.expect(!mem.eql(u8, x, "-Wl,--strip-debug"));
        }
    }
}

test "linux links with a version script: --undefined-version, before the caller's arguments" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // oneTBB's tbbmalloc
    try expectArgs(
        pre ++ &[_][]const u8{ "-Wl,-soname,libtbbmalloc.so.2", "-Wl,--undefined-version", "-Wl,--strip-debug", "-shared", "-Wl,--version-script=tbbmalloc.def", "-o", "libtbbmalloc.so.2", "a.o" },
        try argv(c, .c, &.{ "-shared", "-Wl,--version-script=tbbmalloc.def", "-o", "libtbbmalloc.so.2", "a.o" }),
    );
    // every spelling; the caller's own --no-undefined-version comes later and wins
    for ([_][]const u8{ "-Wl,--version-script,v.map", "-Wl,-version-script=v.map" }) |vs| {
        try expectArgs(pre ++ &[_][]const u8{ "-Wl,--undefined-version", "-Wl,--strip-debug", "-shared", vs, "-o", "p.so", "a.o" }, try argv(c, .c, &.{ "-shared", vs, "-o", "p.so", "a.o" }));
    }
    try expectArgs(
        pre ++ &[_][]const u8{ "-Wl,--undefined-version", "-Wl,--strip-debug", "-shared", "-Xlinker", "--version-script", "-Xlinker", "v.map", "-Wl,--no-undefined-version", "-o", "p.so" },
        try argv(c, .c, &.{ "-shared", "-Xlinker", "--version-script", "-Xlinker", "v.map", "-Wl,--no-undefined-version", "-o", "p.so" }),
    );
    // no version script, a compile, macOS and Windows: nothing
    try expectArgs(pre_link ++ &[_][]const u8{ "-shared", "-o", "p.so", "a.o" }, try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-Wl,--version-script=v.map", "-c", "a.c" }, try argv(c, .c, &.{ "-Wl,--version-script=v.map", "-c", "a.c" }));
    for ([_]Ctx.Os{ .macos, .windows }) |os| {
        c.os = os;
        for (try argv(c, .c, &.{ "-shared", "-Wl,--version-script=v.map", "-o", "p.so", "a.o" })) |x| try testing.expect(!mem.eql(u8, x, "-Wl,--undefined-version"));
    }
}

test "-march=armv<N>-a[+ext]: zig's -mcpu, after -mcpu=baseline; other -march values kept" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // arrow's CMake probe and aws-checksums
    try expectArgs(pre ++ &[_][]const u8{ "-mcpu=generic+v8a", "-c", "a.c", "-o", "a.o" }, try argv(c, .c, &.{ "-march=armv8-a", "-c", "a.c", "-o", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-O2", "-mcpu=generic+v8a+crc", "-c", "a.c", "-o", "a.o" }, try argv(c, .c, &.{ "-O2", "-march=armv8-a+crc", "-c", "a.c", "-o", "a.o" }));
    // a minor version, clang's extension names, no<x>
    try expectArgs(
        pre ++ &[_][]const u8{ "-mcpu=generic+v8_2a+neon-crypto+fullfp16+sve2_aes+rdm+rand+mte+spe+fp_armv8+dotprod", "-c", "a.c", "-o", "a.o" },
        try argv(c, .c, &.{ "-march=armv8.2-a+simd+nocrypto+fp16+sve2-aes+rdma+rng+memtag+profile+fp+dotprod", "-c", "a.c", "-o", "a.o" }),
    );
    try expectArgs(pre ++ &[_][]const u8{ "-mcpu=generic+v9a+sve2", "-c", "a.c", "-o", "a.o" }, try argv(c, .c, &.{ "-march=armv9-a++sve2+", "-c", "a.c", "-o", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-mcpu=generic+v8a+complxnum+jsconv+perfmon-specres2", "-c", "a.c" }, try argv(c, .c, &.{ "-march=armv8-a+fcma+jscvt+pmuv3+nopredres2", "-c", "a.c" }));
    // CPU names, other profiles, odd versions: kept
    const kept: Args = &.{ "-march=native", "-march=haswell", "-march=armv8-r", "-march=armv8-m.main", "-march=armv-a", "-march=armvx-a", "-march=", "-march", "-c", "a.c", "-o", "a.o" };
    try expectArgs(try mem.concat(c.arena, []const u8, &.{ pre, kept }), try argv(c, .c, kept));
    // macOS: after the baseline (apple-m1 on arm64), so the package's wins
    c.os = .macos;
    const got = try argv(c, .cxx, &.{ "-march=armv8-a+crc", "-c", "a.cpp", "-o", "a.o" });
    try testing.expectEqualStrings("-mcpu=baseline", got[2]);
    try expectArgs(&.{ "-mcpu=generic+v8a+crc", "-c", "a.cpp", "-o", "a.o" }, got[got.len - 5 ..]);
    // -Xarch_<arch>'s value is clang's: abseil's CMake on macOS, kept, and
    // so is a -mtune there
    const xarch: Args = &.{ "-Xarch_x86_64", "-maes", "-Xarch_arm64", "-march=armv8-a+crypto", "-Xarch_arm64", "-mtune=apple-m1", "-c", "a.cpp", "-o", "a.o" };
    const got_x = try argv(c, .cxx, xarch);
    try expectArgs(xarch, got_x[got_x.len - xarch.len ..]);
}

test "linker options zig cannot take, through the whole line" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // RcppParallel's bundled TBB through CMake, then its PKG_LIBS
    try expectArgs(
        pre ++ &[_][]const u8{ "-Wl,-soname,libtbb.so.2", "-Wl,--undefined-version", "-Wl,--strip-debug", "-shared", "-Wl,--version-script=tbb.def", "-o", "libtbb.so.2", "a.o" },
        try argv(c, .c, &.{ "-shared", "-Xlinker", "--dependency-file=CMakeFiles/tbb.dir/link.d", "-Wl,--version-script=tbb.def", "-o", "libtbb.so.2", "a.o" }),
    );
    try expectArgs(
        pre_link ++ &[_][]const u8{ "-shared", "-o", "RcppParallel.so", "a.o", "-Ltbb/build/lib_release", "-ltbb", "-ltbbmalloc" },
        try argv(c, .c, &.{ "-shared", "-o", "RcppParallel.so", "a.o", "-Wl,-Ltbb/build/lib_release", "-ltbb", "-ltbbmalloc" }),
    );
    // StanHeaders' Makevars.win
    c.os = .windows;
    try expectArgs(
        &.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-shared", "-o", "StanHeaders.dll", "a.o" },
        try argv(c, .cxx, &.{ "-shared", "-Wl,--allow-multiple-definition", "-o", "StanHeaders.dll", "a.o" }),
    );
}

test "every OS: an archive input without zig's extension goes as a copy named .a" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    try f.write("deps/v8_monolith", "!<arch>\nmember data", .default_file);
    // V8's link line on macOS
    const got = try argv(c, .cxx, &.{ "-dynamiclib", "-o", "V8.so", "a.o", f.path("deps/v8_monolith"), "-lR" });
    try testing.expectEqualStrings(f.path("cache/r-zig/archive-7c6d5f344466ae401a4452a2a4a40ec7/v8_monolith.a"), got[got.len - 2]);
    for ([_]Ctx.Os{ .linux, .windows }) |os| {
        c.os = os;
        const l = try argv(c, .c, &.{ "-shared", "-o", "p.so", f.path("deps/v8_monolith") });
        try testing.expect(mem.endsWith(u8, l[l.len - 1], "/v8_monolith.a"));
    }
}

test "Windows: -c without -o names <stem>.o, as MinGW gcc" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    // QuickJSR
    try expectArgs(
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-O2", "-c", "quickjs/libquickjs.c", "-o", "libquickjs.o" },
        try argv(c, .c, &.{ "-O2", "-c", "quickjs/libquickjs.c" }),
    );
    // unix: zig's default is <stem>.o already
    c.os = .linux;
    try expectArgs(pre ++ &[_][]const u8{ "-O2", "-c", "a.c" }, try argv(c, .c, &.{ "-O2", "-c", "a.c" }));
}

/// A zig stand-in for dso_fini.zig: answers `version`, writes its -o file.
fn fakeZig(f: *testutil.Fixture) ![]const u8 {
    try f.write("bin/zig", "#!/bin/sh\n[ \"$1\" = version ] && { echo 0.16.0; exit 0; }\no=; p=; for a in \"$@\"; do [ \"$p\" = -o ] && o=$a; p=$a; done\n: > \"$o\"\n", .fromMode(0o755));
    return f.path("bin/zig");
}

test "linux shared links: the finalization object first among the inputs; nothing elsewhere" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for zig
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    c.zig = &.{try fakeZig(&f)};
    const fini = (try dso_fini.object(c, linux_target)).?;
    try testing.expect(mem.startsWith(u8, fini, f.path("cache/r-zig/dso-fini-")));
    // after the SONAME and --undefined-version, before the caller's
    // arguments (and an -x it may give)
    try expectArgs(pre_link ++ &[_][]const u8{ fini, "-shared", "-o", "pkg.so", "a.o" }, try argv(c, .c, &.{ "-shared", "-o", "pkg.so", "a.o" }));
    try expectArgs(
        pre ++ &[_][]const u8{ "-Wl,-soname,libx.so", "-Wl,--undefined-version", "-Wl,--strip-debug", fini, "-x", "c", "-shared", "-Wl,--version-script=v", "-o", "libx.so", "x.c" },
        try argv(c, .c, &.{ "-x", "c", "-shared", "-Wl,--version-script=v", "-o", "libx.so", "x.c" }),
    );
    // executables, links that bring their own startup files, compiles
    for ([_]Args{
        &.{ "-o", "prog", "a.o" },
        &.{ "-shared", "-nostartfiles", "-o", "p.so", "crtbeginS.o", "a.o", "crtendS.o" },
        &.{ "-shared", "-nostdlib", "-o", "p.so", "a.o" },
    }) |args| try expectArgs(try mem.concat(c.arena, []const u8, &.{ pre_link, args }), try argv(c, .c, args));
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-c", "a.c", "-o", "a.o" }, try argv(c, .c, &.{ "-shared", "-c", "a.c", "-o", "a.o" }));
    // macOS and Windows: none
    for ([_]Ctx.Os{ .macos, .windows }) |os| {
        c.os = os;
        for (try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o" })) |x| try testing.expect(mem.find(u8, x, "dso_fini") == null);
    }
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "Windows links: the CFG stub before the caller's arguments; nothing elsewhere" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for zig
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("cache"));
    c.zig = &.{try fakeZig(&f)};
    const stub = (try cfguard.object(c)).?;
    try testing.expect(mem.startsWith(u8, stub, f.path("cache/r-zig/cfguard-")));
    const head: Args = &.{ "c++", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" };
    // magick's link, and an executable (CMake's)
    try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, &.{ stub, "-shared", "-s", "-o", "magick.dll", "tmp.def", "a.o", "-lrsvg-2" } }), try argv(c, .cxx, &.{ "-shared", "-s", "-o", "magick.dll", "tmp.def", "a.o", "-lrsvg-2" }));
    try expectArgs(try mem.concat(c.arena, []const u8, &.{ head, &.{ stub, "-o", "cmTC_1.exe", "a.obj" } }), try argv(c, .cxx, &.{ "-o", "cmTC_1.exe", "a.obj" }));
    // compiles, windres' preprocessing, --version
    for ([_]Args{
        &.{ "-c", "a.cpp", "-o", "a.o" },
        &.{ "-E", "-xc", "-DRC_INVOKED", "r.rc" },
        &.{"--version"},
    }) |args| for (try argv(c, .cxx, args)) |x| try testing.expect(mem.find(u8, x, "cfguard") == null);
    // linux and macOS: none
    for ([_]Ctx.Os{ .linux, .macos }) |os| {
        c.os = os;
        for (try argv(c, .c, &.{ "-shared", "-o", "p.so", "a.o" })) |x| try testing.expect(mem.find(u8, x, "cfguard") == null);
    }
    try testing.expectEqualStrings("", f.takeWarnings());
}
