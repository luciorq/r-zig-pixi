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
//!      -fno-sanitize=undefined, -std=gnu23), Fortran through Run steps
//!      (flang, flang-pixi's flang-zig on every platform — zig has no
//!      Fortran frontend of its own),
//!   3. the R-level base-package bootstrap (share/make/basepkg.mk logic)
//!      runs as a sequenced chain of Run steps invoking the freshly built R.
//!
//! `platform`/`os`/`dylib_ext` are resolved at build-script-execution time
//! from the target (see `Os` below) — nothing here is hardcoded to linux.
//!
//! Two independent build options select the profile:
//!   -Dvariant=slim|full|minimal  (default slim) — tcltk/readline/NLS/
//!      jpeg/tiff for full; minimal (the Python-wheel profile, unix only)
//!      additionally drops cairo/png, ICU, OpenMP and libdeflate. Each is
//!      a real configure profile (own vendored config dir), not a flag
//!      toggle, since these are compile-time capabilities in R.
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
//! layout make install produces. That tree is the one that ships
//! (feat-no-host-paths F1, F1.7): scripts/vendor-libs.sh adds the env's
//! shared libraries after the build, and package-standalone.sh only
//! archives it.

const std = @import("std");
const rspec = @import("zigbuild/rspec.zig");
// rzig, the compiler front installed as R_HOME/bin/toolchain/zig-cc etc.
// (feat-no-host-paths F3), and the floors it shares with R's own build.
const rzig_build = @import("zigbuild/tools/rzig/build.zig");
const floors = @import("zigbuild/tools/rzig/floors.zig");
// The static-libc++ mirror against conda-forge zig's shared one, rzig's
// for packages and R's own build's (staticLibcxxLibDir).
const libcxx_mirror = @import("zigbuild/tools/rzig/libcxx_mirror.zig");

const r_version = "4.6.1";

/// macOS deployment target of everything this build links, and of the
/// packages compiled through rzig (which spells it "<arch>-native.13.0"):
/// one definition, zigbuild/tools/rzig/floors.zig. See the target comment
/// in build().
const macos_min: std.SemanticVersion = floors.macos;

/// F5/F6: linux is ELF (.so/DT_NEEDED/RUNPATH); macOS is Mach-O
/// (.dylib/install_name/@rpath); windows is MinGW PE/COFF (.dll, no "lib"
/// prefix on R's own core libs — see FINALIZATION.md F6.0/F6.1a for the
/// CLI-only scoping decision: no Rgui.exe, just R.dll+Rblas.dll+
/// Rlapack.dll+Rgraphapp.dll+Riconv.dll and the console front-ends). The
/// Fortran compiler is flang on all three (fortranOne).
const Os = enum { linux, macos, windows };

/// CPU architecture, orthogonal to `Os`. Only used generically for
/// `zigbuild/config/<platform>-<variant>/` directory-name construction —
/// deliberately NOT threaded through Windows' MinGW-prefix/R_ARCH
/// machinery, which has no arch dimension built in today at all (see
/// .github/devdocs/feat-cross-platform-standardization/PLAN.md Phase 2's
/// explicit non-goal).
const Arch = enum {
    x86_64,
    aarch64,

    /// The exact strings already baked into every existing
    /// zigbuild/config/ directory name — "arm64", not "aarch64", even on
    /// Linux (pre-existing convention, unchanged by introducing this
    /// enum).
    fn condaForgeSuffix(arch: Arch) []const u8 {
        return switch (arch) {
            .x86_64 => "x86_64",
            .aarch64 => "arm64",
        };
    }
};

