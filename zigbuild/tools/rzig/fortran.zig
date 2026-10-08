//! zig-fc (zig-fc.exe on Windows): R's Fortran compiler, Makeconf's FC
//! (feat-no-host-paths F3c). It runs the flang on PATH, adding what the
//! toolchain owns:
//!
//! - A shared link of objects (`-shared` or `-dynamiclib` as a word, and
//!   no source file among the inputs) goes through zig cc, exactly as
//!   zig-cc links (compiler.zig: the baseline CPU, no -mtune=; the glibc
//!   floor, or the macOS target and SDK; the SONAME; the environment's -L
//!   and a conda env's rpath; OpenMP; Windows' import libraries), with
//!   the Fortran runtime appended, which flang_rt.zig resolves to the
//!   static archive of that flang. This is R's USE_FC_TO_LINK: SHLIB_LD =
//!   $(SHLIB_FCLD) = $(FC), and install.R takes $(FLIBS) and $(LIBR) off
//!   that link, leaving the runtime to the Fortran driver. flang's own
//!   driver links with the system linker and the runtime it finds there:
//!   "cannot find -lflang_rt.runtime" (conda-forge's linux-64 flang,
//!   measured 2026-10-02), or a runtime found through its config file,
//!   which also records an absolute rpath into the env (flang-zig's
//!   flang.cfg, `-Wl,-rpath,<CFGDIR>/../lib`; measured on linux-64
//!   2026-10-03).
//!   The runtime goes last, where FLIBS sits on an R CMD SHLIB link; lld
//!   and zig's Mach-O linker resolve archives in any order anyway. R's own
//!   library is left off too: Fortran that calls into R from such a
//!   package needs `PKG_LIBS = $(LIBR)` on Windows (PE resolves every
//!   symbol at link time), as it did with upstream's gfortran.
//! - Everything else, compiles (.f .f90 .F ...), -E, the --version and -v
//!   probes, and configure's mixed source+link calls, runs flang with the
//!   caller's arguments, on macOS after the floor (floors.zig), so the
//!   caller's own -mmacosx-version-min still wins. flang compiles for its
//!   target's baseline CPU unless told otherwise (target-cpu x86-64 on
//!   linux-64 and win-64, measured 2026-10-06), which zig-cc gets from
//!   -mcpu=baseline; flang refuses that flag ("unsupported option
//!   '-mcpu='" on x86_64), and needs none. A -mtune= stays: flang only
//!   tunes for that CPU (target-cpu still x86-64), which zig cc does not
//!   (compiler.zig dropTune). A mixed call stays flang's: splitting it
//!   into compiles and a zig link is the kind of trickery the toolchain
//!   avoids, and a configure probe's executable is no package's library.
//!
//! No flang on PATH: nothing runs; zig-fc says so (no_flang) and exits
//! 127, as a shell does for a command it cannot find (main.zig). FC names
//! zig-fc whether or not a flang is installed, so a test such as
//! `Sys.which(<R CMD config FC>)` finds a file either way: this message,
//! at the first Fortran compile, is where a missing flang shows. It names
//! the remedy itself, not R_ZIG_TOOLCHAIN_HINT: zig-fc ships only in the
//! toolchain, so that hint (install the toolchain) could never help here.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const compiler = @import("compiler.zig");
const flang_rt = @import("flang_rt.zig");
const floors = @import("floors.zig");
const Args = cmdline.Args;

/// What zig-fc runs for the caller's arguments. error.NoFlang, after a
/// message, when there is no flang on PATH.
pub fn command(ctx: *Ctx, caller: Args) !Ctx.Command {
    const flang = (try flang_rt.flang(ctx)) orelse {
        ctx.warn("{s}", .{no_flang});
        return error.NoFlang;
    };
    if (sharedLink(caller)) {
        return .{ .zig = try compiler.argv(ctx, .c, try mem.concat(ctx.arena, []const u8, &.{ caller, flibs(ctx.os) })) };
    }
    const floor: Args = if (ctx.os == .macos) &.{floors.macos_min_flag} else &.{};
    return .{ .program = try mem.concat(ctx.arena, []const u8, &.{ &.{flang}, floor, caller }) };
}

/// What zig-fc says with no flang on PATH. The toolchain is installed
/// wherever zig-fc runs, so the remedy is flang alone: r-zig-toolchain's
/// conda package depends on one, which is on PATH once its environment
/// is activated; the wheels and the standalone tree ship none.
const no_flang = "no flang on PATH: compiling Fortran needs an LLVM flang on PATH " ++
    "(in a conda env, r-zig-toolchain brings one: activate that env; " ++
    "the wheels and the standalone tree bring none: install LLVM flang)";

