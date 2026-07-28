//! Build R with `zig build` — no autoconf, no make (Milestone 5).
//!
//! The build graph replicates what R 4.6.1's configure+make pipeline does,
//! on linux-64 and macOS so far (see .github/devdocs/feat-zig-build/,
//! FINALIZATION.md for phase status — F1-F5 done, F6 Windows remains):
//!   1. configure results are replayed from a vendored per-(platform,variant)
//!      config (zigbuild/config/<plat>-<variant>/: config.h, Rconfig.h,
//!      subst.txt — the S-table dumped from a known-good config.status run;
//!      slim and full are separate dirs since capabilities are compile-time),
//!   2. C compiles natively through zig's Compile steps (zig cc semantics:
//!      -fno-sanitize=undefined, -std=gnu23), Fortran through per-platform
//!      Run steps (flang on linux, gfortran on macOS — zig has no Fortran
//!      frontend of its own on either),
//!   3. the R-level base-package bootstrap (share/make/basepkg.mk logic)
//!      runs as a sequenced chain of Run steps invoking the freshly built R.
//!
//! `platform`/`os`/`dylib_ext` are resolved at build-script-execution time
//! from the target (see `Os` below) — nothing here is hardcoded to linux.
//!
//! Two independent build options select the profile:
//!   -Dvariant=slim|full  (default slim) — tcltk/readline/NLS/jpeg/tiff;
//!      a real second configure profile (own vendored config dir), not a
//!      flag toggle, since these are compile-time capabilities in R.
//!   -Dblas=internal|openblas  (default internal) — orthogonal to variant;
//!      a pure link-time swap (R calls BLAS/LAPACK through a fixed
//!      Fortran ABI either way), so no separate vendored config needed.
//!
//! Prerequisites: run inside the pixi env (`pixi run zig-build`, or
//! `pixi run -e full`/`-e openblas` for the other profiles) with the R
//! source tree fetched at build/R-<version> (`pixi run fetch`).
//!
//! Everything installs directly into the final prefix (zig build --prefix):
//! <prefix>/lib/R is R_HOME, <prefix>/bin holds the launchers — the same
//! layout make install produces, so stage.sh/package-standalone.sh work
//! downstream unchanged (verified F4.1).

const std = @import("std");
const rspec = @import("zigbuild/rspec.zig");

const r_version = "4.6.1";

/// F5/F6: linux uses flang + ELF (.so/DT_NEEDED/RUNPATH); macOS uses
/// gfortran + Mach-O (.dylib/install_name/@rpath — patchelf doesn't apply
/// at all, and per FINALIZATION.md F5.2 all Mach-O rpath/codesign surgery
/// is left to stage.sh, not duplicated here); windows uses MinGW gfortran
/// + PE/COFF (.dll, no "lib" prefix on R's own core libs — see
/// FINALIZATION.md F6.0/F6.1a for the CLI-only scoping decision: no
/// Rgui.exe/Rterm.exe/R.exe/Rcmd.exe, just R.dll+Rblas.dll+Rlapack.dll+
/// Rgraphapp.dll+Riconv.dll+Rscript.exe).
const Os = enum { linux, macos, windows };

/// Capabilities (tcltk/readline/NLS/jpeg/tiff) are compile-time in R, so
/// slim vs full is a genuine second configure profile — its own vendored
/// config.h/Rconfig.h/subst.txt under zigbuild/config/<plat>-<variant>/,
/// not a flag toggle (see FINALIZATION.md F3.1).
const Variant = enum { slim, full };

/// F3.2: orthogonal to Variant — a pure link-time swap, not a separate
/// configure profile. R's own C code calls BLAS/LAPACK through a fixed
/// Fortran-callable ABI regardless of which implementation provides it,
/// so no vendored-config difference is needed; openblas just replaces the
/// internal reference libRblas.so/libRlapack.so wherever they'd be linked.
const Blas = enum { internal, openblas };

const Ctx = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    os: Os,
    dylib_ext: []const u8, // ".so" (linux) or ".dylib" (macOS) — R_DYLIB_EXT;
    // only libR/libRblas/libRlapack use this. Packages/modules always use
    // SHLIB_EXT, which is ".so" on every platform R supports.
    variant: Variant,
    blas: Blas,
    conda: []const u8,
    src_abs: []const u8, // absolute path of R source tree
    src: std.Build.LazyPath,
    prefix: []const u8, // absolute install prefix
    rhome: []const u8, // prefix ++ "/lib/R"
    flangrt_dir: []const u8, // conda clang resource dir with libflang_rt (linux only)
    gfortran_lib_dir: []const u8, // conda gcc versioned lib dir with libgfortran/libquadmath (windows only)
    subst: std.StringHashMap([]const u8),
    geninc: std.Build.LazyPath, // generated headers dir (config.h, Rconfig.h, ...)
    libR: *std.Build.Step.Compile,
    rblas: ?*std.Build.Step.Compile, // null when blas == .openblas
    rlapack: ?*std.Build.Step.Compile, // null when blas == .openblas

    /// Link the BLAS provider: internal libRblas.so or system openblas.
    fn linkBlas(ctx: *const Ctx, mod: *std.Build.Module) void {
        if (ctx.blas == .openblas) {
            mod.linkSystemLibrary("openblas", .{ .use_pkg_config = .no });
        } else {
            mod.linkLibrary(ctx.rblas.?);
        }
    }
    /// Link the LAPACK provider: internal libRlapack.so or system openblas
    /// (conda-forge's openblas package bundles LAPACK too).
    fn linkLapack(ctx: *const Ctx, mod: *std.Build.Module) void {
        if (ctx.blas == .openblas) {
            mod.linkSystemLibrary("openblas", .{ .use_pkg_config = .no });
        } else {
            mod.linkLibrary(ctx.rlapack.?);
        }
    }

    fn path(ctx: *const Ctx, sub: []const u8) std.Build.LazyPath {
        return ctx.src.path(ctx.b, sub);
    }
    fn absSub(ctx: *const Ctx, comptime fmt: []const u8, args: anytype) []const u8 {
        return ctx.b.fmt(fmt, args);
    }
};

