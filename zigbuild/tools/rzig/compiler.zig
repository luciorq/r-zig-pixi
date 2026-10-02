//! zig-cc and zig-cxx (gcc.exe and g++.exe on Windows): what the bash
//! shims did to the caller's arguments, in their order. The steps every OS
//! shares are here; the macOS and Windows ones are darwin.zig and
//! windows.zig, the Fortran runtime flang_rt.zig. Every step works around
//! a zig or conda-forge quirk; the comments say which.
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
///   cc|c++ -fno-sanitize=undefined <target> <soname> <caller's, rewritten> <OpenMP> <SDK -L>
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
        // zig cc's native Windows target is already x86_64-windows-gnu
        .windows, .other => {},
    }

    var args = try flang_rt.resolve(ctx, caller);
    if (ctx.os == .windows) args = try windows.libs(ctx, args);
    const soname = try sonameFlag(ctx, args);
    var omp = try openmpFlags(ctx, args);
    if (ctx.os == .macos) {
        // OpenMP's flags join the caller's after the -l de-duplication
        args = try mem.concat(a, []const u8, &.{ try darwin.dedupLibs(ctx, args), omp });
        omp = &.{};
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
    try out.appendSlice(a, before);
    if (soname) |s| try out.append(a, s);
    try out.appendSlice(a, args);
    try out.appendSlice(a, omp);
    try out.appendSlice(a, link_last);
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

/// zig cc does -fopenmp codegen but bundles neither omp.h nor libomp and
/// won't link it: wire in llvm-openmp's, from the environment R lives in
/// (environment.zig).
fn openmpFlags(ctx: *Ctx, args: Args) !Args {
    if (!cmdline.anyContains(args, "-fopenmp")) return &.{};
    const prefix = (try environment.forOpenmp(ctx)) orelse return &.{};
    const lib = try ctx.fmt("{s}/lib", .{prefix});
    var out: std.ArrayList([]const u8) = .empty;
    try out.append(ctx.arena, try ctx.fmt("-I{s}/include", .{prefix}));
    if (cmdline.compileOnly(args)) return out.items;
    // Some packages (data.table) probe OpenMP themselves and put -lomp in
    // PKG_LIBS on top of R's SHLIB_OPENMP_CFLAGS. A second libomp would be
    // a duplicate LC_LOAD_DYLIB, which newer macOS dyld refuses to load.
    const caller_links = for (args) |x| {
        if (mem.eql(u8, x, "-lomp") or mem.endsWith(u8, x, "/libomp.lib")) break true;
    } else false;
    if (!caller_links) {
        // zig's -l search misses this name on Windows
        const omp_lib = try ctx.fmt("{s}/libomp.lib", .{lib});
        if (ctx.isFile(omp_lib)) {
            try out.append(ctx.arena, omp_lib);
        } else {
            try out.appendSlice(ctx.arena, &.{ try ctx.fmt("-L{s}", .{lib}), "-lomp" });
        }
    } else {
        // The caller's -lomp still needs the directory: Makeconf's LDFLAGS
        // has it, but a probe that calls $CC directly does not, and
        // data.table's macOS probe (PKG_LIBS=-lomp) then built without
        // OpenMP (found 2026-09-30 on a staged slim tree).
        try out.append(ctx.arena, try ctx.fmt("-L{s}", .{lib}));
    }
    return out.items;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;
const pre: Args = &.{ "cc", "-fno-sanitize=undefined", "-target", linux_target };

test "linux: glibc floor pinned, UBSan off, the caller's arguments kept" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try testing.expect(mem.endsWith(u8, linux_target, "-linux-gnu.2.17"));
    try expectArgs(pre ++ &[_][]const u8{ "-std=gnu23", "-c", "a.c", "-o", "a.o" }, try argv(&f.ctx, .c, &.{ "-std=gnu23", "-c", "a.c", "-o", "a.o" }));
    try expectArgs(&.{ "c++", "-fno-sanitize=undefined", "-target", linux_target, "-c", "a.cpp" }, try argv(&f.ctx, .cxx, &.{ "-c", "a.cpp" }));
    // nothing is de-duplicated off macOS
    try expectArgs(pre ++ &[_][]const u8{ "-lm", "-lm" }, try argv(&f.ctx, .c, &.{ "-lm", "-lm" }));
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

test "OpenMP from CONDA_PREFIX: include always, libomp only when linking and not already linked" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("CONDA_PREFIX", "/env");
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp", "-c", "a.c", "-I/env/include" }, try argv(c, .c, &.{ "-fopenmp", "-c", "a.c" }));
    try expectArgs(pre ++ &[_][]const u8{ "-M", "-fopenmp", "a.c", "-I/env/include" }, try argv(c, .c, &.{ "-M", "-fopenmp", "a.c" }));
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp", "a.o", "-I/env/include", "-L/env/lib", "-lomp" }, try argv(c, .c, &.{ "-fopenmp", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp", "a.o", "-lomp", "-I/env/include", "-L/env/lib" }, try argv(c, .c, &.{ "-fopenmp", "a.o", "-lomp" }));
    // a substring: -fopenmp-simd counts, as in the shims
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp-simd", "a.o", "-I/env/include", "-L/env/lib", "-lomp" }, try argv(c, .c, &.{ "-fopenmp-simd", "a.o" }));
    try expectArgs(pre ++ &[_][]const u8{ "-lomp", "a.o" }, try argv(c, .c, &.{ "-lomp", "a.o" }));
    _ = f.env.swapRemove("CONDA_PREFIX");
    try expectArgs(pre ++ &[_][]const u8{ "-fopenmp", "a.o" }, try argv(c, .c, &.{ "-fopenmp", "a.o" }));
}