/// Capabilities (tcltk/readline/NLS/jpeg/tiff) are compile-time in R, so
/// slim vs full is a genuine second configure profile — its own vendored
/// config.h/Rconfig.h/subst.txt under zigbuild/config/<plat>-<variant>/,
/// not a flag toggle (see FINALIZATION.md F3.1). `minimal` is smaller than
/// slim (no cairo/png, ICU, OpenMP or libdeflate; pixi.toml's
/// [feature.minimal] has the rationale) and is what the r-zig Python wheel
/// wraps. Which pieces of the compile graph it drops is not decided here
/// but read from its vendored config (Ctx.openmp/Ctx.devcairo), the same
/// way configure's own Makefiles decide.
const Variant = enum { slim, full, minimal };

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
    config_dir: []const u8, // "zigbuild/config/<platform>-<variant>" — vendored config.h/Rconfig.h/subst.txt/(Makeconf.win on Windows)
    // From the vendored S-table (unix; see build()): OpenMP compile/link
    // flags only when configure found them (R_OPENMP_CFLAGS non-empty), and
    // grDevices' cairo.so only when configure would have built it
    // (BUILD_DEVCAIRO_TRUE is "" — src/library/grDevices/src/Makefile.in's
    // `@BUILD_DEVCAIRO_TRUE@ cairodevice`). Both false for minimal only.
    openmp: bool,
    devcairo: bool,
    flangrt_dir: []const u8, // conda clang resource dir holding libflang_rt.runtime.a (findFlangRt)
    toolchain_hint: []const u8, // -Dtoolchain-hint, "" when unset
    sdk: []const u8, // macOS: the installed SDK's root (xcrun); "" elsewhere
    // The zig lib dir of R's links, null for zig's own: a mirror of it
    // where conda-forge's zig would link a shared libc++
    // (staticLibcxxLibDir). Set on every unix link (addSharedLib, R.bin);
    // always null on Windows, whose links leave it alone.
    zig_lib_dir: ?std.Build.LazyPath,
    prefix_is_env: bool, // the install prefix is the env R is built in (the conda build): samePhysicalDir
    // Every C compile of R's own starts with these (addCGroup, the cairo
    // module): no directory of the build machine in __FILE__, the debug
    // info or the OpenMP source locations (filePathFlags).
    path_flags: []const []const u8,
    // An empty C file, the code of linkRoot's stripped root modules.
    empty_c: std.Build.LazyPath,
    subst: std.StringHashMap([]const u8),
    // Makeconf's own values for the keys that name the build environment
    // (loadSubstFile, makeconfValue): substituted over `subst` into
    // etc/Makeconf only.
    mk_subst: std.StringHashMap([]const u8),
    geninc: std.Build.LazyPath, // generated headers dir (config.h, Rconfig.h, ...)
    libR: *std.Build.Step.Compile,
    rblas: ?*std.Build.Step.Compile, // null when blas == .openblas
    rlapack: ?*std.Build.Step.Compile, // null when blas == .openblas
    // rzig for R's target: the compilers Makeconf names (installRzig)
    rzig: std.Build.LazyPath, // rzig_build.Artifacts.bin

    /// Link a library this build makes (libR, libRblas, libRlapack). Off
    /// Windows by its file: `linkLibrary` would also add the library's
    /// zig-cache directory as an rpath (std.Build does that for every
    /// linked dynamic artifact), a build-machine path in what ships.
    /// Windows links the import library and has no rpaths.
    fn linkSibling(ctx: *const Ctx, mod: *std.Build.Module, lib: *std.Build.Step.Compile) void {
        if (ctx.os == .windows) mod.linkLibrary(lib) else mod.addObjectFile(lib.getEmittedBin());
    }

    /// Where an artifact is installed, for its rpaths.
    const RDir = enum { rlib, modules, exec, pkglibs };

    /// The rpaths of an artifact: R_HOME/lib and <prefix>/lib, relative to
    /// its own directory ($ORIGIN on ELF, @loader_path on Mach-O). conda
    /// and the standalone tree share that layout (<prefix>/lib/R and
    /// <prefix>/lib), so these are final: nothing rewrites them after the
    /// build (feat-no-host-paths PLAN.md, F1.2). No absolute rpath is
    /// added anywhere; the R this build runs finds the env's libraries
    /// through buildLdPath. No-op on Windows.
    fn relRPaths(ctx: *const Ctx, mod: *std.Build.Module, where: RDir) void {
        const origin = switch (ctx.os) {
            .linux => "$ORIGIN",
            .macos => "@loader_path",
            .windows => return,
        };
        const rel: [2][]const u8 = switch (where) {
            .rlib => .{ "", "/../.." },
            .modules => .{ "/../lib", "/../.." },
            .exec => .{ "/../../lib", "/../../.." },
            .pkglibs => .{ "/../../../lib", "/../../../.." },
        };
        for (rel) |r| mod.addRPathSpecial(ctx.b.fmt("{s}{s}", .{ origin, r }));
    }

    /// Link the BLAS provider: internal libRblas.so or system openblas.
    fn linkBlas(ctx: *const Ctx, mod: *std.Build.Module) void {
        if (ctx.blas == .openblas) {
            mod.linkSystemLibrary("openblas", .{ .use_pkg_config = .no });
        } else {
            ctx.linkSibling(mod, ctx.rblas.?);
        }
    }
    /// Link the LAPACK provider: internal libRlapack.so or system openblas
    /// (conda-forge's openblas package bundles LAPACK too).
    fn linkLapack(ctx: *const Ctx, mod: *std.Build.Module) void {
        if (ctx.blas == .openblas) {
            mod.linkSystemLibrary("openblas", .{ .use_pkg_config = .no });
        } else {
            ctx.linkSibling(mod, ctx.rlapack.?);
        }
    }

    fn path(ctx: *const Ctx, sub: []const u8) std.Build.LazyPath {
        return ctx.src.path(ctx.b, sub);
    }
    fn absSub(ctx: *const Ctx, comptime fmt: []const u8, args: anytype) []const u8 {
        return ctx.b.fmt(fmt, args);
    }

    /// conda-forge's own real packaging convention: non-Python Windows
    /// content lives under Library/{bin,lib,include}, unix content lives
    /// flat under {bin,lib,include} — not artificial, but re-derived as
    /// an inline ternary independently at many call sites before this
    /// helper existed. `sub` is a comptime path fragment, e.g. "lib" or
    /// "include".
    fn condaDir(ctx: *const Ctx, comptime sub: []const u8) []const u8 {
        return switch (ctx.os) {
            .windows => ctx.absSub("{s}/Library/" ++ sub, .{ctx.conda}),
            else => ctx.absSub("{s}/" ++ sub, .{ctx.conda}),
        };
    }

    /// Library search path for the R this build runs (bootstrap, `verify
    /// Rscript`, `zig build check`), set as R_LD_LIBRARY_PATH, which the
    /// installed etc/ldpaths honours and turns into LD_LIBRARY_PATH or
    /// DYLD_FALLBACK_LIBRARY_PATH inside bin/R (after macOS's SIP has
    /// dropped DYLD_* from the environment of the /bin/sh it runs under).
    /// The env's lib dir is a build-time need only: nothing installed
    /// records it (feat-no-host-paths PLAN.md, F1.1). Null on Windows,
    /// which finds DLLs through PATH and the exe's directory.
    fn buildLdPath(ctx: *const Ctx) ?[]const u8 {
        if (ctx.os == .windows) return null;
        return ctx.absSub("{s}/lib:{s}", .{ ctx.rhome, ctx.condaDir("lib") });
    }

    /// Add {conda}/lib (Library/lib on Windows) as a library search path
    /// and, on unix/macOS only — rpath is a real ELF/Mach-O concept with
    /// no Windows/PE analogue (PE's DLL search is PATH/same-directory
    /// based instead) — pair it with the identical rpath entry. Every
    /// call site used to do this by hand; this removes the "did I
    /// remember the rpath pairing" question.
    fn addCondaLibPath(ctx: *const Ctx, mod: *std.Build.Module) void {
        const lib_dir = ctx.condaDir("lib");
        mod.addLibraryPath(.{ .cwd_relative = lib_dir });
    }

    /// macOS: the two SDK search dirs a deployment-target link leaves out
    /// (see the target comment in build()): -F for -framework, and usr/lib
    /// for the SDK-only libraries (libresolv, libobjc's dependencies). Call
    /// it last on a module, once every other -L is in: zig searches library
    /// dirs in the order they were added, and the SDK's usr/lib also has
    /// .tbd stubs for libz, libiconv and libcurl, so ahead of conda's lib
    /// dir those -l flags would bind the SDK's older libraries without a
    /// word. No-op off macOS.
    fn addSdkPaths(ctx: *const Ctx, mod: *std.Build.Module) void {
        if (ctx.sdk.len == 0) return;
        mod.addFrameworkPath(.{ .cwd_relative = ctx.absSub("{s}/System/Library/Frameworks", .{ctx.sdk}) });
        mod.addLibraryPath(.{ .cwd_relative = ctx.absSub("{s}/usr/lib", .{ctx.sdk}) });
    }

    /// R_HOME install-dir for `sub` — "Library/lib/R/<sub>" on Windows
    /// (must match ctx.rhome; see the NTFS Lib/ case-fold note at this
    /// struct's rhome-computation call site), "lib/R/<sub>" elsewhere.
    /// `sub` is a comptime path fragment; pass "" for R_HOME itself.
    fn rhomeInstallDir(ctx: *const Ctx, comptime sub: []const u8) std.Build.InstallDir {
        return .{ .custom = switch (ctx.os) {
            .windows => "Library/lib/R/" ++ sub,
            else => "lib/R/" ++ sub,
        } };
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

    var variant = b.option(Variant, "variant", "R build variant: slim (default), full, or minimal (unix only)") orelse .slim;
    const blas = b.option(Blas, "blas", "BLAS/LAPACK flavor: internal (default) or openblas") orelse .internal;
    // What the compile preflight (scripts/zig-build.sh's install.R patch)
    // tells someone without the toolchain package to install: written into
    // etc/Renviron (Windows: etc/Renviron.site). zig-build.sh passes the
    // conda one for the conda build; the wheel sets its own; empty means R's
    // generic message.
    const toolchain_hint = b.option([]const u8, "toolchain-hint", "R_ZIG_TOOLCHAIN_HINT default written into etc/Renviron") orelse "";

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
    // MSVC ABI — this whole toolchain (flang-zig's MinGW target,
    // x86_64-w64-mingw32-* binutils, .dll.a import libraries) is built on
    // the GNU/MinGW ABI instead (what `zig cc` itself defaults to there,
    // and so what rzig's gcc.exe compiles packages for), so re-resolve
    // explicitly.
    //
    // On Linux, pin the glibc floor to 2.17 (RHEL/CentOS 7 era, ~2013) —
    // zig cross-links against its own bundled old-glibc stubs for this,
    // no old build machine/container needed. glibc's own ABI guarantee is
    // strictly backward compatible (a 2.17-targeted binary runs unchanged
    // on any newer glibc), so this is a strict compatibility win with no
    // downside, not a separate build variant: requested for older HPC
    // servers still on glibc 2.17, but there's no reason every other
    // Linux target shouldn't get the same floor for free. Verified this
    // is not just theoretical: conda-forge's own linux-64 packages
    // (libcurl.so.4 checked directly via `objdump -T`) already cap out at
    // GLIBC_2.17 themselves — conda-forge deliberately builds against an
    // old sysroot for exactly this reason, so the non-zig-compiled
    // dependencies (conda libs) were already
    // compatible; only this project's own zig-compiled code defaulted to
    // the host's (much newer) native glibc before this.
    // .cpu_model = .baseline everywhere (not native): these artifacts
    // ship to arbitrary consumer machines through the conda channel, so
    // native-CPU codegen was always wrong for them — same portability
    // argument as the glibc floor above, and conda-forge's own packages
    // are baseline-ISA for the same reason. (Introduced while chasing a
    // SIGILL in R's bootstrap on GitHub's ubuntu-24.04-arm runners, which
    // it did not fix — that crash was unrelated to codegen: gfortran's
    // implicit search dirs put conda's aarch64 *sysroot* lib64, which
    // ships its own libc.so.6/ld-linux, on R_LD_LIBRARY_PATH, so every
    // R process loaded a foreign glibc under the host ld.so and died in
    // startup with SIGILL or SIGSEGV. No platform uses gfortran any more.
    // Baseline stays on its own merits.)
    //
    // macOS: the same floor idea as glibc 2.17, as a deployment target
    // (macos_min, 13.0). A native macOS query makes zig stamp every
    // binary's LC_BUILD_VERSION minos with the *build host's* version, so
    // a tree built on macOS 26 claims to need 26 (and make-wheel.py derives
    // the wheel tag from exactly that). 13.0 is zig 0.16's own supported
    // floor (std.Target's default macOS range); ziglang, the wheel's
    // compiler dependency, needs 12. The query names no OS tag, only
    // os_version_min (the "<arch>-native.13.0" the shims pass): zig then
    // treats the OS as non-native, so it stamps 13.0 and records no rpath
    // per -L directory, while the ABI still counts as native, so headers
    // and libSystem come from the installed SDK (std.Target.Query's
    // isNativeOs requires os_version_min == null; LibCDirs.detect looks
    // for the SDK when isNativeAbi). The non-native link searches neither
    // the SDK's frameworks nor its usr/lib, so ctx.addSdkPaths adds both
    // back. "<arch>-macos.13.0" (an explicit OS tag) would lose the SDK
    // altogether. Verified on omicron 2026-10-01 for every Mach-O under
    // lib/R (feat-no-host-paths PLAN.md, "macOS deployment target").
    const target = if (os == .windows)
        b.resolveTargetQuery(.{ .abi = .gnu, .cpu_model = .baseline })
    else if (os == .linux)
        b.resolveTargetQuery(.{ .abi = .gnu, .glibc_version = floors.glibc, .cpu_model = .baseline })
    else
        b.resolveTargetQuery(.{ .cpu_model = .baseline, .os_version_min = .{ .semver = macos_min } });
    // The installed SDK, asked the way zig itself asks
    // (std.zig.system.darwin.getSdk); "" off macOS.
    const sdk: []const u8 = if (os == .macos)
        std.mem.trim(u8, b.run(&.{ "/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path" }), " \t\r\n")
    else
        "";
    // gnuwin32 has no slim/full switch at all (jpeg/tiff/tcltk are always
    // on — "slim==full on Windows", a pre-existing project convention);
    // -Dvariant is meaningless there, force .full regardless of what was
    // passed rather than silently building something that doesn't exist.
    // Except minimal: nobody asks for it by accident, and quietly handing
    // back a full build (tcltk, jpeg, tiff, cairo) is the opposite of what
    // was asked for.
    if (os == .windows) {
        if (variant == .minimal) {
            std.debug.print("error: -Dvariant=minimal is not available on Windows (gnuwin32 has no switches to drop cairo/ICU/OpenMP; Windows always builds full)\n", .{});
            return error.UnsupportedVariant;
        }
        variant = .full;
    }
    const arch: Arch = switch (target.result.cpu.arch) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        else => {
            std.debug.print("error: unsupported target arch '{s}'\n", .{@tagName(target.result.cpu.arch)});
            return error.UnsupportedArch;
        },
    };
    const arch_str = arch.condaForgeSuffix();
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
    // b.install_prefix carries the OS-native separator too, same as
    // b.pathFromRoot (see src_abs above) — normally harmless, but
    // ctx.prefix/ctx.rhome (derived from it) get interpolated into R
    // code strings throughout bootstrap()/stageLibraryPayload() just
    // like src_abs does. Never hit before by coincidence: a conda-
    // sandbox build with a short `--output-dir` (fixing an unrelated
    // dlltool path-length limit) produced a host-env directory literally
    // named "h_env", and "\h" is not a valid R escape sequence at all
    // ('\h' is an unrecognized escape...) — surfacing a latent bug that,
    // for OTHER letters forming a *valid* (but wrong) R escape (`\n`,
    // `\t`, `\r`, ...), could have been silently corrupting the path
    // instead of erroring. Normalize once here, matching src_abs exactly.
    const install_prefix = std.mem.replaceOwned(u8, arena, b.install_prefix, "\\", "/") catch @panic("OOM");
    const rhome = switch (os) {
        .windows => b.fmt("{s}/Library/lib/R", .{install_prefix}),
        else => b.fmt("{s}/lib/R", .{install_prefix}),
    };

    // R's Fortran compiler is flang, flang-pixi's zig-built flang-zig, on
    // every platform (pixi.toml, recipe.yaml; consolidation/PLAN.md Phase
    // 2, gfortran gone since 2026-10-03). Looked for on disk, in the env
    // and, in a rattler-build sandbox, in $BUILD_PREFIX, where the
    // compilers (build: deps) live while $CONDA_PREFIX is the host env
    // with only the runtime (flang-rt-zig); never on PATH, so a host
    // flang is never mistaken for it. fortranOne runs `flang` by name: the
    // env's bin dirs lead PATH (scripts/env.sh; pixi's activation on
    // Windows). Printed once, so a build log always says which flang
    // built R's Fortran. Without one the build stops here, with one error.
    const flang_bin: []const u8 = blk: {
        var probed = std.ArrayList(u8).empty;
        const prefixes = [_]?[]const u8{ b.graph.environ_map.get("BUILD_PREFIX"), conda };
        for (prefixes) |maybe| {
            const pfx = maybe orelse continue;
            const cand = switch (os) {
                .windows => b.fmt("{s}/Library/bin/flang.exe", .{pfx}),
                else => b.fmt("{s}/bin/flang", .{pfx}),
            };
            std.Io.Dir.cwd().access(io, cand, .{}) catch {
                try probed.appendSlice(arena, b.fmt(" {s}", .{cand}));
                continue;
            };
            break :blk cand;
        }
        std.debug.print("error: no flang in this environment (looked for{s}): R's Fortran needs flang-pixi's flang-zig, a dependency in pixi.toml and recipe/recipe.yaml\n", .{probed.items});
        return error.MissingFlang;
    };
    std.debug.print("r-zig: Fortran compiler = flang ({s}; {s})\n", .{ flang_bin, platform });

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
        .prefix = install_prefix,
        .rhome = rhome,
        .config_dir = config_dir,
        .toolchain_hint = toolchain_hint,
        .sdk = sdk,
        .zig_lib_dir = try staticLibcxxLibDir(b, io, os),
        .prefix_is_env = samePhysicalDir(io, arena, install_prefix, conda),
        // Windows keeps these defaults. Its compile graph never passes
        // `.openmp = true`, so R itself has no OpenMP there, and `openmp`
        // decides only what packages get: etc/x64/Makeconf's
        // SHLIB_OPENMP_*FLAGS (@OPENMP@, installWindowsCompilerContract)
        // and the files their compiles and links need (installOpenMP). It
        // builds its own cairo device. unix overwrites both from subst.txt
        // right after loadSubstTable below.
        .openmp = true,
        .devcairo = true,
        .flangrt_dir = try findFlangRt(b, io, conda, os),
        .path_flags = &.{},
        .empty_c = b.addWriteFiles().add("empty.c", "/* linkRoot: no code of its own */\ntypedef int r_zig_link_root;\n"),
        .subst = std.StringHashMap([]const u8).init(arena),
        .mk_subst = std.StringHashMap([]const u8).init(arena),
        .geninc = undefined,
        .libR = undefined,
        .rblas = undefined,
        .rlapack = undefined,
        .rzig = undefined,
    };
    ctx.path_flags = try filePathFlags(&ctx, io);

    // rzig (zigbuild/tools/rzig/main.zig): the compiler front Makeconf
    // names, for R's own target (glibc floor, deployment target,
    // windows-gnu), installed under the toolchain names by installRzig.
    // `zig build rzig-test` runs its unit tests on the build machine.
    {
        const rz = rzig_build.add(b, b.path("zigbuild/tools/rzig"), target, rzig_build.default_optimize);
        ctx.addSdkPaths(rz.exe.root_module);
        ctx.rzig = rz.bin;
        const inst = installRzig(&ctx);
        b.getInstallStep().dependOn(inst);
        b.step("rzig", "Build rzig and install it as the compilers in R_HOME/bin/toolchain").dependOn(inst);
        b.step("rzig-test", "Run rzig's unit tests").dependOn(&b.addRunArtifact(rz.tests).step);
    }

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
    // Makeconf's CPPFLAGS and LDFLAGS are empty in every distribution
    // (feat-no-host-paths F3b): the compilers, rzig, add the environment's
    // -I and -L, and for a conda env the rpath into its lib dir
    // (zigbuild/tools/rzig/environment.zig). An empty assignment still
    // overrides a CPPFLAGS or LDFLAGS in the environment, as R's own did.
    // R's own build keeps the absolute values (ctx.subst).
    try ctx.mk_subst.put("CPPFLAGS", "");
    try ctx.mk_subst.put("LDFLAGS", "");
    // openblas has no vendored config of its own (F3.2: a link-time swap),
    // so it inherits the internal-BLAS S-table — and with it a Makeconf
    // telling packages `-lRblas`/`-lRlapack`, libraries this flavor never
    // builds. Every package with CRAN's `PKG_LIBS = $(LAPACK_LIBS)
    // $(BLAS_LIBS) $(FLIBS)` failed to link ("unable to find dynamic system
    // library 'Rblas'", quadprog on the CI openblas legs). Replay what a
    // real `configure --with-blas=-lopenblas --with-lapack=-lopenblas`
    // writes (build/obj-*-slim-openblas/config.status): LAPACK is found
    // inside openblas, so LAPACK_LIBS is empty and BLAS_LIBS carries both.
    if (blas == .openblas) {
        try ctx.subst.put("BLAS_LIBS", "-lopenblas");
        try ctx.subst.put("LAPACK_LIBS", "");
    }
    ctx.openmp = ctx.subst.get("R_OPENMP_CFLAGS").?.len > 0;
    ctx.devcairo = ctx.subst.get("BUILD_DEVCAIRO_TRUE").?.len == 0;
    // FC is the toolchain's Fortran front, rzig's zig-fc (feat-no-host-
    // paths F3c, zigbuild/tools/rzig/fortran.zig), as CC and CXX are its
    // zig-cc and zig-cxx: it runs the flang on PATH, on macOS with the
    // floor packages' Fortran objects get (floors.zig, as fortranOne's;
    // FC carried it before), and links a USE_FC_TO_LINK package
    // (SHLIB_FCLD = $(FC)) through zig with the static runtime, which
    // flang's own driver cannot find. Makeconf only: R's own build runs
    // flang itself (fortranOne).
    try ctx.mk_subst.put("FC", "$(R_HOME)/bin/toolchain/zig-fc");

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
        ctx.relRPaths(rblas_mod, .rlib);
        ctx.rblas = addSharedLib(&ctx, "Rblas", rblas_mod);

        const rlapack_mod = newCMod(&ctx);
        for (lapack_objs.items) |o| rlapack_mod.addObjectFile(o);
        ctx.linkSibling(rlapack_mod, ctx.rblas.?);
        linkFortranRt(&ctx, rlapack_mod);
        ctx.relRPaths(rlapack_mod, .rlib);
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
    ctx.relRPaths(libR_mod, .rlib);
    ctx.libR = addSharedLib(&ctx, "R", libR_mod);

    // ------------------------------------------------------------------
    // Executables: bin/exec/R (Rmain.c) and bin/Rscript
    // ------------------------------------------------------------------
    const rbin_mod = newCMod(&ctx);
    rbin_mod.addIncludePath(ctx.geninc);
    rbin_mod.addIncludePath(ctx.path("src/include"));
    addCGroup(&ctx, rbin_mod, "src/main", &.{"Rmain.c"}, .{ .openmp = true });
    ctx.linkSibling(rbin_mod, ctx.libR);
    ctx.linkBlas(rbin_mod);
    linkOmp(&ctx, rbin_mod);
    ctx.relRPaths(rbin_mod, .exec);
    ctx.addSdkPaths(rbin_mod); // last: see addSdkPaths
    const rbin = b.addExecutable(.{ .name = "R.bin", .root_module = linkRoot(&ctx, rbin_mod) });
    rbin.rdynamic = true; // MAIN_LDFLAGS = -Wl,--export-dynamic
    rbin.each_lib_rpath = false; // see addSharedLib
    rbin.zig_lib_dir = ctx.zig_lib_dir; // see addSharedLib
    macHeaderpad(&ctx, rbin);

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
        ctx.linkSibling(lapmod, ctx.rlapack.?);
        ctx.linkSibling(lapmod, ctx.rblas.?);
    }
    ctx.linkSibling(lapmod, ctx.libR);
    linkFortranRt(&ctx, lapmod);
    linkOmp(&ctx, lapmod);
    ctx.relRPaths(lapmod, .modules);
    const mod_lapack = addSharedLib(&ctx, "mod_lapack", lapmod);

    const inetmod = newCMod(&ctx);
    inetmod.addIncludePath(ctx.geninc);
    inetmod.addIncludePath(ctx.path("src/include"));
    addCGroup(&ctx, inetmod, "src/modules/internet", &rspec.internet_c, .{ .openmp = true });
    ctx.linkSibling(inetmod, ctx.libR);
    inetmod.linkSystemLibrary("curl", .{ .use_pkg_config = .no });
    ctx.relRPaths(inetmod, .modules);
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
            ctx.linkSibling(m, ctx.rlapack.?);
            ctx.linkSibling(m, ctx.rblas.?);
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
        const m = newPkgMod(&ctx, "src/library/grDevices/src", &rspec.grdevices_shared_c, .{
            .extra = &.{"-DHAVE_CONFIG_H"},
        });
        addCGroup(&ctx, m, "src/library/grDevices/src", &rspec.grdevices_cairo_c, .{
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
        // library/tcltk/libs/tcltk.so, as newPkgMod's: R_HOME/lib and
        // <prefix>/lib, where vendor-libs.sh puts libtcl and libtk.
        ctx.relRPaths(m, .pkglibs);
        m.addIncludePath(ctx.geninc);
        m.addIncludePath(ctx.path("src/include"));
        var extra = std.ArrayList([]const u8).empty;
        try extra.append(arena, "-DHAVE_CONFIG_H");
        var it = std.mem.tokenizeScalar(u8, ctx.subst.get("TCLTK_CPPFLAGS").?, ' ');
        while (it.next()) |tok| try extra.append(arena, tok);
        addCGroup(&ctx, m, "src/library/tcltk/src", &rspec.tcltk_c, .{ .extra = extra.items });
        // linux: conda-forge's libtcl8.6.so and libtk8.6.so carry no
        // DT_SONAME, and for such a library lld records in DT_NEEDED the
        // path it was given, which zig makes the env's absolute one. So
        // tcltk.so named the build machine, vendor-libs.sh's walk (ldd, by
        // name) never copied the two, and anywhere else library(tcltk)
        // failed in dyn.load. The link takes copies that carry their own
        // file name as DT_SONAME instead (patchelf, in the cache, used for
        // this link only, never installed): tcltk.so then needs them by
        // name, through its relative rpath in <prefix>/lib, where
        // vendor-libs.sh copies the env's. (macOS: their install names are
        // @rpath/..., nothing to do.)
        var libs = std.ArrayList(u8).empty;
        var lt = std.mem.tokenizeScalar(u8, ctx.subst.get("TCLTK_LIBS").?, ' ');
        while (lt.next()) |tok| {
            if (ctx.os == .linux and (std.mem.eql(u8, tok, "-ltcl8.6") or std.mem.eql(u8, tok, "-ltk8.6"))) {
                const so = b.fmt("lib{s}.so", .{tok[2..]});
                const named = b.addSystemCommand(&.{ "patchelf", "--set-soname", so, "--output" });
                named.setName(b.fmt("{s} with DT_SONAME", .{so}));
                const copy = named.addOutputFileArg(so);
                named.addFileArg(.{ .cwd_relative = ctx.absSub("{s}/lib/{s}", .{ ctx.conda, so }) });
                m.addObjectFile(copy);
            } else {
                try libs.appendSlice(arena, tok);
                try libs.append(arena, ' ');
            }
        }
        applyLinkFlags(&ctx, m, libs.items);
        applyLinkFlags(&ctx, m, ctx.subst.get("LIBM").?);
        try pkg_libs.append(arena, .{ .pkg = "tcltk", .lib = addSharedLib(&ctx, "pkg_tcltk", m) });
    }

    // grDevices cairo module (library/grDevices/libs/cairo.so): cairoBM.c +
    // rbitmap.o from src/modules/X11 (built there even with --with-x=no).
    // Not built at all without cairo (minimal): devCairo.c, always in
    // grDevices.so, then reports cairo as unavailable instead of trying
    // to load it.
    const mod_cairo: ?*std.Build.Step.Compile = if (ctx.devcairo) blk: {
        const cairo_mod = newCMod(&ctx);
        cairo_mod.addIncludePath(ctx.geninc);
        cairo_mod.addIncludePath(ctx.path("src/include"));
        {
            var flags = std.ArrayList([]const u8).empty;
            try flags.appendSlice(arena, ctx.path_flags);
            try flags.appendSlice(arena, &.{ "-std=gnu23", "-fno-sanitize=undefined", "-O2", "-DHAVE_CONFIG_H" });
            if (ctx.openmp) try flags.append(arena, "-fopenmp");
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
        ctx.linkSibling(cairo_mod, ctx.libR);
        ctx.relRPaths(cairo_mod, .pkglibs);
        applyLinkFlags(&ctx, cairo_mod, ctx.subst.get("CAIRO_LIBS").?);
        // full only: rbitmap.c's HAVE_JPEG/HAVE_TIFF branches (from the
        // per-variant config.h) need libjpeg/libtiff — CAIRO_LIBS doesn't
        // carry them (only -lpng16), BITMAP_LIBS does (slim's BITMAP_LIBS is
        // just -lpng16 too, already covered via CAIRO_LIBS, so apply it only
        // for full to avoid a harmless but pointless double -lpng16 on slim).
        if (ctx.variant == .full) applyLinkFlags(&ctx, cairo_mod, ctx.subst.get("BITMAP_LIBS").?);
        linkOmp(&ctx, cairo_mod);
        break :blk addSharedLib(&ctx, "pkg_cairo", cairo_mod);
    } else null;

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
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(ctx.libR.getEmittedBin(), lib_dir, libR_name).step);
    if (ctx.rblas) |rblas| b.getInstallStep().dependOn(&b.addInstallFileWithDir(rblas.getEmittedBin(), lib_dir, libRblas_name).step);
    if (ctx.rlapack) |rlapack| b.getInstallStep().dependOn(&b.addInstallFileWithDir(rlapack.getEmittedBin(), lib_dir, libRlapack_name).step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(mod_lapack.getEmittedBin(), modules_dir, "lapack.so").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(mod_internet.getEmittedBin(), modules_dir, "internet.so").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rbin.getEmittedBin(), .{ .custom = "lib/R/bin/exec" }, "R").step);
    // Rscript: the POSIX sh emulator, not the compiled Rscript, which
    // embeds R_HOME as a build path (F1.4). bin/R likewise is a
    // trampoline into lib/R/bin/R.
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("zigbuild/launchers/Rscript"), .{ .custom = "lib/R/bin" }, "Rscript").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("zigbuild/launchers/Rscript"), .{ .custom = "bin" }, "Rscript").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("zigbuild/launchers/R"), .{ .custom = "bin" }, "R").step);
    // Next to the compilers Makeconf names ($(R_HOME)/bin/toolchain, rzig:
    // installRzig, from build()), for minimal (the wheel's tree) GNU make:
    // a pip-installed R has no other make (python:*-slim images ship
    // none); conda-forge's links libc only. The r-zig-toolchain packages
    // own this directory.
    if (ctx.variant == .minimal) {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = ctx.condaDir("bin/make") }, .{ .custom = "lib/R/bin/toolchain" }, "make").step);
    }
    // OpenMP for packages: llvm-openmp's headers in <prefix>/include
    // (libomp itself is vendored into <prefix>/lib, libR needs it).
    try installOpenMP(&ctx, io);
    // The env's runtime data, for a tree that is not the env: the CA
    // bundle (etc/Renviron names it, finalRenviron), fontconfig's
    // configuration, and in full Tcl/Tk's script libraries.
    try installEnvRuntime(&ctx, io);
    // ------------------------------------------------------------------
    // Static R_HOME payload: headers, etc/, bin scripts, share/, doc/,
    // and every base package's R code / DESCRIPTION / NAMESPACE / data.
    // ------------------------------------------------------------------
    const libstage = try installStaticTree(&ctx, io);
    for (pkg_libs.items) |pl| {
        _ = libstage.addCopyFile(pl.lib.getEmittedBin(), ctx.absSub("{s}/libs/{s}.so", .{ pl.pkg, pl.pkg }));
    }
    if (mod_cairo) |mc| _ = libstage.addCopyFile(mc.getEmittedBin(), "grDevices/libs/cairo.so");

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
    // config.h/Rconfig.h (not autoconf templates), so most of unix's
    // loadSubstTable (config.status template-var defaults, AC_SUBST_FILE
    // rules_frag content) doesn't apply here. But the same vendored-
    // subst.txt *mechanism* still does: this config dir's own subst.txt
    // (hand-populated — no config.status to capture it from — with the
    // library lists every Windows-only DLL link below used to hardcode
    // individually) is loaded through the exact same parser unix uses,
    // so every one of those hardcodes becomes a normal
    // `applyLinkFlags(ctx, mod, ctx.subst.get("KEY").?)` call — see
    // .github/devdocs/feat-cross-platform-standardization/PLAN.md
    // Phase 4.
    try loadSubstFile(ctx, io, ctx.config_dir);
    // Only a handful of @VAR@ tokens exist at all (found by grepping the
    // vendored file directly, not assumed): CC_VER/FC_VER/VERSION in
    // config.h, PACKAGE_VERSION/RMATH_HAVE_WORKING_LOG1P in Rmath.h0.in.
    try ctx.subst.put("VERSION", r_version);
    try ctx.subst.put("PACKAGE_VERSION", r_version);
    try ctx.subst.put("CC_VER", "zig cc (LLVM/clang, MinGW target)");
    try ctx.subst.put("FC_VER", "flang (flang-pixi flang-zig, MinGW target)");
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
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, b.pathFromRoot(b.fmt("{s}/config.h", .{ctx.config_dir})), b.allocator, .limited(4 * 1024 * 1024));
        _ = geninc.add("config.h", try substitute(ctx, raw));
    }
    _ = geninc.addCopyFile(b.path(b.fmt("{s}/Rconfig.h", .{ctx.config_dir})), "Rconfig.h");
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
    const blas_f = fortranGroup(ctx, "src/extra/blas", &rspec.blas_f, &.{});
    const blas_f90 = fortranGroup(ctx, "src/extra/blas", &rspec.blas_f90, &.{});

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
    applyLinkFlags(ctx, graphapp_mod, ctx.subst.get("WIN_RGRAPHAPP_LIBS").?);
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
    // icuin/icuuc/icudt: USE_ICU is now on in the vendored config.h (see its
    // own comment) — platform.c/util.c/registryTZ.c's ICU collation code
    // needs these at link time. conda-forge's Windows ICU import libs use
    // ICU4C's short Windows component names (icuin = i18n, not icui18n like
    // unix) with no lib-prefix quirk this time (plain icuin.lib/icuuc.lib/
    // icudt.lib, verified present in the pixi env's Library/lib).
    applyLinkFlags(ctx, r_final_mod, ctx.subst.get("WIN_R_DLL_LIBS").?);
    linkFortranRt(ctx, r_final_mod);
    // R itself is built without OpenMP on Windows, as upstream: gnuwin32's
    // config.h leaves HAVE_OPENMP off ("has it, but it is too slow to be
    // usable", said of GCC's libgomp under MinGW-w64), and R's own OpenMP
    // threads (R_num_math_threads) default to 1 on every platform anyway.
    // So no Windows compile group sets `.openmp = true` and R.dll links no
    // libomp (no linkOmp here). Packages get OpenMP all the same:
    // etc/x64/Makeconf offers SHLIB_OPENMP_*FLAGS = -fopenmp, and rzig
    // links them against conda-forge's LLVM libomp (llvm-openmp, the
    // release unix uses), which a standalone tree carries (installOpenMP;
    // libomp.dll from vendor-libs.sh).
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

    // modules/internet.dll (unix's mod_internet equivalent, same source
    // list — rspec.internet_c) — capabilities()$libcurl/http-ftp were
    // FALSE (this module simply didn't exist on Windows yet, found via a
    // real capabilities() check on kappa, not anticipated in F6.1/F6.2's
    // own spec). Ground truth from src/modules/internet/Makefile.win: same
    // 6 sources as unix, links -lR -lRgraphapp plus -lwininet -lws2_32
    // (gnuwin32's own EXTRA_LIBS) and libcurl itself.
    const inetmod = newCMod(ctx);
    inetmod.addIncludePath(ctx.geninc);
    inetmod.addIncludePath(ctx.path("src/include"));
    // Same psignal.h/trioremap.h need as r_core_mod/rscript_mod/rterm_mod
    // above (Defn.h pulls psignal.h in unconditionally) — found via a real
    // compile error.
    inetmod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    addCGroup(ctx, inetmod, "src/modules/internet", &rspec.internet_c, .{
        // -DHAVE_CURL_CURL_H/-DHAVE_LIBCURL: Makefile.win's own
        // libcurl-CPPFLAGS, gating libcurl.c's real (non-stub) code path.
        .extra = &.{ "-I%S/src/extra/graphapp", "-DHAVE_CURL_CURL_H", "-DHAVE_LIBCURL" },
    });
    inetmod.linkLibrary(libR);
    inetmod.linkLibrary(rgraphapp);
    // "libcurl" not "curl": same lib-prefix naming quirk as libbz2/libpng
    // above (conda-forge's Windows import lib is libcurl.lib).
    applyLinkFlags(ctx, inetmod, ctx.subst.get("WIN_INTERNET_LIBS").?);
    const mod_internet = addSharedLib(ctx, "mod_internet", inetmod);

    // (The package-compilation contract's gcc.exe and g++.exe are rzig,
    // installed from build() by installRzig.)

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
    // R.exe: the "R CMD <subcommand>" dispatcher — genuinely required for
    // `install.packages(type="source")` to work at all, not optional the
    // way Rgui.exe/R.exe's OWN interactive use is (F6.0's original "no
    // R.exe" call only ever checked whether smoke/contract *invoked* it
    // directly, not whether R's own package-installer code shells out to
    // it internally). Found via a real contract-test failure: `utils::
    // install.packages()` hardcodes `cmd0 <- file.path(R.home("bin"), "R")`
    // (src/library/utils/R/packages2.R) unconditionally — both the serial
    // AND the Ncpus>1 parallel-Makefile install paths — so without a real
    // `bin/x64/R.exe`, package installation fails immediately with "No
    // such file or directory", regardless of how the C/C++/Fortran
    // toolchain itself is wired.
    //
    // Rather than reimplement rcmdfn.c's ~15-subcommand CMD dispatch
    // logic (INSTALL/SHLIB/REMOVE/build/check/Rprof/Rdiff/...) from
    // scratch, compile the REAL gnuwin32 sources — R.exe's own real
    // recipe (front-ends/Makefile: `R.exe: R.o ../rhome.o ../shext.o
    // rcico.o rcmdfn.o Renviron.o`), minus rcico.o (icon/manifest
    // resource — cosmetic, same "no icon resource" precedent as Rterm.exe
    // above). Every subcommand rcmdfn.c dispatches to is itself just a
    // templated `Rterm.exe -e tools:::.foo() ... --args ...` string it
    // re-execs (verified by reading rcmdfn.c directly) — the real logic
    // lives in R code this build already has, not in C we'd be
    // duplicating.
    //
    // Rcmd.exe (front-ends/Makefile: `Rcmd.exe: rcmd.o ../rhome.o
    // ../shext.o rcico.o rcmdfn.o Renviron.o`, the exact same recipe with
    // rcmd.c swapped for R.c) shares this whole compile+link shape — its
    // own main() is just `exit(rcmdfn(1, argc, argv))` (rcmd.c, verified
    // directly: no "-h"/"CMD"-token dispatch logic at all, cmdarg is
    // hardcoded to 1, so `Rcmd INSTALL` behaves like `R CMD INSTALL`
    // without needing the literal "CMD" argument). Genuinely required,
    // not just a nicety: many CRAN source packages with compiled code
    // call `system2(file.path(R.home("bin"), "Rcmd.exe"), c("config",
    // ...))` directly to query compiler settings (found via a real
    // `install.packages("pak")` failure — R.exe alone wasn't enough).
    const win_rcmd = winCmdFrontend(ctx, libR, rgraphapp, "R.c", "R");
    const win_rcmd_cmd = winCmdFrontend(ctx, libR, rgraphapp, "rcmd.c", "Rcmd");

    // ------------------------------------------------------------------
    // R_HOME/bin/R.exe and R_HOME/bin/Rscript.exe: CRAN's layout. Packages
    // run R by these paths: Rmpfr's configure `${R_HOME}/bin/R CMD config
    // CC`, rstan's Makevars.win `${R_HOME}/bin/Rscript`, s2's bundled
    // abseil (stress round 1: Rmpfr stopped at "no acceptable C
    // compiler" without them). gnuwin32 builds them as one program,
    // Rfe.exe (front-ends/Makefile: `Rfe.exe: Rfe.o ../rhome.o ../shext.o
    // rcico.o rcmdfn.o Renviron.o`, copied to bin/R.exe and
    // bin/Rscript.exe), which runs bin/x64's R.exe or Rscript.exe, by the
    // name it was started as, with the same arguments. See winRfe.
    const win_rfe = winRfe(ctx);

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
    const bin_dir: std.Build.InstallDir = ctx.rhomeInstallDir("bin/x64");
    // modules/x64/, not modules/ — R's module loader is just as
    // R_ARCH-aware as library.dynam() (see the platform.c/.Platform$r_arch
    // fix above); once R_ARCH was actually set correctly, R started
    // looking for "modules/x64/lapack.dll" specifically and failed to find
    // it at the (correctly-built, but wrongly-located) "modules/lapack.dll"
    // — found via a real "LoadLibrary failure: module not found" error for
    // a file that verifiably existed.
    const modules_dir: std.Build.InstallDir = ctx.rhomeInstallDir("modules/x64");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(libR.getEmittedBin(), bin_dir, "R.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rblas.getEmittedBin(), bin_dir, "Rblas.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rlapack.getEmittedBin(), bin_dir, "Rlapack.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rgraphapp.getEmittedBin(), bin_dir, "Rgraphapp.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(riconv.getEmittedBin(), bin_dir, "Riconv.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(mod_lapack.getEmittedBin(), modules_dir, "lapack.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(mod_internet.getEmittedBin(), modules_dir, "internet.dll").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rscript.getEmittedBin(), bin_dir, "Rscript.exe").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rterm.getEmittedBin(), bin_dir, "Rterm.exe").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(win_rcmd.getEmittedBin(), bin_dir, "R.exe").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(win_rcmd_cmd.getEmittedBin(), bin_dir, "Rcmd.exe").step);
    // R_HOME/bin, not bin/x64: Rfe under both names (above).
    for ([_][]const u8{ "R.exe", "Rscript.exe" }) |n| {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(win_rfe.getEmittedBin(), ctx.rhomeInstallDir("bin"), n).step);
    }
    // bin/config.sh (RHome/bin directly — NOT bin/x64/, unlike Rterm.exe/
    // R.exe/Rcmd.exe themselves; rcmdfn.c's own fallback case builds this
    // path as plain "%s/bin/config.sh" with only RHome, no BINDIR
    // component — found via a real "No such file or directory" once it
    // was first installed into bin_dir/x64 by mistake, confirmed against
    // BINDIR's absence in rcmdfn.c's own snprintf call for this one case).
    // `Rcmd config`/`R CMD config` runs `sh "$RHome/bin/config.sh"` — R
    // packages' configure scripts routinely call this directly (`R CMD
    // config CC`, etc.) to discover compiler settings; found via a real
    // `install.packages("pak")` failure. Confirmed byte-identical to
    // src/scripts/config (the same file installStaticTree's scripts_s
    // already copies verbatim into unix's bin/config, no @VAR@
    // substitution) against a real gnuwin32 build's own bin/config.sh —
    // just copied under the .sh name Windows' `sh "path.sh"` invocation
    // convention expects.
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(ctx.path("src/scripts/config"), ctx.rhomeInstallDir("bin"), "config.sh").step);
    // etc/Rcmd_environ: rcmdfn.c's own `process_Renviron(RHome/etc/
    // Rcmd_environ)` call (right before dispatching to a subcommand) —
    // sets R_OSTYPE=windows among other defaults (R_SHARE_DIR/R_GZIPCMD/
    // etc). Without it, config.sh's own `if test "${R_OSTYPE}" =
    // "windows"` check (which sets MAKE=make) silently fails, leaving
    // MAKE empty — found via a real "eval: -s: invalid option" error
    // (config.sh's `query="${MAKE} -s ..."` becomes just " -s ..." with
    // MAKE unset, and `eval`ing that treats "-s" as its own first,
    // invalid argument) that reproduced identically even when Rcmd.exe
    // was launched from inside a real Rscript.exe session (ruling out
    // "R's own startup sets this" as an alternative explanation — it
    // doesn't). A real, static gnuwin32 file (src/gnuwin32/fixed/etc/
    // Rcmd_environ) already exists for exactly this — same "vendor
    // gnuwin32's own ready-made file" pattern as config.h/Rconsole.
    // RHome/etc/ directly, no bin/x64 arch subdir (matches config.sh's
    // own path convention, confirmed via rcmdfn.c's literal
    // string-concat: RHome + "/etc/Rcmd_environ"). r-zig's lines follow
    // R's (rcmdEnviron).
    const rcmd_env_wf = b.addWriteFiles();
    const rcmd_env = rcmd_env_wf.add("Rcmd_environ", try rcmdEnviron(ctx, io));
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rcmd_env, ctx.rhomeInstallDir("etc"), "Rcmd_environ").step);

    try installWindowsCompilerContract(ctx, io);
    // OpenMP for packages (R itself has none on Windows, see R.dll's link
    // above): llvm-openmp's headers and libomp.lib.
    try installOpenMP(ctx, io);
    // The env's runtime data, for a tree that is not the env (Tcl/Tk with
    // its headers, and fontconfig's configuration), and etc/Renviron.site
    // (in the conda build: MY_TCLTK, the env's Tcl/Tk).
    try installEnvRuntime(ctx, io);

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
    // Set inside the grDevices block below; winCairo.dll links against it
    // (gnuwin32's own cairo/Makefile.win: `PKG_LIBS = $(CAIRO_LIBS) -L.. -lgrDevices`).
    var grdevices_lib: ?*std.Build.Step.Compile = null;
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
        // devWindows.c needs opt.h/console.h/rui.h/graphapp headers
        // (gnuwin32, extra) plus R_ARCH for its own .Platform$r_arch-style
        // path logic; winbitmap.c needs the bitmap format #defines — both
        // straight from grDevices/src/Makefile.win's own per-file
        // CPPFLAGS. Applied to the whole module (including the 12 files
        // shared with unix, grdevices_shared_c) rather than splitting
        // per-file flags further — harmless on files that don't
        // reference them, and matches this module's pre-existing,
        // already-verified-on-kappa compile flags exactly.
        const win_grdevices_extra = &.{ "-I%S/src/gnuwin32", "-I%S/src/extra", "-DR_ARCH=\"x64\"", "-DHAVE_PNG", "-DHAVE_JPEG", "-DHAVE_TIFF" };
        const m = newPkgMod(ctx, "src/library/grDevices/src", &rspec.grdevices_shared_c, .{
            .extra = win_grdevices_extra,
        });
        addCGroup(ctx, m, "src/library/grDevices/src", &rspec.win_grdevices_c, .{
            .extra = win_grdevices_extra,
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
        applyLinkFlags(ctx, m, ctx.subst.get("WIN_BITMAP_LIBS").?);
        // Named grDevices, not pkg_grDevices as the other package DLLs
        // are: winCairo.dll imports it, and a PE import names the DLL by
        // the file name it was linked as; the loader then matches it
        // against the installed grDevices.dll's name. With the pkg_ name,
        // winCairo.dll never loaded ("unable to load winCairo.dll" from
        // svg(), cairo_pdf() and png(type = "cairo"), while
        // capabilities("cairo") said TRUE); found by verify-tree.sh's DLL
        // closure check (F1.7).
        grdevices_lib = addSharedLib(ctx, "grDevices", m);
        try win_pkg_libs.append(b.allocator, .{ .pkg = "grDevices", .lib = grdevices_lib.? });
    }

    // grDevices/libs/x64/winCairo.dll: a SEPARATE device DLL from
    // grDevices.dll itself (distinct from grDevices' own devWindows.c
    // device) — capabilities()$cairo was FALSE without it (a real gap
    // found via kappa's capabilities() check, not just F6.2's already-
    // documented "still deferred" note). Ground truth from gnuwin32's real
    // src/library/grDevices/src/cairo/Makefile.win: one source (cairoBM.c),
    // linked against grDevices.dll itself (-lgrDevices) plus cairo
    // (CAIRO_LIBS/CAIRO_CPPFLAGS). CAIRO_LIBS now comes from this config
    // dir's own vendored subst.txt (-lcairo -lfontconfig — hand-populated
    // rather than captured from a config.status, since gnuwin32 has none;
    // same values this used to hardcode directly here before Phase 4 of
    // feat-cross-platform-standardization unified the mechanism with
    // unix's applyLinkFlags/ctx.subst.get pattern).
    const win_cairo = blk: {
        const m = newCMod(ctx);
        m.addIncludePath(ctx.geninc);
        m.addIncludePath(ctx.path("src/include"));
        addCGroup(ctx, m, "src/library/grDevices/src/cairo", &.{"cairoBM.c"}, .{
            .extra = &.{
                "-I%S/src/library/grDevices/src/cairo",
                "-I%S/src/library/grDevices/src",
                "-I%C/Library/include/cairo",
                "-I%C/Library/include/freetype2",
            },
        });
        // cairoBM.c/cairoFns.c call R API + graphics-engine functions
        // (Rf_cons, R_GlobalEnv, GEcurrentDevice, ...) directly, not just
        // through grDevices.dll — gnuwin32's real Makefile.win link line
        // (`-lgrDevices` only) relies on gcc's transitive DLL relinking,
        // which lld-link does not replicate; needs libR explicitly too
        // (found via a real ~80-symbol undefined-symbol link error).
        m.linkLibrary(libR);
        m.linkLibrary(grdevices_lib.?);
        applyLinkFlags(ctx, m, ctx.subst.get("CAIRO_LIBS").?);
        break :blk addSharedLib(ctx, "winCairo", m);
    };
    {
        // grDevices' own bootstrap step (`tools:::makeLazyLoading
        // ("grDevices")`) transitively loadNamespace()s utils (a NAMESPACE
        // import) — found via a real bootstrap failure once grDevices'
        // own DLL was in place.
        const m = newPkgMod(ctx, "src/library/utils/src", &rspec.utils_c, .{
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
    try win_pkg_libs.append(b.allocator, .{ .pkg = "tcltk", .lib = winTcltkLib(ctx, libR) });

    // ------------------------------------------------------------------
    // library/ + share/ + doc/ + bootstrap: without this, Rscript.exe can
    // link/load fine but can't evaluate any real code (no base package to
    // find) — `Rscript.exe --version` works either way (doesn't touch
    // R_HOME's tree at all), but `-e` needs the full bootstrap below.
    // ------------------------------------------------------------------
    const libstage_dir = try installLibraryWindows(ctx, io, win_pkg_libs.items, win_cairo);
    const boot_step = try bootstrap(ctx, io, libstage_dir.getDirectory());

    const top = b.step("r", "Build R.dll+Rblas+Rlapack+Rgraphapp+Riconv+Rscript.exe (Windows, CLI-only — F6.0)");
    top.dependOn(boot_step);
    b.default_step = top;
    addCheckStepWindows(ctx, top);
}

/// library/tcltk/libs/x64/tcltk.dll, from src/library/tcltk/src/
/// Makefile.win: its three sources, -DWin32, Tcl/Tk 8.6 from the env
/// (conda-forge's is the threaded build, tcl86t/tk86t: WIN_TCLTK_LIBS,
/// which also names user32 for tcltk_win.c's foreground-window calls).
/// Windows R is always built with tcltk (capabilities("tcltk") is TRUE)
/// and the package's R code is installed, so without the DLL
/// library(tcltk) failed with "DLL 'tcltk' not found"; make check's
/// tcltk examples found it (addCheckStepWindows).
fn winTcltkLib(ctx: *Ctx, libR: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const m = newPkgMod(ctx, "src/library/tcltk/src", &rspec.win_tcltk_c, .{ .extra = &.{"-DWin32"} });
    m.linkLibrary(libR);
    applyLinkFlags(ctx, m, ctx.subst.get("WIN_TCLTK_LIBS").?);
    return addSharedLib(ctx, "pkg_tcltk", m);
}

const WinPkgLib = struct { pkg: []const u8, lib: *std.Build.Step.Compile };

/// Package-compilation contract on Windows: bundles a real toolchain into
/// Library/lib/R/bin/toolchain/ (gcc.exe/g++.exe — rzig, installed by
/// installRzig; the MinGW binutils, plain copies from the conda env) and
/// installs etc/x64/Makeconf (subst of the vendored gnuwin32
/// Makeconf.win) with BINPREF pointed at that directory — so
/// `$(BINPREF)$(CCBASE)` etc. resolve to real, absolute, working paths
/// rather than a bare name that Windows would resolve to whatever
/// unrelated compiler happens to be on PATH. flang is NOT bundled here
/// (see the FC replacement below) — it locates its own pieces relative to
/// its own install location, so a standalone copy breaks it; FC is rzig's
/// zig-fc.exe, which runs the flang on PATH.
fn installWindowsCompilerContract(ctx: *Ctx, io: std.Io) !void {
    const b = ctx.b;
    const toolchain_dir: std.Build.InstallDir = ctx.rhomeInstallDir("bin/toolchain");

    // Real conda-forge MinGW binutils — plain copies, no wrapper needed
    // (already real .exe files that find nothing relative to where they
    // are installed, unlike flang, below). They ship only under the
    // x86_64-w64-mingw32- prefix.
    for ([_][]const u8{ "ar", "ranlib", "nm", "dlltool", "strip", "as", "ld", "windres" }) |t| {
        const src: std.Build.LazyPath = .{ .cwd_relative = ctx.absSub("{s}/Library/bin/x86_64-w64-mingw32-{s}.exe", .{ ctx.conda, t }) };
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(src, toolchain_dir, ctx.absSub("{s}.exe", .{t})).step);
    }

    // etc/x64/Makeconf: subst of the vendored gnuwin32 Makeconf.win.
    // Real values for the handful of @VAR@ placeholders it carries
    // (gnuwin32's own fixed/Makefile substitutes these; captured from a
    // real generated Makeconf on kappa's milestone-3 gnuwin32 objdir,
    // same vendoring discipline as config.h/Rconfig.h) — none are
    // @ZR_CONDA@/config.status-style (that's unix's subst.txt mechanism,
    // sourced from a real captured config.status this file has no
    // equivalent of), but as of the cross-platform-standardization
    // milestone this file's own @VAR@ tokens ARE processed through the
    // same generic `substitute()`/`ctx.subst` mechanism unix uses for
    // its own templates, not a bespoke replaceOwned loop — the same
    // unification Phase 4 already did for this file's link-flag
    // siblings (CAIRO_LIBS etc., loaded via loadSubstFile above).
    // The four values that would name a place (feat-no-host-paths F1.5), as
    // unix's Makeconf writes them (makeconfValue): R_HOME-relative, bare or empty,
    // never the build machine's paths, so the Windows zip and the conda
    // package carry the same file. They go into etc/x64/Makeconf only
    // (`mk`), not ctx.subst.
    var mk = std.StringHashMap([]const u8).init(b.allocator);
    try mk.put("BINPREF", "$(R_HOME)/bin/toolchain/");
    // IMPDIR = bin/x64, not the vendored template's bare "bin" — real
    // gnuwin32 value (`bin$(R_ARCH)`, confirmed against a real generated
    // Makeconf on kappa) — LIBR/BLAS_LIBS/LAPACK_LIBS all key off it to
    // find R.dll/Rblas.dll/Rlapack.dll, which live in the arch subdir,
    // not directly under bin/ (found via a real "unable to find dynamic
    // system library 'R'" link error).
    try ctx.subst.put("IMPDIR", "bin/x64");
    // R_ARCH = /x64, as gnuwin32's fixed/Makefile writes it (CRAN R's
    // etc/x64/Makeconf). Packages and R's own make files name the arch
    // directories with it: winshlib.mk's symbols.rds step runs
    // $(R_HOME)/bin$(R_ARCH)/Rterm.exe (igraph, duckdb: "bin/Rterm.exe: No
    // such file or directory" while it was empty), and arrow links its
    // prebuilt -L.../lib$(R_ARCH)$(CRT), lib/x64-ucrt (stress round 1,
    // kappa, 2026-10-08). IMPDIR above is its literal form, bin/x64.
    try mk.put("R_ARCH", "/x64");
    // COMPILED_BY, gnuwin32's `$(CCBASE)-<version>` (MkRules.rules; on CRAN
    // gcc-<version>): clang-<version> of the zig that builds R (compiledBy).
    try mk.put("COMPILED_BY", try compiledBy(b));
    // LDFLAGS: empty, as in the vendored template and a real generated
    // Makeconf (gnuwin32 provides external-library search paths via
    // MkRules.local's LOCAL_SOFT, sourced only at R's OWN build time).
    // CRAN packages routinely link bare "-lz"/"-lpng" etc. expecting
    // *some* global search path to exist (data.table: "unable to find
    // dynamic system library 'z'"): rzig (gcc.exe) adds the environment's
    // -L<prefix>/Library/lib and -idirafter <prefix>/Library/include, as
    // on unix (zigbuild/tools/rzig/environment.zig, F3b). Token-anchored
    // (@LDFLAGS@), unlike an earlier bare "LDFLAGS =" substring replace
    // that also matched DYLIB_LDFLAGS, SHLIB_LDFLAGS and ten more.
    try mk.put("LDFLAGS", "");
    // FC: rzig's zig-fc.exe (installRzig; MSYS make and sh find it by the
    // name without .exe), as on unix (F3c): it runs the flang on PATH (an
    // activated env has Library/bin there) and links a USE_FC_TO_LINK
    // package through zig with the static runtime and libc++. flang
    // itself is not copied into bin/toolchain: its driver finds its own
    // pieces (flang.cfg and its intrinsic modules) relative to where it is
    // installed. Fortran that calls into R under USE_FC_TO_LINK needs
    // $(LIBR) in PKG_LIBS (install.R drops it from that link), as with
    // upstream's gfortran.
    try mk.put("FC", "$(R_HOME)/bin/toolchain/zig-fc");
    // FLIBS: what R CMD SHLIB appends to every package link that has
    // Fortran sources (tools:::.SHLIB → shlib_libadd "$(FLIBS)"); the
    // link itself goes through SHLIB_LD = gcc.exe (rzig), not the Fortran
    // driver, so the runtime must be spelled out here: flang's runtime,
    // which rzig resolves to the archive of the flang on PATH (as on
    // unix), plus zig's libc++ — libflang_rt.runtime is C++ and PE refuses
    // unresolved symbols (flang-pixi handoff: only Linux's archive is
    // libc++-free).
    try mk.put("FLIBS", "-lflang_rt.runtime -lc++");
    // (SAFE_FFLAGS, what CRAN Fortran packages such as quadprog put in
    // PKG_FFLAGS, is a plain -O2 in the vendored Makeconf.win: gnuwin32
    // adds gfortran's x87-avoidance switches `-msse2 -mfpmath=sse` unless
    // USE_LLVM, and flang, which defaults to SSE2 on x86_64, rejects them
    // ("flang: error: unknown argument: '-msse2'"). Our build is not
    // USE_LLVM, which also switches CC to clang.)
    try ctx.subst.put("CSTD", "-std=gnu2x");
    try ctx.subst.put("EOPTS", "");
    try ctx.subst.put("SANOPTS", "");
    // SHLIB_OPENMP_*FLAGS, from the same value that decides whether the
    // tree carries omp.h and libomp for them (installOpenMP).
    try ctx.subst.put("OPENMP", if (ctx.openmp) "-fopenmp" else "");
    try ctx.subst.put("PTHREAD", "-pthread");
    try ctx.subst.put("SYMPAT", "'s/^.* [BCDRT] / /p'");

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, b.pathFromRoot(b.fmt("{s}/Makeconf.win", .{ctx.config_dir})), b.allocator, .limited(1024 * 1024));
    var mkc = try gnuwin32O3ToO2(b, try substituteWith(ctx, raw, &mk));
    // Tcl/Tk headers and libraries where the standalone tree has them
    // (installEnvRuntime installs R_HOME/Tcl: include, bin, lib); inside a
    // conda env this is unused. TCL_VERSION is the vendored file's 86t,
    // the names of conda-forge's threaded Tcl/Tk (tcl86t.dll, a conda
    // env's tcl86t.lib), which TCLTK_LIBS links (verify-tree.sh checks
    // them against R_HOME/Tcl/bin).
    mkc = try replaceLine(b, mkc, "TCL_HOME", "TCL_HOME = $(R_HOME)/Tcl");
    try assertNoBuildPath(ctx, "etc/x64/Makeconf", raw, mkc);
    const mkc_wf = b.addWriteFiles();
    const mkc_out = mkc_wf.add("Makeconf", mkc);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(mkc_out, ctx.rhomeInstallDir("etc/x64"), "Makeconf").step);

    // Library/bin/R.bat and Rscript.bat: a conda env's activation puts
    // Library/bin on PATH, never Library/lib/R/bin/x64, so without these
    // `R`/`Rscript` are not found in an installed env.
    const bat_wf = b.addWriteFiles();
    for ([_][]const u8{ "R", "Rscript" }) |exe| {
        _ = bat_wf.add(b.fmt("{s}.bat", .{exe}), b.fmt("@echo off\r\n\"%~dp0..\\lib\\R\\bin\\x64\\{s}.exe\" %*\r\n", .{exe}));
    }
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = bat_wf.getDirectory(),
        .install_dir = .{ .custom = "Library/bin" },
        .install_subdir = "",
    }).step);
    // (etc/Renviron.site, with the compile preflight's hint: installEnvRuntime)
}