pub fn build(b: *std.Build) !void {
    const arena = b.allocator;
    const io = b.graph.io;

    const conda = b.graph.environ_map.get("CONDA_PREFIX") orelse {
        std.debug.print("error: CONDA_PREFIX not set — run through pixi (`pixi run zig-build`)\n", .{});
        return error.MissingCondaPrefix;
    };

    const src_rel = "build/R-" ++ r_version;
    // b.pathFromRoot resolves using the OS-native separator (backslash on
    // Windows) — harmless for compile-flag/file-path use (zig cc/clang and
    // Windows APIs both accept forward slashes just fine either way), but
    // this same string also gets interpolated directly into R code string
    // literals throughout bootstrap()/stageLibraryPayload() (e.g.
    // "tools:::sysdata2LazyLoadDB(\"{s}/...\", ...)"), where R's parser
    // reads a literal backslash as the start of an escape sequence —
    // `C:\Users\...` breaks specifically on the "\U" in "Users", which R
    // parses as (and rejects) a malformed `\Uxxxxxxxx` Unicode escape.
    // Found via a real bootstrap parse error ("'\U' used without hex
    // digits") that only surfaced once the R_HOME/dirstrip fix let R
    // actually start up far enough to parse the piped code at all.
    // Normalize once here so every downstream use — compile flags AND R
    // code strings — is uniformly forward-slash, matching ctx.rhome/
    // ctx.prefix (already forward-slash, since Windows' own --prefix
    // argument is passed that way); a no-op on unix, which has no
    // backslashes to replace.
    const src_abs = std.mem.replaceOwned(u8, b.allocator, b.pathFromRoot(src_rel), "\\", "/") catch @panic("OOM");
    std.Io.Dir.cwd().access(io, b.fmt("{s}/VERSION", .{src_abs}), .{}) catch {
        std.debug.print("error: R source tree not found at {s} — run `pixi run fetch` first\n", .{src_abs});
        return error.MissingRSource;
    };

    var variant = b.option(Variant, "variant", "R build variant: slim (default) or full") orelse .slim;
    const blas = b.option(Blas, "blas", "BLAS/LAPACK flavor: internal (default) or openblas") orelse .internal;

    const native = b.resolveTargetQuery(.{});
    const os: Os = switch (native.result.os.tag) {
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        else => {
            std.debug.print("error: unsupported target OS '{s}' (only linux, macos, and windows are supported so far)\n", .{@tagName(native.result.os.tag)});
            return error.UnsupportedOS;
        },
    };
    // On real Windows hardware, native target resolution defaults to the
    // MSVC ABI — this whole toolchain (conda-forge MinGW gfortran,
    // x86_64-w64-mingw32-* binutils, .dll.a import libraries) is built on
    // the GNU/MinGW ABI instead (matches the existing toolchain/zig-cc
    // shim's own `-target x86_64-windows-gnu`), so re-resolve explicitly.
    const target = if (os == .windows) b.resolveTargetQuery(.{ .abi = .gnu }) else native;
    // gnuwin32 has no slim/full switch at all (jpeg/tiff/tcltk are always
    // on — "slim==full on Windows", a pre-existing project convention);
    // -Dvariant is meaningless there, force .full regardless of what was
    // passed rather than silently building something that doesn't exist.
    if (os == .windows) variant = .full;
    const arch_str = switch (target.result.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        else => {
            std.debug.print("error: unsupported target arch '{s}'\n", .{@tagName(target.result.cpu.arch)});
            return error.UnsupportedArch;
        },
    };
    const platform = switch (os) {
        .linux => b.fmt("linux-{s}", .{arch_str}),
        .macos => b.fmt("osx-{s}", .{arch_str}),
        .windows => b.fmt("win-{s}", .{arch_str}),
    };
    const dylib_ext = switch (os) {
        .linux => ".so",
        .macos => ".dylib",
        .windows => ".dll",
    };
    const config_dir = b.fmt("zigbuild/config/{s}-{s}", .{ platform, @tagName(variant) });

    // R_HOME: <prefix>/lib/R on unix. On Windows this MUST NOT be "lib/R"
    // — NTFS case-folds it into a conda/pixi env's own "Lib" (Python's
    // stdlib), silently dumping R's tree inside site-packages and off
    // PATH entirely (same bug class scripts/env.sh already works around
    // for the autoconf/gnuwin32 path — see FINALIZATION.md F6.2).
    const rhome = switch (os) {
        .windows => b.fmt("{s}/Library/lib/R", .{b.install_prefix}),
        else => b.fmt("{s}/lib/R", .{b.install_prefix}),
    };

    var ctx = Ctx{
        .b = b,
        .target = target,
        .os = os,
        .dylib_ext = dylib_ext,
        .variant = variant,
        .blas = blas,
        .conda = conda,
        .src_abs = src_abs,
        .src = b.path(src_rel),
        .prefix = b.install_prefix,
        .rhome = rhome,
        .flangrt_dir = if (os == .linux) try findFlangRt(b, io, conda) else "",
        .gfortran_lib_dir = if (os == .windows) try findGfortranLibDir(b, io, conda) else "",
        .subst = std.StringHashMap([]const u8).init(arena),
        .geninc = undefined,
        .libR = undefined,
        .rblas = undefined,
        .rlapack = undefined,
    };

    try checkConfigFreshness(b, io, config_dir);

    // Windows (F6): gnuwin32's build is structurally different enough
    // (no config.status, no shell launchers, mutual-DLL linking) that
    // threading it through the unix/macOS pipeline below would risk the
    // two already-proven platforms. Branch early into a fully separate
    // implementation instead — see FINALIZATION.md F6 for the ground-
    // truth extraction and F6.0 for the CLI-only scoping decision this
    // implements (R.dll+Rblas.dll+Rlapack.dll+Rgraphapp.dll+Riconv.dll+
    // Rscript.exe only, no Rgui.exe/Rterm.exe/R.exe/Rcmd.exe).
    if (os == .windows) return buildWindows(&ctx, io);

    try loadSubstTable(&ctx, io, config_dir);

    // ------------------------------------------------------------------
    // Generated headers (what config.status + src/include/Makefile make)
    // ------------------------------------------------------------------
    const geninc = b.addWriteFiles();
    _ = geninc.addCopyFile(b.path(b.fmt("{s}/config.h", .{config_dir})), "config.h");
    _ = geninc.addCopyFile(b.path(b.fmt("{s}/Rconfig.h", .{config_dir})), "Rconfig.h");
    _ = geninc.add("Rversion.h", try genRversionH(&ctx, io));
    _ = geninc.add("Rmath.h", try substFile(&ctx, io, "src/include/Rmath.h0.in"));
    ctx.geninc = geninc.getDirectory();

    // ------------------------------------------------------------------
    // Fortran objects (flang Run steps; zig has no Fortran frontend)
    // ------------------------------------------------------------------
    const appl_f = fortranGroup(&ctx, "src/appl", &rspec.appl_f, &.{});
    const xxxpr = fortranGroup(&ctx, "src/main", &.{"xxxpr.f"}, &.{});
    const stats_f = fortranGroup(&ctx, "src/library/stats/src", &rspec.stats_f, &.{});

    // ------------------------------------------------------------------
    // libRblas.so / libRlapack.so — internal reference implementation
    // only; openblas (F3.2) skips compiling these entirely and every
    // linkBlas()/linkLapack() call below links -lopenblas instead. Same
    // Fortran-callable ABI either way, so no source-level branching
    // anywhere else in the compile graph needs to know which flavor this is.
    // ------------------------------------------------------------------
    ctx.rblas = null;
    ctx.rlapack = null;
    if (ctx.blas == .internal) {
        const blas_fixed = fortranGroup(&ctx, "src/extra/blas", &rspec.blas_f, &.{});
        const blas_free = fortranGroup(&ctx, "src/extra/blas", &rspec.blas_f90, &.{});

        // libRlapack's f90 files have real module dependencies:
        // la_constants then la_xisnan must be compiled before their users
        // (-I their .mod dirs).
        var lapack_objs = std.ArrayList(std.Build.LazyPath).empty;
        var lapack_mods = std.ArrayList(std.Build.LazyPath).empty;
        for (rspec.rlapack_f90_ordered) |f| {
            const r = fortranOne(&ctx, "src/modules/lapack", f, lapack_mods.items);
            try lapack_objs.append(arena, r.obj);
            try lapack_mods.append(arena, r.mods);
        }
        for (rspec.rlapack_f) |f| {
            const r = fortranOne(&ctx, "src/modules/lapack", f, lapack_mods.items);
            try lapack_objs.append(arena, r.obj);
        }

        const rblas_mod = newCMod(&ctx);
        for (blas_fixed) |o| rblas_mod.addObjectFile(o);
        for (blas_free) |o| rblas_mod.addObjectFile(o);
        linkFortranRt(&ctx, rblas_mod);
        ctx.rblas = addSharedLib(&ctx, "Rblas", rblas_mod);

        const rlapack_mod = newCMod(&ctx);
        for (lapack_objs.items) |o| rlapack_mod.addObjectFile(o);
        rlapack_mod.linkLibrary(ctx.rblas.?);
        linkFortranRt(&ctx, rlapack_mod);
        ctx.rlapack = addSharedLib(&ctx, "Rlapack", rlapack_mod);
    }

    // ------------------------------------------------------------------
    // libR.so — src/main + appl/nmath/tre/tzone/xdr/unix, all one link
    // (make links the constituent .o files directly, never archives, so
    // every symbol stays exported for packages to resolve against)
    // ------------------------------------------------------------------
    const libR_mod = newCMod(&ctx);
    libR_mod.addIncludePath(ctx.geninc);
    libR_mod.addIncludePath(ctx.path("src/include"));
    addCGroup(&ctx, libR_mod, "src/main", &rspec.main_c, .{
        .openmp = true,
        .extra = &.{ "-I%S/src/extra", "-I%S/src/extra/xdr", "-I%S/src/nmath" },
    });
    addCGroup(&ctx, libR_mod, "src/appl", &rspec.appl_c, .{ .openmp = true });
    addCGroup(&ctx, libR_mod, "src/nmath", &rspec.nmath_c, .{ .openmp = true });
    addCGroup(&ctx, libR_mod, "src/extra/tre", &rspec.tre_c, .{
        .openmp = true,
        .extra = &.{"-I%S/src/extra"},
    });
    addCGroup(&ctx, libR_mod, "src/extra/tzone", &rspec.tzone_c, .{
        .extra = &.{ "-I%S/src/extra/tzone", "-I%S/src/main" },
    });
    addCGroup(&ctx, libR_mod, "src/extra/xdr", &rspec.xdr_c, .{
        .openmp = true,
        .extra = &.{"-I%S/src/extra/xdr"},
    });
    addCGroup(&ctx, libR_mod, "src/unix", &rspec.unix_c, .{ .openmp = true });
    for (appl_f) |o| libR_mod.addObjectFile(o);
    for (xxxpr) |o| libR_mod.addObjectFile(o);
    ctx.linkBlas(libR_mod);
    linkFortranRt(&ctx, libR_mod);
    linkCoreLibs(&ctx, libR_mod);
    ctx.libR = addSharedLib(&ctx, "R", libR_mod);

    // ------------------------------------------------------------------
    // Executables: bin/exec/R (Rmain.c) and bin/Rscript
    // ------------------------------------------------------------------
    const rbin_mod = newCMod(&ctx);
    rbin_mod.addIncludePath(ctx.geninc);
    rbin_mod.addIncludePath(ctx.path("src/include"));
    addCGroup(&ctx, rbin_mod, "src/main", &.{"Rmain.c"}, .{ .openmp = true });
    rbin_mod.linkLibrary(ctx.libR);
    ctx.linkBlas(rbin_mod);
    linkOmp(&ctx, rbin_mod);
    const rbin = b.addExecutable(.{ .name = "R.bin", .root_module = rbin_mod });
    rbin.rdynamic = true; // MAIN_LDFLAGS = -Wl,--export-dynamic

    const rscript_mod = newCMod(&ctx);
    rscript_mod.addIncludePath(ctx.geninc);
    rscript_mod.addIncludePath(ctx.path("src/include"));
    // "we need to build at install time to capture the correct rhome"
    addCGroup(&ctx, rscript_mod, "src/unix", &.{"Rscript.c"}, .{
        .extra = &.{ctx.absSub("-DR_HOME=\"{s}\"", .{ctx.rhome})},
    });
    const rscript = b.addExecutable(.{ .name = "Rscript", .root_module = rscript_mod });

    // ------------------------------------------------------------------
    // Loadable modules: modules/lapack.so, modules/internet.so
    // ------------------------------------------------------------------
    const lapmod = newCMod(&ctx);
    lapmod.addIncludePath(ctx.geninc);
    lapmod.addIncludePath(ctx.path("src/include"));
    addCGroup(&ctx, lapmod, "src/modules/lapack", &.{"Lapack.c"}, .{ .openmp = true });
    addCGroup(&ctx, lapmod, "src/main", &.{"flexiblas.c"}, .{ .openmp = true });
    if (ctx.blas == .openblas) {
        lapmod.linkSystemLibrary("openblas", .{ .use_pkg_config = .no });
    } else {
        lapmod.linkLibrary(ctx.rlapack.?);
        lapmod.linkLibrary(ctx.rblas.?);
    }
    lapmod.linkLibrary(ctx.libR);
    linkFortranRt(&ctx, lapmod);
    linkOmp(&ctx, lapmod);
    const mod_lapack = addSharedLib(&ctx, "mod_lapack", lapmod);

    const inetmod = newCMod(&ctx);
    inetmod.addIncludePath(ctx.geninc);
    inetmod.addIncludePath(ctx.path("src/include"));
    addCGroup(&ctx, inetmod, "src/modules/internet", &rspec.internet_c, .{ .openmp = true });
    inetmod.linkLibrary(ctx.libR);
    inetmod.linkSystemLibrary("curl", .{ .use_pkg_config = .no });
    const mod_internet = addSharedLib(&ctx, "mod_internet", inetmod);

    // ------------------------------------------------------------------
    // Base-package shared libs (library/<pkg>/libs/<pkg>.so)
    // ------------------------------------------------------------------
    const PkgLib = struct { pkg: []const u8, lib: *std.Build.Step.Compile };
    var pkg_libs = std.ArrayList(PkgLib).empty;

    {
        const m = newPkgMod(&ctx, "src/library/stats/src", &rspec.stats_c, .{
            .openmp = true,
            .extra = &.{"-DHAVE_CONFIG_H"},
        });
        for (stats_f) |o| m.addObjectFile(o);
        if (ctx.blas == .openblas) {
            m.linkSystemLibrary("openblas", .{ .use_pkg_config = .no });
        } else {
            m.linkLibrary(ctx.rlapack.?);
            m.linkLibrary(ctx.rblas.?);
        }
        linkFortranRt(&ctx, m);
        linkOmp(&ctx, m);
        try pkg_libs.append(arena, .{ .pkg = "stats", .lib = addSharedLib(&ctx, "pkg_stats", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/graphics/src", &rspec.graphics_c, .{
            .extra = &.{ "-DHAVE_CONFIG_H", "-I%S/src/main" },
        });
        try pkg_libs.append(arena, .{ .pkg = "graphics", .lib = addSharedLib(&ctx, "pkg_graphics", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/grDevices/src", &rspec.grdevices_c, .{
            .extra = &.{"-DHAVE_CONFIG_H"},
        });
        m.linkSystemLibrary("z", .{ .use_pkg_config = .no });
        try pkg_libs.append(arena, .{ .pkg = "grDevices", .lib = addSharedLib(&ctx, "pkg_grDevices", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/grid/src", &rspec.grid_c, .{});
        try pkg_libs.append(arena, .{ .pkg = "grid", .lib = addSharedLib(&ctx, "pkg_grid", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/methods/src", &rspec.methods_c, .{
            .extra = &.{"-DHAVE_CONFIG_H"},
        });
        try pkg_libs.append(arena, .{ .pkg = "methods", .lib = addSharedLib(&ctx, "pkg_methods", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/parallel/src", &rspec.parallel_c, .{
            .extra = &.{"-DHAVE_CONFIG_H"},
        });
        try pkg_libs.append(arena, .{ .pkg = "parallel", .lib = addSharedLib(&ctx, "pkg_parallel", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/splines/src", &rspec.splines_c, .{});
        try pkg_libs.append(arena, .{ .pkg = "splines", .lib = addSharedLib(&ctx, "pkg_splines", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/tools/src", &rspec.tools_c, .{
            .extra = &.{ "-DHAVE_CONFIG_H", "-I%S/src/main" },
        });
        try pkg_libs.append(arena, .{ .pkg = "tools", .lib = addSharedLib(&ctx, "pkg_tools", m) });
    }
    {
        const m = newPkgMod(&ctx, "src/library/utils/src", &rspec.utils_c, .{
            .extra = &.{ "-DHAVE_CONFIG_H", "-I%S/src/main" },
        });
        try pkg_libs.append(arena, .{ .pkg = "utils", .lib = addSharedLib(&ctx, "pkg_utils", m) });
    }
    if (ctx.variant == .full) {
        // tcltk (library/tcltk/libs/tcltk.so): real Tk bindings, only
        // built for full — slim ships a stub .onLoad that errors out and
        // no compiled code at all (see the R-code side in
        // installStaticTree). PKG_CPPFLAGS/PKG_LIBS from
        // src/library/tcltk/src/Makefile.in: `-I../../../include
        // -I$(top_srcdir)/src/include -DHAVE_CONFIG_H @TCLTK_CPPFLAGS@`
        // and `@TCLTK_LIBS@ @LIBM@` — geninc/src/include are the zig
        // equivalent of the first two -I's.
        const m = newCMod(&ctx);
        m.addIncludePath(ctx.geninc);
        m.addIncludePath(ctx.path("src/include"));
        var extra = std.ArrayList([]const u8).empty;
        try extra.append(arena, "-DHAVE_CONFIG_H");
        var it = std.mem.tokenizeScalar(u8, ctx.subst.get("TCLTK_CPPFLAGS").?, ' ');
        while (it.next()) |tok| try extra.append(arena, tok);
        addCGroup(&ctx, m, "src/library/tcltk/src", &rspec.tcltk_c, .{ .extra = extra.items });
        applyLinkFlags(&ctx, m, ctx.subst.get("TCLTK_LIBS").?);
        applyLinkFlags(&ctx, m, ctx.subst.get("LIBM").?);
        try pkg_libs.append(arena, .{ .pkg = "tcltk", .lib = addSharedLib(&ctx, "pkg_tcltk", m) });
    }

    // grDevices cairo module (library/grDevices/libs/cairo.so): cairoBM.c +
    // rbitmap.o from src/modules/X11 (built there even with --with-x=no).
    const cairo_mod = newCMod(&ctx);
    cairo_mod.addIncludePath(ctx.geninc);
    cairo_mod.addIncludePath(ctx.path("src/include"));
    {
        var flags = std.ArrayList([]const u8).empty;
        try flags.appendSlice(arena, &.{ "-std=gnu23", "-fno-sanitize=undefined", "-O2", "-fopenmp", "-DHAVE_CONFIG_H" });
        var it = std.mem.tokenizeScalar(u8, ctx.subst.get("CAIRO_CPPFLAGS").?, ' ');
        while (it.next()) |tok| try flags.append(arena, tok);
        try flags.append(arena, ctx.absSub("-I{s}/include/libpng16", .{conda}));
        try flags.append(arena, ctx.absSub("-I{s}/src/modules/X11", .{src_abs}));
        try flags.append(arena, ctx.absSub("-I{s}/src/library/grDevices/src/cairo", .{src_abs}));
        try flags.append(arena, ctx.absSub("-I{s}/include", .{conda}));
        cairo_mod.addCSourceFiles(.{
            .root = ctx.path("src/library/grDevices/src/cairo"),
            .files = &.{"cairoBM.c"},
            .flags = flags.items,
        });
        cairo_mod.addCSourceFiles(.{
            .root = ctx.path("src/modules/X11"),
            .files = &.{"rbitmap.c"},
            .flags = flags.items,
        });
    }
    cairo_mod.linkLibrary(ctx.libR);
    applyLinkFlags(&ctx, cairo_mod, ctx.subst.get("CAIRO_LIBS").?);
    // full only: rbitmap.c's HAVE_JPEG/HAVE_TIFF branches (from the
    // per-variant config.h) need libjpeg/libtiff — CAIRO_LIBS doesn't
    // carry them (only -lpng16), BITMAP_LIBS does (slim's BITMAP_LIBS is
    // just -lpng16 too, already covered via CAIRO_LIBS, so apply it only
    // for full to avoid a harmless but pointless double -lpng16 on slim).
    if (ctx.variant == .full) applyLinkFlags(&ctx, cairo_mod, ctx.subst.get("BITMAP_LIBS").?);
    linkOmp(&ctx, cairo_mod);
    const mod_cairo = addSharedLib(&ctx, "pkg_cairo", cairo_mod);

    // ------------------------------------------------------------------
    // Install: binaries into the R_HOME layout
    // ------------------------------------------------------------------
    const lib_dir: std.Build.InstallDir = .{ .custom = "lib/R/lib" };
    const modules_dir: std.Build.InstallDir = .{ .custom = "lib/R/modules" };
    // libR/libRblas/libRlapack use R_DYLIB_EXT (.dylib on macOS, .so on
    // linux); packages and modules (lapack.so/internet.so below) always
    // use SHLIB_EXT, which is ".so" on every platform R supports.
    const libR_name = ctx.absSub("libR{s}", .{ctx.dylib_ext});
    const libRblas_name = ctx.absSub("libRblas{s}", .{ctx.dylib_ext});
    const libRlapack_name = ctx.absSub("libRlapack{s}", .{ctx.dylib_ext});
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(fixRpath(&ctx, ctx.libR.getEmittedBin(), libR_name), lib_dir, libR_name).step);
    if (ctx.rblas) |rblas| b.getInstallStep().dependOn(&b.addInstallFileWithDir(fixRpath(&ctx, rblas.getEmittedBin(), libRblas_name), lib_dir, libRblas_name).step);
    if (ctx.rlapack) |rlapack| b.getInstallStep().dependOn(&b.addInstallFileWithDir(fixRpath(&ctx, rlapack.getEmittedBin(), libRlapack_name), lib_dir, libRlapack_name).step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(fixRpath(&ctx, mod_lapack.getEmittedBin(), "lapack.so"), modules_dir, "lapack.so").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(fixRpath(&ctx, mod_internet.getEmittedBin(), "internet.so"), modules_dir, "internet.so").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(fixRpath(&ctx, rbin.getEmittedBin(), "R.bin"), .{ .custom = "lib/R/bin/exec" }, "R").step);
    const rscript_fixed = fixRpath(&ctx, rscript.getEmittedBin(), "Rscript");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rscript_fixed, .{ .custom = "lib/R/bin" }, "Rscript").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rscript_fixed, .{ .custom = "bin" }, "Rscript").step);
    // ------------------------------------------------------------------
    // Static R_HOME payload: headers, etc/, bin scripts, share/, doc/,
    // and every base package's R code / DESCRIPTION / NAMESPACE / data.
    // ------------------------------------------------------------------
    const libstage = try installStaticTree(&ctx, io);
    for (pkg_libs.items) |pl| {
        _ = libstage.addCopyFile(fixRpath(&ctx, pl.lib.getEmittedBin(), ctx.absSub("{s}.so", .{pl.pkg})), ctx.absSub("{s}/libs/{s}.so", .{ pl.pkg, pl.pkg }));
    }
    _ = libstage.addCopyFile(fixRpath(&ctx, mod_cairo.getEmittedBin(), "cairo.so"), "grDevices/libs/cairo.so");

    // ------------------------------------------------------------------
    // Bootstrap: sequenced R runs (the R-level half make used to drive)
    // ------------------------------------------------------------------
    const final = try bootstrap(&ctx, io, libstage.getDirectory());

    const top = b.step("r", "Build a complete, bootstrapped R in the install prefix");
    top.dependOn(final);
    b.default_step = top;

    try addCheckStep(&ctx, io, top);
}

// ----------------------------------------------------------------------
// Windows (F6): R.dll + Rblas.dll + Rlapack.dll + Rgraphapp.dll +
// Riconv.dll + Rscript.exe only — see FINALIZATION.md F6.0 (scoping
// decision) and F6.1a (ground-truth file lists, extracted from kappa's
// own already-built gnuwin32 objdir, not guessed from Makefiles).
// ----------------------------------------------------------------------

fn buildWindows(ctx: *Ctx, io: std.Io) !void {
    const b = ctx.b;
    const arena = b.allocator;

    // No config.status on Windows — gnuwin32 ships static, ready-made
    // config.h/Rconfig.h (not autoconf templates). Only a handful of
    // @VAR@ tokens exist at all (found by grepping the vendored file
    // directly, not assumed): CC_VER/FC_VER/VERSION in config.h,
    // PACKAGE_VERSION/RMATH_HAVE_WORKING_LOG1P in Rmath.h0.in.
    try ctx.subst.put("VERSION", r_version);
    try ctx.subst.put("PACKAGE_VERSION", r_version);
    try ctx.subst.put("CC_VER", "zig cc (LLVM/clang, MinGW target)");
    try ctx.subst.put("FC_VER", "gfortran (conda-forge, MinGW target)");
    try ctx.subst.put("RMATH_HAVE_WORKING_LOG1P", "# define HAVE_WORKING_LOG1P 1");
    // libgnuintl.h.in's 4 tokens — gnuwin32's own Makefile.win generates
    // libgnuintl.h from this .in via the exact same 4 sed substitutions
    // (src/extra/intl/Makefile.win), not real configure output.
    try ctx.subst.put("HAVE_POSIX_PRINTF", "1");
    try ctx.subst.put("HAVE_ASPRINTF", "0");
    try ctx.subst.put("HAVE_SNPRINTF", "1");
    try ctx.subst.put("HAVE_WPRINTF", "0");

    const geninc = b.addWriteFiles();
    {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, b.pathFromRoot("zigbuild/config/win-x86_64-full/config.h"), b.allocator, .limited(4 * 1024 * 1024));
        _ = geninc.add("config.h", try substitute(ctx, raw));
    }
    _ = geninc.addCopyFile(b.path("zigbuild/config/win-x86_64-full/Rconfig.h"), "Rconfig.h");
    _ = geninc.add("Rversion.h", try genRversionH(ctx, io));
    _ = geninc.add("Rmath.h", try substFile(ctx, io, "src/include/Rmath.h0.in"));
    // intl's own Makefile.win does `cp libgnuintl.h libintl.h` — client code
    // (win-nls.h etc.) includes <libintl.h>, not <libgnuintl.h>. Without our
    // own copy on the include path, conda-forge's REAL gettext package
    // (Library/include/libintl.h, a completely different implementation)
    // gets picked up instead for angle-bracket includes, silently
    // redefining fprintf/vfprintf/setlocale to libintl_* names that our own
    // compiled intl sources (built against R's config.h, HAVE_POSIX_PRINTF=1)
    // never define — found via real undefined-symbol link errors.
    const libgnuintl_h = try substFile(ctx, io, "src/extra/intl/libgnuintl.h.in");
    _ = geninc.add("libgnuintl.h", libgnuintl_h);
    _ = geninc.add("libintl.h", libgnuintl_h);
    ctx.geninc = geninc.getDirectory();

    // ------------------------------------------------------------------
    // Fortran: BLAS (internal only — no ATLAS/OpenBLAS on Windows yet)
    // and LAPACK (dlapack.f is one aggregated file, unlike unix's
    // per-routine split; the la_constants->la_xisnan module chain is the
    // one place Windows' LAPACK layout still matches unix's shape).
    // ------------------------------------------------------------------
    const blas_f = fortranGroup(ctx, "src/extra/blas", &rspec.win_blas_f, &.{});
    const blas_f90 = fortranGroup(ctx, "src/extra/blas", &rspec.win_blas_f90, &.{});

    var lapack_mods = std.ArrayList(std.Build.LazyPath).empty;
    var lapack_objs = std.ArrayList(std.Build.LazyPath).empty;
    for (rspec.win_lapack_f90_ordered) |f| {
        const r = fortranOne(ctx, "src/modules/lapack", f, lapack_mods.items);
        try lapack_objs.append(arena, r.obj);
        try lapack_mods.append(arena, r.mods);
    }
    for (rspec.win_lapack_f) |f| {
        const r = fortranOne(ctx, "src/modules/lapack", f, lapack_mods.items);
        try lapack_objs.append(arena, r.obj);
    }
    const r_appl_f = fortranGroup(ctx, "src/appl", &rspec.appl_f, &.{});
    const r_xxxpr_f = fortranGroup(ctx, "src/main", &.{"xxxpr.f"}, &.{});

    // ------------------------------------------------------------------
    // R.dll's core object set: reused unix groups (main/appl/nmath/xdr/
    // tzone/tre — identical sources, just compiled for the MinGW target)
    // plus the Windows-only groups (F6.0: required, not prunable —
    // gnuwin32 built R.dll as one monolithic library with the console/
    // GUI plumbing and NLS baked in as required compile units).
    // ------------------------------------------------------------------
    const r_core_mod = newCMod(ctx);
    r_core_mod.addIncludePath(ctx.geninc);
    r_core_mod.addIncludePath(ctx.path("src/include"));
    // src/gnuwin32/fixed/h/ also ships psignal.h and trioremap.h — plain,
    // static headers (unlike config.h/Rconfig.h there, which are handled via
    // ctx.geninc's substituted copies instead) that R's own main/*.c sources
    // include unconditionally on Windows. Found via real compile errors
    // ('psignal.h' / 'trioremap.h' file not found).
    r_core_mod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    const dll_build = "-DR_DLL_BUILD";
    addCGroup(ctx, r_core_mod, "src/main", &rspec.main_c, .{
        // -I%S/src/gnuwin32: builtin.c/printutils.c (`rgui_UTF8.h`),
        // edit.c (`run.h`), platform.c/sysutils.c (`dos_wglob.h`) all pull
        // headers straight from gnuwin32's own dir (found via real compile
        // errors — file not found).
        //
        // -DR_ARCH="x64": platform.c's do_Platform() populates R-level
        // `.Platform$r_arch` from this same macro (`#ifdef R_ARCH
        // SET_VECTOR_ELT(value, 7, mkString(R_ARCH))`) — without it,
        // `.Platform$r_arch` is empty, so `library.dynam()`'s own R-level
        // path construction looks for `libs/<pkg>.dll` instead of
        // `libs/x64/<pkg>.dll`, failing with "DLL not found: maybe not
        // installed for this architecture?" even though the compiled DLL
        // is right there in libs/x64/. Same macro as system.c's dirstrip
        // fix, just needed again here since platform.c is a different
        // compile group (found via a real bootstrap failure — the very
        // first R invocation, "tools sysdata", needs `tools:::` namespace
        // access, which triggers `library.dynam("tools", ...)`).
        .extra = &.{ "-I%S/src/extra", "-I%S/src/extra/xdr", "-I%S/src/nmath", "-I%S/src/gnuwin32", "-DR_ARCH=\"x64\"", dll_build },
    });
    // mkdtemp.c: Windows-only POSIX mkdtemp() substitute, not part of
    // unix's main_c list (found via a real undefined-symbol link error).
    addCGroup(ctx, r_core_mod, "src/main", &rspec.win_mkdtemp_c, .{
        .extra = &.{ "-I%S/src/extra", "-I%S/src/extra/xdr", "-I%S/src/nmath", "-I%S/src/gnuwin32", dll_build },
    });
    addCGroup(ctx, r_core_mod, "src/appl", &rspec.appl_c, .{ .extra = &.{dll_build} });
    addCGroup(ctx, r_core_mod, "src/nmath", &rspec.nmath_c, .{ .extra = &.{dll_build} });
    addCGroup(ctx, r_core_mod, "src/extra/tre", &rspec.tre_c, .{
        .extra = &.{ "-I%S/src/extra", dll_build },
    });
    addCGroup(ctx, r_core_mod, "src/extra/tzone", &rspec.tzone_c, .{
        .extra = &.{ "-I%S/src/extra/tzone", "-I%S/src/main", dll_build },
    });
    // registryTZ.c: Windows-only registry-based TZ lookup, added on top of
    // unix's tzone_c list (real Makefile.win: `CSOURCES = localtime.c
    // registryTZ.c strftime.c`); getTZinfo was undefined without it (real
    // link error).
    addCGroup(ctx, r_core_mod, "src/extra/tzone", &rspec.win_tzone_c, .{
        .extra = &.{ "-I%S/src/extra/tzone", "-I%S/src/main", dll_build },
    });
    addCGroup(ctx, r_core_mod, "src/extra/xdr", &rspec.xdr_c, .{
        .extra = &.{ "-I%S/src/extra/xdr", dll_build },
    });
    addCGroup(ctx, r_core_mod, "src/gnuwin32", &rspec.win_gnuwin32_c, .{
        // gnuwin32's own Makefile carries `extra-CPPFLAGS = -I../library/
        // grDevices/src` specifically for extra.c's `devWindows.h` include
        // (found via a real compile error).
        //
        // -DR_ARCH="x64": system.c's cmdlineoptions() computes R_HOME by
        // taking Rterm.exe's own module path (GetModuleFileName) and
        // stripping `dirstrip` trailing path components — `dirstrip = 2`
        // by default, `+1` only `if (strlen(R_ARCH) > 0)`. Real gnuwin32
        // installs front-ends at <RHOME>/bin/<R_ARCH>/*.exe (3 levels:
        // exe/x64/bin) and gets R_ARCH="/x64" injected externally at build
        // time for exactly this; we install at bin/x64/ too (matching
        // smoke-test.sh's existing lookup) but never defined R_ARCH, so
        // dirstrip stayed at 2 — one level short — computing R_HOME as
        // ".../bin" instead of the real R_HOME, and every subsequent
        // R_Home-relative lookup (starting with R_OpenLibraryFile("base"))
        // silently pointed one directory too high. Found via a real
        // bootstrap failure ("unable to open the base package") traced all
        // the way through main.c's R_OpenLibraryFile down to this exact
        // strip-count computation in system.c.
        // -DloadRconsole=Rwin_loadRconsole: preferences.c's internal
        // `int loadRconsole(Gui, const char *)` (GUI-preferences loading,
        // called from rui.c/extra.c) collides by NAME ONLY with utils.dll's
        // own, unrelated, intentionally-exported `SEXP loadRconsole(SEXP)`
        // (utils/src/stubs.c, a .Call entry point) — two coincidentally
        // same-named, unrelated functions, one per DLL, that a real
        // gnuwin32 build never conflates since each DLL only exports what
        // its own hand-curated `Rdll.hide` list allows (which we don't
        // replicate). Since utils.dll links against R.dll (needed for its
        // OTHER R API calls), zig/lld-link's default "export everything
        // public" DLL policy surfaces the clash as a real duplicate-symbol
        // link error. A blanket textual rename via -D (applied to this
        // whole compile group; harmless for the 16 other files that never
        // reference the identifier at all) sidesteps it without patching
        // R's own source. Found via a real link error compiling utils.dll.
        .extra = &.{ "-I%S/src/gnuwin32", "-I%S/src/extra", "-I%S/src/library/grDevices/src", "-DR_ARCH=\"x64\"", "-DloadRconsole=Rwin_loadRconsole", dll_build },
    });
    // src/gnuwin32/getline/*.c (gl.a in the real build) — console.c calls
    // wgl_hist_next/prev/histadd from wc_history.c (found via a real
    // undefined-symbol link error).
    addCGroup(ctx, r_core_mod, "src/gnuwin32/getline", &rspec.win_getline_c, .{
        .extra = &.{ "-DWin32", dll_build },
    });
    addCGroup(ctx, r_core_mod, "src/extra/intl", &rspec.win_intl_c, .{
        .extra = &.{ "-DIN_LIBINTL", "-DLOCALEDIR=\"\"" },
    });
    addCGroup(ctx, r_core_mod, "src/extra/trio", &rspec.win_trio_c, .{
        .extra = &.{ "-I%S/src/main", "-DTRIO_FEATURE_WIDECHAR=1" },
    });
    for (r_appl_f) |o| r_core_mod.addObjectFile(o);
    for (r_xxxpr_f) |o| r_core_mod.addObjectFile(o);

    // Break the R.dll<->Rblas.dll/Rgraphapp.dll mutual dependency the way
    // gnuwin32's own make build does — a `.dll.a` import stub generated
    // *before* R.dll itself is linked. Unlike gnuwin32 (which derives the
    // stub from R.dll's real, fully-compiled objects), ours is a small,
    // hand-written, independent stub: zig's COFF backend can't merge many
    // objects into one the way `nm $(LIBOBJECTS)` needs (`error: coff
    // does not support linking multiple objects into one`, found from a
    // real build attempt), so compiling R's actual ~150 source files just
    // to extract a symbol list isn't viable. Instead: the exact symbol
    // set was read directly off kappa's own working reference DLLs via
    // `objdump -p` (not guessed) — Rblas.dll imports only `fprintf`/
    // `vfprintf`/`xerbla_` from R.dll; Rgraphapp.dll imports
    // R_ContinueUnwind/R_MakeUnwindCont/R_NilValue/R_ShowMessage/
    // R_UnwindProtect/Rf_mbrtowc/Rf_protect/Rf_strchr/Rf_unprotect/
    // Rf_utf8towcs/libintl_dgettext/libintl_gettext/localeCP. The stub's
    // bodies are never actually executed: Windows' loader binds against
    // whatever DLL genuinely exports each name at load time (the real
    // R.dll, built last, below) — this stub only needs to exist long
    // enough to satisfy the *linker* when Rblas.dll/Rgraphapp.dll are
    // built, matching name-for-name, not by real implementation.
    const r_stub_mod = newCMod(ctx);
    const stub_wf = b.addWriteFiles();
    const stub_c = stub_wf.add("r_stub.c",
        \\typedef struct SEXPREC *SEXP;
        \\int fprintf(void *stream, const char *fmt, ...) { return 0; }
        \\int vfprintf(void *stream, const char *fmt, void *ap) { return 0; }
        \\void xerbla_(const char *srname, int *info) {}
        \\void *R_ContinueUnwind(void *cont) { return 0; }
        \\void *R_MakeUnwindCont(void) { return 0; }
        \\SEXP R_NilValue;
        \\void R_ShowMessage(const char *s) {}
        \\void *R_UnwindProtect(void *fun, void *data, void *cleanfun, void *cleandata, void *cont) { return 0; }
        \\unsigned long Rf_mbrtowc(void *wc, const char *s, unsigned long n, void *ps) { return 0; }
        \\SEXP Rf_protect(SEXP x) { return x; }
        \\char *Rf_strchr(const char *s, int c) { return 0; }
        \\void Rf_unprotect(int n) {}
        \\unsigned long Rf_utf8towcs(void *wc, const char *s, unsigned long n) { return 0; }
        \\char *libintl_dgettext(const char *domainname, const char *msgid) { return (char *)msgid; }
        \\char *libintl_gettext(const char *msgid) { return (char *)msgid; }
        \\unsigned int localeCP(void) { return 0; }
        \\
    );
    r_stub_mod.addCSourceFile(.{ .file = stub_c, .flags = &.{"-std=gnu23"} });
    const r_stub_obj = b.addObject(.{ .name = "R_stub", .root_module = r_stub_mod });
    const r_stub = winMakeImportStub(ctx, r_stub_obj.getEmittedBin(), "R.dll", "R_stub_lib");

    // ------------------------------------------------------------------
    // Rblas.dll — links against the R.dll stub for `xerbla_`/fprintf/
    // vfprintf. unix/macOS never need this because ELF/Mach-O tolerate
    // the symbol staying unresolved until runtime, when libR is already
    // loaded; PE/COFF does not.
    // ------------------------------------------------------------------
    const rblas_mod = newCMod(ctx);
    for (blas_f) |o| rblas_mod.addObjectFile(o);
    for (blas_f90) |o| rblas_mod.addObjectFile(o);
    rblas_mod.addObjectFile(r_stub);
    linkFortranRt(ctx, rblas_mod);
    const rblas = addSharedLib(ctx, "Rblas", rblas_mod);

    // ------------------------------------------------------------------
    // Rlapack.dll — one-directional (needs R.dll + Rblas.dll, but R.dll
    // does not link Rlapack back), so it also needs the stub (for the
    // same fprintf/vfprintf/xerbla_ trio, transitively via R.dll's ABI).
    // ------------------------------------------------------------------
    const rlapack_mod = newCMod(ctx);
    for (lapack_objs.items) |o| rlapack_mod.addObjectFile(o);
    rlapack_mod.addObjectFile(r_stub);
    rlapack_mod.linkLibrary(rblas);
    linkFortranRt(ctx, rlapack_mod);
    const rlapack = addSharedLib(ctx, "Rlapack", rlapack_mod);

    // ------------------------------------------------------------------
    // Rgraphapp.dll — full Win32 GUI-widget toolkit, required link-time
    // dependency of R.dll (F6.0), not exercised at runtime by Rscript.exe.
    // Also needs the R.dll stub (mutual dependency, same as Rblas.dll).
    // ------------------------------------------------------------------
    const graphapp_mod = newCMod(ctx);
    // graphapp's own internal.h must resolve before R's src/include/
    // internal.h (a same-named but unrelated file). Module-level
    // addIncludePath entries precede per-source-file "extra" cflags in the
    // actual compile invocation, so reordering only within addCGroup's
    // `extra` list (tried first) had no effect — graphapp's own dir has to
    // be added as a module include path here, before src/include, to
    // actually win the search order. Found via a real build error: gif.c's
    // `#include <internal.h>` was silently resolving to the wrong file.
    graphapp_mod.addIncludePath(ctx.path("src/extra/graphapp"));
    graphapp_mod.addIncludePath(ctx.geninc);
    graphapp_mod.addIncludePath(ctx.path("src/include"));
    addCGroup(ctx, graphapp_mod, "src/extra/graphapp", &rspec.win_graphapp_c, .{
        .extra = &.{ "-I%S/src/gnuwin32", "-DGA_DLL_BUILD", "-DENABLE_NLS=1" },
    });
    graphapp_mod.addObjectFile(r_stub);
    // gnuwin32's own Makefile.win link line is just
    // `-lR -lole32 -luuid -lcomctl32 -limm32 -lmsimg32` — it never mentions
    // gdi32/user32/comdlg32 because gcc's `-mwindows` implicitly pulls those
    // in via its default MinGW subsystem spec. zig cc/lld does not replicate
    // that implicit linking, so they must be listed explicitly here (found
    // via real link errors: gdi32 for CreateBitmap/SelectObject/etc.,
    // comdlg32 for the common-dialog APIs in dialogs.c/printer.c/init.c
    // — GetOpenFileNameA, PrintDlgA, FindTextA, GetFileTitleA, ...).
    for ([_][]const u8{ "gdi32", "user32", "comdlg32", "ole32", "uuid", "comctl32", "imm32", "msimg32" }) |lib|
        graphapp_mod.linkSystemLibrary(lib, .{ .use_pkg_config = .no });
    const rgraphapp = addSharedLib(ctx, "Rgraphapp", graphapp_mod);

    // ------------------------------------------------------------------
    // Riconv.dll — R's own bundled iconv (independent, no R.dll
    // dependency at all).
    // ------------------------------------------------------------------
    const iconv_mod = newCMod(ctx);
    // win_iconv.c does `#define BUILDING_LIBICONV` then `#include <iconv.h>`,
    // expecting R's OWN bundled fixed/h/iconv.h (which declares the matching
    // prototypes for BUILDING_LIBICONV) — not conda-forge's libiconv header,
    // which conflicts (`#if 0 && BUILDING_LIBICONV` parse error, clashing
    // `iconv`/`libiconv` macro). Same include-shadowing class of bug as
    // graphapp's internal.h: R's own dir must win, so list it before the
    // conda include path (found via a real compile error).
    iconv_mod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    iconv_mod.addIncludePath(ctx.geninc);
    iconv_mod.addIncludePath(ctx.path("src/include"));
    addCGroup(ctx, iconv_mod, "src/extra/win_iconv", &rspec.win_iconv_c, .{});
    const riconv = addSharedLib(ctx, "Riconv", iconv_mod);

    // ------------------------------------------------------------------
    // The real R.dll: r_core_mod's sources, linked for real against
    // Rblas.dll/Rgraphapp.dll/Riconv.dll (R-DLLLIBS from
    // src/gnuwin32/Makefile) — no stub involved here, this is the DLL
    // that actually gets loaded at runtime and genuinely exports every
    // symbol the stub only pretended to.
    // ------------------------------------------------------------------
    const r_final_mod = r_core_mod;
    r_final_mod.linkLibrary(rblas);
    r_final_mod.linkLibrary(rgraphapp);
    r_final_mod.linkLibrary(riconv);
    // gdi32/user32 not in gnuwin32's own R-DLLLIBS either, for the same
    // implicit-gcc-`-mwindows`-linking reason as Rgraphapp.dll above — R.dll's
    // own gnuwin32 sources (console.c, rui.c, run.c, ...) call Win32 GUI APIs
    // directly and need them listed explicitly under zig cc/lld.
    // "libbz2" not "bz2": conda-forge's Windows import lib is named
    // libbz2.lib (matching its unix lib*.a convention) rather than bz2.lib,
    // so zig's dynamic-lookup naming (which tries {name}.lib, not
    // lib{name}.lib) misses it under the plain "bz2" name — found via a real
    // link error.
    for ([_][]const u8{ "gdi32", "user32", "comctl32", "ole32", "uuid", "winmm", "version", "deflate", "pcre2-8", "z", "libbz2", "lzma", "zstd" }) |lib|
        r_final_mod.linkSystemLibrary(lib, .{ .use_pkg_config = .no });
    linkFortranRt(ctx, r_final_mod);
    // No Windows compile group currently sets `.openmp = true` (appl_c/
    // nmath_c above omit it, unlike the unix pipeline), so nothing emits
    // -fopenmp or references libomp/libgomp symbols yet — linking it here
    // was speculative copy-paste from linkOmp's unix use and just breaks the
    // link (conda-forge ships no LLVM libomp on Windows, only GCC's
    // libgomp, which isn't ABI-compatible with clang's default OpenMP
    // codegen anyway). Revisit if/when Windows OpenMP support is added.
    const libR = addSharedLib(ctx, "R", r_final_mod);
    ctx.libR = libR;
    ctx.rblas = rblas;
    ctx.rlapack = rlapack;

    // modules/lapack.dll (the loadable module, unix's mod_lapack
    // equivalent) — just Lapack.c; "flexiblas not supported on Windows"
    // per Makefile.win, so no flexiblas.c counterpart here. Unlike
    // Rblas.dll/Rlapack.dll/Rgraphapp.dll, this is a runtime-loaded module
    // (like a base package), not part of R.dll's own circular link-time
    // dependency — it needs the REAL libR (built above), not the r_stub,
    // for the R API calls (Rf_getAttrib, R_PPStack, R_chk_calloc, ...) its
    // own Lapack.c makes (found via real undefined-symbol link errors; the
    // unix build's mod_lapack already does `linkLibrary(ctx.libR)` for the
    // same reason — this was simply missing here).
    const lapmod = newCMod(ctx);
    lapmod.addIncludePath(ctx.geninc);
    lapmod.addIncludePath(ctx.path("src/include"));
    addCGroup(ctx, lapmod, "src/modules/lapack", &rspec.win_lapack_module_c, .{});
    lapmod.linkLibrary(rlapack);
    lapmod.linkLibrary(rblas);
    lapmod.linkLibrary(libR);
    linkFortranRt(ctx, lapmod);
    const mod_lapack = addSharedLib(ctx, "mod_lapack", lapmod);

    // ------------------------------------------------------------------
    // Rscript.exe — the ONLY front-end built (F6.0): same unix/Rscript.c
    // linux/macOS already use, linked against R.dll/Rgraphapp.dll/shlwapi.
    // ------------------------------------------------------------------
    const rscript_mod = newCMod(ctx);
    rscript_mod.addIncludePath(ctx.geninc);
    rscript_mod.addIncludePath(ctx.path("src/include"));
    // Same psignal.h/trioremap.h need as r_core_mod above (found via a real
    // compile error).
    rscript_mod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    addCGroup(ctx, rscript_mod, "src/unix", &.{"Rscript.c"}, .{
        // On Windows, Rscript.c's own source directly `#include "rterm.c"`
        // (with FOR_Rscript defined) as its Windows entry-point
        // implementation — not an artifact of building a separate Rterm.exe
        // (out of scope per F6.0), genuinely required for Rscript.exe
        // itself to compile here (found via a real compile error).
        .extra = &.{ "-I%S/src/gnuwin32/front-ends", ctx.absSub("-DR_HOME=\"{s}\"", .{ctx.rhome}) },
    });
    rscript_mod.linkLibrary(libR);
    rscript_mod.linkLibrary(rgraphapp);
    rscript_mod.linkSystemLibrary("shlwapi", .{ .use_pkg_config = .no });
    const rscript = b.addExecutable(.{ .name = "Rscript", .root_module = rscript_mod });

    // ------------------------------------------------------------------
    // Rterm.exe — NOT a droppable GUI front-end (F6.0's original read on
    // this was wrong): on Windows, Rscript.c's own main() handles only
    // `--version`/`--help` directly — every other invocation constructs
    // `<RHOME>\bin\x64\Rterm.exe` and re-execs it (`Rscript-LIBS`/the
    // `RHOME`-relative `Rterm.exe` path built in Rscript.c, mirroring
    // exactly how unix's Rscript re-execs `bin/R`, which is why unix
    // already builds a full `bin/exec/R` binary alongside it). Without
    // Rterm.exe actually present, every real Rscript.exe invocation beyond
    // --version/--help fails with "unable to open the base package" —
    // found via a real bootstrap failure, traced through Rscript.c's own
    // source (its Windows branch builds `cmd = "<RHOME>\\bin\\x64\\
    // Rterm.exe"` and directly re-execs it). Same gnuwin32 Makefile
    // (front-ends/Makefile) builds it from graphappmain.c (WinMain, calls
    // GA_startgraphapp then AppMain) + rterm.c (defines AppMain — the
    // console-mode R engine loop); no icon resource (not needed for our
    // CLI-only build).
    const rterm_mod = newCMod(ctx);
    rterm_mod.addIncludePath(ctx.geninc);
    rterm_mod.addIncludePath(ctx.path("src/include"));
    rterm_mod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    addCGroup(ctx, rterm_mod, "src/gnuwin32/front-ends", &.{ "graphappmain.c", "rterm.c" }, .{
        // -DWin32: R's own legacy macro (distinct from the compiler's
        // built-in _WIN32) gating `R_ext/RStartup.h`'s UImode/RGui/RTerm
        // enum — front-ends/Makefile's own `rterm-CPPFLAGS = -DWin32` does
        // the same (found via a real compile error: unknown type 'UImode').
        .extra = &.{ "-I%S/src/gnuwin32", "-DWin32" },
    });
    rterm_mod.linkLibrary(libR);
    rterm_mod.linkLibrary(rgraphapp);
    rterm_mod.linkSystemLibrary("shlwapi", .{ .use_pkg_config = .no });
    const rterm = b.addExecutable(.{ .name = "Rterm", .root_module = rterm_mod });
    // Rterm-LINKFLAGS in front-ends/Makefile: a much larger default stack
    // than MinGW's 2MB default, for R's own deep-recursion interpreter loop.
    rterm.stack_size = 0x4000000;

    // ------------------------------------------------------------------
    // Install: bin/x64/ is gnuwin32's own arch-specific binary dir
    // convention (matches smoke-test.sh's existing lookup path).
    // "Library/lib/R", not "lib/R" — must match ctx.rhome (NTFS is
    // case-insensitive and collides with Python's "Lib" otherwise;
    // `-DR_HOME` embedded in Rscript.c above already uses ctx.rhome, so
    // the actual install location has to agree with it (found via a real
    // mismatch: everything installed under plain lib/R while R_HOME
    // pointed at Library/lib/R).
    // ------------------------------------------------------------------
    const bin_dir: std.Build.InstallDir = .{ .custom = "Library/lib/R/bin/x64" };
    // modules/x64/, not modules/ — R's module loader is just as
    // R_ARCH-aware as library.dynam() (see the platform.c/.Platform$r_arch
    // fix above); once R_ARCH was actually set correctly, R started
    // looking for "modules/x64/lapack.dll" specifically and failed to find
    // it at the (correctly-built, but wrongly-located) "modules/lapack.dll"
    // — found via a real "LoadLibrary failure: module not found" error for
    // a file that verifiably existed.
    const modules_dir: std.Build.InstallDir = .{ .custom = "Library/lib/R/modules/x64" };
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(libR.getEmittedBin(), bin_dir, "R.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rblas.getEmittedBin(), bin_dir, "Rblas.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rlapack.getEmittedBin(), bin_dir, "Rlapack.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rgraphapp.getEmittedBin(), bin_dir, "Rgraphapp.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(riconv.getEmittedBin(), bin_dir, "Riconv.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(mod_lapack.getEmittedBin(), modules_dir, "lapack.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rscript.getEmittedBin(), bin_dir, "Rscript.exe").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rterm.getEmittedBin(), bin_dir, "Rterm.exe").step);

    // ------------------------------------------------------------------
    // Base-package shared libs (library/<pkg>/libs/x64/<pkg>.dll — R's
    // Windows `library.dynam()` looks in an arch-specific `libs/x64/`
    // subdir, unlike unix's flat `libs/<pkg>.so`). Bootstrap's per-package
    // `tools:::makeLazyLoading(pkg)`/mklazycomp steps need the compiled
    // library loadable already for any base package that has one — found
    // via a real bootstrap failure ("DLL 'tools' not found") once the
    // R_HOME/backslash fixes let bootstrap actually reach that far.
    // Starting with the packages needed for bootstrap to progress; extend
    // as later steps reveal more (same iterative approach as the rest of
    // this build.zig).
    var win_pkg_libs = std.ArrayList(WinPkgLib).empty;
    {
        const m = newPkgMod(ctx, "src/library/tools/src", &rspec.tools_c, .{
            .extra = &.{"-I%S/src/main"},
        });
        // Unlike unix (ELF tolerates undefined symbols in shared libs, so
        // packages there never link libR directly — see addSharedLib's own
        // doc comment), PE/COFF needs every base-package DLL to link libR
        // explicitly for its R API calls (same reason mod_lapack needed it
        // — found via a real link error, ~100 undefined Rf_*/R_* symbols).
        m.linkLibrary(libR);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "tools", .lib = addSharedLib(ctx, "pkg_tools", m) });
    }
    {
        // grDevices needs its own DLL earlier than most base packages:
        // `tools:::makeLazyLoading("grDevices")` itself fails without it
        // (found via a real bootstrap failure), unlike e.g. utils/methods/
        // parallel/splines/graphics/stats, whose own mklazycomp steps
        // succeeded fine without their compiled libs existing yet — their
        // compiled code is only actually touched once something really
        // attaches the namespace via library(), not during bootstrap.
        const m = newPkgMod(ctx, "src/library/grDevices/src", &rspec.win_grdevices_c, .{
            // devWindows.c needs opt.h/console.h/rui.h/graphapp headers
            // (gnuwin32, extra) plus R_ARCH for its own .Platform$r_arch-
            // style path logic; winbitmap.c needs the bitmap format
            // #defines — both straight from grDevices/src/Makefile.win's
            // own per-file CPPFLAGS.
            .extra = &.{ "-I%S/src/gnuwin32", "-I%S/src/extra", "-DR_ARCH=\"x64\"", "-DHAVE_PNG", "-DHAVE_JPEG", "-DHAVE_TIFF" },
        });
        m.linkLibrary(libR);
        m.linkLibrary(rgraphapp);
        // grDevices/src/Makefile.win's own PKG_LIBS: -lpng -ltiff -ljpeg
        // -lzstd -lz -lwebp -llzma (skipping the optional LIBLERC/
        // LIBDEFLATE/LIBSHARPYUV extras unless a real link error needs one).
        // "libpng" not "png": conda-forge's Windows import lib is named
        // libpng.lib, not png.lib (same lib{name}.lib naming quirk as
        // libbz2 earlier — found via a real link error). webp dropped
        // entirely: conda-forge's Windows env doesn't ship it at all here
        // (no webp/libwebp lib file anywhere in Library/lib).
        for ([_][]const u8{ "libpng", "tiff", "jpeg", "zstd", "z", "lzma" }) |lib|
            m.linkSystemLibrary(lib, .{ .use_pkg_config = .no });
        try win_pkg_libs.append(b.allocator, .{ .pkg = "grDevices", .lib = addSharedLib(ctx, "pkg_grDevices", m) });
    }
    {
        // grDevices' own bootstrap step (`tools:::makeLazyLoading
        // ("grDevices")`) transitively loadNamespace()s utils (a NAMESPACE
        // import) — found via a real bootstrap failure once grDevices'
        // own DLL was in place.
        const m = newPkgMod(ctx, "src/library/utils/src", &rspec.win_utils_c, .{
            .extra = &.{ "-I%S/src/main", "-I%S/src/gnuwin32", "-I%S/src/extra", "-I%S/src/library/grDevices/src" },
        });
        // windows/*.c (dataentry/dialogs/registry/util/widgets) — a second
        // source group on the same module, per Makefile.win's SOURCES_C.
        addCGroup(ctx, m, "src/library/utils/src/windows", &rspec.win_utils_windows_c, .{
            .extra = &.{ "-DNDEBUG", "-I%S/src/main", "-I%S/src/gnuwin32", "-I%S/src/extra", "-I%S/src/library/grDevices/src" },
        });
        m.linkLibrary(libR);
        m.linkLibrary(rgraphapp);
        m.linkSystemLibrary("version", .{ .use_pkg_config = .no });
        m.linkSystemLibrary("lzma", .{ .use_pkg_config = .no });
        try win_pkg_libs.append(b.allocator, .{ .pkg = "utils", .lib = addSharedLib(ctx, "pkg_utils", m) });
    }
    {
        // stats' bootstrap step namespace-imports graphics — found via a
        // real bootstrap failure. Windows source list is identical to
        // unix's graphics_c (graphics/src/Makefile.win's own SOURCES_C).
        const m = newPkgMod(ctx, "src/library/graphics/src", &rspec.graphics_c, .{
            .extra = &.{"-I%S/src/main"},
        });
        m.linkLibrary(libR);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "graphics", .lib = addSharedLib(ctx, "pkg_graphics", m) });
    }
    {
        // datasets' bootstrap step namespace-imports stats — found via a
        // real bootstrap failure. Windows source list is identical to
        // unix's stats_c/stats_f (stats/src/Makefile.win's own SOURCES_C/
        // SOURCES_F); needs LAPACK_LIBS/BLAS_LIBS/FLIBS, same as Rblas.dll/
        // Rlapack.dll themselves.
        const stats_f_win = fortranGroup(ctx, "src/library/stats/src", &rspec.stats_f, &.{});
        const m = newPkgMod(ctx, "src/library/stats/src", &rspec.stats_c, .{});
        for (stats_f_win) |o| m.addObjectFile(o);
        m.linkLibrary(libR);
        m.linkLibrary(rlapack);
        m.linkLibrary(rblas);
        linkFortranRt(ctx, m);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "stats", .lib = addSharedLib(ctx, "pkg_stats", m) });
    }
    {
        // methods RfilesLazy needs its own DLL — same source list as unix
        // (methods/src/Makefile.win's own SOURCES_C).
        const m = newPkgMod(ctx, "src/library/methods/src", &rspec.methods_c, .{});
        m.linkLibrary(libR);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "methods", .lib = addSharedLib(ctx, "pkg_methods", m) });
    }
    {
        // Same source list as unix (grid/src/Makefile.win's own SOURCES_C).
        const m = newPkgMod(ctx, "src/library/grid/src", &rspec.grid_c, .{});
        m.linkLibrary(libR);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "grid", .lib = addSharedLib(ctx, "pkg_grid", m) });
    }
    {
        // Same source list as unix (splines/src/Makefile.win's own SOURCES_C).
        const m = newPkgMod(ctx, "src/library/splines/src", &rspec.splines_c, .{});
        m.linkLibrary(libR);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "splines", .lib = addSharedLib(ctx, "pkg_splines", m) });
    }
    {
        // Windows source list drops fork.c (no fork() on Windows) for
        // ncpus.c (Windows CPU-count detection) instead — parallel/src/
        // Makefile.win's own SOURCES_C: `init.c rngstream.c ncpus.c`.
        const m = newPkgMod(ctx, "src/library/parallel/src", &.{ "init.c", "rngstream.c", "ncpus.c" }, .{});
        m.linkLibrary(libR);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "parallel", .lib = addSharedLib(ctx, "pkg_parallel", m) });
    }

    // ------------------------------------------------------------------
    // library/ + share/ + doc/ + bootstrap: without this, Rscript.exe can
    // link/load fine but can't evaluate any real code (no base package to
    // find) — `Rscript.exe --version` works either way (doesn't touch
    // R_HOME's tree at all), but `-e` needs the full bootstrap below.
    // ------------------------------------------------------------------
    const libstage_dir = try installLibraryWindows(ctx, io, win_pkg_libs.items);
    const boot_step = try bootstrap(ctx, io, libstage_dir.getDirectory());

    const top = b.step("r", "Build R.dll+Rblas+Rlapack+Rgraphapp+Riconv+Rscript.exe (Windows, CLI-only — F6.0)");
    top.dependOn(boot_step);
    b.default_step = top;
}