test "OpenMP from the tree rzig is installed in, when it has omp.h" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("CONDA_PREFIX", "/env");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    try f.touch("tree/include/omp.h");
    const inc = f.fmt("-I{s}", .{f.path("tree/include")});
    const l = f.fmt("-L{s}", .{f.path("tree/lib")});
    try expectArgs(pre ++ &[_][]const u8{ "-shared", "-fopenmp", "-o", "p.so", "a.o", inc, l, "-lomp" }, try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }));
}

test "Windows OpenMP: libomp.lib by path, also a caller's -lomp resolved to it" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.touch("env/Library/lib/libomp.lib");
    try f.env.put("CONDA_PREFIX", f.path("env"));
    const inc = f.fmt("-I{s}", .{f.path("env/Library/include")});
    const omp = f.path("env/Library/lib/libomp.lib");
    try expectArgs(&.{ "c++", "-fno-sanitize=undefined", "-fopenmp", "a.o", inc, omp }, try argv(&f.ctx, .cxx, &.{ "-fopenmp", "a.o" }));
    const l = f.fmt("-L{s}", .{f.path("env/Library/lib")});
    try expectArgs(&.{ "cc", "-fno-sanitize=undefined", "-fopenmp", l, omp, inc, l }, try argv(&f.ctx, .c, &.{ "-fopenmp", l, "-lomp" }));
    // installed: <prefix>/Library/lib/R/bin/toolchain/gcc.exe
    try f.touch("env/Library/include/omp.h");
    f.ctx.self_exe = f.path("env/Library/lib/R/bin/toolchain/gcc.exe");
    _ = f.env.swapRemove("CONDA_PREFIX");
    try expectArgs(&.{ "cc", "-fno-sanitize=undefined", "-fopenmp", "-c", "a.c", inc }, try argv(&f.ctx, .c, &.{ "-fopenmp", "-c", "a.c" }));
}

test "Windows: no target, the Fortran runtime before the -l lookup" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.env.put("PATH", f.path("nothing"));
    try f.touch("d/libz.dll.a");
    const l = f.fmt("-L{s}", .{f.path("d")});
    try expectArgs(
        &.{ "cc", "-fno-sanitize=undefined", "-shared", "-o", "pkg.dll", "a.o", l, f.path("d/libz.dll.a"), "-lc++" },
        try argv(&f.ctx, .c, &.{ "-shared", "-o", "pkg.dll", "a.o", l, "-lz", "-lflang_rt.runtime", "-lc++" }),
    );
}

test "macOS: target, SONAME, -l de-duplicated, OpenMP merged, SDK -L last on links only" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for xcrun
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const c = &f.ctx;
    try f.write("bin/xcrun", "#!/bin/sh\necho /SDK\n", .fromMode(0o755));
    c.xcrun = f.path("bin/xcrun");
    try f.env.put("CONDA_PREFIX", "/env");
    try f.env.put("PATH", f.path("nothing"));
    const t: Args = &.{ "-target", (if (builtin.cpu.arch == .aarch64) "aarch64" else "x86_64") ++ "-native.13.0", "-F/SDK/System/Library/Frameworks" };
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined" } ++ t ++ &[_][]const u8{ "-Wl,-soname,libx.so", "-shared", "-fopenmp", "-o", "libx.so", "-L/r", "-lR", "-lomp", "-I/env/include", "-L/env/lib", "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-shared", "-fopenmp", "-o", "libx.so", "-L/r", "-lR", "-lomp", "-lR", "-lflang_rt.runtime", "-lomp" }),
    );
    // data.table: no -lomp from us when the caller has one; compiles get no SDK -L
    try expectArgs(
        &[_][]const u8{ "c++", "-fno-sanitize=undefined" } ++ t ++ &[_][]const u8{ "-Xclang", "-fopenmp", "-c", "a.cpp", "-I/env/include" },
        try argv(c, .cxx, &.{ "-Xclang", "-fopenmp", "-c", "a.cpp" }),
    );
    try expectArgs(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-o", "p.so", "a.o", "-L/env/lib", "-lomp", "-fopenmp", "-I/env/include", "-L/env/lib", "-L/SDK/usr/lib" },
        try argv(c, .c, &.{ "-dynamiclib", "-o", "p.so", "a.o", "-L/env/lib", "-lomp", "-fopenmp", "-lomp" }),
    );
}