/// Makeconf's COMPILED_BY on Windows: clang-<version> of the zig that
/// builds R, in gnuwin32's `$(CCBASE)-<version>` form. zig cc is clang, and
/// this is the version R reports at run time in R_COMPILED_BY ("clang
/// 21.1.8": system.c, from the same compiler's __clang_*__ macros).
/// Packages' winlibs.R read R_COMPILED_BY to download the r-windows
/// bundles built with clang against libc++, zig's C++ runtime (curl,
/// magick and V8 load and pass: stress round 1). Their Makevars name
/// `lib$(subst gcc,,$(COMPILED_BY))$(R_ARCH)` first, a directory no bundle
/// has, then the bundle's lib, as with CRAN's gcc-<version>. Not zig-0.16.0:
/// no package looks for zig, and the code is clang's. `zig cc --version`
/// starts "clang version 21.1.8 (...)" with conda-forge's zig and
/// upstream's.
fn compiledBy(b: *std.Build) ![]const u8 {
    const out = b.run(&.{ b.graph.zig_exe, "cc", "--version" });
    const tag = "clang version ";
    const i = std.mem.indexOf(u8, out, tag) orelse {
        std.debug.print("error: no '{s}' in `zig cc --version`:\n{s}\n", .{ tag, out });
        return error.NoClangVersion;
    };
    const v = out[i + tag.len ..];
    return b.fmt("clang-{s}", .{v[0 .. std.mem.indexOfAny(u8, v, " \r\n") orelse v.len]});
}