/// The Fortran runtime as Makeconf's FLIBS spells it (build.zig): flang's,
/// plus libm; on Windows plus libc++ instead, since the runtime is C++
/// there and PE refuses unresolved symbols.
pub fn flibs(os: Ctx.Os) Args {
    return switch (os) {
        .windows => &.{ flang_rt.flag, "-lc++" },
        else => &.{ flang_rt.flag, "-lm" },
    };
}

/// A shared link of objects: `-shared` or `-dynamiclib` as a word, no
/// compile-only flag, no source file among the inputs, and no `-x` (which
/// makes any input a source).
fn sharedLink(args: Args) bool {
    if (!cmdline.anyWord(args, "-shared") and !cmdline.anyWord(args, "-dynamiclib")) return false;
    if (cmdline.compileOnly(args)) return false;
    for (args) |x| {
        if (mem.startsWith(u8, x, "-x") or isSource(x)) return false;
    }
    return true;
}

/// A file a compiler driver would compile, by its extension: Fortran's
/// (fixed and free form, preprocessed or not) and the C family's.
fn isSource(x: []const u8) bool {
    if (x.len == 0 or x[0] == '-') return false;
    const base = if (mem.findLastAny(u8, x, "/\\")) |i| x[i + 1 ..] else x;
    const dot = mem.findScalarLast(u8, base, '.') orelse return false;
    return source_ext.has(base[dot + 1 ..]);
}

const source_ext = std.StaticStringMap(void).initComptime(.{
    // Fortran (flang's driver)
    .{"f"},   .{"for"}, .{"ftn"}, .{"fpp"}, .{"f77"}, .{"f90"}, .{"f95"}, .{"f03"}, .{"f08"}, .{"cuf"},
    .{"F"},   .{"FOR"}, .{"FTN"}, .{"FPP"}, .{"F77"}, .{"F90"}, .{"F95"}, .{"F03"}, .{"F08"}, .{"CUF"},
    // the C family, assembler, LLVM IR (clang's)
    .{"c"},   .{"i"},   .{"cc"},  .{"cp"},  .{"cpp"}, .{"cxx"}, .{"c++"}, .{"C"},   .{"CC"},  .{"CPP"},
    .{"CXX"}, .{"ii"},  .{"m"},   .{"mi"},  .{"mm"},  .{"mii"}, .{"M"},   .{"s"},   .{"S"},   .{"sx"},
    .{"cu"},  .{"ll"},  .{"bc"},
});

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

fn expectProgram(expected: Args, cmd: Ctx.Command) !void {
    switch (cmd) {
        .program => |p| try expectArgs(expected, p),
        .zig => |z| {
            std.debug.print("expected flang, got zig: {any}\n", .{z});
            return error.TestExpectedProgram;
        },
    }
}

fn expectZig(expected: Args, cmd: Ctx.Command) !void {
    switch (cmd) {
        .zig => |z| try expectArgs(expected, z),
        .program => |p| {
            std.debug.print("expected zig, got: {any}\n", .{p});
            return error.TestExpectedZig;
        },
    }
}

/// An executable flang on PATH (flang.exe on a Windows host), which these
/// cases never run. Its path, as zig-fc finds it.
fn plainFlang(f: *testutil.Fixture) ![]const u8 {
    if (builtin.os.tag == .windows) try f.touch("bin/flang.exe") else try f.touchExe("bin/flang");
    try f.env.put("PATH", f.path("bin"));
    return (try flang_rt.flang(&f.ctx)).?;
}