const WinPkgLib = struct { pkg: []const u8, lib: *std.Build.Step.Compile };

/// Windows equivalent of installStaticTree: stages library/ (via the shared
/// stageLibraryPayload), share/, doc/, and include/ under ctx.rhome
/// (Library/lib/R/...). No bin/R wrapper, no etc/{Renviron,ldpaths,
/// Makeconf,javaconf} — Rscript.exe is the only front end (F6.0) and the
/// package-compilation contract (Makeconf.win wiring) is still deferred
/// (F6.1/1b territory), so there's nothing to consume those yet; revisit if
/// bootstrap or a real package build turns out to need one of them after all.
fn installLibraryWindows(ctx: *Ctx, io: std.Io, pkg_libs: []const WinPkgLib) !*std.Build.Step.WriteFile {
    const b = ctx.b;
    const inst = b.getInstallStep();
    const libstage = b.addWriteFiles();

    try stageLibraryPayload(ctx, io, libstage, "windows", "windows");
    // library/<pkg>/libs/x64/<pkg>.dll — gnuwin32's own arch-specific
    // `libs$(R_ARCH)` convention (found via a real "DLL not found: maybe
    // not installed for this architecture?" error).
    for (pkg_libs) |pl| {
        _ = libstage.addCopyFile(pl.lib.getEmittedBin(), b.fmt("{s}/libs/x64/{s}.dll", .{ pl.pkg, pl.pkg }));
    }

    // include/ (public headers) — not consumed by anything yet (package
    // compilation isn't wired up on Windows), but installed alongside
    // share/doc for parity with the unix layout.
    const inc_wf = b.addWriteFiles();
    for (rspec.public_headers) |h| {
        _ = inc_wf.addCopyFile(ctx.path(b.fmt("src/include/{s}", .{h})), h);
    }
    _ = inc_wf.addCopyFile(ctx.geninc.path(b, "Rconfig.h"), "Rconfig.h");
    _ = inc_wf.addCopyFile(ctx.geninc.path(b, "Rversion.h"), "Rversion.h");
    _ = inc_wf.addCopyFile(ctx.geninc.path(b, "Rmath.h"), "Rmath.h");
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = inc_wf.getDirectory(),
        .install_dir = .{ .custom = "Library/lib/R/include" },
        .install_subdir = "",
    }).step);
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("src/include/R_ext"),
        .install_dir = .{ .custom = "Library/lib/R/include/R_ext" },
        .install_subdir = "",
        .include_extensions = &.{".h"},
    }).step);

    // etc/repositories: R reads this at startup for install.packages()'s
    // default CRAN-mirror-style repo list — cheap to install even though
    // the rest of etc/ (Renviron/ldpaths/Makeconf/javaconf) stays deferred
    // (found via a real bootstrap warning, not yet fatal but trivial to fix).
    inst.dependOn(&b.addInstallFileWithDir(ctx.path("etc/repositories"), .{ .custom = "Library/lib/R/etc" }, "repositories").step);
    // etc/Rconsole: rterm.c's AppMain() unconditionally calls
    // readconsolecfg() on startup, which R_Suicide()s with exit(10) and
    // ZERO output if it can't find *either* $R_USER/Rconsole or
    // $R_HOME/etc/Rconsole — this is what was silently killing every
    // `Rscript.exe -e`/non-`--vanilla` Rterm.exe invocation (found by
    // testing Rterm.exe directly with `--vanilla` — which works — vs. its
    // documented individual-flag expansion — which still failed the same
    // way, then tracing exit code 10 to this exact R_Suicide call). gnuwin32
    // ships a static, ready-to-use etc/Rconsole (like config.h/Rconsole.h);
    // vendor it as-is rather than reverse-engineering a `--vanilla`-only
    // workaround.
    inst.dependOn(&b.addInstallFileWithDir(ctx.path("src/gnuwin32/fixed/etc/Rconsole"), .{ .custom = "Library/lib/R/etc" }, "Rconsole").step);

    // share/ and doc/ wholesale from the source tree — same content as
    // unix, installed under the Windows R_HOME layout.
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("share"),
        .install_dir = .{ .custom = "Library/lib/R/share" },
        .install_subdir = "",
        .exclude_extensions = &.{"Makefile.in"},
    }).step);
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("doc"),
        .install_dir = .{ .custom = "Library/lib/R/doc" },
        .install_subdir = "",
        .exclude_extensions = &.{ "Makefile.in", ".texi", "R.aux", "Rscript.aux" },
    }).step);

    // utils iconvlist (basepkg iconvlist target: `iconv -l`) — same as
    // unix; conda-forge's Windows env also ships iconv.exe.
    const iconv_run = b.addSystemCommand(&.{ "iconv", "-l" });
    const iconv_out = iconv_run.captureStdOut(.{});
    _ = libstage.addCopyFile(iconv_out, "utils/iconvlist");

    return libstage;
}