/// `text` with the line starting `key` (then spaces or `=`) replaced by
/// `line`; unchanged when there is none.
fn replaceLine(b: *std.Build, text: []const u8, key: []const u8, line: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (it.next()) |l| {
        if (!first) try out.append(b.allocator, '\n');
        first = false;
        const rest = if (std.mem.startsWith(u8, l, key)) std.mem.trimStart(u8, l[key.len..], " ") else "";
        if (std.mem.startsWith(u8, l, key) and std.mem.startsWith(u8, rest, "=")) {
            try out.appendSlice(b.allocator, line);
        } else {
            try out.appendSlice(b.allocator, l);
        }
    }
    return out.items;
}

/// gnuwin32's src/gnuwin32/fixed/Makefile installs etc/Makeconf through
/// a sed that also runs `s/-O3/-O2/` — first match per line, no /g — so a
/// real Windows R compiles packages at -O2, not the -O3 the Makeconf.win
/// template spells out (its own header says so: "Things which are
/// substituted by fixed/Makefile (and also -O3 -> -O2)"). Replaying only
/// the @VAR@ substitutions left CFLAGS/C*FLAGS/FFLAGS/FCFLAGS at -O3 for
/// every package built through this R; FFLAGS' -O3 even came last on the
/// command line and overrode a package's `PKG_FFLAGS = $(SAFE_FFLAGS)`
/// -O2 (quadprog). Same first-occurrence-per-line semantics as the sed.
fn gnuwin32O3ToO2(b: *std.Build, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(b.allocator, '\n');
        first = false;
        if (std.mem.indexOf(u8, line, "-O3")) |i| {
            try out.appendSlice(b.allocator, line[0..i]);
            try out.appendSlice(b.allocator, "-O2");
            try out.appendSlice(b.allocator, line[i + 3 ..]);
        } else {
            try out.appendSlice(b.allocator, line);
        }
    }
    return out.items;
}

/// Windows equivalent of installStaticTree: stages library/ (via the shared
/// stageLibraryPayload), share/, doc/, and include/ under ctx.rhome
/// (Library/lib/R/...). No bin/R script, no etc/{Renviron,ldpaths,
/// javaconf}: the front ends are .exe files (buildWindows; bin/R.exe and
/// bin/Rscript.exe are winRfe's); Makeconf is installed separately by
/// installWindowsCompilerContract, above.
/// share/ and doc/ wholesale from the source tree into R_HOME — identical
/// mechanism on every platform (same source dirs, same exclusions),
/// parameterized only by `rhomeInstallDir`'s install-dir split. Was two
/// independent, byte-for-byte-identical-except-for-install_dir copies in
/// `installLibraryWindows`/`installStaticTree` before this helper existed
/// — unlike the header/R_ext staging nearby (deliberately NOT folded in
/// here: unix stages those into the same WriteFiles tree as everything
/// else in `stage`/`installStaticTree`, bulk-installed together later,
/// while Windows installs them directly via their own addInstallDirectory
/// calls with no WriteFiles intermediary at all — a genuine mechanism
/// difference, not just a parameterization, so forcing one shape onto the
/// other belongs in its own reviewed change, not this "zero behavior
/// change" pass).
fn installCommonPayload(ctx: *Ctx) void {
    const b = ctx.b;
    const inst = b.getInstallStep();
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("share"),
        .install_dir = ctx.rhomeInstallDir("share"),
        .install_subdir = "",
        .exclude_extensions = &.{"Makefile.in"},
    }).step);
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("doc"),
        .install_dir = ctx.rhomeInstallDir("doc"),
        .install_subdir = "",
        .exclude_extensions = &.{ "Makefile.in", ".texi", "R.aux", "Rscript.aux" },
    }).step);
}

fn installLibraryWindows(ctx: *Ctx, io: std.Io, pkg_libs: []const WinPkgLib, win_cairo: *std.Build.Step.Compile) !*std.Build.Step.WriteFile {
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
    // winCairo.dll: NOT a package DLL (no R-level package named "winCairo"),
    // it's an extra file dropped into grDevices' own libs dir — ground
    // truth from gnuwin32's real installed tree
    // (library/grDevices/libs/x64/winCairo.dll).
    _ = libstage.addCopyFile(win_cairo.getEmittedBin(), "grDevices/libs/x64/winCairo.dll");

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
        .install_dir = ctx.rhomeInstallDir("include"),
        .install_subdir = "",
    }).step);
    inst.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.path("src/include/R_ext"),
        .install_dir = ctx.rhomeInstallDir("include/R_ext"),
        .install_subdir = "",
        .include_extensions = &.{".h"},
    }).step);

    // etc/repositories: R reads this at startup for install.packages()'s
    // default CRAN-mirror-style repo list — cheap to install even though
    // the rest of etc/ (Renviron/ldpaths/Makeconf/javaconf) stays deferred
    // (found via a real bootstrap warning, not yet fatal but trivial to fix).
    inst.dependOn(&b.addInstallFileWithDir(ctx.path("etc/repositories"), ctx.rhomeInstallDir("etc"), "repositories").step);
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
    inst.dependOn(&b.addInstallFileWithDir(ctx.path("src/gnuwin32/fixed/etc/Rconsole"), ctx.rhomeInstallDir("etc"), "Rconsole").step);

    // share/ and doc/ wholesale from the source tree — same content as
    // unix, installed under the Windows R_HOME layout.
    installCommonPayload(ctx);

    // utils iconvlist (basepkg iconvlist target: `iconv -l`) — same as
    // unix; conda-forge's Windows env also ships iconv.exe.
    const iconv_run = b.addSystemCommand(&.{ "iconv", "-l" });
    const iconv_out = iconv_run.captureStdOut(.{});
    _ = libstage.addCopyFile(iconv_out, "utils/iconvlist");

    return libstage;
}