test "compiles, -E and probes: flang with the caller's arguments, after the floor on macOS" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const fc = try plainFlang(&f);
    try testing.expectEqualStrings("-mmacosx-version-min=13.0", floors.macos_min_flag);
    const calls = [_]Args{
        &.{ "-fpic", "-O2", "-c", "a.f", "-o", "a.o" },
        &.{ "-O2", "-c", "m.f90", "-o", "m.o" },
        &.{ "-I/r/include", "-DX=1", "-c", "p.F", "-o", "p.o" },
        // flang tunes for -mtune's CPU only, unlike zig cc: kept
        &.{ "-mtune=native", "-O2", "-c", "t.f90", "-o", "t.o" },
        &.{ "-E", "p.F90" },
        &.{"--version"},
        &.{"-v"},
        &.{},
    };
    for (calls) |call| {
        for ([_]Ctx.Os{ .linux, .windows }) |os| {
            c.os = os;
            try expectProgram(try mem.concat(c.arena, []const u8, &.{ &.{fc}, call }), try command(c, call));
        }
        c.os = .macos;
        try expectProgram(try mem.concat(c.arena, []const u8, &.{ &.{ fc, "-mmacosx-version-min=13.0" }, call }), try command(c, call));
    }
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "mixed source+link calls, -x, compile-only and executable links stay flang's" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const fc = try plainFlang(&f);
    const calls = [_]Args{
        // configure's AC_LANG(Fortran) link probe
        &.{ "-o", "conftest", "-O2", "conftest.f" },
        &.{ "-shared", "-o", "p.so", "a.f", "b.o" },
        &.{ "-shared", "-fpic", "-o", "libx.so", "x.F90" },
        &.{ "-dynamiclib", "-o", "p.so", "/src/dir.v2/a.f95" },
        &.{ "-shared", "-o", "p.dll", "C:\\src\\a.f08" },
        &.{ "-shared", "-o", "p.so", "a.o", "glue.c" },
        &.{ "-shared", "-x", "f95", "-o", "p.so", "a" },
        &.{ "-shared", "-xf95", "-o", "p.so", "a" },
        &.{ "-shared", "-c", "a.o" },
        // an executable of objects: flang's own driver, as today
        &.{ "-o", "prog", "a.o", "b.o" },
        // a word inside another argument is no flag
        &.{ "-Wl,-shared", "-o", "p.so", "a.o" },
    };
    for ([_]Ctx.Os{ .linux, .windows }) |os| {
        c.os = os;
        for (calls) |call| try expectProgram(try mem.concat(c.arena, []const u8, &.{ &.{fc}, call }), try command(c, call));
    }
    c.os = .macos;
    for (calls) |call| try expectProgram(try mem.concat(c.arena, []const u8, &.{ &.{ fc, floors.macos_min_flag }, call }), try command(c, call));
    // the source test, by itself
    for ([_][]const u8{ "a.f", "a.FOR", "dir/a.f03", "a.b.F95", "x.cpp", "y.c", "z.S" }) |x| try testing.expect(isSource(x));
    for ([_][]const u8{ "a.o", "a.so", "p.dll", "tmp.def", "-fa.f", "f", "dir.f/a", "liba.a", "x.mod", "" }) |x| try testing.expect(!isSource(x));
}

/// A flang on PATH that answers -print-resource-dir with an LLVM tree
/// holding the static runtime for `triple`. The archive's path.
fn runtimeFlang(f: *testutil.Fixture, triple: []const u8) ![]const u8 {
    const rd = f.path("llvm/lib/clang/23");
    const a = f.fmt("{s}/lib/{s}/libflang_rt.runtime.a", .{ rd, triple });
    try f.touch(f.fmt("llvm/lib/clang/23/lib/{s}/libflang_rt.runtime.a", .{triple}));
    try f.write("bin/flang", f.fmt("#!/bin/sh\n[ \"$1\" = -print-resource-dir ] && printf '%s\\n' '{s}'\n", .{rd}), .fromMode(0o755));
    try f.env.put("PATH", f.path("bin"));
    return a;
}

const linux_target = @tagName(builtin.cpu.arch) ++ "-linux-gnu." ++ floors.majorMinor(floors.glibc);