/// Build a proper, complete dlltool-generated import library for `dllname`
/// covering exactly `symbols` — same dlltool mechanism as winMakeImportStub
/// below, but from a hardcoded symbol list rather than an object's own
/// exports. First tried extracting the individual archive members that
/// define these symbols straight out of conda-forge's real libgcc_s.a
/// (`-lgcc_s`/`-lgcc`/`-lgcc_eh` in any combination couldn't get lld-link to
/// resolve them at all) — that got Rlapack.dll to LINK, but the resulting
/// R.dll then failed to LOAD at runtime with STATUS_DLL_NOT_FOUND:
/// hand-assembling fragments of an import library skips whatever else
/// dlltool normally bundles alongside each symbol's thunk (e.g.
/// null-descriptor/null-thunk terminator members marking the end of the
/// import directory), which the real Windows loader needs even though
/// lld-link's own linking didn't complain. Generating a fresh, complete
/// import lib through dlltool's normal path avoids relying on the internal
/// structure of a real DLL's own import archive at all.
fn winMakeImportLibFor(ctx: *const Ctx, dllname: []const u8, symbols: []const []const u8, out_stem: []const u8) std.Build.LazyPath {
    const b = ctx.b;
    var def_body = std.ArrayList(u8).empty;
    def_body.appendSlice(b.allocator, "EXPORTS\n") catch @panic("OOM");
    for (symbols) |s| {
        def_body.appendSlice(b.allocator, s) catch @panic("OOM");
        def_body.append(b.allocator, '\n') catch @panic("OOM");
    }
    const wf = b.addWriteFiles();
    const def = wf.add(b.fmt("{s}.def", .{out_stem}), def_body.items);
    const run = b.addSystemCommand(&.{
        "x86_64-w64-mingw32-dlltool", "--dllname", dllname, "--input-def",
    });
    run.addFileArg(def);
    run.addArg("--output-lib");
    const implib = run.addOutputFileArg(b.fmt("{s}.dll.a", .{out_stem}));
    run.setName(b.fmt("win import lib for {s} ({s})", .{ dllname, out_stem }));
    return implib;
}