/// PE/COFF (unlike ELF/Mach-O) refuses to link a DLL with unresolved
/// symbols, so R.dll's mutual dependency with Rblas.dll/Rgraphapp.dll
/// needs breaking the same way gnuwin32's own make build does: derive an
/// import library from the *object file's* exported symbols before the
/// real DLL exists, exactly mirroring gnuwin32's own Rlapack.def/R.exp
/// generation (`nm | sed -n <SYMPAT> | sort -u`, then `dlltool`).
fn winMakeImportStub(ctx: *const Ctx, obj: std.Build.LazyPath, dllname: []const u8, out_stem: []const u8) std.Build.LazyPath {
    const b = ctx.b;
    // No pipes, one command per line, plus an export-count check: MSYS's
    // process spawning fails intermittently on GitHub's windows-latest
    // ("child_info::sync: wait failed ... cygheap read copy failed, Win32
    // error 299" — the classic Cygwin fork flake), and this step is where
    // it lands. As a `nm | sed | sort` pipeline (conda-package win-64,
    // 2026-09-19) a dead `sed` left `set -e` seeing only `sort`'s exit 0:
    // the .def held a bare EXPORTS line, dlltool built an *empty* import
    // lib, and the failure surfaced 80 steps later as "lld-link:
    // undefined symbol: xerbla_" (Rblas) plus every R API symbol
    // Rgraphapp uses. With `pipefail` added, the next flake instead
    // *hung* the job for the full timeout: `nm` blocked forever writing
    // into a pipe whose reader had died (the runner reported it as the
    // orphan process at cancel). Files between the stages make every
    // failure its own command's non-zero exit — loud, at the cause, and
    // fixed by a plain re-run.
    const run = b.addSystemCommand(&.{
        "sh",          "-c",
        \\set -eu
        \\x86_64-w64-mingw32-nm "$1" > "$2.nm"
        \\sed -n 's/^[0-9a-fA-F]* [BCDRT] //p' "$2.nm" > "$2.syms"
        \\echo EXPORTS > "$2"
        \\sort -u "$2.syms" >> "$2"
        \\n=$(wc -l < "$2")
        \\if [ "$n" -le 1 ]; then echo "error: no exported symbols found in $1 (nm/sed step broke?)" >&2; exit 1; fi
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
        if (ctx.buildLdPath()) |p| run.setEnvironmentVariable("R_LD_LIBRARY_PATH", p);
        run.has_side_effects = true;
        run.step.dependOn(&chmod_w.step);
        check.dependOn(&run.step);
    }
}

/// Windows: the same three targets through R's own tests/Makefile.win,
/// as src/gnuwin32/Makefile's `check` runs it (`make -C ../../tests -f
/// Makefile.win check`, i.e. these three plus Internet, left out as on
/// unix: it needs the network, and upstream ignores its failures).
///
/// Makefile.win expects to sit in R_HOME/tests, because R builds in
/// place on Windows: it sets R_HOME = .., includes ../src/gnuwin32/
/// MkRules and ../share/make/vars.mk, and runs $(R_HOME)/$(BINDIR)/Rterm
/// (BINDIR = bin/x64); tests/Examples/Makefile.win includes $(R_HOME)/
/// src/gnuwin32/MkRules. So the check runs in a stand-in for that tree,
/// as addCheckStep writes a top_builddir with a bin/R wrapper: R's
/// tests directory, src/gnuwin32/MkRules (MkRules.rules alone, which is
/// what src/gnuwin32/Makefile makes it from when there is no
/// MkRules.local), share/make/vars.mk, and bin/x64/Rterm, R and Rcmd,
/// scripts that run the installed tree's .exe of that name (MSYS sh
/// finds the script first and honours its #!). The Makefiles then run
/// unmodified. Setting R_HOME on make's command line instead does not
/// work: it reaches the Examples sub-make through MAKEFLAGS, whose
/// include then looks for src/gnuwin32/MkRules in the installed tree.
///
/// The stand-in is made fresh on every run, in the output directory of
/// a first step (removed, then copied again): the files written here
/// (a WriteFiles in the zig cache, which make never writes to) plus R's
/// tests directory, copied from the R source. make writes into that
/// copy, so each run starts from R's own files and nothing an earlier
/// run wrote; the copy stays after the run, for reading a failed test's
/// .Rout.fail. make must not run in the WriteFiles directory itself:
/// zig does not look at it again on a cache hit, so its outputs would
/// stay there for every later run, and would even count as up to date
/// (the .R files keep the tarball's dates), skipping those tests.
/// (b.tmpPath would also give a fresh directory, but zig 0.16's build
/// runner never deletes those, so each run would leave a copy behind.)
/// If an earlier run's Rterm.exe is still running and holds a file in
/// the copy, the first step fails until that process ends.
///
/// Two make variables say what unix's tests/Makefile gets from configure
/// when the recommended packages are not installed (they are not built
/// here) and Makefile.win always assumes they are: test-src-sloppy-b
/// empty (eval-etc-2.R, which needs Matrix) and test-src-reg3 =
/// reg-plot-latin1.R (reg-tests-3.R and reg-examples3.R need MASS,
/// survival and Matrix).
///
/// test-Examples compares each base package's example output with R's
/// <pkg>-Ex.Rout.save, as unix's tests/Examples/Makefile does with
/// srcdir=$(srcdir). Upstream finds them in R_HOME/tests/Examples
/// (testInstalledPackages' default srcdir), the directory make runs the
/// examples in; the installed tree has no tests directory, as on unix.
/// tests/Examples/Makefile.win has no srcdir to set; TEST_DONTTEST is
/// the one variable it puts into its R call, so it carries the argument:
/// `FALSE,srcdir=getwd()`, that same directory, here the fresh copy of
/// R's tests/Examples (unix's Makefile, too, passes srcdir only while
/// TEST_DONTTEST is FALSE, its default). No path is spelled out: the
/// MSYS runtime takes quotes, single ones too, out of make's Windows
/// command line, and R needs a path quoted. A difference prints a NOTE
/// with the diff, as on unix; only R_STRICT_PACKAGE_CHECK=TRUE makes it
/// fail.
///
/// The environment is pixi's, as for the build, and the tree is the one
/// that ships (F1.7): R.dll's DLLs are in bin/x64, which Windows searches
/// before PATH (zig-build.sh runs vendor-libs.sh before and after zig
/// build), and Tcl/Tk in R_HOME/Tcl (installEnvRuntime). MY_TCLTK and
/// TCL_LIBRARY are removed, as a user's would be absent: with MY_TCLTK
/// set, tcltk's .onLoad (src/library/tcltk/R/windows/zzz.R) never looks
/// at R_HOME/Tcl, and TCL_LIBRARY would point Tcl at other scripts. So
/// the tcltk examples load the tree's own Tcl/Tk.
///
/// No TZ, as in upstream's tests/Makefile.win: Sys.timezone() then asks
/// Windows (registryTZ.c, built for Windows only), which test-TimeZone's
/// timezone.R checks; with TZ set it only returns TZ. (Unix sets
/// TZ=UTC.)
///
/// The targets run one after another, as test-all-basics runs them,
/// since they share the tests directory; stdin is empty, so nothing in
/// them can wait for input.
fn addCheckStepWindows(ctx: *Ctx, r_top: *std.Build.Step) void {
    const b = ctx.b;

    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(ctx.path("src/gnuwin32/MkRules.rules"), "src/gnuwin32/MkRules");
    _ = wf.addCopyFile(ctx.path("share/make/vars.mk"), "share/make/vars.mk");
    for ([_][]const u8{ "Rterm", "R", "Rcmd" }) |exe| {
        _ = wf.add(b.fmt("bin/x64/{s}", .{exe}), b.fmt("#!/bin/sh\nexec \"{s}/bin/x64/{s}.exe\" \"$@\"\n", .{ ctx.rhome, exe }));
    }

    const fresh = b.addSystemCommand(&.{ "sh", "-c", "rm -rf \"$3\" && cp -R \"$1\" \"$3\" && cp -R \"$2\" \"$3/tests\"", "check-tree" });
    fresh.setName("check: fresh tests tree");
    fresh.addDirectoryArg(wf.getDirectory());
    fresh.addDirectoryArg(ctx.path("tests"));
    const tests = fresh.addOutputDirectoryArg("check").path(b, "tests");
    fresh.has_side_effects = true;
    fresh.step.dependOn(r_top);

    const check = b.step("check", "Run R's regression suite (Examples/Specific/Reg) against the zig-built R");
    var last = &fresh.step;
    for ([_][]const u8{ "test-Examples", "test-Specific", "test-Reg" }) |target| {
        const run = b.addSystemCommand(&.{ "make", "-f", "Makefile.win", "test-src-sloppy-b=", "test-src-reg3=reg-plot-latin1.R" });
        if (std.mem.eql(u8, target, "test-Examples")) {
            run.addArg("TEST_DONTTEST=FALSE,srcdir=getwd()");
        }
        run.addArg(target);
        run.setName(b.fmt("make check: {s}", .{target}));
        run.setCwd(tests);
        run.setStdIn(.{ .bytes = "" });
        run.removeEnvironmentVariable("MY_TCLTK");
        run.removeEnvironmentVariable("TCL_LIBRARY");
        run.has_side_effects = true;
        run.step.dependOn(last);
        last = &run.step;
    }
    check.dependOn(last);
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

/// The zig lib dir R's links get (Ctx.zig_lib_dir; std.Build passes it as
/// --zig-lib-dir, Step/Compile.zig). libc++ is static everywhere (decided
/// 2026-09-30), and R itself links it on macOS (flang's runtime is C++,
/// linkFortranRt). Upstream zig always links its own; conda-forge's zig
/// links a shared one whenever one sits in <lib dir>/../../lib (every
/// macOS env, any env with `libcxx`), unless its lib dir is a mirror with
/// nothing beside it: zigbuild/tools/rzig/libcxx_mirror.zig, which rzig
/// uses for packages, made here in zig build's local cache (which env.sh
/// keeps one of per zig). Where the probe would fire the mirror is always
/// used, so no shared-libc++ link ever enters that cache. Null otherwise,
/// so upstream zig builds with its own lib dir. On Windows symlink
/// mirrors cannot be made (no win-64 env has libc++.dll.a): stop instead.
fn staticLibcxxLibDir(b: *std.Build, io: std.Io, os: Os) !?std.Build.LazyPath {
    const lib_dir = b.graph.zig_lib_directory.path orelse ".";
    if (os == .windows) {
        if (try libcxx_mirror.sharedLibcxx(io, b.allocator, lib_dir, .windows)) |p| {
            std.debug.print("error: {s} would make zig link a shared libc++; remove the libcxx package from this env\n", .{p});
            return error.SharedLibcxx;
        }
        return null;
    }
    const cache = try b.cache_root.handle.realPathFileAlloc(io, ".", b.allocator);
    switch (try libcxx_mirror.prepare(io, b.allocator, lib_dir, b.fmt("{s}/r-zig", .{cache}))) {
        .none => return null,
        .failed => |m| {
            std.debug.print("error: could not make {s}, the zig lib dir mirror for a static libc++ (remove it if an interrupted build left it)\n", .{m});
            return error.LibcxxMirror;
        },
        .ready => |mirror| {
            std.debug.print("r-zig: static libc++ (zig lib dir {s} mirrored to {s})\n", .{ lib_dir, mirror });
            return .{ .cwd_relative = mirror };
        },
    }
}

/// Locate the directory holding libflang_rt.runtime.a: the clang resource
/// dir, `$CONDA/lib/clang/<major>/lib/<subdir>/` (`$CONDA/Library/lib/
/// clang/...` on Windows). `<subdir>` is an LLVM triple on linux
/// (`x86_64-unknown-linux-gnu`) but plain `darwin` on macOS (verified by
/// listing flang-pixi's osx-arm64 flang-rt-zig package), so this globs
/// both levels — the same `lib/clang/*/lib/*/libflang_rt.runtime.a`
/// search zigbuild/tools/configure-only.sh uses for FLIBS — instead of
/// deriving a triple per platform. flang-pixi's docs/11 contract #2: the
/// runtime stays in the resource dir on every platform (its `$CONDA/lib`
/// copy is a convenience only), so this is the one place to look.
fn findFlangRt(b: *std.Build, io: std.Io, conda: []const u8, os: Os) ![]const u8 {
    const clang_root = switch (os) {
        .windows => b.fmt("{s}/Library/lib/clang", .{conda}),
        else => b.fmt("{s}/lib/clang", .{conda}),
    };
    var dir = std.Io.Dir.cwd().openDir(io, clang_root, .{ .iterate = true }) catch {
        return error.FlangRtNotFound;
    };
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |ver| {
        if (ver.kind != .directory) continue;
        const lib_root = b.fmt("{s}/{s}/lib", .{ clang_root, ver.name });
        var lib_dir = std.Io.Dir.cwd().openDir(io, lib_root, .{ .iterate = true }) catch continue;
        defer lib_dir.close(io);
        var lit = lib_dir.iterate();
        while (try lit.next(io)) |sub| {
            if (sub.kind != .directory) continue;
            const cand = b.fmt("{s}/{s}", .{ lib_root, sub.name });
            std.Io.Dir.cwd().access(io, b.fmt("{s}/libflang_rt.runtime.a", .{cand}), .{}) catch continue;
            return cand;
        }
    }
    std.debug.print("error: libflang_rt.runtime.a not found under {s}/*/lib/* — is flang-rt-zig installed?\n", .{clang_root});
    return error.FlangRtNotFound;
}

fn newCMod(ctx: *const Ctx) *std.Build.Module {
    const m = ctx.b.createModule(.{
        .target = ctx.target,
        // Windows-only: .ReleaseSafe instead of .ReleaseFast (F7.1,
        // 2026-07-29 — real fix, not a diagnostic toggle). A genuine,
        // 100%-reproducible access violation (0xC0000005 in R.dll,
        // consistent fault offset across 5 separate reproductions) hits
        // every recursive front-end invocation on Windows (R CMD INSTALL
        // -> Rterm.exe -> a package's own configure script -> R.exe ->
        // another Rterm.exe — a real, common pattern: e.g. pak's
        // configure re-invokes R directly). Root-caused via Windows'
        // own crash log (Get-WinEvent) plus raw disassembly
        // (x86_64-w64-mingw32-objdump — R.dll ships with no symbol table
        // in ReleaseFast) to a null-pointer dereference immediately after
        // a call into a small local helper, in a pattern consistent with
        // an inlined TLS-access fast path (R.dll does import a real
        // native Windows TLS directory + TlsGetValue). Bisected by
        // optimize level rather than guessing further: .Debug and
        // .ReleaseSafe BOTH make the crash vanish entirely (0/1
        // reproductions each, tested with a real `install.packages
        // ("pak")` run) — pak's build gets all the way past the
        // recursive invocation and fails later on a real, unrelated
        // mbedtls/Windows-platform-detection compile error in its own
        // bundled zip library, identically under both. .Debug is too
        // slow/heavy to ship; .ReleaseSafe keeps optimizations and is a
        // real, shippable fix without needing to fully root-cause Zig's
        // exact ReleaseFast TLS-lowering behavior on the windows-gnu
        // target. Linux/macOS keep .ReleaseFast — this crash was never
        // observed there, and there's no reason to pay ReleaseSafe's
        // (bounds-checking, etc.) runtime cost where nothing is broken.
        .optimize = if (ctx.os == .windows) .ReleaseSafe else .ReleaseFast,
        .link_libc = true,
        .pic = true,
        .sanitize_c = .off,
        // Debug info, where the binary carries it: linux (ELF embeds the
        // DWARF) keeps it for slim and full, remapped by filePathFlags so
        // it names no directory of the build machine; zig's own runtime
        // libraries leave theirs out (linkRoot). minimal ships inside a
        // wheel, where size is the point: without this, ReleaseFast still
        // carries full DWARF (libR.so 12.6 MiB). macOS strips: its DWARF
        // stays in the object files in zig's cache, and the binary only
        // names them (N_OSO entries, absolute paths into the build
        // machine's cache, which zig's Mach-O linker writes as they are).
        // Windows as before (unset): the debug info goes to a .pdb beside
        // each DLL in zig's cache, which nothing installs, and the DLL
        // names only that file's name.
        .strip = switch (ctx.os) {
            .linux => ctx.variant == .minimal,
            .macos => true,
            .windows => null,
        },
    });
    // LDFLAGS from Makeconf: -L$CONDA/lib -Wl,-rpath,$CONDA/lib on every
    // link (addCondaLibPath skips the rpath half on Windows — see its
    // own doc comment).
    ctx.addCondaLibPath(m);
    return m;
}

/// A "CMD dispatcher" front-end (R.exe or Rcmd.exe): both share the exact
/// same real gnuwin32 recipe (front-ends/Makefile: `<name>.o ../rhome.o
/// ../shext.o rcico.o rcmdfn.o Renviron.o`, minus the icon/manifest
/// resource) — only the top-level `main()` differs (`front_c`: "R.c" reads
/// -h/--help/looks-for-a-"CMD"-token before falling into rcmdfn.c's
/// dispatch; "rcmd.c" is a one-liner that always dispatches straight in).
/// rhome.c/shext.c are NOT recompiled here — see the caller's own comment
/// on why (duplicate-symbol against libR's own exports).
fn winCmdFrontend(ctx: *Ctx, libR: *std.Build.Step.Compile, rgraphapp: *std.Build.Step.Compile, front_c: []const u8, name: []const u8) *std.Build.Step.Compile {
    const b = ctx.b;
    const mod = newCMod(ctx);
    mod.addIncludePath(ctx.geninc);
    mod.addIncludePath(ctx.path("src/include"));
    mod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    addCGroup(ctx, mod, "src/gnuwin32/front-ends", &.{front_c}, .{
        .extra = &.{"-I%S/src/gnuwin32"},
    });
    addCGroup(ctx, mod, "src/gnuwin32/front-ends", &.{"rcmdfn.c"}, .{
        // BINDIR="bin/x64"/R_ARCH="x64": see the caller's own comment
        // (found via a real "system cannot find the path specified"
        // failure tracing rcmdfn.c's own Rterm.exe-launch path).
        .extra = &.{ "-I%S/src/gnuwin32", "-DBINDIR=\"bin/x64\"", "-DR_ARCH=\"x64\"" },
    });
    addCGroup(ctx, mod, "src/main", &.{"Renviron.c"}, .{
        .extra = &.{"-DRENVIRON_WIN32_STANDALONE"},
    });
    mod.linkLibrary(libR);
    mod.linkLibrary(rgraphapp);
    mod.linkSystemLibrary("shlwapi", .{ .use_pkg_config = .no });
    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// Rfe.exe, installed as R_HOME/bin/R.exe and R_HOME/bin/Rscript.exe
/// (gnuwin32's front-ends/Makefile: `Rfe.exe: Rfe.o ../rhome.o ../shext.o
/// rcico.o rcmdfn.o Renviron.o`, `Rfe-LIBS = -lole32 -luuid`; no icon
/// resource, as above). It runs bin\x64\Rscript.exe when its own name ends
/// in Rscript.exe or Rscript, else bin\x64\R.exe, with its arguments
/// (R_ARCH or --arch picks another arch directory). Unlike R.exe and
/// Rcmd.exe it does not link R.dll, which is in bin/x64, where the loader
/// does not look for a program in bin. So rhome.c and shext.c are compiled
/// in, as gnuwin32 does, and the Windows libraries are named here:
/// advapi32 (rhome.c's registry lookup), shell32 (shext.c's Documents
/// folder), user32 (MessageBox), ole32 and uuid.
fn winRfe(ctx: *Ctx) *std.Build.Step.Compile {
    const b = ctx.b;
    const mod = newCMod(ctx);
    mod.addIncludePath(ctx.geninc);
    mod.addIncludePath(ctx.path("src/include"));
    mod.addIncludePath(ctx.path("src/gnuwin32/fixed/h"));
    // R_ARCH="x64": Rfe.c's default arch directory, bin\x64. rcmdfn.c as
    // in winCmdFrontend; Rfe calls only its argument quoting.
    addCGroup(ctx, mod, "src/gnuwin32/front-ends", &.{ "Rfe.c", "rcmdfn.c" }, .{
        .extra = &.{ "-I%S/src/gnuwin32", "-DBINDIR=\"bin/x64\"", "-DR_ARCH=\"x64\"" },
    });
    addCGroup(ctx, mod, "src/gnuwin32", &.{ "rhome.c", "shext.c" }, .{});
    addCGroup(ctx, mod, "src/main", &.{"Renviron.c"}, .{
        .extra = &.{"-DRENVIRON_WIN32_STANDALONE"},
    });
    for ([_][]const u8{ "advapi32", "shell32", "user32", "ole32", "uuid" }) |l| {
        mod.linkSystemLibrary(l, .{ .use_pkg_config = .no });
    }
    return b.addExecutable(.{ .name = "Rfe", .root_module = mod });
}

/// etc/Rcmd_environ on Windows: gnuwin32's file, then r-zig's lines. R
/// CMD (rcmdfn.c) reads it before every subcommand, so what it sets is in
/// the environment of package builds (R CMD INSTALL, install.packages())
/// and nowhere else. Each value is a default: one set in the environment
/// wins (`${VAR-default}`; Renviron expands a nested default only when it
/// is a whole ${...} term, hence the R_ZIG_ helpers, as in etc/Renviron).
///   - CMAKE_GENERATOR: CMake builds of a package's bundled library
///     (RcppParallel's TBB, Rhdf5lib's HDF5 through biocmake) pass no -G,
///     and conda-forge's cmake then picks NMake Makefiles ("make: invalid
///     option -- ?"). MSYS Makefiles are makefiles for make and sh, which
///     R runs packages' own makefiles with (in a conda env m2-make, first
///     on PATH, and m2-bash's sh).
///   - RC, RCFLAGS: CMake compiles a .rc file (TBB's) with RC, else a
///     windres on PATH, where there is none; the tree's is in
///     bin/toolchain. windres preprocesses with a gcc it looks for by
///     name; RCFLAGS names the toolchain's, with the arguments windres
///     gives its default one (-E -xc -DRC_INVOKED), which --preprocessor
///     drops.
/// Tested in stress round 1 on kappa with these values in the
/// environment (feat-stress-suite stress/results/2026-10-08.md, T3).
fn rcmdEnviron(ctx: *const Ctx, io: std.Io) ![]u8 {
    const b = ctx.b;
    const src = try readSrcFile(ctx, io, "src/gnuwin32/fixed/etc/Rcmd_environ");
    // R's file has CRLF line ends; ours follow it.
    const eol = if (std.mem.indexOf(u8, src, "\r\n") != null) "\r\n" else "\n";
    var out = std.ArrayList(u8).empty;
    try out.appendSlice(b.allocator, src);
    for ([_][]const u8{
        "## r-zig: CMake for packages that build a bundled library with it.",
        "CMAKE_GENERATOR=${CMAKE_GENERATOR-'MSYS Makefiles'}",
        "R_ZIG_RC=${R_HOME}/bin/toolchain/windres.exe",
        "RC=${RC-${R_ZIG_RC}}",
        "R_ZIG_RCFLAGS=--preprocessor=${R_HOME}/bin/toolchain/gcc.exe --preprocessor-arg=-E --preprocessor-arg=-xc --preprocessor-arg=-DRC_INVOKED",
        "RCFLAGS=${RCFLAGS-${R_ZIG_RCFLAGS}}",
    }) |line| {
        try out.appendSlice(b.allocator, line);
        try out.appendSlice(b.allocator, eol);
    }
    return out.items;
}

/// rzig into R_HOME/bin/toolchain under the names Makeconf uses
/// (feat-no-host-paths F3): one binary, a copy per name, dispatching on
/// the name it was started as. The r-zig-toolchain packages own this
/// directory; the compile preflight (zigbuild/patches/, install.R) looks
/// for its zig-cc on every OS.
///   unix:    zig-cc, zig-cxx (CC/CXX/OBJC/OBJCXX), zig-fc (FC), zig-ar,
///            zig-ranlib
///   Windows: gcc.exe, g++.exe (Makeconf.win's $(BINPREF)gcc.exe and
///            g++.exe: CMake takes R CMD config CC only when it names an
///            existing file, stress round 1's RcppParallel and Rhdf5lib),
///            zig-fc.exe (FC, which names it without .exe), and zig-cc,
///            zig-cxx for the preflight. A real PE executable
///            is what R's Windows system() can run: it resolves a bare
///            command name by appending ".exe" only, never through
///            PATHEXT (found on kappa: `system("gcc --version")` reached an
///            unrelated gcc.exe on PATH). AR/RANLIB there are the MinGW
///            binutils (installWindowsCompilerContract).
/// Before rzig these were bash scripts (toolchain/), and on Windows a C
/// forwarder that ran them through the env's bash; rzig needs neither
/// bash nor CONDA_PREFIX to compile.
fn installRzig(ctx: *const Ctx) *std.Build.Step {
    const b = ctx.b;
    const step = b.step("install-rzig", "Install rzig into R_HOME/bin/toolchain");
    const names: []const []const u8 = switch (ctx.os) {
        .windows => &.{ "gcc.exe", "g++.exe", "zig-fc.exe", "zig-cc", "zig-cxx" },
        else => &.{ "zig-cc", "zig-cxx", "zig-fc", "zig-ar", "zig-ranlib" },
    };
    for (names) |n| {
        step.dependOn(&b.addInstallFileWithDir(ctx.rzig, ctx.rhomeInstallDir("bin/toolchain"), n).step);
    }
    return step;
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
    ctx.addSdkPaths(mod); // last: every caller has added its -L dirs by now
    // Windows, for upstream zig (the ziglang.org release, PyPI's ziglang):
    // a DLL without a .def file exports every global symbol (LLD's MinGW
    // auto-export) except the C runtime's, which LLD knows by their GNU
    // object names (dllcrt2.o), not zig's (dllcrt2.obj). So the DLL's own
    // atexit (mingw's crtdll.c) is exported too, and an exe that calls
    // atexit and links the DLL's import library fails with "duplicate
    // symbol: atexit" against its own CRT object's (crtexe.c): Rterm.exe
    // and Rscript.exe (rterm.c's atexit(restore_cp)) with Rgraphapp's.
    // -exclude-symbols in the object's .drectve section is the directive
    // gcc and clang emit for a hidden symbol on MinGW. conda-forge's zig
    // hides atexit by accident (feedstock patches mingw-crtexe-no-atexit,
    // ucrtbase-export-atexit-alias), and there this is a no-op. Packages
    // are not affected: R links them with a .def file of their own.
    // (feat-no-host-paths PLAN.md, F4: the upstream report's draft.)
    if (ctx.os == .windows) {
        const wf = ctx.b.addWriteFiles();
        mod.addCSourceFile(.{ .file = wf.add("no_crt_exports.c",
            \\__asm__(".section .drectve,\"yni\"\n\t.ascii \" -exclude-symbols:atexit\"\n\t.text");
            \\
        ), .flags = &.{} });
    }
    const lib = ctx.b.addLibrary(.{ .linkage = .dynamic, .name = name, .root_module = linkRoot(ctx, mod) });
    // conda-forge's zig: a lib dir it finds no shared libc++ beside
    // (staticLibcxxLibDir)
    lib.zig_lib_dir = ctx.zig_lib_dir;
    if (ctx.os == .macos) lib.linker_allow_shlib_undefined = true;
    // A native target would otherwise turn every -L directory (the env's
    // lib dir, flang's) into an absolute rpath; relRPaths sets the ones
    // that ship. Redundant with macOS's deployment-target query (a
    // non-native OS gets no implicit rpaths), kept so a target change
    // can't bring them back.
    lib.each_lib_rpath = false;
    macHeaderpad(ctx, lib);
    return lib;
}

/// macOS: reserve load-command headroom (`-headerpad_max_install_names`,
/// what R's own Makeconf passes for every package .so and what every
/// conda-forge macOS build does). Without it, zig's Mach-O linker on
/// x86_64 starts the first __TEXT section at exactly mach_header +
/// sizeofcmds — zero slack — so no `install_name_tool -add_rpath`/`-id`/
/// `-change` can ever grow the load commands: Apple's tool says "larger
/// updated load commands do not fit", conda's older cctools reports the
/// same file as "malformed object (offset field of section 0 in
/// LC_SEGMENT command 0 not past the headers)". That killed the osx-64
/// conda package in rattler-build's relink pass on every zig-linked
/// binary (lapack.so, stats.so, cairo.so, bin/exec/R, ...) and would kill
/// stage.sh's own `-add_rpath` the same way. osx-arm64 never noticed: its
/// 16 KiB page alignment leaves ~15 KiB of slack by accident. Reproduced
/// and verified on omicron under Rosetta 2026-09-19 with conda's
/// install_name_tool running rattler's exact delete/add/id/change
/// sequence. No-op on the other OSes.
fn macHeaderpad(ctx: *const Ctx, c: *std.Build.Step.Compile) void {
    if (ctx.os == .macos) c.headerpad_max_install_names = true;
}

/// The flags that keep the build machine's directories out of what R's C
/// compiles record (feat-no-host-paths PLAN.md, Goal 1): __FILE__, which
/// R's own error messages print ("long vectors not supported yet:
/// src/main/character.c:1806", where upstream's make build prints
/// "character.c:1806"), the OpenMP runtime's source locations, and the
/// debug info's file names and compilation directory (linux slim and
/// full keep debug info, newCMod). clang's -ffile-prefix-map (both
/// -fmacro-prefix-map and -fdebug-prefix-map) rewrites a path that starts
/// with OLD; the compilation directory is "." (-ffile-compilation-dir,
/// not clang's getcwd, which a symlinked checkout would not match):
///   the checkout                    -> ""           (relative to ".")
///   R's source tree                 -> ""           (src/main/array.c)
///   the env (CONDA_PREFIX; the
///   conda build's host prefix)      -> conda-env/   (its include/)
///   zig's local cache               -> zig-cache/   (config.h, Rconfig.h, ...)
///   zig's lib dir, and the mirror
///   staticLibcxxLibDir gives links  -> zig-lib/     (libc and clang headers)
/// The R source tree, the cache and conda's env are inside the checkout
/// in a pixi build, while rattler-build's host and build envs (where its
/// zig lives) are not. Each directory is mapped as it is given (std.Build
/// names the caches and zig's lib dir relative to the checkout) and as it
/// resolves. The longest OLD a path starts with wins: clang tries the
/// macro map's entries longest first and the debug map's last flag
/// first, so the flags go in order of length. The separator after OLD
/// keeps /x/env from matching /x/env2; on a Windows host clang matches
/// either separator and any case. flang has no such flag; R's Fortran
/// objects record no path (no debug info, and no statement whose runtime
/// call carries the file name).
fn filePathFlags(ctx: *const Ctx, io: std.Io) ![]const []const u8 {
    const b = ctx.b;
    const a = b.allocator;
    const Map = struct {
        old: []const u8,
        new: []const u8,
        fn shorter(_: void, x: @This(), y: @This()) bool {
            return x.old.len < y.old.len;
        }
    };
    var maps = std.ArrayList(Map).empty;
    const mirror: ?[]const u8 = if (ctx.zig_lib_dir) |lp| switch (lp) {
        .cwd_relative => |p| p,
        else => null,
    } else null;
    const dirs = [_]struct { ?[]const u8, []const u8 }{
        .{ b.build_root.path, "" },
        .{ ctx.src_abs, "" },
        .{ ctx.conda, "conda-env/" },
        .{ b.cache_root.path, "zig-cache/" },
        .{ b.graph.zig_lib_directory.path, "zig-lib/" },
        .{ mirror, "zig-lib/" },
    };
    for (dirs) |d| {
        const dir = d[0] orelse continue;
        const real = std.Io.Dir.cwd().realPathFileAlloc(io, dir, a) catch dir;
        for ([_][]const u8{ dir, real }) |form| {
            const trimmed = std.mem.trimEnd(u8, form, "/\\");
            if (trimmed.len == 0 or std.mem.eql(u8, trimmed, ".")) continue;
            try maps.append(a, .{ .old = b.fmt("{s}/", .{trimmed}), .new = d[1] });
        }
    }
    std.mem.sort(Map, maps.items, {}, Map.shorter);
    var flags = std.ArrayList([]const u8).empty;
    try flags.append(a, "-ffile-compilation-dir=.");
    for (maps.items) |m| try flags.append(a, b.fmt("-ffile-prefix-map={s}={s}", .{ m.old, m.new }));
    return flags.items;
}

/// The root module of one of R's links (addSharedLib, bin/exec/R). zig
/// builds its own runtime libraries (compiler_rt, glibc's
/// libc_nonshared, libc++, the MinGW CRT) with the root module's strip
/// (Compilation.compilerRtStrip in zig 0.16), and their debug info names
/// zig's lib dir and global cache, which -ffile-prefix-map does not
/// reach (compiler_rt is Zig code). Where R's own code keeps its debug
/// info (`mod.strip == false`: linux slim and full, newCMod), the root
/// is a stripped module of its own whose only code is an empty C file
/// (std.Build names to zig only a module with sources, and zig takes the
/// first one it is given as the root), with `mod`, which holds R's code
/// and every link setting, as its import. A module with no C source of
/// its own (libRblas, libRlapack: Fortran objects, which carry no debug
/// info) is simply stripped. Elsewhere `mod` is the root.
fn linkRoot(ctx: *const Ctx, mod: *std.Build.Module) *std.Build.Module {
    if (mod.strip != false) return mod;
    const has_c = for (mod.link_objects.items) |o| switch (o) {
        .c_source_file, .c_source_files => break true,
        else => {},
    } else false;
    if (!has_c) {
        mod.strip = true;
        return mod;
    }
    const root = ctx.b.createModule(.{
        .target = mod.resolved_target,
        .optimize = mod.optimize,
        .link_libc = true,
        .pic = true,
        .strip = true,
    });
    root.addCSourceFile(.{ .file = ctx.empty_c, .flags = &.{} });
    root.addImport("r_code", mod);
    return root;
}

const CGroupOpts = struct {
    openmp: bool = false,
    extra: []const []const u8 = &.{}, // %S → srcdir, %C → conda
};

fn addCGroup(ctx: *const Ctx, mod: *std.Build.Module, dir: []const u8, files: []const []const u8, opts: CGroupOpts) void {
    const b = ctx.b;
    var flags = std.ArrayList([]const u8).empty;
    flags.appendSlice(b.allocator, ctx.path_flags) catch @panic("OOM");
    flags.appendSlice(b.allocator, &.{ "-std=gnu23", "-fno-sanitize=undefined", "-O2", "-fpic", "-DHAVE_CONFIG_H" }) catch @panic("OOM");
    if (opts.openmp and ctx.openmp) flags.append(b.allocator, "-fopenmp") catch @panic("OOM");
    for (opts.extra) |f| {
        const f1 = std.mem.replaceOwned(u8, b.allocator, f, "%S", ctx.src_abs) catch @panic("OOM");
        const f2 = std.mem.replaceOwned(u8, b.allocator, f1, "%C", ctx.conda) catch @panic("OOM");
        flags.append(b.allocator, f2) catch @panic("OOM");
    }
    flags.append(b.allocator, b.fmt("-I{s}", .{ctx.condaDir("include")})) catch @panic("OOM");
    mod.addCSourceFiles(.{ .root = ctx.path(dir), .files = files, .flags = flags.items });
}

/// Package src modules share the pattern: -DNDEBUG, geninc+src/include.
fn newPkgMod(ctx: *const Ctx, dir: []const u8, files: []const []const u8, opts: CGroupOpts) *std.Build.Module {
    const b = ctx.b;
    const m = newCMod(ctx);
    ctx.relRPaths(m, .pkglibs); // library/<pkg>/libs/<pkg>.so
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
    ctx.addCondaLibPath(mod);
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
    // No OpenMP in this configure profile (minimal): nothing was compiled
    // with -fopenmp (addCGroup), so there is nothing for libomp to satisfy.
    if (!ctx.openmp) return;
    // zig cc does -fopenmp codegen but ships no libomp — conda-forge's.
    ctx.addCondaLibPath(mod);
    mod.linkSystemLibrary("omp", .{ .use_pkg_config = .no });
}

/// Link the Fortran runtime: flang's, one runtime archive on every
/// platform (flang-pixi docs/11 contract #2), in the clang resource dir
/// findFlangRt found, linked *statically*, explicitly: flang-rt-zig >= 9
/// ships no shared runtime, but a flang-rt that does (older flang-rt-zig
/// on macOS, conda-forge's) must not hand every standalone bundle an
/// rpath dependency to vendor. The runtime is C++ (docs/11 Q5): on macOS
/// and Windows zig's own libc++ is linked into the module, so libR,
/// libRblas and libRlapack stay self-contained instead of relying on
/// `-undefined dynamic_lookup` (macOS) finding some libc++ in the process
/// at load time; flang-pixi's handoff measured that only the Linux
/// archives are libc++-free (their sole C++-runtime reference is
/// __cxa_atexit).
fn linkFortranRt(ctx: *const Ctx, mod: *std.Build.Module) void {
    mod.addLibraryPath(.{ .cwd_relative = ctx.flangrt_dir });
    mod.linkSystemLibrary("flang_rt.runtime", .{ .use_pkg_config = .no, .preferred_link_mode = .static });
    mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    if (ctx.os == .macos or ctx.os == .windows) mod.link_libcpp = true;
}

/// Tokenize a "-L/x -lfoo ..." string into module link calls.
fn applyLinkFlags(ctx: *const Ctx, mod: *std.Build.Module, flags: []const u8) void {
    var it = std.mem.tokenizeScalar(u8, flags, ' ');
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-L")) {
            mod.addLibraryPath(.{ .cwd_relative = ctx.b.dupe(tok[2..]) });
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

const FortranOut = struct { obj: std.Build.LazyPath, mods: std.Build.LazyPath };

fn fortranOne(ctx: *const Ctx, dir: []const u8, file: []const u8, mod_deps: []const std.Build.LazyPath) FortranOut {
    const b = ctx.b;
    // flang (found in build()), -O2 on every platform, as configure-only.sh
    // captures it; -module-dir sets and searches the module output dir.
    // Windows' own Makeconf.win default is -O3; -O2 there too (R's check
    // passes with it, -O3 was never tried). (gfortran, which flang
    // replaced everywhere, had to be capped at -O1 on macOS: it silently
    // miscompiled R's complex LAPACK, zgesdd, at -O2.)
    // -fpic is meaningless on Windows (PE has no PIC distinction; flang
    // reports it as an unused argument on every file) — omit it there.
    const run = b.addSystemCommand(&.{ "flang", "-O2", "-c" });
    if (ctx.os != .windows) run.addArg("-fpic");
    // macOS: flang stamps its objects with the host SDK's version (minos
    // 26.0 on a macOS 26 machine) unless given the floor, and zig's link
    // relabels them 13.0 without a word. The flag rather than
    // MACOSX_DEPLOYMENT_TARGET: flang lets the flag win over the variable.
    if (ctx.os == .macos) run.addArg(floors.macos_min_flag);
    run.setName(b.fmt("flang {s}/{s}", .{ dir, file }));
    run.addFileArg(ctx.path(b.fmt("{s}/{s}", .{ dir, file })));
    run.addArg("-o");
    const stem = file[0..std.mem.lastIndexOfScalar(u8, file, '.').?];
    const obj = run.addOutputFileArg(b.fmt("{s}.o", .{stem}));
    run.addArg("-module-dir");
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
        // No dir at all is the normal state of a (platform, variant) pair
        // nobody has captured yet — e.g. minimal before its first
        // gen-config.yaml run on that platform — not a corrupted checkout.
        std.Io.Dir.cwd().access(io, b.pathFromRoot(config_dir), .{}) catch {
            std.debug.print("error: no vendored config for this platform/variant yet ({s}) — capture one with `pixi run -e <env> configure` + `pixi run -e <env> bash zigbuild/tools/gen-subst.sh` on that platform (or the gen-config workflow), see PLAN.md's \"Regenerating the vendored config\"\n", .{config_dir});
            return error.MissingVendoredConfig;
        };
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
            \\     use `pixi run -e full configure` / `-e minimal` for those variants)
            \\  2. cp build/obj-{s}-<variant>/src/include/{{config.h,Rconfig.h}} {s}/
            \\  3. pixi run bash zigbuild/tools/gen-subst.sh   (regenerates subst.txt;
            \\     `pixi run -e full|minimal bash zigbuild/tools/gen-subst.sh` for those)
            \\  4. update {s}/GENERATED_FROM to "{s}"
            \\See PLAN.md's "Regenerating the vendored config" section.
            \\
        , .{ config_dir, generated_from, r_version, r_version, r_version, config_dir, config_dir, r_version });
        return error.StaleVendoredConfig;
    }
}

/// Parses a vendored `zigbuild/config/<platform>-<variant>/subst.txt`
/// (`S["KEY"]="VALUE"` lines, `@ZR_*@` machine-path placeholders) into
/// `ctx.subst`. Generic across every platform that has a subst.txt at
/// all — unix's has one because it's a real captured `config.status`
/// S-table; Windows' is hand-populated (gnuwin32 has no config.status to
/// replay — see gen-subst.sh's own permanent Windows refusal) but is the
/// exact same file format, read by this exact same parser, so the same
/// `applyLinkFlags(ctx, mod, ctx.subst.get("KEY").?)` call shape works
/// identically on every platform. `loadSubstTable` below wraps this with
/// unix-only template-var extras that Windows' Makeconf.win has no
/// equivalent need for (it's substituted via its own separate
/// find/replace list, not `ctx.subst`/`substitute()` — see buildWindows's
/// own Makeconf.win handling).
fn loadSubstFile(ctx: *Ctx, io: std.Io, config_dir: []const u8) !void {
    const b = ctx.b;
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, b.pathFromRoot(b.fmt("{s}/subst.txt", .{config_dir})), b.allocator, .limited(4 * 1024 * 1024));
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |raw_line| {
        // Tolerate CRLF: a checkout with core.autocrlf=true (how GitHub's
        // windows-latest runners ship Git) hands us `S["KEY"]="VALUE"\r`,
        // and without this the trailing `"\r` survived into every value —
        // WIN_RGRAPHAPP_LIBS's last token became `-lmsimg32"\r`, a name
        // zig's mingw import-lib existence check could not even stat
        // ("failed to check zig installation for DLL import libs:
        // Unexpected" — Win32 ERROR_INVALID_NAME has no zig error mapping).
        // .gitattributes now forces LF on checkout too; this is the belt
        // to those braces, for any local clone with autocrlf on.
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        // format: S["KEY"]="VALUE"
        if (!std.mem.startsWith(u8, line, "S[\"")) continue;
        const key_end = std.mem.indexOf(u8, line, "\"]=\"") orelse continue;
        const key = line[3..key_end];
        var val: []const u8 = line[key_end + 4 ..];
        if (val.len > 0 and val[val.len - 1] == '"') val = val[0 .. val.len - 1];
        // Tools configure found in the env become bare names, looked up on
        // PATH when used (phase A5); the compilers (rzig) are
        // R_HOME/bin/toolchain, where build.zig installs them (F1.4, F3).
        // Neither records a path of the build machine.
        var v = try std.mem.replaceOwned(u8, b.allocator, val, "@ZR_CONDA@/bin/", "");
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_CONDA@", ctx.conda);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_SRC@", ctx.src_abs);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_OBJ@", ctx.rhome);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_PREFIX@", ctx.prefix);
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_TOOLCHAIN@", "$(R_HOME)/bin/toolchain");
        v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_ROOT@", b.pathFromRoot("."));
        // flang's runtime dir (see gen-subst.sh): resolved by findFlangRt at
        // build time so the LLVM major never gets baked into Makeconf.
        if (std.mem.indexOf(u8, v, "@ZR_FLANGRT_DIR@") != null) {
            // FLIBS/FLIBS_IN_SO name the static archive, not `-L<dir>
            // -lflang_rt.runtime`: the dir also holds the shared runtime,
            // which a native macOS link prefers (linux's pinned target
            // already took the .a). libR links it statically too, and a
            // compiled Fortran package has to load without the toolchain,
            // so no rpath into it can be relied on (feat-no-host-paths).
            v = try std.mem.replaceOwned(u8, b.allocator, v, "-L@ZR_FLANGRT_DIR@ -lflang_rt.runtime", "@ZR_FLANGRT_DIR@/libflang_rt.runtime.a");
            v = try std.mem.replaceOwned(u8, b.allocator, v, "@ZR_FLANGRT_DIR@", ctx.flangrt_dir);
        }
        // config.status escapes for awk: \$ → $ and \" → " (checked: no
        // vendored value contains a literal \\, so unescape order is safe)
        v = try std.mem.replaceOwned(u8, b.allocator, v, "\\$", "$");
        v = try std.mem.replaceOwned(u8, b.allocator, v, "\\\"", "\"");
        try ctx.subst.put(try b.allocator.dupe(u8, key), v);
        // Makeconf's form of a value that names the build environment
        // (CPPFLAGS, LDFLAGS, LIBS_PKGS, FLIBS_IN_SO, TCLTK_*, the
        // R_CONFIG_ARGS comment): see makeconfValue.
        for ([_][]const u8{ "@ZR_CONDA@", "@ZR_PREFIX@", "@ZR_FLANGRT_DIR@" }) |ph| {
            if (std.mem.indexOf(u8, val, ph) != null) {
                try ctx.mk_subst.put(try b.allocator.dupe(u8, key), try makeconfValue(ctx, val));
                break;
            }
        }
    }
}