test "linux: a shared link of objects goes through zig cc, as zig-cc's, with the static runtime and -lm" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for flang
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const a = try runtimeFlang(&f, "x86_64-unknown-linux-gnu");
    // installed in a conda env: its -L and rpath, as zig-cc adds them
    try f.tmp.dir.createDirPath(testing.io, "env/lib/R/bin/toolchain");
    try f.tmp.dir.createDirPath(testing.io, "env/conda-meta");
    c.self_exe = f.path("env/lib/R/bin/toolchain/zig-fc");
    const l = f.fmt("-L{s}", .{f.path("env/lib")});
    const rp = f.fmt("-Wl,-rpath,{s}", .{f.path("env/lib")});
    const pre: Args = &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-target", linux_target };
    // R CMD SHLIB under USE_FC_TO_LINK: $(SHLIB_FCLD) $(SHLIB_FCLDFLAGS)
    // $(LIBR0) $(LDFLAGS) -o pkg.so <objects> $(PKG_LIBS) $(SHLIB_LIBADD)
    try expectZig(
        pre ++ &[_][]const u8{ "-shared", "-L/r/lib", l, rp, "-o", "pkg.so", "a.o", "b.o", "-L/opt/lib", "-lfoo", a, "-lm" },
        try command(c, &.{ "-shared", "-L/r/lib", "-o", "pkg.so", "a.o", "b.o", "-L/opt/lib", "-lfoo" }),
    );
    // a package that also asks for $(FLIBS): the runtime once; a SONAME for lib*.so
    try expectZig(
        pre ++ &[_][]const u8{ "-Wl,-soname,libfx.so", "-shared", l, rp, "-o", "libfx.so", "a.o", a, "-lm", "-lm" },
        try command(c, &.{ "-shared", "-o", "libfx.so", "a.o", "-lflang_rt.runtime", "-lm" }),
    );
    // a -mtune= on the link (zig cc's: dropped, compiler.zig dropTune)
    try expectZig(
        pre ++ &[_][]const u8{ "-shared", "-O2", l, rp, "-o", "pkg.so", "a.o", a, "-lm" },
        try command(c, &.{ "-shared", "-O2", "-mtune=native", "-o", "pkg.so", "a.o" }),
    );
    // OpenMP, as zig-cc: -lomp when an environment has omp.h
    try f.touch("env/include/omp.h");
    try expectZig(
        pre ++ &[_][]const u8{ "-shared", "-fopenmp", l, rp, "-o", "p.so", "a.o", a, "-lm", f.fmt("-I{s}", .{f.path("env/include")}), "-lomp" },
        try command(c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }),
    );
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "macOS: the shared link has the target, the SDK and the runtime; -dynamiclib counts" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins for flang and xcrun
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const c = &f.ctx;
    const a = try runtimeFlang(&f, "darwin");
    try f.write("xcrun", "#!/bin/sh\necho /SDK\n", .fromMode(0o755));
    c.xcrun = f.path("xcrun");
    const t: Args = &.{ "-target", (if (builtin.cpu.arch == .aarch64) "aarch64" else "x86_64") ++ "-native.13.0", "-F/SDK/System/Library/Frameworks" };
    // macOS SHLIB_FCLDFLAGS; the caller's -lm is kept and the runtime's
    // second one dropped (darwin.dedupLibs), the SDK's -L last
    try expectZig(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-Wl,-headerpad_max_install_names", "-undefined", "dynamic_lookup", "-L/r/lib", "-o", "p.so", "a.o", "-lflangish", "-lm", a, "-L/SDK/usr/lib" },
        try command(c, &.{ "-dynamiclib", "-Wl,-headerpad_max_install_names", "-undefined", "dynamic_lookup", "-L/r/lib", "-o", "p.so", "a.o", "-lflangish", "-lm" }),
    );
    try expectZig(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-o", "p.so", "a.o", a, "-lm", "-L/SDK/usr/lib" },
        try command(c, &.{ "-dynamiclib", "-o", "p.so", "a.o" }),
    );
}

test "Windows: the shared link resolves -l to import libraries, adds -lc++, no .exe; executables stay flang's" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for flang
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    const a = try runtimeFlang(&f, "x86_64-w64-windows-gnu");
    try f.touch("d/libz.dll.a");
    const l = f.fmt("-L{s}", .{f.path("d")});
    // winshlib.mk: $(SHLIB_LD) $(SHLIB_LDFLAGS) $(LDFLAGS) $(DLLFLAGS) -o pkg.dll tmp.def <objects> $(ALL_LIBS)
    try expectZig(
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-shared", "-O2", "-s", "-static-libgcc", "-o", "pkg.dll", "tmp.def", "a.o", l, f.path("d/libz.dll.a"), a, "-lc++" },
        try command(c, &.{ "-shared", "-O2", "-s", "-static-libgcc", "-o", "pkg.dll", "tmp.def", "a.o", l, "-lz" }),
    );
    try expectProgram(&.{ f.path("bin/flang"), "-o", "px", "a.o" }, try command(c, &.{ "-o", "px", "a.o" }));
}

test "no flang on PATH: nothing runs, the message names flang's remedy, not the toolchain hint" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("PATH", f.path("nothing"));
    const msg = "rzig-test: no flang on PATH: compiling Fortran needs an LLVM flang on PATH " ++
        "(in a conda env, r-zig-toolchain brings one: activate that env; " ++
        "the wheels and the standalone tree bring none: install LLVM flang)\n";
    for ([_]Args{ &.{ "-c", "a.f" }, &.{"--version"}, &.{ "-shared", "-o", "p.so", "a.o" } }) |call| {
        try testing.expectError(error.NoFlang, command(c, call));
        try testing.expectEqualStrings(msg, f.takeWarnings());
    }
    // R_ZIG_TOOLCHAIN_HINT (install the toolchain zig-fc came in) changes nothing
    for ([_][]const u8{
        "pip install r-zig-toolchain (same Python environment as r-zig)",
        "add the r-zig-toolchain package to this environment",
    }) |hint| {
        try f.env.put("R_ZIG_TOOLCHAIN_HINT", hint);
        for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
            c.os = os;
            try testing.expectError(error.NoFlang, command(c, &.{ "-c", "a.f" }));
            try testing.expectEqualStrings(msg, f.takeWarnings());
        }
    }
    c.os = .macos;
    // a file named flang that is not executable is no flang
    if (builtin.os.tag != .windows) {
        try f.touch("bin/flang");
        try f.env.put("PATH", f.path("bin"));
        try testing.expectError(error.NoFlang, command(c, &.{ "-c", "a.f" }));
    }
}