/// PE/COFF (unlike ELF/Mach-O) refuses to link a DLL with unresolved
/// symbols, so R.dll's mutual dependency with Rblas.dll/Rgraphapp.dll
/// needs breaking the same way gnuwin32's own make build does: derive an
/// import library from the *object file's* exported symbols before the
/// real DLL exists, exactly mirroring gnuwin32's own Rlapack.def/R.exp
/// generation (`nm | sed -n <SYMPAT> | sort -u`, then `dlltool`).
fn winMakeImportStub(ctx: *const Ctx, obj: std.Build.LazyPath, dllname: []const u8, out_stem: []const u8) std.Build.LazyPath {
    const b = ctx.b;
    const run = b.addSystemCommand(&.{
        "sh", "-c",
        \\set -e
        \\echo EXPORTS > "$2"
        \\x86_64-w64-mingw32-nm "$1" | sed -n 's/^[0-9a-fA-F]* [BCDRT] //p' | sort -u >> "$2"
        \\x86_64-w64-mingw32-dlltool --dllname "$4" --input-def "$2" --output-lib "$3"
        ,
        "make-implib",
    });
    run.setName(b.fmt("win import stub for {s}", .{dllname}));
    run.addFileArg(obj);
    const def = run.addOutputFileArg(b.fmt("{s}.def", .{out_stem}));
    _ = def;
    const implib = run.addOutputFileArg(b.fmt("{s}.dll.a", .{out_stem}));
    run.addArg(dllname);
    return implib;
}

// ----------------------------------------------------------------------
// `zig build check`: R's own regression suite (make check), replayed
// against the zig-built R the same way `make check` runs it against an
// autoconf objdir — see FINALIZATION.md phase F1.1.
// ----------------------------------------------------------------------

/// Runs the base-package Examples + Specific + Reg subsets of R's `make
/// check` (skips Internet — needs network, already `-@`-guarded upstream;
/// skips Packages/recommended — not built here; skips Embedding/Standalone
/// — separate opt-in targets, not part of plain `check`).
fn addCheckStep(ctx: *Ctx, io: std.Io, r_top: *std.Build.Step) !void {
    const b = ctx.b;

    const wf = b.addWriteFiles();
    // Fake "top_builddir" for the test Makefiles: bin/R + a top-level
    // Makeconf (config.status's *other* Makeconf.in — distinct from
    // etc/Makeconf.in — is what tests/Makefile's `include .../Makeconf`
    // wants). config.status itself is stubbed: tests/Makefile's `Makefile:
    // ... $(top_builddir)/config.status` rule only re-fires if this file
    // is missing or newer than the Makefile, so an empty stub that predates
    // our generated Makefile (WriteFiles are all written together) is
    // enough to keep `make` from trying to regenerate anything.
    _ = wf.add("bin/R", b.fmt("#!/bin/sh\nexec \"{s}/bin/R\" \"$@\"\n", .{ctx.rhome}));
    _ = wf.add("Makeconf", try substFile(ctx, io, "Makeconf.in"));
    _ = wf.add("config.status", "#!/bin/sh\nexit 0\n");
    _ = wf.add("tests/Makefile", try substFileTests(ctx, io, "tests/Makefile.in", ctx.b.fmt("{s}/tests", .{ctx.src_abs})));
    _ = wf.addCopyFile(ctx.path("tests/Makefile.common"), "tests/Makefile.common");
    _ = wf.add("tests/Examples/Makefile", try substFileTests(ctx, io, "tests/Examples/Makefile.in", ctx.b.fmt("{s}/tests/Examples", .{ctx.src_abs})));

    const dir = wf.getDirectory();

    const chmod = b.addSystemCommand(&.{"chmod"});
    chmod.setName("chmod +x check bin/R");
    chmod.addArg("+x");
    chmod.addFileArg(dir.path(b, "bin/R"));
    chmod.step.dependOn(&wf.step);
    chmod.step.dependOn(r_top);

    // zig cache artifacts can be read-only; make needs to write .Rout files
    // (and directories to create Examples/*.Rd, .Rin etc) under this tree.
    const chmod_w = b.addSystemCommand(&.{ "chmod", "-R", "u+w" });
    chmod_w.setName("chmod -R u+w check tree");
    chmod_w.addDirectoryArg(dir);
    chmod_w.step.dependOn(&chmod.step);

    const check = b.step("check", "Run R's regression suite (Examples/Specific/Reg) against the zig-built R");
    for ([_][]const u8{ "test-Examples", "test-Specific", "test-Reg" }) |target| {
        const run = b.addSystemCommand(&.{ "make", "-C" });
        run.setName(b.fmt("make check: {s}", .{target}));
        run.addDirectoryArg(dir.path(b, "tests"));
        run.addArg(target);
        run.setEnvironmentVariable("TZ", "UTC");
        run.has_side_effects = true;
        run.step.dependOn(&chmod_w.step);
        check.dependOn(&run.step);
    }
}

/// Like substFile, but with a caller-supplied `srcdir` (each generated
/// subdirectory Makefile needs its own — config.status computes these
/// per-output-file; we only ever generate two, so just override directly).
fn substFileTests(ctx: *Ctx, io: std.Io, rel: []const u8, srcdir_val: []const u8) ![]u8 {
    const old = ctx.subst.get("srcdir").?;
    try ctx.subst.put("srcdir", srcdir_val);
    const out = try substFile(ctx, io, rel);
    try ctx.subst.put("srcdir", old);
    return out;
}

// ----------------------------------------------------------------------
// helpers
// ----------------------------------------------------------------------

fn findFlangRt(b: *std.Build, io: std.Io, conda: []const u8) ![]const u8 {
    // libflang_rt.runtime.a lives at $CONDA/lib/clang/<ver>/lib/<triple>/
    const clang_root = b.fmt("{s}/lib/clang", .{conda});
    var dir = std.Io.Dir.cwd().openDir(io, clang_root, .{ .iterate = true }) catch {
        return error.FlangRtNotFound;
    };
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |ent| {
        if (ent.kind != .directory) continue;
        const cand = b.fmt("{s}/{s}/lib/x86_64-unknown-linux-gnu", .{ clang_root, ent.name });
        std.Io.Dir.cwd().access(io, b.fmt("{s}/libflang_rt.runtime.a", .{cand}), .{}) catch continue;
        return cand;
    }
    return error.FlangRtNotFound;
}

/// libgfortran.dll.a/libquadmath.dll.a live under $CONDA/Library/lib/gcc/
/// x86_64-w64-mingw32/<gcc-version>/ (not directly under Library/lib, unlike
/// most other conda-forge Windows libs) — found via a real link error
/// ("unable to find dynamic system library 'gfortran'"). Scan for the single
/// installed gcc version rather than hardcoding it, since it tracks whatever
/// gcc_impl_win-64/gfortran_win-64 build conda-forge currently ships.
fn findGfortranLibDir(b: *std.Build, io: std.Io, conda: []const u8) ![]const u8 {
    const gcc_root = b.fmt("{s}/Library/lib/gcc/x86_64-w64-mingw32", .{conda});
    var dir = std.Io.Dir.cwd().openDir(io, gcc_root, .{ .iterate = true }) catch {
        return error.GfortranLibNotFound;
    };
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |ent| {
        if (ent.kind != .directory) continue;
        const cand = b.fmt("{s}/{s}", .{ gcc_root, ent.name });
        std.Io.Dir.cwd().access(io, b.fmt("{s}/libgfortran.dll.a", .{cand}), .{}) catch continue;
        return cand;
    }
    return error.GfortranLibNotFound;
}

fn newCMod(ctx: *const Ctx) *std.Build.Module {
    const m = ctx.b.createModule(.{
        .target = ctx.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .pic = true,
        .sanitize_c = .off,
    });
    // LDFLAGS from Makeconf: -L$CONDA/lib -Wl,-rpath,$CONDA/lib on every
    // link. On Windows conda-forge libs live under Library/lib (the
    // conda-forge convention for non-Python Windows content), and rpath
    // is an ELF/Mach-O concept that doesn't exist for PE — DLL search
    // there is PATH/same-directory based instead, so skip addRPath.
    switch (ctx.os) {
        .windows => {
            m.addLibraryPath(.{ .cwd_relative = ctx.b.fmt("{s}/Library/lib", .{ctx.conda}) });
        },
        else => {
            m.addLibraryPath(.{ .cwd_relative = ctx.b.fmt("{s}/lib", .{ctx.conda}) });
            m.addRPath(.{ .cwd_relative = ctx.b.fmt("{s}/lib", .{ctx.conda}) });
        },
    }
    return m;
}

/// Every shared lib/module/package .so in this build (base packages don't
/// link libR directly — its symbols resolve at runtime since libR is
/// already loaded into the R process; "zig allows undefined symbols in
/// shared libs" on ELF/linux, verified). Mach-O's lld backend does NOT
/// tolerate that by default (link fails with "undefined symbol" on every
/// R API call packages make) — the real macOS make build's Makeconf
/// carries `-undefined dynamic_lookup` on every SHLIB_LDFLAGS/DYLIB_LDFLAGS
/// for exactly this; `linker_allow_shlib_undefined` is zig's equivalent
/// knob (found via FINALIZATION.md F5.1's first real build attempt, not
/// anticipated in the spec).
fn addSharedLib(ctx: *const Ctx, name: []const u8, mod: *std.Build.Module) *std.Build.Step.Compile {
    const lib = ctx.b.addLibrary(.{ .linkage = .dynamic, .name = name, .root_module = mod });
    if (ctx.os == .macos) lib.linker_allow_shlib_undefined = true;
    return lib;
}

const CGroupOpts = struct {
    openmp: bool = false,
    extra: []const []const u8 = &.{}, // %S → srcdir, %C → conda
};

fn addCGroup(ctx: *const Ctx, mod: *std.Build.Module, dir: []const u8, files: []const []const u8, opts: CGroupOpts) void {
    const b = ctx.b;
    var flags = std.ArrayList([]const u8).empty;
    flags.appendSlice(b.allocator, &.{ "-std=gnu23", "-fno-sanitize=undefined", "-O2", "-fpic", "-DHAVE_CONFIG_H" }) catch @panic("OOM");
    if (opts.openmp) flags.append(b.allocator, "-fopenmp") catch @panic("OOM");
    for (opts.extra) |f| {
        const f1 = std.mem.replaceOwned(u8, b.allocator, f, "%S", ctx.src_abs) catch @panic("OOM");
        const f2 = std.mem.replaceOwned(u8, b.allocator, f1, "%C", ctx.conda) catch @panic("OOM");
        flags.append(b.allocator, f2) catch @panic("OOM");
    }
    const conda_inc = if (ctx.os == .windows) b.fmt("{s}/Library/include", .{ctx.conda}) else b.fmt("{s}/include", .{ctx.conda});
    flags.append(b.allocator, b.fmt("-I{s}", .{conda_inc})) catch @panic("OOM");
    mod.addCSourceFiles(.{ .root = ctx.path(dir), .files = files, .flags = flags.items });
}

/// Package src modules share the pattern: -DNDEBUG, geninc+src/include.
fn newPkgMod(ctx: *const Ctx, dir: []const u8, files: []const []const u8, opts: CGroupOpts) *std.Build.Module {
    const b = ctx.b;
    const m = newCMod(ctx);
    m.addIncludePath(ctx.geninc);
    m.addIncludePath(ctx.path("src/include"));
    // Same psignal.h/trioremap.h need as r_core_mod/rscript_mod — any base
    // package's C source including <Defn.h> hits this too (found via a
    // real compile error compiling pkg_tools, the first package DLL built
    // for Windows).
    if (ctx.os == .windows) m.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    var extra = std.ArrayList([]const u8).empty;
    extra.append(b.allocator, "-DNDEBUG") catch @panic("OOM");
    extra.appendSlice(b.allocator, opts.extra) catch @panic("OOM");
    addCGroup(ctx, m, dir, files, .{ .openmp = opts.openmp, .extra = extra.items });
    return m;
}

fn linkCoreLibs(ctx: *const Ctx, mod: *std.Build.Module) void {
    // LIBS from the vendored S-table: pcre2, compression stack, dl/m,
    // iconv, ICU — pulled from subst.txt (not hand-listed) specifically so
    // platform differences (e.g. linux's "-lrt" for POSIX realtime timers,
    // which doesn't exist as a separate lib on macOS — those symbols are
    // in libSystem there) come from the real configure capture, not a
    // hardcoded list that would silently omit the macOS port's needs.
    mod.addLibraryPath(.{ .cwd_relative = ctx.b.fmt("{s}/lib", .{ctx.conda}) });
    mod.addRPath(.{ .cwd_relative = ctx.b.fmt("{s}/lib", .{ctx.conda}) });
    applyLinkFlags(ctx, mod, ctx.subst.get("LIBS").?);
    // full only: src/unix/sys-std.c + sys-unix.c + src/main/platform.c
    // already compile their HAVE_LIBREADLINE branch correctly (it comes
    // from the per-variant vendored config.h); just needs -lreadline.
    if (ctx.variant == .full) mod.linkSystemLibrary("readline", .{ .use_pkg_config = .no });
    // LIBINTL: empty on linux (glibc provides gettext() natively) but a
    // REAL value on macOS full (`-lintl -framework CoreFoundation` —
    // macOS's libc has no gettext at all, unlike glibc). Found the hard
    // way: omitting this let `-undefined dynamic_lookup` (needed for the
    // base-package link, addSharedLib) mask the missing gettext symbols at
    // link time, then crash with SIGSEGV at a null function pointer the
    // instant R's startup code called _() (gettext) for the first time —
    // slim never hit it (NLS off, LIBINTL empty there too).
    applyLinkFlags(ctx, mod, ctx.subst.get("LIBINTL").?);
    linkOmp(ctx, mod);
}

fn linkOmp(ctx: *const Ctx, mod: *std.Build.Module) void {
    // zig cc does -fopenmp codegen but ships no libomp — conda-forge's.
    switch (ctx.os) {
        .windows => mod.addLibraryPath(.{ .cwd_relative = ctx.b.fmt("{s}/Library/lib", .{ctx.conda}) }),
        else => {
            mod.addLibraryPath(.{ .cwd_relative = ctx.b.fmt("{s}/lib", .{ctx.conda}) });
            mod.addRPath(.{ .cwd_relative = ctx.b.fmt("{s}/lib", .{ctx.conda}) });
        },
    }
    mod.linkSystemLibrary("omp", .{ .use_pkg_config = .no });
}