/// etc/Makeconf's form of a subst.txt value (feat-no-host-paths F1.5): the
/// tree that ships carries no path of the machine that built it. The
/// environment is written $(R_HOME)/../.., which make expands where it
/// runs: the conda env, the standalone prefix, the wheel's r_zig/R (on
/// Windows R_HOME is <prefix>/Library/lib/R, so it is <prefix>/Library).
/// The flang runtime is -lflang_rt.runtime, which rzig (zig-cc and
/// zig-cxx) turns into the static archive of the flang on PATH, whatever
/// its LLVM major. R's own build keeps the absolute values in ctx.subst.
fn makeconfValue(ctx: *const Ctx, raw: []const u8) ![]const u8 {
    const a = ctx.b.allocator;
    var v = try std.mem.replaceOwned(u8, a, raw, "@ZR_CONDA@/bin/", "");
    // No rpath into the environment, and no CPPFLAGS/LDFLAGS (set empty in
    // build()): rzig adds them, the rpath for a conda env only
    // (zigbuild/tools/rzig/environment.zig, F3b). So the `# configure`
    // comment line (R_CONFIG_ARGS) loses its 'CPPFLAGS=…' and 'LDFLAGS=…'
    // words too, which would name flags the file does not use; the file is
    // the same in the conda package, the standalone tree and the wheel.
    v = try std.mem.replaceOwned(u8, a, v, " -Wl,-rpath,@ZR_CONDA@/lib", "");
    for ([_][]const u8{ " 'CPPFLAGS=", " 'LDFLAGS=" }) |word| {
        const i = std.mem.indexOf(u8, v, word) orelse continue;
        const end = std.mem.indexOfScalarPos(u8, v, i + word.len, '\'') orelse continue;
        v = try std.mem.concat(a, u8, &.{ v[0..i], v[end + 1 ..] });
    }
    v = try std.mem.replaceOwned(u8, a, v, "-L@ZR_FLANGRT_DIR@ -lflang_rt.runtime", "-lflang_rt.runtime");
    v = try std.mem.replaceOwned(u8, a, v, "@ZR_CONDA@", "$(R_HOME)/../..");
    v = try std.mem.replaceOwned(u8, a, v, "@ZR_PREFIX@", "$(R_HOME)/../..");
    v = try std.mem.replaceOwned(u8, a, v, "@ZR_TOOLCHAIN@", "$(R_HOME)/bin/toolchain");
    v = try std.mem.replaceOwned(u8, a, v, "\\$", "$");
    v = try std.mem.replaceOwned(u8, a, v, "\\\"", "\"");
    return v;
}