/// Link the Fortran runtime: flang_rt.runtime on linux (found by
/// findFlangRt's clang-resource-dir search); gfortran's own runtime libs
/// on macOS, taken straight from the vendored FLIBS (captured on omicron:
/// `-L.../lib/gcc/<triple>/<ver> -L.../lib/gcc -lemutls_w -lheapt_w
/// -lgfortran -lquadmath` — gfortran's private libdir convention, distinct
/// from flang's single clang-resource-dir .a file).
fn linkFortranRt(ctx: *const Ctx, mod: *std.Build.Module) void {
    switch (ctx.os) {
        .linux => {
            mod.addLibraryPath(.{ .cwd_relative = ctx.flangrt_dir });
            mod.linkSystemLibrary("flang_rt.runtime", .{ .use_pkg_config = .no });
            mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
        },
        .macos => applyLinkFlags(ctx, mod, ctx.subst.get("FLIBS").?),
        // No real `configure` capture on Windows (F6) to pull FLIBS from
        // — conda-forge's MinGW gfortran runtime libs, standard names,
        // found on the default library search path already set up by
        // newCMod (Library/lib); unverified against a real config.status,
        // revisit if link errors surface a different need.
        .windows => {
            // libgfortran.dll.a/libquadmath.dll.a (dynamic import stubs for
            // the real libgfortran-5.dll/libquadmath-0.dll runtime, both
            // present in Library/bin) live in a gcc-version-specific
            // subdirectory, not directly on the default Library/lib search
            // path — add it explicitly (found via a real link error).
            mod.addLibraryPath(.{ .cwd_relative = ctx.gfortran_lib_dir });
            mod.linkSystemLibrary("gfortran", .{ .use_pkg_config = .no });
            mod.linkSystemLibrary("quadmath", .{ .use_pkg_config = .no });
            // libgfortran.a itself references __gthr_win32_create/_join/_self
            // (MinGW's generic-thread glue), __emutls_get_address
            // (emulated-TLS helper), and _Unwind_GetIPInfo/_Unwind_Backtrace
            // (libbacktrace) — needed only by Rlapack.dll's f90-module LAPACK
            // code specifically (Rblas.dll/R.dll's plain f77 objects never
            // pull in libgfortran's error/async-I/O runtime that references
            // them). All are real exports of the actual libgcc_s_seh-1.dll
            // runtime (present in Library/bin) but `-lgcc_s`/`-lgcc`/
            // `-lgcc_eh` in any combination couldn't get lld-link to resolve
            // them, and hand-extracting the individual archive members that
            // define them (tried first) got everything to LINK but produced
            // an R.dll that failed to LOAD at runtime (STATUS_DLL_NOT_FOUND)
            // — an incomplete/malformed import table, missing whatever else
            // a real dlltool-built import archive bundles alongside each
            // symbol's thunk. Generating a fresh, complete import library
            // through dlltool's normal path (same mechanism as the R_stub
            // import lib above) sidesteps both problems at once.
            const gthr_lib = winMakeImportLibFor(ctx, "libgcc_s_seh-1.dll", &.{
                "__gthr_win32_create",
                "__gthr_win32_join",
                "__gthr_win32_self",
                "__emutls_get_address",
                "_Unwind_GetIPInfo",
                "_Unwind_Backtrace",
            }, "gthr_win32_lib");
            mod.addObjectFile(gthr_lib);
        },
    }
}

/// Tokenize a "-L/x -lfoo ..." string into module link calls.
fn applyLinkFlags(ctx: *const Ctx, mod: *std.Build.Module, flags: []const u8) void {
    var it = std.mem.tokenizeScalar(u8, flags, ' ');
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-L")) {
            mod.addLibraryPath(.{ .cwd_relative = ctx.b.dupe(tok[2..]) });
            mod.addRPath(.{ .cwd_relative = ctx.b.dupe(tok[2..]) });
        } else if (std.mem.startsWith(u8, tok, "-l")) {
            mod.linkSystemLibrary(ctx.b.dupe(tok[2..]), .{ .use_pkg_config = .no });
        } else if (std.mem.eql(u8, tok, "-framework")) {
            // macOS only (e.g. CAIRO_LIBS/LIBINTL carry "-framework X" as
            // two tokens) — silently dropped before this fix, since
            // neither "-framework" nor the framework name matched -L/-l;
            // harmless on linux (this token never appears there).
            if (it.next()) |name| mod.linkFramework(ctx.b.dupe(name), .{});
        }
    }
}

/// F2.3: zig's linker adds a RUNPATH entry for the build/zig-cache path of
/// every sibling artifact a module links against (e.g. libR.so -> the
/// zig-cache location it found libRblas.so at) — harmless in place (it's
/// relative, so it only resolves if a process happens to run with that
/// exact cwd, which never happens outside `zig build` itself) but it's
/// grit the make build never had, and stage.sh's downstream rpath rewrite
/// shouldn't have to clean up zig-specific debris it didn't create. Strip
/// every non-absolute RUNPATH entry, keeping the real conda/flang-rt ones.
fn fixRpath(ctx: *const Ctx, in: std.Build.LazyPath, out_name: []const u8) std.Build.LazyPath {
    // macOS (F5.2): patchelf is ELF-only. Mach-O's equivalent grit (zig
    // may add a load-command referencing the zig-cache path of a sibling
    // artifact) is handled by stage.sh's existing install_name_tool +
    // mandatory ad-hoc re-codesign pass instead of duplicating Mach-O
    // surgery here — per FINALIZATION.md F5.2, leave it there.
    if (ctx.os == .macos) return in;

    const b = ctx.b;
    const run = b.addSystemCommand(&.{
        "sh", "-c",
        \\set -e
        \\rp="$(patchelf --print-rpath "$1")"
        \\newrp="$(printf '%s' "$rp" | tr ':' '\n' | grep '^/' | tr '\n' ':' | sed 's/:$//')"
        \\cp "$1" "$2"
        \\chmod u+w "$2"
        \\patchelf --set-rpath "$newrp" "$2"
        ,
        "fix-rpath",
    });
    run.setName(b.fmt("fix-rpath {s}", .{out_name}));
    run.addFileArg(in);
    return run.addOutputFileArg(out_name);
}

const FortranOut = struct { obj: std.Build.LazyPath, mods: std.Build.LazyPath };

fn fortranOne(ctx: *const Ctx, dir: []const u8, file: []const u8, mod_deps: []const std.Build.LazyPath) FortranOut {
    const b = ctx.b;
    // flang (linux): -module-dir sets/searches the module output dir.
    // gfortran (macOS): -J does the same job (its own flag spelling).
    // gfortran-darwin -O2 miscompiles complex LAPACK (zgesdd — silent
    // wrong SVD, found on real hardware in an earlier milestone); cap at
    // -O1 there, exactly like configure-r.sh's FOPT logic.
    const compiler = switch (ctx.os) {
        .linux => "flang",
        .macos, .windows => "gfortran",
    };
    // Windows' own Makeconf.win default is -O3, but the complex-LAPACK
    // miscompile risk found on gfortran-darwin is unverified either way
    // on MinGW gfortran — cautious -O2 for a first working build; revisit
    // via `make check` (F1.1-equivalent) before trusting -O3 there.
    const opt = switch (ctx.os) {
        .linux, .windows => "-O2",
        .macos => "-O1",
    };
    const moddir_flag = switch (ctx.os) {
        .linux => "-module-dir",
        .macos, .windows => "-J",
    };
    const run = b.addSystemCommand(&.{ compiler, "-fpic", opt, "-c" });
    run.setName(b.fmt("{s} {s}/{s}", .{ compiler, dir, file }));
    run.addFileArg(ctx.path(b.fmt("{s}/{s}", .{ dir, file })));
    run.addArg("-o");
    const stem = file[0 .. std.mem.lastIndexOfScalar(u8, file, '.').?];
    const obj = run.addOutputFileArg(b.fmt("{s}.o", .{stem}));
    run.addArg(moddir_flag);
    const mods = run.addOutputDirectoryArg("mods");
    for (mod_deps) |d| run.addPrefixedDirectoryArg("-I", d);
    return .{ .obj = obj, .mods = mods };
}

fn fortranGroup(ctx: *const Ctx, dir: []const u8, files: []const []const u8, mod_deps: []const std.Build.LazyPath) []std.Build.LazyPath {
    const b = ctx.b;
    var objs = std.ArrayList(std.Build.LazyPath).empty;
    for (files) |f| {
        const r = fortranOne(ctx, dir, f, mod_deps);
        objs.append(b.allocator, r.obj) catch @panic("OOM");
    }
    return objs.items;
}

// ----------------------------------------------------------------------
// configure replay: substitution table + template processing
// ----------------------------------------------------------------------

/// The vendored config.h/Rconfig.h/subst.txt are a pure function of
/// (platform, pixi.lock, R version) — see FINALIZATION.md F2.1. An R
/// version bump would silently build with stale feature flags if nothing
/// checked this, so GENERATED_FROM records the version they were captured
/// from and every build compares it against r_version.
fn checkConfigFreshness(b: *std.Build, io: std.Io, config_dir: []const u8) !void {
    const path = b.pathFromRoot(b.fmt("{s}/GENERATED_FROM", .{config_dir}));
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, b.allocator, .limited(256)) catch {
        std.debug.print("error: {s} not found — the vendored config dir is missing its GENERATED_FROM marker\n", .{path});
        return error.MissingGeneratedFromMarker;
    };
    const generated_from = std.mem.trim(u8, raw, " \n\r\t");
    if (!std.mem.eql(u8, generated_from, r_version)) {
        std.debug.print(
            \\error: {s} was generated from R {s}, but build.zig
            \\targets R {s}. The vendored config.h/Rconfig.h/subst.txt are a pure
            \\function of (platform, variant, pixi.lock, R version) and must be
            \\regenerated:
            \\  1. pixi run configure   (writes build/obj-{s}-<variant>/config.status;
            \\     use `pixi run -e full configure` for the full variant)
            \\  2. cp build/obj-{s}-<variant>/src/include/{{config.h,Rconfig.h}} {s}/
            \\  3. pixi run bash zigbuild/tools/gen-subst.sh   (regenerates subst.txt;
            \\     `pixi run -e full bash zigbuild/tools/gen-subst.sh` for full)
            \\  4. update {s}/GENERATED_FROM to "{s}"
            \\See PLAN.md's "Regenerating the vendored config" section.
            \\
        , .{ config_dir, generated_from, r_version, r_version, r_version, config_dir, config_dir, r_version });
        return error.StaleVendoredConfig;
    }
}

fn loadSubstTable(ctx: *Ctx, io: std.Io, config_dir: []const u8) !void {
    const b = ctx.b;
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, b.pathFromRoot(b.fmt("{s}/subst.txt", .{config_dir})), b.allocator, .limited(4 * 1024 * 1024));
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        // format: S["KEY"]="VALUE"
        if (!std.mem.startsWith(u8, line, "S[\"")) continue;
        const key_end = std.mem.indexOf(u8, line, "\"]=\"") orelse continue;
        const key = line[3..key_end];
        var val: []const u8 = line[key_end + 4 ..];
        if (val.len > 0 and val[val.len - 1] == '"') val = val[0 .. val.len - 1];
        var v = try std.mem.replaceOwned(u8, b.allocator, val, "@ZR_CONDA@", ctx.conda);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_SRC@", ctx.src_abs);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_OBJ@", ctx.rhome);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_PREFIX@", ctx.prefix);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_TOOLCHAIN@", b.pathFromRoot("toolchain"));
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_ROOT@", b.pathFromRoot("."));
        // config.status escapes for awk: \$ → $ and \" → " (checked: no
        // vendored value contains a literal \\, so unescape order is safe)
        v = try std.mem.replaceOwned(u8, b.allocator, v, "\\$", "$");
        v = try std.mem.replaceOwned(u8, b.allocator, v, "\\\"", "\"");
        try ctx.subst.put(try b.allocator.dupe(u8, key), v);
    }
    // template vars that are config.status *defaults*, not S-table entries
    try ctx.subst.put("abs_top_builddir", ctx.rhome);
    try ctx.subst.put("abs_top_srcdir", ctx.src_abs);
    try ctx.subst.put("top_srcdir", ctx.src_abs);
    try ctx.subst.put("srcdir", ctx.src_abs);
    try ctx.subst.put("VERSION", r_version);
    try ctx.subst.put("PACKAGE", "R");

    // r_c{c,xx}_rules_frag / r_objc_rules_frag: configure's AC_SUBST_FILE
    // vars, which config.status inlines file *contents* for (not looked up
    // in the S-table, so they're missing from subst.txt entirely). The
    // content is fixed shell heredoc text from configure (search
    // "r_cc_rules_frag=Makefrag.cc"); zig cc/zig c++ both support -M, so
    // use the dependency-generating branch (verified: `zig-cc -M`/`zig-cxx
    // -M` on a conftest both emit a correct "conftest.o: conftest.c" line).
    try ctx.subst.put("r_cc_rules_frag", ".c.o:\n" ++
        "\t$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) -c $< -o $@\n" ++
        ".c.d:\n" ++
        "\t@echo \"making $@ from $<\"\n" ++
        "\t@$(CC) -M $(ALL_CPPFLAGS) $< > $@\n");
    try ctx.subst.put("r_cxx_rules_frag", ".cc.o:\n" ++
        "\t$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) -c $< -o $@\n" ++
        ".cpp.o:\n" ++
        "\t$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) -c $< -o $@\n" ++
        ".cc.d:\n" ++
        "\t@echo \"making $@ from $<\"\n" ++
        "\t@$(CXX) -M $(ALL_CPPFLAGS) $< > $@\n" ++
        ".cpp.d:\n" ++
        "\t@echo \"making $@ from $<\"\n" ++
        "\t@$(CXX) -M $(ALL_CPPFLAGS) $< > $@\n");
    // No ObjC sources are built on linux; keep this syntactically valid.
    try ctx.subst.put("r_objc_rules_frag", ".m.o:\n" ++
        "\t$(OBJC) $(ALL_CPPFLAGS) $(ALL_OBJCFLAGS) -c $< -o $@\n" ++
        ".m.d:\n" ++
        "\t@echo > $@\n");
}

/// config.status-style substitution: replace @KEY@ tokens found in the map,
/// leave unknown tokens untouched.
fn substitute(ctx: *const Ctx, content: []const u8) ![]u8 {
    const b = ctx.b;
    var out = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '@') {
            if (std.mem.indexOfScalarPos(u8, content, i + 1, '@')) |j| {
                const key = content[i + 1 .. j];
                if (key.len > 0 and key.len < 64 and isVarName(key)) {
                    if (ctx.subst.get(key)) |val| {
                        try out.appendSlice(b.allocator, val);
                        i = j + 1;
                        continue;
                    }
                }
            }
        }
        try out.append(b.allocator, content[i]);
        i += 1;
    }
    return out.items;
}

fn isVarName(s: []const u8) bool {
    for (s) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    }
    return true;
}

fn readSrcFile(ctx: *const Ctx, io: std.Io, rel: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, ctx.b.fmt("{s}/{s}", .{ ctx.src_abs, rel }), ctx.b.allocator, .limited(64 * 1024 * 1024));
}

fn substFile(ctx: *const Ctx, io: std.Io, rel: []const u8) ![]u8 {
    return substitute(ctx, try readSrcFile(ctx, io, rel));
}

/// Replicates tools/GETVERSION (Rversion.h) without the shell.
fn genRversionH(ctx: *const Ctx, io: std.Io) ![]u8 {
    const b = ctx.b;
    const ver = std.mem.trim(u8, try readSrcFile(ctx, io, "VERSION"), " \n");
    const nick = std.mem.trim(u8, try readSrcFile(ctx, io, "VERSION-NICK"), " \n");
    const svnrev_file = try readSrcFile(ctx, io, "SVN-REVISION");

    var ver_status: []const u8 = "";
    var ver_num = ver;
    if (std.mem.indexOfScalar(u8, ver, ' ')) |sp| {
        ver_num = ver[0..sp];
        ver_status = ver[sp + 1 ..];
    }
    var parts = std.mem.splitScalar(u8, ver_num, '.');
    const maj = parts.next().?;
    const pl = parts.next().?;
    const sl = parts.next() orelse "0";
    const minor = b.fmt("{s}.{s}", .{ pl, sl });
    const vnum = (try std.fmt.parseInt(u32, maj, 10)) * 65536 +
        (try std.fmt.parseInt(u32, pl, 10)) * 256 +
        (try std.fmt.parseInt(u32, sl, 10));

    var svn_rev: []const u8 = "unknown";
    var date_y: []const u8 = "2006";
    var date_m: []const u8 = "01";
    var date_d: []const u8 = "01";
    var lines = std.mem.splitScalar(u8, svnrev_file, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "Revision: ")) svn_rev = std.mem.trim(u8, line[10..], " \r");
        if (std.mem.startsWith(u8, line, "Last Changed Date: ")) {
            const d = std.mem.trim(u8, line[19..], " \r");
            var dp = std.mem.splitScalar(u8, d, '-');
            date_y = dp.next() orelse date_y;
            date_m = dp.next() orelse date_m;
            date_d = dp.next() orelse date_d;
        }
    }
    const svn_rev16 = (std.fmt.parseInt(u32, svn_rev, 10) catch 0) % 65536;

    return b.fmt(
        \\/* Rversion.h.  Generated automatically. */
        \\#ifndef R_VERSION_H
        \\#define R_VERSION_H
        \\
        \\#ifdef __cplusplus
        \\extern "C" {{
        \\#endif
        \\
        \\#define R_VERSION {d}
        \\#define R_NICK "{s}"
        \\#define R_Version(v,p,s) (((v) * 65536) + ((p) * 256) + (s))
        \\#define R_MAJOR  "{s}"
        \\#define R_MINOR  "{s}"
        \\#define R_STATUS "{s}"
        \\#define R_YEAR   "{s}"
        \\#define R_MONTH  "{s}"
        \\#define R_DAY    "{s}"
        \\#define R_SVN_REVISION {s}
        \\#ifdef __llvm__
        \\# define R_FILEVERSION    {s},{s}{s},{d},0
        \\#else
        \\# define R_FILEVERSION    {s},{s}{s},{s},0
        \\#endif
        \\
        \\#ifdef __cplusplus
        \\}}
        \\#endif
        \\
        \\#endif /* not R_VERSION_H */
        \\
    , .{ vnum, nick, maj, minor, ver_status, date_y, date_m, date_d, svn_rev, maj, pl, sl, svn_rev16, maj, pl, sl, svn_rev });
}

// ----------------------------------------------------------------------
// static R_HOME payload + library/ package sources
// ----------------------------------------------------------------------

/// The per-package library/ payload (basepkg.mk's mkR1/mkR2/mkRbase, plus
/// the fixed set of per-package extras) — identical logic on every OS,
/// parameterized only by which R/<os_subdir>/*.R directory basepkg.mk (or
/// its Windows counterpart, src/library/Makefile.win's `R_OSTYPE`) appends,
/// and the OS name recorded in each package's `Built:` DESCRIPTION stamp.
/// Shared by installStaticTree (unix/macOS, os_subdir="unix") and
/// installLibraryWindows (os_subdir="windows").
fn stageLibraryPayload(ctx: *const Ctx, io: std.Io, libstage: *std.Build.Step.WriteFile, os_subdir: []const u8, os_stamp: []const u8) !void {
    const b = ctx.b;

    // profile: library/base/R/Rprofile = Common.R + Rprofile.<os_subdir>
    {
        const common = try readSrcFile(ctx, io, "src/library/profile/Common.R");
        const osp = try readSrcFile(ctx, io, b.fmt("src/library/profile/Rprofile.{s}", .{os_subdir}));
        _ = libstage.add("base/R/Rprofile", b.fmt("{s}{s}", .{ common, osp }));
    }

    const built_stamp = b.fmt("Built: R {s}; ; {s}; {s}\n", .{ r_version, utcNow(b, io), os_stamp });

    for (rspec.pkgs_base) |pkg| {
        const pkg_src = b.fmt("src/library/{s}", .{pkg});

        // R code concatenation (basepkg.mk mkR1/mkR2/mkRbase)
        if (std.mem.eql(u8, pkg, "datasets")) {
            // no R code, data only
        } else if (std.mem.eql(u8, pkg, "tcltk") and ctx.variant == .slim) {
            // slim: use_tcltk=no → stub only, none of the top-level R/*.R
            // (dead branch on Windows: variant is always forced to .full there)
            _ = libstage.addCopyFile(ctx.path(b.fmt("{s}/R/{s}/zzzstub.R", .{ pkg_src, os_subdir })), b.fmt("{s}/R/{s}", .{ pkg, pkg }));
        } else if (std.mem.eql(u8, pkg, "tcltk")) {
            // full: real R/*.R + R/<os_subdir>/zzz.R (not zzzstub.R)
            const all_r = try concatRSourcesEx(ctx, io, b.fmt("{s}/R", .{pkg_src}), os_subdir, null, &.{"zzzstub.R"});
            _ = libstage.add(b.fmt("{s}/R/{s}", .{ pkg, pkg }), all_r);
        } else {
            const s4 = std.mem.eql(u8, pkg, "methods") or std.mem.eql(u8, pkg, "stats4");
            const with_os = std.mem.eql(u8, pkg, "base") or std.mem.eql(u8, pkg, "utils") or
                std.mem.eql(u8, pkg, "grDevices") or std.mem.eql(u8, pkg, "parallel");
            var all_r = try concatRSources(ctx, io, b.fmt("{s}/R", .{pkg_src}), if (with_os) os_subdir else null, if (s4) pkg else null);
            if (std.mem.eql(u8, pkg, "base")) {
                // mkRbase: substitute configure's @WHICH@ — only appears in
                // R/unix/system.unix.R (real value comes from vendored
                // config.status, which only exists on unix/macOS); Windows's
                // R/windows/-only concatenation never even includes that
                // file, so the token is never actually present there — the
                // "which" fallback is a no-op in that case, not a real value.
                all_r = try std.mem.replaceOwned(u8, b.allocator, all_r, "@WHICH@", ctx.subst.get("WHICH") orelse "which");
            }
            _ = libstage.add(b.fmt("{s}/R/{s}", .{ pkg, pkg }), all_r);
        }

        // NAMESPACE (base has none)
        if (!std.mem.eql(u8, pkg, "base")) {
            _ = libstage.addCopyFile(ctx.path(b.fmt("{s}/NAMESPACE", .{pkg_src})), b.fmt("{s}/NAMESPACE", .{pkg}));
        }

        // DESCRIPTION: base and tools get the file + Built stamp directly
        // (mkdesc2); the rest are installed by R during bootstrap (mkdesc).
        if (std.mem.eql(u8, pkg, "base") or std.mem.eql(u8, pkg, "tools")) {
            const desc = try substFile(ctx, io, b.fmt("{s}/DESCRIPTION.in", .{pkg_src}));
            _ = libstage.add(b.fmt("{s}/DESCRIPTION", .{pkg}), b.fmt("{s}{s}", .{ desc, built_stamp }));
        }
    }

    // package-specific extras
    _ = libstage.addCopyFile(ctx.path("src/library/base/inst/CITATION"), "base/CITATION");
    _ = libstage.addCopyDirectory(ctx.path("src/library/base/demo"), "base/demo", .{ .exclude_extensions = &.{"00Index"} });
    _ = libstage.add("tools/misc/top.txt", b.fmt("{s}\n", .{ctx.src_abs}));
    _ = libstage.add("tools/misc/wre.txt", try makeWreTxt(ctx, io));
    _ = libstage.addCopyDirectory(ctx.path("src/library/utils/inst/Sweave"), "utils/Sweave", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/utils/inst/doc"), "utils/doc", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/utils/inst/misc"), "utils/misc", .{});
    for ([_][]const u8{ "afm", "enc", "fonts/Roboto", "fonts/Montserrat/static", "icc" }) |d| {
        _ = libstage.addCopyDirectory(ctx.path(b.fmt("src/library/grDevices/inst/{s}", .{d})), b.fmt("grDevices/{s}", .{d}), .{});
    }
    _ = libstage.addCopyDirectory(ctx.path("src/library/graphics/man/figures"), "graphics/help/figures", .{});
    _ = libstage.addCopyFile(ctx.path("src/library/stats/COPYRIGHTS.modreg"), "stats/COPYRIGHTS.modreg");
    _ = libstage.addCopyFile(ctx.path("src/library/stats/SOURCES.ts"), "stats/SOURCES.ts");
    _ = libstage.addCopyDirectory(ctx.path("src/library/stats/inst/doc"), "stats/doc", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/grid/inst/doc"), "grid/doc", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/parallel/inst/doc"), "parallel/doc", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/datasets/data"), "datasets/data", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/tcltk/exec"), "tcltk/exec", .{});
    _ = libstage.addCopyDirectory(ctx.path("src/library/translations/inst"), "translations", .{});
}

fn installStaticTree(ctx: *Ctx, io: std.Io) !*std.Build.Step.WriteFile {
    const b = ctx.b;
    const inst = b.getInstallStep();
    const stage = b.addWriteFiles();
    // library/ is staged separately: R mutates it during bootstrap, so the
    // bootstrap chain resets it from this pristine copy on every build
    // instead of trusting install-step caching.
    const libstage = b.addWriteFiles();

    // --- top-level files ---
    _ = stage.addCopyFile(ctx.path("COPYING"), "COPYING");
    _ = stage.addCopyFile(ctx.path("SVN-REVISION"), "SVN-REVISION");

    // lib/pkgconfig/libR.pc (src/unix/Makefile.in install-pc; sed-style
    // tokens, not @VAR@ substitution)
    {
        var pc = try readSrcFile(ctx, io, "src/unix/libR.pc.in");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@rhome", ctx.rhome);
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@rincludedir", b.fmt("{s}/include", .{ctx.rhome}));
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@rarch", "");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@libsprivate", "");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@others", b.fmt("-Wl,--export-dynamic -fopenmp -L{s}/lib -Wl,-rpath,{s}/lib", .{ ctx.conda, ctx.conda }));
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@VERSION", r_version);
        const pc_wf = b.addWriteFiles();
        _ = pc_wf.add("libR.pc", pc);
        inst.dependOn(&b.addInstallDirectory(.{
            .source_dir = pc_wf.getDirectory(),
            .install_dir = .{ .custom = "lib/pkgconfig" },
            .install_subdir = "",
        }).step);
    }

    // doc/html/index.html is a rename of index-default.html (doc/html/Makefile)
    _ = stage.addCopyFile(ctx.path("doc/html/index-default.html"), "doc/html/index.html");

    // --- etc/ ---
    _ = stage.add("etc/Renviron", try substFile(ctx, io, "etc/Renviron.in"));
    _ = stage.add("etc/ldpaths", try substFile(ctx, io, "etc/ldpaths.in"));
    _ = stage.add("etc/Makeconf", try substFile(ctx, io, "etc/Makeconf.in"));
    _ = stage.add("etc/javaconf", try substFile(ctx, io, "etc/javaconf.in"));
    _ = stage.addCopyFile(ctx.path("etc/repositories"), "etc/repositories");

    // --- include/ (public headers) ---
    for (rspec.public_headers) |h| {
        _ = stage.addCopyFile(ctx.path(b.fmt("src/include/{s}", .{h})), b.fmt("include/{s}", .{h}));
    }
    _ = stage.addCopyFile(ctx.geninc.path(b, "Rconfig.h"), "include/Rconfig.h");
    _ = stage.addCopyFile(ctx.geninc.path(b, "Rversion.h"), "include/Rversion.h");
    _ = stage.addCopyFile(ctx.geninc.path(b, "Rmath.h"), "include/Rmath.h");
    _ = stage.addCopyDirectory(ctx.path("src/include/R_ext"), "include/R_ext", .{ .include_extensions = &.{".h"} });

    // --- bin/ scripts ---
    for (rspec.scripts_s) |s| {
        _ = stage.addCopyFile(ctx.path(b.fmt("src/scripts/{s}", .{s})), b.fmt("bin/{s}", .{s}));
    }
    for (rspec.scripts_b) |s| {
        _ = stage.add(b.fmt("bin/{s}", .{s}), try substFile(ctx, io, b.fmt("src/scripts/{s}.in", .{s})));
    }
    const r_front = try makeRFrontScript(ctx, io);
    _ = stage.add("bin/R", r_front);

    // --- library/: per-package static payload ---
    try stageLibraryPayload(ctx, io, libstage, "unix", "unix");

    const stage_install = b.addInstallDirectory(.{
        .source_dir = stage.getDirectory(),
        .install_dir = .{ .custom = "lib/R" },
        .install_subdir = "",
    });
    inst.dependOn(&stage_install.step);

    // share/ and doc/ wholesale from the source tree
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("share"),
        .install_dir = .{ .custom = "lib/R/share" },
        .install_subdir = "",
        .exclude_extensions = &.{"Makefile.in"},
    }).step);
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("doc"),
        .install_dir = .{ .custom = "lib/R/doc" },
        .install_subdir = "",
        .exclude_extensions = &.{ "Makefile.in", ".texi", "R.aux", "Rscript.aux" },
    }).step);

    // prefix/bin/R: same front script (make install copies Rexecbindir/R there)
    const bin_wf = b.addWriteFiles();
    _ = bin_wf.add("R", r_front);
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = bin_wf.getDirectory(),
        .install_dir = .{ .custom = "bin" },
        .install_subdir = "",
    }).step);

    // utils iconvlist (basepkg iconvlist target: `iconv -l`)
    const iconv_run = b.addSystemCommand(&.{ "iconv", "-l" });
    const iconv_out = iconv_run.captureStdOut(.{});
    _ = libstage.addCopyFile(iconv_out, "utils/iconvlist");

    return libstage;
}

/// bin/R: R.sh.in substituted, then the four install-time seds make applies
/// (R_HOME_DIR first occurrence + R_SHARE_DIR/R_INCLUDE_DIR/R_DOC_DIR).
fn makeRFrontScript(ctx: *const Ctx, io: std.Io) ![]u8 {
    const b = ctx.b;
    const raw = try substFile(ctx, io, "src/scripts/R.sh.in");
    var out = std.ArrayList(u8).empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    var home_done = false;
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(b.allocator, '\n');
        first = false;
        if (!home_done and std.mem.indexOf(u8, line, "R_HOME_DIR=") != null) {
            try out.appendSlice(b.allocator, b.fmt("R_HOME_DIR=\"{s}\"", .{ctx.rhome}));
            home_done = true;
        } else if (std.mem.startsWith(u8, line, "R_SHARE_DIR=")) {
            try out.appendSlice(b.allocator, b.fmt("R_SHARE_DIR=\"{s}/share\"", .{ctx.rhome}));
        } else if (std.mem.startsWith(u8, line, "R_INCLUDE_DIR=")) {
            try out.appendSlice(b.allocator, b.fmt("R_INCLUDE_DIR=\"{s}/include\"", .{ctx.rhome}));
        } else if (std.mem.startsWith(u8, line, "R_DOC_DIR=")) {
            try out.appendSlice(b.allocator, b.fmt("R_DOC_DIR=\"{s}/doc\"", .{ctx.rhome}));
        } else {
            try out.appendSlice(b.allocator, line);
        }
    }
    return out.items;
}

/// tools' wre.txt: grep -E '^@(api|eapi|emb|for)(fun|var|hdr)' R-exts.texi
fn makeWreTxt(ctx: *const Ctx, io: std.Io) ![]u8 {
    const b = ctx.b;
    const texi = try readSrcFile(ctx, io, "doc/manual/R-exts.texi");
    var out = std.ArrayList(u8).empty;
    var lines = std.mem.splitScalar(u8, texi, '\n');
    while (lines.next()) |line| {
        for ([_][]const u8{ "@apifun", "@apivar", "@apihdr", "@eapifun", "@eapivar", "@eapihdr", "@embfun", "@embvar", "@embhdr", "@forfun", "@forvar", "@forhdr" }) |p| {
            if (std.mem.startsWith(u8, line, p)) {
                try out.appendSlice(b.allocator, line);
                try out.append(b.allocator, '\n');
                break;
            }
        }
    }
    return out.items;
}

/// Concatenate a package's R sources the way basepkg.mk does:
/// LC_COLLATE=C sorted R/*.R (+ R/<os_subdir>/*.R), S4 packages prefixed
/// with `.packageName <- "pkg"`. `os_subdir` is `"unix"` on linux/macOS,
/// `"windows"` on Windows (`src/library/Makefile.win`'s own `R_OSTYPE =
/// windows; RSRC = ... $(srcdir)/R/$(R_OSTYPE)/*.R` — the same per-OS-
/// subdir convention as unix's basepkg.mk, just a different directory
/// name), or `null` for packages with no OS-specific R code at all.
fn concatRSources(ctx: *const Ctx, io: std.Io, rdir_rel: []const u8, os_subdir: ?[]const u8, s4_pkgname: ?[]const u8) ![]u8 {
    return concatRSourcesEx(ctx, io, rdir_rel, os_subdir, s4_pkgname, &.{});
}

/// Like concatRSources, but skips any filename in `exclude` — tcltk's
/// R/unix/ has both zzz.R (real, full only) and zzzstub.R (slim's
/// no-op .onLoad); alphabetical sort would concatenate both.
fn concatRSourcesEx(ctx: *const Ctx, io: std.Io, rdir_rel: []const u8, os_subdir: ?[]const u8, s4_pkgname: ?[]const u8, exclude: []const []const u8) ![]u8 {
    const b = ctx.b;
    var out = std.ArrayList(u8).empty;
    if (s4_pkgname) |p| try out.appendSlice(b.allocator, b.fmt(".packageName <- \"{s}\"\n", .{p}));

    const dirs: []const []const u8 = if (os_subdir) |sub|
        &.{ rdir_rel, b.fmt("{s}/{s}", .{ rdir_rel, sub }) }
    else
        &.{rdir_rel};

    for (dirs) |drel| {
        var names = std.ArrayList([]const u8).empty;
        const dabs = b.fmt("{s}/{s}", .{ ctx.src_abs, drel });
        var dir = try std.Io.Dir.cwd().openDir(io, dabs, .{ .iterate = true });
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |ent| {
            if (ent.kind != .file) continue;
            if (!std.mem.endsWith(u8, ent.name, ".R")) continue;
            var skip = false;
            for (exclude) |e| {
                if (std.mem.eql(u8, ent.name, e)) {
                    skip = true;
                    break;
                }
            }
            if (skip) continue;
            try names.append(b.allocator, try b.allocator.dupe(u8, ent.name));
        }
        std.mem.sort([]const u8, names.items, {}, strLessThan);
        for (names.items) |n| {
            const content = try readSrcFile(ctx, io, b.fmt("{s}/{s}", .{ drel, n }));
            try out.appendSlice(b.allocator, content);
        }
    }
    return out.items;
}

fn strLessThan(_: void, a: []const u8, b_: []const u8) bool {
    return std.mem.lessThan(u8, a, b_);
}

/// F2.2: honors SOURCE_DATE_EPOCH (https://reproducible-builds.org/specs/
/// source-date-epoch/) when set, instead of the wall clock, so the `Built:`
/// DESCRIPTION stamp — currently the only wall-clock read in the whole
/// build — doesn't make two builds of the same tree differ.
fn utcNow(b: *std.Build, io: std.Io) []const u8 {
    const secs: u64 = if (b.graph.environ_map.get("SOURCE_DATE_EPOCH")) |sde|
        std.fmt.parseInt(u64, std.mem.trim(u8, sde, " \n\r\t"), 10) catch @panic("invalid SOURCE_DATE_EPOCH (must be an integer unix timestamp)")
    else blk: {
        const ts = std.Io.Timestamp.now(io, .real);
        break :blk @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
    };
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return b.fmt("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
        yd.year, md.month.numeric(), md.day_index + 1,
        ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute(),
    });
}

// ----------------------------------------------------------------------
// bootstrap: the R-level package installation, as sequenced Run steps
// ----------------------------------------------------------------------