/// Whether two paths name the same directory, by real path (what
/// vendor-libs.sh's `pwd -P` compares). One that does not resolve, such as
/// an install prefix not made yet, names another.
fn samePhysicalDir(io: std.Io, a: std.mem.Allocator, x: []const u8, y: []const u8) bool {
    const rx = std.Io.Dir.cwd().realPathFileAlloc(io, x, a) catch return false;
    const ry = std.Io.Dir.cwd().realPathFileAlloc(io, y, a) catch return false;
    return std.mem.eql(u8, rx, ry);
}

fn pathExists(io: std.Io, p: []const u8) bool {
    std.Io.Dir.cwd().access(io, p, .{}) catch return false;
    return true;
}

/// OpenMP for packages, in a tree that is not the env R is built in (the
/// standalone archive, the dev tree), from the env's llvm-openmp: what
/// R CMD SHLIB's $(SHLIB_OPENMP_*FLAGS) compiles and links need, as a
/// conda env with llvm-openmp has it. Nothing when the profile has no
/// OpenMP (minimal: Makeconf offers none) or the prefix is the env (the
/// conda build: llvm-openmp is a run dependency there, and owns these
/// paths; the same test as vendor-libs.sh's).
///   - The headers (omp.h and the ones beside it; win-64's llvm-openmp
///     ships only omp.h and ompx.h) into the environment's include/,
///     where rzig looks (zigbuild/tools/rzig/environment.zig: R's own
///     environment is <prefix>, <prefix>/Library on Windows): its omp.h
///     is what makes rzig add -lomp to a -fopenmp link, and packages'
///     OpenMP probes (data.table's includes omp.h with no flag) find it.
///   - Windows: libomp.lib into <prefix>/Library/lib, the environment's
///     lib/, where rzig's -L points and windows.libs resolves -lomp.
/// libomp itself comes with the env's other shared libraries, from
/// vendor-libs.sh after the build: on unix because libR links it (into
/// <prefix>/lib); on Windows, where none of R's own DLLs imports it,
/// because the tree has libomp.lib (into R_HOME/bin/x64, the directory of
/// R's executables, where the loader finds a package DLL's import of it).
/// Phase T's standalone toolchain archive takes the headers and the import
/// library over.
fn installOpenMP(ctx: *const Ctx, io: std.Io) !void {
    if (!ctx.openmp or ctx.prefix_is_env) return;
    const b = ctx.b;
    const include: std.Build.InstallDir = .{ .custom = if (ctx.os == .windows) "Library/include" else "include" };
    inline for (.{ "omp.h", "ompx.h", "omp-tools.h", "ompt.h" }) |h| {
        const src = ctx.condaDir("include/" ++ h);
        if (pathExists(io, src)) {
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = src }, include, h).step);
        } else if (comptime std.mem.eql(u8, h, "omp.h")) {
            std.debug.print("error: {s} is missing (llvm-openmp not in the env?); the tree ships it for packages' OpenMP\n", .{src});
            return error.MissingOpenMP;
        }
    }
    if (ctx.os == .windows) {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = ctx.condaDir("lib/libomp.lib") }, .{ .custom = "Library/lib" }, "libomp.lib").step);
    }
}

/// The runtime data a tree that is not the env R is built in needs from
/// that env, installed with the tree as the OpenMP headers are
/// (feat-no-host-paths F1.7: the installed tree is the shipped tree on
/// every OS, and package-standalone.sh only archives it). The env's
/// shared libraries come after the build instead, from
/// scripts/vendor-libs.sh, since which ones is a walk over what the built
/// binaries need. The conda build (ctx.prefix_is_env) gets none of it:
/// the env's own packages (ca-certificates, fontconfig, tk) provide it
/// where conda-forge's libraries look for it. Windows' tcltk is the one
/// exception, below.
///   - unix: the env's CA bundle as R_HOME/etc/ca-bundle.crt, which
///     etc/Renviron names (finalRenviron); the build fails without it.
///     fontconfig's configuration as <prefix>/etc/fonts, without the
///     env's own directories (installFontconfig), when the env has one
///     (minimal has no fontconfig). full (the variant that builds
///     tcltk): Tcl's and Tk's script libraries and Tcl's modules as
///     <prefix>/lib/{tcl8.6,tk8.6,tcl8}, beside the libtcl and libtk
///     vendor-libs.sh copies, the layout of a Tcl install; etc/Renviron
///     points TCL_LIBRARY at the first (finalRenviron).
///   - Windows: the Tcl/Tk runtime in R_HOME/Tcl, where tcltk's .onLoad
///     loads it from (Tcl/bin as library.dynam's DLLpath, Tcl/lib as
///     TCLLIBPATH); the build fails without it, tcltk is always built
///     there. Also Tcl/Tk's headers in R_HOME/Tcl/include, for packages
///     that compile against Tcl/Tk (tkrplot): compile-time files, kept
///     in the base by T1 (feat-standalone-toolchain PLAN.md; below).
///     fontconfig's configuration (installFontconfig) as
///     R_HOME/etc/fonts, which
///     etc/Renviron.site points FONTCONFIG_PATH at. etc/Renviron.site is
///     written here, for the conda build too: it carries the compile
///     preflight's hint (Windows R reads Renviron.site, not etc/Renviron,
///     which finalRenviron writes for unix), and in the conda build
///     MY_TCLTK: tcltk's .onLoad (src/library/tcltk/R/windows/zzz.R)
///     stops with "Tcl/Tk support files were not installed" unless
///     R_HOME/Tcl/bin exists or MY_TCLTK names the directory of the Tcl/Tk
///     DLLs, which in a conda env is the tk package's Library/bin
///     (tcl86t.dll finds its scripts in Library/lib relative to itself).
///     `R --vanilla` skips Renviron.site, and on Windows no other file R
///     reads at startup, so there library(tcltk) needs MY_TCLTK set by
///     hand.
fn installEnvRuntime(ctx: *const Ctx, io: std.Io) !void {
    const b = ctx.b;
    const fonts = !ctx.prefix_is_env and pathExists(io, ctx.condaDir("etc/fonts"));
    if (ctx.os != .windows) {
        if (ctx.prefix_is_env) return;
        // TLS trust. The vendored libcurl and OpenSSL are conda-forge's,
        // built with this env's paths compiled in (libcurl's default CA
        // file is <env>/ssl/cacert.pem, OpenSSL's directory <env>/ssl):
        // outside this machine every HTTPS request failed with "libcurl
        // error code 77: error adding trust anchors from file" (found
        // 2026-09-28; the wheel, built from this tree, had the same). Ship
        // the env's Mozilla bundle and set R_ZIG_CA_BUNDLE: R's libcurl.c,
        // patched (zigbuild/patches/), then takes CURL_CA_BUNDLE if the
        // user set one, else SSL_CERT_FILE, else the system's bundle, else
        // this file, and passes it to curl as CURLOPT_CAINFO, so the
        // compiled-in path is never used. Not CURL_CA_BUNDLE itself:
        // Renviron exports to every program R starts, and curl or Python's
        // requests would drop their own trust for this frozen copy.
        // Interim fix: the per-platform curl in
        // .github/devdocs/feat-no-host-paths/PLAN.md ("libcurl") replaces
        // it. Windows needs none of this: conda-forge's curl there uses
        // Schannel, the Windows certificate store.
        const ca = ctx.condaDir("ssl/cacert.pem");
        const ca_size = if (std.Io.Dir.cwd().statFile(io, ca, .{})) |st| st.size else |_| 0;
        if (ca_size == 0) {
            std.debug.print("error: {s} is missing or empty (ca-certificates not in the env?); the tree ships it as etc/ca-bundle.crt\n", .{ca});
            return error.MissingCaBundle;
        }
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = ca }, ctx.rhomeInstallDir("etc"), "ca-bundle.crt").step);
        if (fonts) try installFontconfig(ctx, io, .{ .custom = "etc/fonts" });
        // tcltk (full). conda-forge's libtcl has the env's lib/tcl8.6
        // compiled in as its script library, and R starts Tcl with no
        // executable name to search from (Tcl_FindExecutable(NULL)), so
        // off this machine Tcl_Init found no init.tcl and library(tcltk)
        // failed. Tk's library and the modules (tcl8: msgcat, which
        // `clock` needs, http, ...) are found beside Tcl's: Tcl's auto_path
        // and module roots include [file dirname [info library]].
        if (ctx.variant == .full) {
            inline for (.{ "tcl8.6", "tk8.6", "tcl8" }) |d| {
                if (!pathExists(io, ctx.condaDir("lib/" ++ d))) {
                    std.debug.print("error: {s} is missing (tk not in the env?); the tree ships it as lib/{s}\n", .{ ctx.condaDir("lib/" ++ d), d });
                    return error.MissingTclTk;
                }
                try installEnvDir(ctx, io, ctx.condaDir("lib/" ++ d), .{ .custom = "lib/" ++ d }, &.{});
            }
        }
        return;
    }
    var site = std.ArrayList(u8).empty;
    if (ctx.toolchain_hint.len > 0) {
        try site.appendSlice(b.allocator, b.fmt("R_ZIG_TOOLCHAIN_HINT=${{R_ZIG_TOOLCHAIN_HINT-'{s}'}}\n", .{ctx.toolchain_hint}));
    }
    if (ctx.prefix_is_env) {
        // R_HOME is <env>/Library/lib/R, so this is <env>/Library/bin.
        // Renviron expands a nested default only when it is a whole ${...}
        // term, hence the helper variable (as finalRenviron's MAKE).
        try site.appendSlice(b.allocator, "R_ZIG_TCLTK=${R_HOME}/../../bin\nMY_TCLTK=${MY_TCLTK-${R_ZIG_TCLTK}}\n");
    } else {
        inline for (.{ "bin/tcl86t.dll", "bin/tk86t.dll", "lib/tcl8.6", "lib/tk8.6", "lib/tcl8" }) |sub| {
            if (!pathExists(io, ctx.condaDir(sub))) {
                std.debug.print("error: {s} is missing (tk not in the env?); the tree ships Tcl/Tk in R_HOME/Tcl\n", .{ctx.condaDir(sub)});
                return error.MissingTclTk;
            }
        }
        // The DLLs only in Tcl/bin, CRAN's layout: a copy in bin/x64 wins
        // the search order and then looks for init.tcl relative to itself
        // (vendor-libs.sh keeps them out of bin/x64).
        inline for (.{ "tcl86t.dll", "tk86t.dll" }) |dll| {
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = ctx.condaDir("bin/" ++ dll) }, ctx.rhomeInstallDir("Tcl/bin"), dll).step);
        }
        // tcl8 holds Tcl's modules (msgcat, which `clock` needs, http,
        // platform, tcltest); Tcl looks for them under the parent of its
        // script library, Tcl/lib.
        inline for (.{ "tcl8.6", "tk8.6", "tcl8" }) |d| {
            try installEnvDir(ctx, io, ctx.condaDir("lib/" ++ d), ctx.rhomeInstallDir("Tcl/lib/" ++ d), &.{});
        }
        // Tcl/Tk's headers in Tcl/include, where Makeconf's TCLTK_CPPFLAGS
        // (-I "$(TCL_HOME)/include") and packages' Makevars.win look, as
        // in CRAN's R_HOME/Tcl. They are compile-time files, the one
        // exception to "compile-time files go in the toolchain"
        // (feat-standalone-toolchain PLAN.md, T1). Without them a tree
        // used alone compiled no Tcl/Tk C code: tkrplot stopped at
        // "'tk.h' file not found". The set is tcl.h, tk.h and
        // tkPlatDecls.h (Tk_GetHWND and the rest) with what they include,
        // from conda-forge's win-64 tk; tk.h includes X11/Xlib.h, Tk's own
        // stand-in for Xlib on Windows. Left out: tk's other 15 headers
        // (tclOO, tclTomMath, itcl, tdbc, and the X11 headers none of
        // these include).
        inline for (.{
            "tcl.h",            "tclDecls.h",  "tclPlatDecls.h",
            "tk.h",             "tkDecls.h",   "tkPlatDecls.h",
            "tkIntXlibDecls.h", "X11/X.h",     "X11/Xfuncproto.h",
            "X11/Xlib.h",       "X11/Xutil.h", "X11/keysym.h",
            "X11/keysymdef.h",
        }) |h| {
            if (!pathExists(io, ctx.condaDir("include/" ++ h))) {
                std.debug.print("error: {s} is missing (tk not in the env?); the tree ships Tcl/Tk's headers in R_HOME/Tcl/include\n", .{ctx.condaDir("include/" ++ h)});
                return error.MissingTclTk;
            }
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = ctx.condaDir("include/" ++ h) }, ctx.rhomeInstallDir("Tcl/include"), h).step);
        }
        if (fonts) {
            try installFontconfig(ctx, io, ctx.rhomeInstallDir("etc/fonts"));
            try site.appendSlice(b.allocator, "FONTCONFIG_PATH=${R_HOME}/etc/fonts\n");
        }
    }
    if (site.items.len > 0) {
        const site_wf = b.addWriteFiles();
        const f = site_wf.add("Renviron.site", site.items);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(f, ctx.rhomeInstallDir("etc"), "Renviron.site").step);
    }
}

/// Install every file under `src`, a directory of the env, into `dest`,
/// following symlinks: conda-forge's fontconfig links etc/fonts/conf.d/
/// *.conf to ../../../share/fontconfig/conf.avail, which a tree outside
/// the env does not have, and std.Build's InstallDir skips symlinks
/// altogether; so each arrives as the file it names. A link to nothing,
/// or to a directory, is left out, and so are the paths in `except`
/// (relative to `src`, `/`-separated).
fn installEnvDir(ctx: *const Ctx, io: std.Io, src: []const u8, dest: std.Build.InstallDir, except: []const []const u8) !void {
    const b = ctx.b;
    var dir = try std.Io.Dir.cwd().openDir(io, src, .{ .iterate = true });
    defer dir.close(io);
    var it = try dir.walk(b.allocator);
    defer it.deinit();
    walk: while (try it.next(io)) |e| {
        const rel = try std.mem.replaceOwned(u8, b.allocator, e.path, "\\", "/");
        for (except) |x| if (std.mem.eql(u8, rel, x)) continue :walk;
        const from = b.fmt("{s}/{s}", .{ src, e.path });
        switch (e.kind) {
            .file => {},
            .sym_link => {
                const st = std.Io.Dir.cwd().statFile(io, from, .{}) catch continue;
                if (st.kind != .file) continue;
            },
            else => continue,
        }
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = from }, dest, b.dupe(e.path)).step);
    }
}

/// fontconfig's configuration, for a tree that is not the env
/// (installEnvRuntime): the env's etc/fonts (Library/etc/fonts on
/// Windows), without the env. conda-forge builds fontconfig with the env
/// as its prefix, so its fonts.conf names <env>/share/fonts and <env>/fonts
/// as font directories and <env>/var/cache/fontconfig as the first cache
/// (linux; macOS only the cache; Windows none), and conf.d/README says the
/// env's share/fontconfig/conf.avail holds the conf.d files. fonts.conf is
/// installed without those lines (fontsConfWithoutEnv), README not at all
/// (fontconfig reads only conf.d's *.conf files, and this tree's are
/// copies, not links into conf.avail). What remains are the system's and
/// the user's font directories and caches: /usr/share/fonts on linux,
/// /System/Library/Fonts and the rest on macOS, Windows' font folders,
/// then the XDG ones and ~/.fonts; the cache in the XDG cache directory
/// (~/.cache/fontconfig) and ~/.fontconfig. The launchers point
/// FONTCONFIG_PATH here (zigbuild/launchers/; Windows: etc/Renviron.site),
/// since the vendored libfontconfig names only the build env's etc/fonts.
fn installFontconfig(ctx: *const Ctx, io: std.Io, dest: std.Build.InstallDir) !void {
    const b = ctx.b;
    const src = ctx.condaDir("etc/fonts");
    try installEnvDir(ctx, io, src, dest, &.{ "fonts.conf", "conf.d/README" });
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/fonts.conf", .{src}), b.allocator, .limited(1024 * 1024));
    const wf = b.addWriteFiles();
    const conf = wf.add("fonts.conf", try fontsConfWithoutEnv(ctx, io, raw));
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(conf, dest, "fonts.conf").step);
}

/// `raw`, an env's fonts.conf, without the lines that name the env (as
/// written, or resolved, with either separator). Each is one <dir> or
/// <cachedir> element on a line of its own, as fontconfig writes the file
/// (fonts.conf.in); a line naming the env that is not one of those stops
/// the build, so a change in fontconfig's format cannot ship the env's
/// path or a broken file.
fn fontsConfWithoutEnv(ctx: *const Ctx, io: std.Io, raw: []const u8) ![]u8 {
    const b = ctx.b;
    const a = b.allocator;
    var forms = std.ArrayList([]const u8).empty;
    const real = std.Io.Dir.cwd().realPathFileAlloc(io, ctx.conda, a) catch ctx.conda;
    for ([_][]const u8{ ctx.conda, real }) |p| {
        try forms.append(a, p);
        try forms.append(a, try std.mem.replaceOwned(u8, a, p, "\\", "/"));
        try forms.append(a, try std.mem.replaceOwned(u8, a, p, "/", "\\"));
    }
    var out = std.ArrayList(u8).empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    var first = true;
    while (lines.next()) |line| {
        const names_env = for (forms.items) |f| {
            if (std.mem.indexOf(u8, line, f) != null) break true;
        } else false;
        if (names_env) {
            const t = std.mem.trim(u8, line, " \t\r");
            const element = (std.mem.startsWith(u8, t, "<dir") and std.mem.endsWith(u8, t, "</dir>")) or
                (std.mem.startsWith(u8, t, "<cachedir") and std.mem.endsWith(u8, t, "</cachedir>"));
            if (!element) {
                std.debug.print("error: the env's fonts.conf names it outside a <dir> or <cachedir> line of its own:\n  {s}\n", .{line});
                return error.FontconfigNamesEnv;
            }
            continue;
        }
        if (!first) try out.append(a, '\n');
        first = false;
        try out.appendSlice(a, line);
    }
    return out.items;
}