const Boot = struct {
    ctx: *const Ctx,
    last: *std.Build.Step,

    /// Run `bin/R --vanilla --no-echo` with `code` on stdin (unix/macOS), or
    /// `bin/x64/Rterm.exe --vanilla --no-echo` with `code` on stdin
    /// (Windows) — exactly gnuwin32's own bootstrap mechanism
    /// (`src/gnuwin32/fixed/Makeconf`: `R_EXE = ... Rterm.exe --vanilla
    /// --no-echo`, fed via `cat file | $(R_EXE)`), NOT Rscript.exe: on
    /// Windows, Rscript.c's own main() only handles `--version`/`--help`
    /// directly — anything else gets re-exec'd to `<RHOME>\bin\x64\
    /// Rterm.exe` internally, so bootstrapping straight against Rterm.exe
    /// is both more direct and the one path gnuwin32 actually exercises
    /// (found the hard way: an earlier Rscript.exe+tempfile version of this
    /// function got every bootstrap step to report success, but silently
    /// never produced a working base package, since Rscript.exe's own
    /// startup for anything beyond --version/--help depends on a real,
    /// already-installed Rterm.exe existing).
    fn r(self: *Boot, name: []const u8, code: []const u8) *std.Build.Step.Run {
        const b = self.ctx.b;
        const rbin = switch (self.ctx.os) {
            .windows => b.fmt("{s}/bin/x64/Rterm.exe", .{self.ctx.rhome}),
            else => b.fmt("{s}/bin/R", .{self.ctx.rhome}),
        };
        const run = b.addSystemCommand(&.{ rbin, "--vanilla", "--no-echo" });
        run.setStdIn(.{ .bytes = b.dupe(code) });
        run.setName(b.fmt("R bootstrap: {s}", .{name}));
        run.setEnvironmentVariable("TZ", "UTC");
        run.setEnvironmentVariable("LC_ALL", "C");
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "NULL");
        run.setEnvironmentVariable("R_ENABLE_JIT", "0");
        run.has_side_effects = true;
        run.step.dependOn(self.last);
        self.last = &run.step;
        return run;
    }

    fn cmd(self: *Boot, name: []const u8, argv: []const []const u8) *std.Build.Step.Run {
        const run = self.ctx.b.addSystemCommand(argv);
        run.setName(name);
        run.has_side_effects = true;
        run.step.dependOn(self.last);
        self.last = &run.step;
        return run;
    }
};

fn bootstrap(ctx: *Ctx, io: std.Io, libstage_dir: std.Build.LazyPath) !*std.Build.Step {
    const b = ctx.b;
    const rhome = ctx.rhome;
    const lib = b.fmt("{s}/library", .{rhome});
    const srclib = b.fmt("{s}/src/library", .{ctx.src_abs});

    var boot = Boot{ .ctx = ctx, .last = b.getInstallStep() };

    // Reset library/ to the pristine staged payload: the bootstrap mutates
    // it in place (lazyload DBs, Meta/, baseloader), so an interrupted or
    // repeated build must never start from half-bootstrapped state.
    _ = boot.cmd("reset library", &.{ "rm", "-rf", lib });
    {
        const run = boot.cmd("copy library payload", &.{ "cp", "-R" });
        run.addDirectoryArg(libstage_dir);
        run.addArg(lib);
    }
    // zig cache artifacts can carry read-only modes; R must write here
    _ = boot.cmd("make library writable", &.{ "chmod", "-R", "u+w", lib });

    // executable bits: WriteFiles/InstallDir produce 0644 files. Windows has
    // neither a bin/R wrapper script nor the unix scripts_s/scripts_b shell
    // scripts (Rscript.exe *is* the front end, and .exe files need no
    // execute bit on NTFS) — skip entirely there.
    if (ctx.os != .windows) {
        var argv = std.ArrayList([]const u8).empty;
        try argv.appendSlice(b.allocator, &.{ "chmod", "+x" });
        try argv.append(b.allocator, b.fmt("{s}/bin/R", .{ctx.prefix}));
        try argv.append(b.allocator, b.fmt("{s}/bin/R", .{rhome}));
        for (rspec.scripts_s) |s| try argv.append(b.allocator, b.fmt("{s}/bin/{s}", .{ rhome, s }));
        for (rspec.scripts_b) |s| try argv.append(b.allocator, b.fmt("{s}/bin/{s}", .{ rhome, s }));
        _ = boot.cmd("chmod scripts", argv.items);
    }

    // share/zoneinfo (internal tzcode database; needs conda unzip)
    _ = boot.cmd("unzip zoneinfo", &.{
        "unzip", "-qo",
        b.fmt("{s}/src/extra/tzone/zoneinfo.zip", .{ctx.src_abs}),
        "-d", b.fmt("{s}/share", .{rhome}),
    });

    // tools sysdata (needs only base+tools R sources, both installed as text)
    _ = boot.r("tools sysdata", b.fmt(
        "tools:::sysdata2LazyLoadDB(\"{s}/tools/R/sysdata.rda\",\"{s}/tools/R\")",
        .{ srclib, lib },
    ));

    // per-package DESCRIPTION install runs R in a dir containing DESCRIPTION
    // (basepkg.mk mkdesc): stage each substituted DESCRIPTION in a wf dir.
    const mkdesc = struct {
        fn add(bt: *Boot, ctx2: *const Ctx, io2: std.Io, pkg: []const u8) !void {
            const b2 = ctx2.b;
            const wf = b2.addWriteFiles();
            const desc = try substFile(ctx2, io2, b2.fmt("src/library/{s}/DESCRIPTION.in", .{pkg}));
            _ = wf.add("DESCRIPTION", desc);
            // builtStamp: tools:::.install_package_description() defaults
            // to Sys.time() when omitted (undoing utcNow's SOURCE_DATE_
            // EPOCH honoring at the R level) — R has a builtStamp param
            // "some build systems want to supply a package-build
            // timestamp for reproducibility" exactly for this; use it.
            const run = bt.r(b2.fmt("{s} mkdesc", .{pkg}), b2.fmt(
                "tools:::.install_package_description('.', '{s}/library/{s}', '{s}')",
                .{ ctx2.rhome, pkg, utcNow(b2, io2) },
            ));
            run.setCwd(wf.getDirectory());
        }
    }.add;

    // compiler: description, then byte-compile itself (mklazycomp)
    try mkdesc(&boot, ctx, io, "compiler");
    {
        const run = boot.r("compiler mklazycomp", "tools:::makeLazyLoading(\"compiler\")");
        run.setEnvironmentVariable("_R_COMPILE_PKGS_", "1");
        run.setEnvironmentVariable("R_COMPILER_SUPPRESS_ALL", "1");
    }

    // translations
    try mkdesc(&boot, ctx, io, "translations");

    // base: makebasedb.R builds base.rdb/rdx, then baseloader takes over R/base
    {
        const code = try readSrcFile(ctx, io, "src/library/base/makebasedb.R");
        const run = boot.r("base mklazycomp", code);
        run.setEnvironmentVariable("_R_COMPILE_PKGS_", "1");
        run.setEnvironmentVariable("R_COMPILER_SUPPRESS_ALL", "1");
    }
    _ = boot.cmd("install baseloader", &.{
        "cp", b.fmt("{s}/base/baseloader.R", .{srclib}), b.fmt("{s}/base/R/base", .{lib}),
    });

    // tools: its own makeLazyLoad.R + makeLazyLoading (needs R_SYSTEM_ABI)
    {
        const mk = try readSrcFile(ctx, io, "src/library/tools/R/makeLazyLoad.R");
        const code = b.fmt("{s}\nmakeLazyLoading(\"tools\")\n", .{mk});
        const run = boot.r("tools mklazycomp", code);
        run.setEnvironmentVariable("_R_COMPILE_PKGS_", "1");
        run.setEnvironmentVariable("R_COMPILER_SUPPRESS_ALL", "1");
        // R_SYSTEM_ABI: configure's case-statement has no mingw/Windows
        // branch at all (falls through to "?"), and there's no real
        // config.status to capture on Windows anyway (F6.1) — only read by
        // tools/R/sotools.R (informational ABI-compatibility string for
        // compiled-package loading, not load-bearing for base bootstrap).
        // Shape matches configure's own gcc/gfortran-detected pattern
        // ("<os>,<cc>,<cxx>,<fc>,<fc>"); revisit if a real value is needed.
        run.setEnvironmentVariable("R_SYSTEM_ABI", ctx.subst.get("R_SYSTEM_ABI") orelse "windows,gcc,gxx,gfortran,gfortran");
    }
    // tools/Makefile.in's `all` ends with .install_package_description —
    // unlike other mkdesc2 users this is not optional: it writes
    // Meta/features.rds (internalsID), without which loadNamespace refuses
    // any package that has a libs/ dir once Meta/ exists.
    try mkdesc(&boot, ctx, io, "tools");

    // remaining base packages, R_PKGS_BASE1 order
    const base1 = [_][]const u8{ "utils", "grDevices", "graphics", "stats", "datasets", "methods", "grid", "splines", "stats4", "tcltk", "parallel" };
    for (base1) |pkg| {
        try mkdesc(&boot, ctx, io, pkg);

        if (std.mem.eql(u8, pkg, "utils")) {
            _ = boot.r("utils sysdata", b.fmt(
                "tools:::sysdata2LazyLoadDB(\"{s}/utils/R/sysdata.rda\",\"{s}/utils/R\")",
                .{ srclib, lib },
            ));
        }
        if (std.mem.eql(u8, pkg, "grDevices")) {
            _ = boot.r("grDevices mkdemos", b.fmt(
                "tools:::.install_package_demos('{s}/grDevices', '{s}/grDevices')",
                .{ srclib, lib },
            ));
            const afms = try listFiles(ctx, io, "src/library/grDevices/inst/afm", ".afm");
            var argv = std.ArrayList([]const u8).empty;
            // -n: omit the original filename/mtime from the gzip header —
            // without it every .afm.gz embeds the compression wall-clock
            // time, breaking reproducibility (F2.2) even with identical
            // input bytes and a fixed SOURCE_DATE_EPOCH.
            try argv.appendSlice(b.allocator, &.{ "gzip", "-9fn" });
            for (afms) |f| try argv.append(b.allocator, b.fmt("{s}/grDevices/afm/{s}", .{ lib, f }));
            _ = boot.cmd("gzip grDevices afm", argv.items);
        }
        if (std.mem.eql(u8, pkg, "graphics")) {
            _ = boot.r("graphics mkdemos", b.fmt(
                "tools:::.install_package_demos('{s}/graphics', '{s}/graphics')",
                .{ srclib, lib },
            ));
        }
        if (std.mem.eql(u8, pkg, "stats")) {
            _ = boot.r("stats mkdemos", b.fmt(
                "tools:::.install_package_demos('{s}/stats', '{s}/stats')",
                .{ srclib, lib },
            ));
        }
        if (std.mem.eql(u8, pkg, "tcltk")) {
            _ = boot.r("tcltk mkdemos", b.fmt(
                "tools:::.install_package_demos('{s}/tcltk', '{s}/tcltk')",
                .{ srclib, lib },
            ));
            if (ctx.variant == .slim) continue; // stub: no real R code to lazycomp
        }
        if (std.mem.eql(u8, pkg, "datasets")) {
            _ = boot.r("datasets data db", "tools:::data2LazyLoadDB(\"datasets\", compress=3)");
            _ = boot.cmd("restore morley.tab", &.{
                "cp", b.fmt("{s}/datasets/data/morley.tab", .{srclib}), b.fmt("{s}/datasets/data/", .{lib}),
            });
            continue; // no R code
        }

        if (std.mem.eql(u8, pkg, "methods")) {
            // methods bootstraps itself via loadNamespace, then nspackloader
            const run = boot.r("methods RfilesLazy", "invisible(loadNamespace(\"methods\"))");
            run.setEnvironmentVariable("_R_COMPILE_PKGS_", "1");
            run.setEnvironmentVariable("R_COMPILER_SUPPRESS_ALL", "1");
            _ = boot.cmd("install methods nspackloader", &.{
                "cp", b.fmt("{s}/share/R/nspackloader.R", .{ctx.src_abs}), b.fmt("{s}/methods/R/methods", .{lib}),
            });
        } else {
            const run = boot.r(b.fmt("{s} mklazycomp", .{pkg}), b.fmt("tools:::makeLazyLoading(\"{s}\")", .{pkg}));
            run.setEnvironmentVariable("_R_COMPILE_PKGS_", "1");
            run.setEnvironmentVariable("R_COMPILER_SUPPRESS_ALL", "1");
        }
    }

    // base DESCRIPTION refresh (src/library/Makefile: cd base && make mkdesc)
    try mkdesc(&boot, ctx, io, "base");

    // metadata caches
    {
        const run = boot.r("descriptions as RDS", b.fmt(
            "tools:::.vinstall_package_descriptions_as_RDS(\"{s}\", \"{s}\")",
            .{ lib, joinSpace(b, &rspec.pkgs_base) },
        ));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "tools");
    }
    _ = boot.cmd("rm nsInfo cache", &.{ "rm", "-f", b.fmt("{s}/tools/Meta/nsInfo.rds", .{lib}) });
    {
        const run = boot.r("namespaces as RDS", b.fmt(
            "tools:::.vinstall_package_namespaces_as_RDS(\"{s}\", \"{s}\")",
            .{ lib, joinSpace(b, &rspec.pkgs_base) },
        ));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "tools");
    }
    {
        const run = boot.r("R bibliographies", b.fmt(
            "tools:::.install_R_bibliographies_as_RDS(\"{s}/share/bibliographies\")",
            .{rhome},
        ));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "tools,utils");
    }
    {
        const run = boot.r("R dictionaries", b.fmt(
            "tools:::.install_R_dictionaries_as_RDS(\"{s}/share/dictionaries\")",
            .{rhome},
        ));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "tools");
    }

    // docs: parsed Rd DBs, package metadata, help indices
    _ = boot.r("install parsed Rd", b.fmt(
        \\options(warn=2)
        \\for (p in strsplit("{s}", " ")[[1]])
        \\    tools:::.install_package_Rd_objects(file.path("{s}", p), file.path("{s}", p))
    , .{ joinSpace(b, &rspec.pkgs_base), srclib, lib }));
    {
        const run = boot.r("package metadata", b.fmt(
            "tools:::.vinstall_package_indices(\"{s}\", \"{s}\", \"{s}\")",
            .{ srclib, lib, joinSpace(b, &rspec.pkgs_base) },
        ));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "tools");
    }
    {
        const run = boot.r("help indices", b.fmt(
            \\for (p in strsplit("{s}", " ")[[1]])
            \\    tools:::.writePkgIndices(file.path("{s}", p), file.path("{s}", p))
        , .{ joinSpace(b, &rspec.pkgs_base), srclib, lib }));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "utils");
    }

    // doc/NEWS artifacts (doc/Makefile docs target, sans pdflatex/help2man)
    {
        const run = boot.r("doc NEWS", b.fmt(
            \\options(warn=1)
            \\saveRDS(tools:::prepare_Rd(tools::parse_Rd("{s}/doc/NEWS.Rd", macros = "../share/Rd/macros/system.Rd"), stages = 'install', warningCalls = FALSE), 'NEWS.rds')
            \\tools:::Rd2txt_NEWS_in_Rd("NEWS.rds", "NEWS")
            \\tools:::Rd2HTML_NEWS_in_Rd("NEWS.rds", "html/NEWS.html")
            \\saveRDS(tools:::prepare_Rd(tools::parse_Rd("{s}/doc/NEWS.2.Rd", macros = "../share/Rd/macros/system.Rd"), stages = 'install', warningCalls = FALSE), 'NEWS.2.rds')
            \\saveRDS(tools:::prepare_Rd(tools::parse_Rd("{s}/doc/NEWS.3.Rd", macros = "../share/Rd/macros/system.Rd"), stages = 'install', warningCalls = FALSE), 'NEWS.3.rds')
        , .{ ctx.src_abs, ctx.src_abs, ctx.src_abs }));
        run.setEnvironmentVariable("R_DEFAULT_PACKAGES", "");
        run.setCwd(.{ .cwd_relative = b.fmt("{s}/doc", .{rhome}) });
    }

    // sanity: the built product answers from its own launchers. Windows has
    // no top-level {prefix}/bin/Rscript convenience copy (F6.0: no unix-style
    // bin/ front-end layer at all) — verify against the real installed
    // Rscript.exe directly instead.
    {
        const rscript_path = switch (ctx.os) {
            .windows => b.fmt("{s}/bin/x64/Rscript.exe", .{rhome}),
            else => b.fmt("{s}/bin/Rscript", .{ctx.prefix}),
        };
        const run = boot.cmd("verify Rscript", &.{
            rscript_path,
            "-e",
            "set.seed(1); m <- matrix(rnorm(64), 8); s <- svd(m); stopifnot(max(abs(s$u %*% diag(s$d) %*% t(s$v) - m)) < 1e-9); cat('zig-built R OK:', R.version.string, '\\n')",
        });
        run.setEnvironmentVariable("TZ", "UTC");
    }

    return boot.last;
}

fn joinSpace(b: *std.Build, items: []const []const u8) []const u8 {
    return std.mem.join(b.allocator, " ", items) catch @panic("OOM");
}

fn listFiles(ctx: *const Ctx, io: std.Io, rel: []const u8, suffix: []const u8) ![]const []const u8 {
    const b = ctx.b;
    var names = std.ArrayList([]const u8).empty;
    var dir = try std.Io.Dir.cwd().openDir(io, b.fmt("{s}/{s}", .{ ctx.src_abs, rel }), .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |ent| {
        if (ent.kind != .file) continue;
        if (!std.mem.endsWith(u8, ent.name, suffix)) continue;
        try names.append(b.allocator, try b.allocator.dupe(u8, ent.name));
    }
    std.mem.sort([]const u8, names.items, {}, strLessThan);
    return names.items;
}