/// Fail the build when an installed text file (etc/Makeconf, libR.pc)
/// names the machine that built it: the conda env, the install prefix,
/// the R source, this checkout, rattler-build's build prefix, or a
/// subst.txt placeholder nothing replaced. Comment lines count: R CMD
/// config and humans read them too. Measured against the template the
/// text came from: only what substitution added counts, so a prefix of
/// /usr/local does not trip over Makeconf.in's own "/usr/local/lib"
/// comment (no rule about the characters around a match could tell that
/// from a leaked <prefix>/lib).
fn assertNoBuildPath(ctx: *const Ctx, name: []const u8, template: []const u8, text: []const u8) !void {
    const b = ctx.b;
    var needles = std.ArrayList([]const u8).empty;
    for ([_][]const u8{ ctx.conda, ctx.prefix, ctx.src_abs, b.pathFromRoot("."), b.graph.environ_map.get("BUILD_PREFIX") orelse "" }) |p| {
        if (p.len == 0) continue;
        try needles.append(b.allocator, p);
        // Windows paths appear with either separator
        try needles.append(b.allocator, try std.mem.replaceOwned(u8, b.allocator, p, "\\", "/"));
    }
    try needles.append(b.allocator, "@ZR_");
    for (needles.items) |n| {
        if (std.mem.count(u8, text, n) <= std.mem.count(u8, template, n)) continue;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, n) != null) {
                std.debug.print("error: {s} names a build path ({s}):\n  {s}\n", .{ name, n, line });
                break;
            }
        }
        return error.BuildPathInInstalledFile;
    }
}

fn loadSubstTable(ctx: *Ctx, io: std.Io, config_dir: []const u8) !void {
    try loadSubstFile(ctx, io, config_dir);
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
    return substituteWith(ctx, content, null);
}

/// substitute(), looking keys up in `overlay` first (etc/Makeconf: ctx.mk_subst).
fn substituteWith(ctx: *const Ctx, content: []const u8, overlay: ?*const std.StringHashMap([]const u8)) ![]u8 {
    const b = ctx.b;
    var out = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '@') {
            if (std.mem.indexOfScalarPos(u8, content, i + 1, '@')) |j| {
                const key = content[i + 1 .. j];
                if (key.len > 0 and key.len < 64 and isVarName(key)) {
                    if ((if (overlay) |o| o.get(key) else null) orelse ctx.subst.get(key)) |val| {
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
        } else if (std.mem.eql(u8, pkg, "tcltk") and ctx.variant != .full) {
            // slim/minimal: use_tcltk=no → stub only, none of the top-level R/*.R
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
            // (base: mkRbase's one substitution, configure's @WHICH@ in
            // R/unix/system.unix.R, is gone with patch 0002's Sys.which.)
            const all_r = try concatRSources(ctx, io, b.fmt("{s}/R", .{pkg_src}), if (with_os) os_subdir else null, if (s4) pkg else null);
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
    // No tools/misc/top.txt: R's make writes the source tree's absolute
    // path there (tools/Makefile.in, `$(ECHO) $(abs_top_srcdir)`;
    // Makefile.win `pwd -W`) and make install ships it, a path of the
    // build machine. Its one reader, tools:::.R_top_srcdir() (utils.R),
    // locates R's sources for R-core's maintenance helpers (aspell over
    // R's manuals and dictionaries, R-exts' DESCRIPTION fields), and reads
    // a missing file as "" (`if(nzchar(system.file(...)))`), the answer
    // for a tree without R's sources; _R_TOP_SRCDIR_ names them for
    // whoever has a copy. The value is read once, when tools' code is
    // lazy-loaded during the bootstrap, so it is "" in tools.rdb too.
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
    // Translation catalogs: with NLS off (slim and minimal) R never opens
    // them, but upstream's make install copies them regardless, and slim
    // keeps that parity. minimal drops them (10 MiB): the wheel it feeds
    // is size-driven. bootstrap() still creates the package dir itself.
    if (ctx.variant != .minimal) {
        _ = libstage.addCopyDirectory(ctx.path("src/library/translations/inst"), "translations", .{});
    }
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
        // Relative to the .pc file (pkg-config's ${pcfiledir}), as
        // Makeconf is to R_HOME: <prefix>/lib/pkgconfig/../R is R_HOME.
        // @others is upstream's $(MAIN_LDFLAGS) $(LDFLAGS) minus LDFLAGS,
        // the build env's -L/-rpath (libR is in ${rlibdir}, which no env
        // rpath ever covered).
        const pc_in = try readSrcFile(ctx, io, "src/unix/libR.pc.in");
        var pc = pc_in;
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@rhome", "${pcfiledir}/../R");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@rincludedir", "${rhome}/include");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@rarch", "");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@libsprivate", "");
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@others", std.mem.trim(u8, ctx.subst.get("MAIN_LDFLAGS") orelse "", " "));
        pc = try std.mem.replaceOwned(u8, b.allocator, pc, "@VERSION", r_version);
        try assertNoBuildPath(ctx, "lib/pkgconfig/libR.pc", pc_in, pc);
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
    _ = stage.add("etc/Renviron", try finalRenviron(ctx, try substFile(ctx, io, "etc/Renviron.in")));
    _ = stage.add("etc/ldpaths", ldpaths(ctx));
    const makeconf_in = try readSrcFile(ctx, io, "etc/Makeconf.in");
    const makeconf = try substituteWith(ctx, makeconf_in, &ctx.mk_subst);
    try assertNoBuildPath(ctx, "etc/Makeconf", makeconf_in, makeconf);
    _ = stage.add("etc/Makeconf", makeconf);
    _ = stage.add("etc/javaconf", try substFile(ctx, io, "etc/javaconf.in"));
    _ = stage.addCopyFile(ctx.path("etc/repositories"), "etc/repositories");
    if (ctx.os == .macos) _ = stage.add("etc/r-zig.cmake", macos_cmake_toolchain);

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
    installCommonPayload(ctx);

    // utils iconvlist (basepkg iconvlist target: `iconv -l`)
    const iconv_run = b.addSystemCommand(&.{ "iconv", "-l" });
    const iconv_out = iconv_run.captureStdOut(.{});
    _ = libstage.addCopyFile(iconv_out, "utils/iconvlist");

    return libstage;
}

/// bin/R: R.sh.in substituted, with the lines make install rewrites set
/// to the values that ship (F1.4): R_HOME_DIR found from the script's own
/// location (one symlink hop at a time with plain `readlink`, POSIX sh,
/// see zigbuild/launchers/R), R_SHARE_DIR/R_INCLUDE_DIR/R_DOC_DIR under it,
/// and R.sh.in's lib64 probe (`if test "${R_HOME_DIR}" = "<prefix>/lib/R"`,
/// which runs `uname -m`) dropped: a self-located R_HOME_DIR matches it on
/// the build machine only.
fn makeRFrontScript(ctx: *const Ctx, io: std.Io) ![]u8 {
    const b = ctx.b;
    const raw = try substFile(ctx, io, "src/scripts/R.sh.in");
    const home_line =
        \\R_HOME_DIR=$(_s="$0"; while [ -h "$_s" ]; do case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac; _d=$(cd -P "${_d:-/}" && pwd); _s=$(readlink "$_s"); case "$_s" in (/*) ;; (*) _s="$_d/$_s" ;; esac; done; case "$_s" in (*/*) _d="${_s%/*}" ;; (*) _d=. ;; esac; cd -P "${_d:-/}/.." && pwd)
    ;
    var out = std.ArrayList(u8).empty;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    var home_done = false;
    var in_probe = false;
    var first = true;
    while (lines.next()) |line| {
        if (in_probe) {
            if (std.mem.eql(u8, line, "fi")) in_probe = false;
            continue;
        }
        if (std.mem.startsWith(u8, line, "if test \"${R_HOME_DIR}\" = \"")) {
            in_probe = true;
            continue;
        }
        if (!first) try out.append(b.allocator, '\n');
        first = false;
        if (!home_done and std.mem.indexOf(u8, line, "R_HOME_DIR=") != null) {
            try out.appendSlice(b.allocator, home_line);
            home_done = true;
        } else if (std.mem.startsWith(u8, line, "R_SHARE_DIR=")) {
            try out.appendSlice(b.allocator, "R_SHARE_DIR=\"${R_HOME_DIR}/share\"");
        } else if (std.mem.startsWith(u8, line, "R_INCLUDE_DIR=")) {
            try out.appendSlice(b.allocator, "R_INCLUDE_DIR=\"${R_HOME_DIR}/include\"");
        } else if (std.mem.startsWith(u8, line, "R_DOC_DIR=")) {
            try out.appendSlice(b.allocator, "R_DOC_DIR=\"${R_HOME_DIR}/doc\"");
        } else {
            try out.appendSlice(b.allocator, line);
        }
    }
    return out.items;
}

/// etc/ldpaths: R_HOME/lib only (the env's or a vendored lib dir is found
/// through the binaries' relative rpaths). DYLD_FALLBACK_LIBRARY_PATH on
/// macOS, LD_LIBRARY_PATH elsewhere. R_LD_LIBRARY_PATH from the
/// environment wins, which is how this build runs its own R
/// (Ctx.buildLdPath).
fn ldpaths(ctx: *const Ctx) []const u8 {
    return switch (ctx.os) {
        .macos =>
        \\: "${R_LD_LIBRARY_PATH=${R_HOME}/lib}"
        \\if [ -z "${DYLD_FALLBACK_LIBRARY_PATH}" ]; then
        \\  DYLD_FALLBACK_LIBRARY_PATH="${R_LD_LIBRARY_PATH}"
        \\else
        \\  DYLD_FALLBACK_LIBRARY_PATH="${R_LD_LIBRARY_PATH}:${DYLD_FALLBACK_LIBRARY_PATH}"
        \\fi
        \\export DYLD_FALLBACK_LIBRARY_PATH
        \\
        ,
        else =>
        \\: "${R_LD_LIBRARY_PATH=${R_HOME}/lib}"
        \\LD_LIBRARY_PATH="${R_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}"
        \\export LD_LIBRARY_PATH
        \\
        ,
    };
}

/// etc/r-zig.cmake on macOS, in every tree (the conda build's too): a
/// CMake toolchain file that keeps the host's package managers out of
/// CMake's searches. etc/Renviron makes it CMAKE_TOOLCHAIN_FILE's default
/// (finalRenviron), which CMake (>= 3.21) reads from the environment when
/// the command line names no toolchain file: a package's own
/// -DCMAKE_TOOLCHAIN_FILE wins, and so does the variable when it is set
/// already, an empty one included (CMake then uses none).
///   - Why: CMake's Platform/Darwin.cmake puts Homebrew's prefix (`brew
///     --prefix`, else /opt/homebrew on arm64 and /usr/local on Intel)
///     first in CMAKE_SYSTEM_PREFIX_PATH, before the environment's, and
///     Fink's /sw and MacPorts' /opt/local last, whatever PATH says.
///     Packages then link the host's libraries (stress round 2, H2: arrow
///     linked /opt/homebrew/lib/libsnappy.a; feat-stress-suite
///     stress/results/2026-10-08-round2.md). The four are the prefixes
///     Darwin.cmake adds for a package manager, and $HOMEBREW_PREFIX
///     (`brew shellenv` sets it) is Homebrew's when it lives elsewhere
///     (`brew --prefix`); unset, it adds nothing.
///   - CMAKE_SYSTEM_IGNORE_PREFIX_PATH (CMake >= 3.23; older ones skip it)
///     drops exactly these prefixes from every find_* search: the
///     system's, PATH's (find_package's <prefix> for each <prefix>/bin)
///     and CMAKE_PREFIX_PATH's. A prefix below one of them (a conda env in
///     /opt/homebrew/Caskroom) is kept, and so is a program found on PATH.
///     The variable without SYSTEM stays the project's.
///   - The environment's libraries: CMake finds them through the prefix
///     of the cmake it runs (UnixPaths.cmake; the env's cmake), PATH's
///     <env>/bin and CMAKE_PREFIX_PATH, none of them one of these four;
///     the conda build's R_HOME is <env>/lib/R.
///   - Not linux: CMake's Linux platform adds no package manager's prefix
///     (UnixPaths.cmake: /usr/local, /usr, /, its own and the install
///     prefix, /usr/X11R6, /usr/pkg, /opt); Linuxbrew is searched only
///     when PATH or CMAKE_PREFIX_PATH names it. Not Windows: CMake adds
///     Program Files and its own prefix there (WindowsPaths.cmake), and
///     etc/Rcmd_environ sets its generator and windres (rcmdEnviron).
const macos_cmake_toolchain =
    \\# r-zig: CMake's default toolchain file for package builds on macOS.
    \\# etc/Renviron sets CMAKE_TOOLCHAIN_FILE to it; a CMAKE_TOOLCHAIN_FILE
    \\# already set (empty: none) or a package's -DCMAKE_TOOLCHAIN_FILE wins.
    \\# CMake searches Homebrew's, Fink's and MacPorts' prefixes whatever
    \\# PATH says. This leaves them out of every find_* search (CMake >= 3.23),
    \\# so packages link their environment's libraries, not the host's.
    \\set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH /opt/homebrew /usr/local /opt/local /sw $ENV{HOMEBREW_PREFIX})
    \\
;

/// etc/Renviron as it ships (phase A4, F1.4): untar() and unzip() use R's
/// internal code (installing a package without compiling runs no tar or
/// unzip), printing goes to a bare `lpr`, minimal's MAKE is the bundled
/// GNU make, the compile preflight's hint comes from -Dtoolchain-hint, on
/// macOS CMake's default toolchain file is etc/r-zig.cmake
/// (macos_cmake_toolchain), and a tree that is not the env names its CA
/// bundle and, in full, Tcl's script library (installEnvRuntime).
/// `${X-default}` keeps a value set in the environment, as upstream's
/// Renviron does. The tool defaults PAGER/R_BROWSER/... come from the
/// normalized configure table (zigbuild/tools/normalize-subst.sh).
fn finalRenviron(ctx: *const Ctx, raw: []const u8) ![]u8 {
    const b = ctx.b;
    var out = std.ArrayList(u8).empty;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, raw, "\n"), '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "TAR=")) {
            try out.appendSlice(b.allocator, "TAR=${TAR-'internal'}");
        } else if (std.mem.startsWith(u8, line, "R_UNZIPCMD=")) {
            try out.appendSlice(b.allocator, "R_UNZIPCMD=${R_UNZIPCMD-'internal'}");
        } else if (std.mem.startsWith(u8, line, "R_PRINTCMD=")) {
            try out.appendSlice(b.allocator, "R_PRINTCMD=${R_PRINTCMD-'lpr'}");
        } else if (std.mem.startsWith(u8, line, "MAKE=") and ctx.variant == .minimal) {
            // Renviron expands a nested default only when it is a whole
            // ${...} term, hence the helper variable.
            try out.appendSlice(b.allocator, "R_ZIG_MAKE=${R_HOME}/bin/toolchain/make\nMAKE=${MAKE-${R_ZIG_MAKE}}");
        } else {
            try out.appendSlice(b.allocator, line);
        }
        try out.append(b.allocator, '\n');
    }
    if (ctx.toolchain_hint.len > 0) {
        try out.appendSlice(b.allocator, b.fmt("R_ZIG_TOOLCHAIN_HINT=${{R_ZIG_TOOLCHAIN_HINT-'{s}'}}\n", .{ctx.toolchain_hint}));
    }
    // macOS: CMake's default toolchain file (macos_cmake_toolchain), in the
    // conda build too. R reads this file at startup and R CMD sources it,
    // so package builds get it either way. The helper variable: see MAKE
    // above.
    if (ctx.os == .macos) {
        try out.appendSlice(b.allocator,
            \\## r-zig: CMake leaves out Homebrew's, Fink's and MacPorts' prefixes.
            \\R_ZIG_CMAKE_TOOLCHAIN_FILE=${R_HOME}/etc/r-zig.cmake
            \\CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE-${R_ZIG_CMAKE_TOOLCHAIN_FILE}}
            \\
        );
    }
    // etc/Renviron, not Renviron.site: `R --vanilla`/`Rscript --vanilla`
    // imply --no-environ, which skips Renviron.site but still reads this
    // file. Why R_ZIG_CA_BUNDLE and not CURL_CA_BUNDLE: installEnvRuntime.
    if (!ctx.prefix_is_env) {
        try out.appendSlice(b.allocator,
            \\## r-zig: fallback trust anchors (read by the patched libcurl.c).
            \\R_ZIG_CA_BUNDLE=${R_HOME}/etc/ca-bundle.crt
            \\
        );
    }
    // full: Tcl's script library, which installEnvRuntime installs as
    // <prefix>/lib/tcl8.6 (R_HOME is <prefix>/lib/R); the vendored libtcl
    // names only the build env's. A Tcl that R starts gets this too, and
    // skips it when its version differs (init.tcl requires its exact
    // patchlevel, and Tcl moves on to its own). The helper variable: see
    // MAKE above.
    if (!ctx.prefix_is_env and ctx.variant == .full) {
        try out.appendSlice(b.allocator,
            \\## r-zig: Tcl's script library, shipped in the tree (tcltk).
            \\R_ZIG_TCL_LIBRARY=${R_HOME}/../tcl8.6
            \\TCL_LIBRARY=${TCL_LIBRARY-${R_ZIG_TCL_LIBRARY}}
            \\
        );
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
        yd.year,              md.month.numeric(),      md.day_index + 1,
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
        if (self.ctx.buildLdPath()) |p| run.setEnvironmentVariable("R_LD_LIBRARY_PATH", p);
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
        try argv.append(b.allocator, b.fmt("{s}/bin/Rscript", .{ctx.prefix}));
        try argv.append(b.allocator, b.fmt("{s}/bin/R", .{rhome}));
        try argv.append(b.allocator, b.fmt("{s}/bin/Rscript", .{rhome}));
        for (rspec.scripts_s) |s| try argv.append(b.allocator, b.fmt("{s}/bin/{s}", .{ rhome, s }));
        for (rspec.scripts_b) |s| try argv.append(b.allocator, b.fmt("{s}/bin/{s}", .{ rhome, s }));
        _ = boot.cmd("chmod scripts", argv.items);
    }

    // share/zoneinfo (internal tzcode database; needs conda unzip)
    _ = boot.cmd("unzip zoneinfo", &.{
        "unzip",                                                   "-qo",
        b.fmt("{s}/src/extra/tzone/zoneinfo.zip", .{ctx.src_abs}), "-d",
        b.fmt("{s}/share", .{rhome}),
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

    // translations (minimal stages no catalogs, see stageLibraryPayload —
    // but .install_package_description writes into the package dir, so
    // it has to exist)
    if (ctx.variant == .minimal) {
        _ = boot.cmd("mkdir translations", &.{ "mkdir", "-p", b.fmt("{s}/translations", .{lib}) });
    }
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
        // Shape matches configure's own pattern ("<os>,<cc>,<cxx>,<fc>,
        // <fc>"): zig's clang is GCC-compatible, as unix's captures say
        // (gcc,gxx), and the Fortran compiler is flang, spelled as
        // tools/Makefile.win spells it for an LLVM build.
        run.setEnvironmentVariable("R_SYSTEM_ABI", ctx.subst.get("R_SYSTEM_ABI") orelse "windows,gcc,gxx,flang,flang");
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
            if (ctx.variant != .full) continue; // stub: no real R code to lazycomp
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
        if (ctx.buildLdPath()) |p| run.setEnvironmentVariable("R_LD_LIBRARY_PATH", p);
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
