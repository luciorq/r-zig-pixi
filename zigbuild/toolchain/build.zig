//! The toolchain tree (feat-standalone-toolchain B30; PHASE3 open point A
//! (a)): the toolchain groups' third-party files, copied unchanged from
//! the env R is built in (CONDA_PREFIX) into
//! <prefix>/lib/R/bin/toolchain/<dir>/ (Windows:
//! <prefix>/Library/lib/R/bin/toolchain/<dir>/), each directory with
//! SOURCES and LICENSES/ (point 3). Its own build root, as rzig's is:
//!   zig build --build-file zigbuild/toolchain/build.zig --prefix <tree> -Dprefix=<tree>
//! needs no R source and runs no R configure. scripts/zig-toolchain.sh
//! (pixi run toolchain) installs dist/toolchain/R-<ver>-zig with it, and
//! package-standalone.sh's toolchain mode archives the groups from there
//! (B17). `test` runs conda.zig's, wheel.zig's and pkgconf.zig's unit
//! tests (pixi run toolchain-test). With -Dbase it writes the R tree's records instead
//! (PHASE8 open points A a, F a; installBase, below):
//!   zig build --build-file zigbuild/toolchain/build.zig --prefix <R tree> -Dprefix=<R tree> -Dbase
//! which scripts/zig-build.sh runs after vendor-libs.sh. zig 0.17's
//! configure step does not see --prefix, so -Dprefix repeats it: this
//! build reads the tree and the env's records at configure time. Each
//! directory's SOURCES is written at make time by sources_tool.zig (a
//! built file's line needs its sha256).
//!
//! What it installs, today's third-party files (phase 3's table, zig/ from
//! phase 5, flang/ from phase 6, Windows' usr/ and etc/ from phase 7):
//!   zig/       compilers    upstream zig, PyPI's ziglang wheel as
//!                           fetch-zig pins it (B4, phase 5): zig and
//!                           lib/, LICENSES/ziglang/ from the wheel's
//!                           dist-info, SOURCES from its RECORD
//!   flang/     compilers    flang's compile set from the env (B9 a):
//!                           flang-zig's driver as bin/flang (once),
//!                           flang-rt-zig's intrinsic and OpenMP
//!                           modules and its static runtime, by their
//!                           conda-meta records; no cfg, no lld, no
//!                           ISO_Fortran_binding.h (PHASE6 open point V)
//!   openmp/    compilers    llvm-openmp's omp.h and the headers beside it
//!                           (B22); Windows also libomp.lib
//!   usr/       build-tools  unix: conda-forge's GNU make as usr/bin/make
//!                           (B7, B23); Windows: B39's tools in usr/bin/,
//!                           every file of conda-forge's m2 packages'
//!                           usr/bin/ (MSYS2's bash, make, coreutils, sed,
//!                           grep, gawk, which, findutils, patch) with the MSYS
//!                           DLLs they import (B11; PHASE7 open points
//!                           A-C), and pkgconf as pkgconf.exe and
//!                           pkg-config.exe, which this build compiles
//!                           from source (pkgconf.zig, installPkgconf;
//!                           B43), on both channels
//!   etc/       build-tools  Windows: fstab, r-zig's own MSYS mount table,
//!                           written here, not copied (PHASE7 open point D)
//! (Windows' binutils are rzig's own names beside it, R's base, since
//! feat-win-zig-binutils: no binutils/ directory, B24's conda copies gone.)
//! Which group holds which directory: scripts/env.sh's group_dirs.
//!
//! Each file's package is the conda-meta record whose `files` lists its
//! path (conda.zig). SOURCES names the package, its URL and sha256, where
//! its program comes from (its recipe's sources, P3-C) and the feedstock
//! that built it, and each file with the package's sha256 of it;
//! LICENSES/<package>/ is the package's info/licenses/. Both come from the
//! package cache the env was installed from (the record's
//! extracted_package_dir). A package that ships no licence files (the m2
//! packages; libgcc, libstdcxx and libfreetype6 in the R tree) has the
//! texts r-zig took by hand from its source archive in
//! licenses/<package>/ beside this file, for the version its VERSION names
//! (PHASE7 open point E a, PHASE8 open point H a; its README says how). A
//! file no record lists, one with a prefix placeholder (conda rewrote it),
//! a package with no licence files (none here either, or for another
//! version), or a GPL one whose recipe lists no source stops this build
//! and names it.
//! R's own build (build.zig) never reads the package cache. zig/'s files
//! are the wheel's, each with the wheel's own sha256 of it (its RECORD,
//! the counterpart of paths_data), in a SOURCES block of the same shape
//! (wheel.zig; PHASE5 open points A, B, C): the wheel's URL and sha256
//! and the source of its zig come from fetch-zig's marker, which
//! scripts/zig-toolchain.sh passes the directory of as -Dziglang=<dir>.
//!
//! The conda build (recipe/build.sh, from step 3) runs this into the env
//! itself, with R_TOOLCHAIN_PREFIX=$PREFIX: there conda's own packages
//! provide every file where it is looked for: only Windows'
//! usr/bin/pkgconf is installed, which no conda package provides, built
//! from the recipe's pkgconf
//! source (-Dpkgconf=<dir>; the standalone build fetches the same tarball
//! as build.zig.zon's lazy `pkgconf`). No etc/, zig/ or flang/ and no
//! other usr/ file there: the env's MSYS tools are its own m2 packages
//! (Library/usr/bin), and conda keeps
//! conda-forge's zig and flang-pixi's flang-zig, through r-zig-compilers
//! (B30); the conda build fetches nothing (PHASE5 open point J;
//! zig-toolchain.sh skips fetch-zig by the same test as prefix_is_env
//! below).
const std = @import("std");
const mem = std.mem;
const conda = @import("conda.zig");
const wheel = @import("wheel.zig");
const pkgconf = @import("pkgconf.zig");
const sources_tool = @import("sources_tool.zig");

/// A file a directory copies from the env.
const Copy = struct {
    /// In the env, relative to its prefix: the path in its package.
    from: []const u8,
    /// In the directory.
    to: []const u8,
    /// A missing file stops the build; an optional one is left out.
    required: bool = true,
};

/// Every regular file of `package`'s record under `from` (relative to
/// the env), installed at the same path less a leading `strip`:
/// flang-rt-zig's modules and runtime, whose triple directory differs per
/// platform and whose module set follows LLVM (B9 a; PHASE6 open point A),
/// and an m2 package's usr/bin/ (PHASE7 open point C a). None stops the
/// build. Never installed into the env (the conda build), as no copy is
/// (PHASE6 Cc4).
const Tree = struct {
    package: []const u8,
    from: []const u8,
    /// Only the files of this base name.
    name: ?[]const u8 = null,
    /// What the copy's path loses: win-64's `Library/` (flang/'s trees),
    /// or `Library/usr/` (usr/'s: their files sit in bin/).
    strip: []const u8 = "Library/",
};

/// A group directory under R_HOME/bin/toolchain and what it copies: its
/// copies first, then its trees.
const Dir = struct {
    name: []const u8,
    copies: []const Copy,
    trees: []const Tree = &.{},
};

/// llvm-openmp's headers: omp.h, which makes rzig add -lomp to a -fopenmp
/// link, and the ones beside it where the env has them (win-64's
/// llvm-openmp ships only omp.h and ompx.h): the list the R trees carried
/// in their include/ until phase 3, now in openmp/include, where rzig
/// looks (B22, B40).
fn ompHeaders(comptime include: []const u8) [4]Copy {
    return .{
        .{ .from = include ++ "omp.h", .to = "include/omp.h" },
        .{ .from = include ++ "ompx.h", .to = "include/ompx.h", .required = false },
        .{ .from = include ++ "omp-tools.h", .to = "include/omp-tools.h", .required = false },
        .{ .from = include ++ "ompt.h", .to = "include/ompt.h", .required = false },
    };
}

/// flang-zig's LLVM major, which names flang-rt-zig's directories
/// (lib/clang/<major>/). It is the pin's (pixi.toml: flang-zig 23.1.5): a
/// new major moves the pin, this constant and SOURCES together. R's
/// build.zig (findFlangRt) and rzig (flang_rt.modulesDir) scan
/// lib/clang/* instead, because they must find whatever flang the env or
/// PATH has; this build copies what the pin says (PHASE6 open point A2).
const llvm_major = "23";

/// flang/ (B9 a; PHASE6 open points A, B, C): flang-zig's driver as
/// bin/flang (`driver`, the real file, not its flang softlink), and
/// flang-rt-zig's every module directory (linux and macOS one, win-64's
/// two twins) and its static runtime, under `prefix` (win-64's
/// `Library/`). No cfg: zig-fc passes the modules path; no lld: zig links.
fn flangDir(comptime prefix: []const u8, comptime driver: []const u8) Dir {
    const exe = if (mem.endsWith(u8, driver, ".exe")) ".exe" else "";
    const clang = prefix ++ "lib/clang/" ++ llvm_major ++ "/";
    return .{ .name = "flang", .copies = &.{.{ .from = driver, .to = "bin/flang" ++ exe }}, .trees = &.{
        .{ .package = "flang-rt-zig", .from = clang ++ "finclude/flang/" },
        .{ .package = "flang-rt-zig", .from = clang ++ "lib/", .name = "libflang_rt.runtime.a" },
    } };
}

const unix_dirs = [_]Dir{
    flangDir("", "bin/flang-" ++ llvm_major),
    .{ .name = "openmp", .copies = &ompHeaders("include/") },
    .{ .name = "usr", .copies = &.{.{ .from = "bin/make", .to = "bin/make" }} },
};

/// A file of the env's Library/usr/bin/ or Library/bin/ in usr/bin/.
fn usrBin(comptime from: []const u8) Copy {
    return .{ .from = from, .to = "bin/" ++ comptime from[mem.lastIndexOfScalar(u8, from, '/').? + 1 ..] };
}

/// Every file of an m2 tool package's usr/bin/ (PHASE7 open point C a).
fn m2Tool(comptime package: []const u8) Tree {
    return .{ .package = package, .from = "Library/usr/bin/", .strip = "Library/usr/" };
}

const windows_dirs = [_]Dir{
    flangDir("Library/", "Library/bin/flang.exe"),
    .{ .name = "openmp", .copies = &(ompHeaders("Library/include/") ++ [_]Copy{
        .{ .from = "Library/lib/libomp.lib", .to = "lib/libomp.lib" },
    }) },
    .{
        // B39's tools (B11; PHASE7 open points A-C, G): MSYS2's, from
        // conda-forge's m2 packages, every file of each tool package's
        // usr/bin/, unchanged.
        .name = "usr",
        // The DLLs those import, one package each (PHASE7's package
        // survey; every other import is the system's): msys-2.0.dll makes
        // R_HOME/bin/toolchain the MSYS root, which reads etc/fstab.
        // verify-toolchain.sh checks the closure.
        .copies = &[_]Copy{
            usrBin("Library/usr/bin/msys-2.0.dll"),
            usrBin("Library/usr/bin/msys-intl-8.dll"),
            usrBin("Library/usr/bin/msys-iconv-2.dll"),
            usrBin("Library/usr/bin/msys-pcre-1.dll"),
            usrBin("Library/usr/bin/msys-gmp-10.dll"),
            usrBin("Library/usr/bin/msys-mpfr-6.dll"),
            usrBin("Library/usr/bin/msys-readline8.dll"),
            usrBin("Library/usr/bin/msys-ncursesw6.dll"),
            usrBin("Library/usr/bin/msys-gcc_s-seh-1.dll"),
            // pkg-config (B43) is not a copy: pkgconf, built from source
            // (pkgconf.zig; installPkgconf), on both channels.
        },
        .trees = &[_]Tree{
            m2Tool("m2-bash"),
            m2Tool("m2-make"),
            m2Tool("m2-coreutils"),
            m2Tool("m2-sed"),
            m2Tool("m2-grep"),
            m2Tool("m2-gawk"),
            m2Tool("m2-which"),
            m2Tool("m2-findutils"),
            // patch.exe (feat-win-link-fixes item 4): a configure script
            // that patches its sources (hdf5r's unix configure: "patch:
            // command not found"). It imports msys-2.0.dll alone.
            m2Tool("m2-patch"),
        },
    },
};

/// MSYS's mount table (PHASE7 open point D a): msys-2.0.dll in usr/bin/
/// makes R_HOME/bin/toolchain the MSYS root, which reads etc/fstab. The
/// lines are MSYS2's (m2-filesystem's, less its build-env /conda_bin line,
/// which conda rewrites at install): drives at /c, no POSIX ACLs on
/// created files, /tmp Windows' temporary directory (usertemp: TMP, else
/// TEMP), so a read-only R install works. Not a copy: etc/SOURCES says so,
/// with the file's sha256, and etc/ has no LICENSES/. verify-toolchain.sh
/// checks these exact lines.
const fstab =
    "none / cygdrive binary,posix=0,noacl,user 0 0\n" ++
    "none /tmp usertemp binary,posix=0 0 0\n";

pub fn build(b: *std.Build) !void {
    const arena = b.allocator;
    const io = b.graph.io;

    const test_step = b.step("test", "Run the conda-meta and wheel readers', SOURCES writer's and pkgconf's and cairo's pins' unit tests");
    // pkgconf.zig's and cairo.zig's pin tests read the recipe and R's
    // build.zig.zon (paths). cairo.zig is R's build's (zigbuild/), tested
    // here with the other pins.
    const root_abs = try buildRoot(b, io);
    const paths = b.addOptions();
    paths.addOption([]const u8, "recipe", b.fmt("{s}/../../recipe/recipe.yaml", .{root_abs}));
    paths.addOption([]const u8, "zon", b.fmt("{s}/../../build.zig.zon", .{root_abs}));
    for ([_]std.Build.LazyPath{
        b.path("conda.zig"),
        b.path("wheel.zig"),
        b.path("pkgconf.zig"),
        b.graph.cwdRelativePath(b.fmt("{s}/../cairo.zig", .{root_abs})),
    }) |root| {
        const mod = b.createModule(.{
            .root_source_file = root,
            .target = b.graph.host,
        });
        mod.addOptions("paths", paths);
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);
    }
    const ziglang = b.option([]const u8, "ziglang", "PyPI's ziglang wheel, unpacked (scripts/fetch-zig.sh's directory): the compilers group's zig/");
    const pkgconf_dir = b.option([]const u8, "pkgconf", "pkgconf's source tarball, unpacked (the conda build's; else build.zig.zon's pkgconf): Windows' usr/bin/pkgconf.exe");
    const base = b.option(bool, "base", "Write the records of the R tree at --prefix (its files from the env) instead of the toolchain tree") orelse false;
    // zig 0.17's configure step does not see --prefix (the maker installs
    // there): -Dprefix names the same directory, which the toolchain tree's
    // copies, records and prefix_is_env read now. scripts/zig-toolchain.sh
    // and zig-build.sh pass both. Without it, only `test` runs.
    const prefix_opt = b.option([]const u8, "prefix", "The same directory as --prefix (zig 0.17's configure step does not see --prefix): the toolchain tree, or with -Dbase the R tree");

    // This configure step reads the env's conda-meta, the package cache and
    // the tree at -Dprefix: nothing zig's configure cache can track.
    b.graph.poisonCache();
    const env = b.graph.environ_map.get("CONDA_PREFIX") orelse
        return fail("CONDA_PREFIX is not set: run through pixi (pixi run toolchain)", .{});
    const os = b.graph.host.result.os.tag;
    const prefix = try mem.replaceOwned(u8, arena, prefix_opt orelse {
        b.getInstallStep().dependOn(&b.addFail("pass -Dprefix=<dir>, the same directory as --prefix (scripts/zig-toolchain.sh and zig-build.sh do)").step);
        return;
    }, "\\", "/");
    const prefix_is_env = samePhysicalDir(io, arena, prefix, env);
    if (base) return installBase(b, io, env, prefix, prefix_is_env, os);
    const tc = if (os == .windows) "Library/lib/R/bin/toolchain" else "lib/R/bin/toolchain";
    const dirs: []const Dir = if (os == .windows) &windows_dirs else &unix_dirs;

    const records = try readRecords(b, io, env, try dirNeedles(b, dirs));
    var summary: std.ArrayList(u8) = .empty;
    // Windows' usr/bin/pkgconf.exe, built (installPkgconf): on both
    // channels. error.LazyDependencyNeeded, returned from here, makes zig
    // fetch build.zig.zon's pkgconf and run this configure step again.
    const built: ?BuiltDir = if (os == .windows) try installPkgconf(b, io, tc, pkgconf_dir) else null;
    // SOURCES' writer, run when a directory's files are made
    // (sources_tool.zig).
    const tool = b.addExecutable(.{ .name = "sources_tool", .root_module = b.createModule(.{
        .root_source_file = b.path("sources_tool.zig"),
        .target = b.graph.host,
    }) });
    for (dirs) |d| {
        const dest: std.Build.InstallDir = .{ .custom = b.fmt("{s}/{s}", .{ tc, d.name }) };
        var copies: std.ArrayList(conda.Copy) = .empty;
        for (d.copies) |c| {
            // the env's own packages provide every copy where it is
            // looked for (the conda build; B41's binutils were the one
            // exception until feat-win-zig-binutils)
            if (prefix_is_env) continue;
            const src = b.fmt("{s}/{s}", .{ env, c.from });
            if (!pathExists(io, src)) {
                if (!c.required) continue;
                return fail("{s} is missing from the env {s}: the toolchain tree's {s}/ copies it", .{ c.from, env, d.name });
            }
            try copies.append(arena, try copyOf(b, records, src, c.from, c.to, dest));
        }
        // Trees are the standalone tree's only: skipped when the prefix is
        // the env, as copies are, before their files are
        // listed or an empty one stops the build (PHASE6 Cc4).
        for (d.trees) |t| {
            if (prefix_is_env) continue;
            var n: usize = 0;
            for (try conda.under(arena, records, t.package, t.from)) |from| {
                if (t.name) |name| {
                    if (!mem.eql(u8, from[mem.lastIndexOfScalar(u8, from, '/').? + 1 ..], name)) continue;
                }
                const src = b.fmt("{s}/{s}", .{ env, from });
                if (!pathExists(io, src))
                    return fail("{s} is missing from the env {s}, though {s}'s record lists it: the toolchain tree's {s}/ copies it", .{ from, env, t.package, d.name });
                try copies.append(arena, try copyOf(b, records, src, from, conda.inDir(from, t.strip), dest));
                n += 1;
            }
            if (n == 0) return fail("{s}'s record lists no {s} under {s} in the env {s}: the toolchain tree's {s}/ copies {s}", .{
                t.package, t.name orelse "file", t.from, env, d.name, if (t.name == null) "every file there" else "it",
            });
        }
        const own: []const BuiltFile = if (built != null and mem.eql(u8, d.name, built.?.dir)) built.?.files else &.{};
        if (copies.items.len == 0 and own.len == 0) continue;
        for (records) |*r| {
            if (r.upstream != null) continue;
            for (copies.items) |c| {
                if (c.record == r) {
                    r.upstream = try readUpstream(b, io, r);
                    break;
                }
            }
        }

        try installSources(b, tool, copies.items, own, dest);

        try summary.print(arena, "{s}{s}/ (", .{ if (summary.items.len == 0) "" else ", ", d.name });
        var packages: std.ArrayList(*const conda.Record) = .empty;
        for (copies.items) |c| {
            if (mem.indexOfScalar(*const conda.Record, packages.items, c.record) != null) continue;
            if (packages.items.len > 0) try summary.appendSlice(arena, ", ");
            try installLicenses(b, io, c.record, dest, b.fmt("LICENSES/{s}", .{c.record.name}));
            try summary.appendSlice(arena, c.record.name);
            try packages.append(arena, c.record);
        }
        if (own.len > 0) try summary.print(arena, "{s}{s} (built)", .{ if (packages.items.len > 0) ", " else "", own[0].record.name });
        try summary.appendSlice(arena, ")");
    }
    // Windows' etc/ (PHASE7 open point D a): written, never into the env.
    if (os == .windows and !prefix_is_env) {
        const dest: std.Build.InstallDir = .{ .custom = b.fmt("{s}/etc", .{tc}) };
        var sha: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(fstab, &sha, .{});
        const wf = b.addWriteFiles();
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(wf.add("fstab", fstab), dest, "fstab").step);
        const sources = b.fmt("written: r-zig's toolchain build (zigbuild/toolchain/build.zig), MSYS's mount table for usr/bin's tools\nfile: fstab -> fstab {s}\n", .{&std.fmt.bytesToHex(sha, .lower)});
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(wf.add("SOURCES", sources), dest, "SOURCES").step);
        try summary.print(arena, "{s}etc/ (r-zig's fstab)", .{if (summary.items.len == 0) "" else ", "});
    }
    // The compilers group's zig/ (B4): never into the env (B30, open point
    // J). A failing step, not a configure error, when the wheel is not
    // given, so that `test` (toolchain-test) runs without it.
    if (!prefix_is_env) {
        if (ziglang) |dir| {
            try installZig(b, io, try mem.replaceOwned(u8, arena, dir, "\\", "/"), tc, os);
            try summary.print(arena, "{s}zig/ (ziglang)", .{if (summary.items.len == 0) "" else ", "});
        } else {
            b.getInstallStep().dependOn(&b.addFail("the toolchain tree's zig/ comes from PyPI's ziglang wheel: run pixi run toolchain (scripts/zig-toolchain.sh runs fetch-zig and passes -Dziglang=<dir>)").step);
        }
    }
    std.debug.print("r-zig: toolchain tree {s}: {s}{s}\n", .{
        prefix,
        if (summary.items.len == 0) "nothing to install" else summary.items,
        if (prefix_is_env) " (the prefix is the env)" else "",
    });
}

/// The env's file `src`, `from` in its package, installed as `to` in the
/// directory `dest`: its owner and sha256 by path (conda.find), or the
/// reason it cannot be copied, which stops the build.
fn copyOf(b: *std.Build, records: []const conda.Record, src: []const u8, from: []const u8, to: []const u8, dest: std.Build.InstallDir) !conda.Copy {
    const copy = conda.find(records, from, to) catch |err| {
        const name = if (conda.owner(records, from)) |r| r.name else "";
        return switch (err) {
            error.NoOwner => fail("{s}: no package of the env lists it in conda-meta, so its source and licence are unknown", .{from}),
            error.TwoOwners => fail("{s}: two packages of the env list it (a clobber), so which one installed it is unknown", .{from}),
            error.NotInPathsData, error.NoSha256 => fail("{s}: {s}'s conda-meta record has no sha256 for it (paths_data)", .{ from, name }),
            error.PrefixPlaceholder => fail("{s}: conda rewrote it at install ({s} has a prefix placeholder in it), so the env's file names the env and is not the package's", .{ from, name }),
        };
    };
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.graph.cwdRelativePath(src), dest, to).step);
    return copy;
}

/// What the toolchain build compiles itself for a group directory, not a
/// copy from the env: its files and their record.
const BuiltDir = struct {
    /// The group directory.
    dir: []const u8,
    files: []const BuiltFile,
};

/// A file the toolchain build compiles, as SOURCES lists it.
const BuiltFile = struct {
    record: *const conda.Record,
    from: []const u8,
    to: []const u8,
    file: std.Build.LazyPath,
};

/// Windows' usr/bin/pkgconf.exe and pkg-config.exe, one exe (pkgconf.zig),
/// for this machine's arch, on both channels; LICENSES/pkgconf/, its
/// COPYING and the mingw-w64 CRT's (zig links its CRT startup into every
/// exe); and the record SOURCES writes for it: the tarball's URL and
/// sha256 (pkgconf.zig's, which the recipe and build.zig.zon pin), the
/// zig that built it in place of a conda build string, and this repository
/// as its recipe. The source: `dir` (-Dpkgconf, the conda build's
/// unpacked source), else build.zig.zon's lazy `pkgconf`, which zig
/// fetches into zigbuild/toolchain/zig-pkg/.
fn installPkgconf(b: *std.Build, io: std.Io, tc: []const u8, dir: ?[]const u8) !BuiltDir {
    const arena = b.allocator;
    const src = if (dir) |d| d else blk: {
        // Not yet fetched: zig fetches it and runs this configure step
        // again (std.Build.dependencyLazy).
        const dep = try b.dependencyLazy("pkgconf", .{});
        break :blk dep.builder.root.root_dir.path orelse ".";
    };
    const abs = try realPath(b, io, src);
    const arch = b.graph.host.result.cpu.arch;
    const exe = pkgconf.add(b, arch, abs) catch return error.ToolchainBuild;
    const dest: std.Build.InstallDir = .{ .custom = b.fmt("{s}/usr", .{tc}) };
    const bin = exe.getEmittedBin();
    for ([_][]const u8{ "pkgconf.exe", "pkg-config.exe" }) |name|
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(bin, dest, b.fmt("bin/{s}", .{name})).step);
    const copying = b.fmt("{s}/COPYING", .{abs});
    if (!pathExists(io, copying)) return fail("pkgconf: {s} is missing (LICENSES/pkgconf/COPYING)", .{copying});
    for ([_]struct { std.Build.LazyPath, []const u8 }{
        .{ b.graph.cwdRelativePath(copying), "COPYING" },
        .{ std.Build.LazyPath.zig_lib.path(b, "libc/mingw/COPYING"), "mingw-w64-crt-COPYING" },
    }) |l| b.getInstallStep().dependOn(&b.addInstallFileWithDir(l[0], dest, b.fmt("LICENSES/pkgconf/{s}", .{l[1]})).step);
    const record = try arena.create(conda.Record);
    record.* = .{
        .name = "pkgconf",
        .version = pkgconf.version,
        .build = b.fmt("zig{s}_{t}-windows-gnu", .{ @import("builtin").zig_version_string, arch }),
        .url = pkgconf.url,
        .sha256 = pkgconf.sha256,
        .license = pkgconf.license,
        .upstream = .{
            .sources = try arena.dupe(conda.Source, &.{.{ .url = pkgconf.url, .sha256 = pkgconf.sha256 }}),
            .feedstock = "https://github.com/luciorq/r-zig-pixi",
            .commit = "zigbuild/toolchain/pkgconf.zig",
        },
    };
    const files = try arena.alloc(BuiltFile, 2);
    files[0] = .{ .record = record, .from = "pkgconf.exe", .to = "bin/pkgconf.exe", .file = bin };
    files[1] = .{ .record = record, .from = "pkgconf.exe", .to = "bin/pkg-config.exe", .file = bin };
    return .{ .dir = "usr", .files = files };
}

/// A group directory's SOURCES: conda.zig's writer, run by sources_tool
/// when the directory's files are made, from a spec written now (the
/// copies' lines are known at configure time, a built file's sha256 only
/// once it is built; zig 0.17 has no custom steps).
fn installSources(b: *std.Build, tool: *std.Build.Step.Compile, copies: []const conda.Copy, built: []const BuiltFile, dest: std.Build.InstallDir) !void {
    const arena = b.allocator;
    var records: std.ArrayList(conda.Record) = .empty;
    var ptrs: std.ArrayList(*const conda.Record) = .empty;
    const index = struct {
        fn of(a: mem.Allocator, rs: *std.ArrayList(conda.Record), ps: *std.ArrayList(*const conda.Record), r: *const conda.Record) !u32 {
            if (mem.indexOfScalar(*const conda.Record, ps.items, r)) |i| return @intCast(i);
            // only what SOURCES writes: no files, paths_data or cache path
            try rs.append(a, .{ .name = r.name, .version = r.version, .build = r.build, .url = r.url, .sha256 = r.sha256, .license = r.license, .upstream = r.upstream });
            try ps.append(a, r);
            return @intCast(ps.items.len - 1);
        }
    }.of;
    var spec_copies: std.ArrayList(sources_tool.Spec.Copy) = .empty;
    for (copies) |c| try spec_copies.append(arena, .{
        .record = try index(arena, &records, &ptrs, c.record),
        .from = c.from,
        .to = c.to,
        .sha256 = c.sha256,
        .changed = c.changed,
    });
    for (built, 0..) |f, i| try spec_copies.append(arena, .{
        .record = try index(arena, &records, &ptrs, f.record),
        .from = f.from,
        .to = f.to,
        .built = @intCast(i),
    });
    const spec: sources_tool.Spec = .{ .records = records.items, .copies = spec_copies.items };
    const json = try std.json.Stringify.valueAlloc(arena, spec, .{});
    const run = b.addRunArtifact(tool);
    run.addFileArg(b.addWriteFiles().add("spec.json", json));
    const out = run.addOutputFileArg("SOURCES");
    for (built) |f| run.addFileArg(f.file);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(out, dest, "SOURCES").step);
}

/// A directory of the R tree whose files came from the env (PHASE8 open
/// point F a): every file under `to` (relative to the tree's top), from
/// the same path under the env's `from`; or, `vendored`, vendor-libs.sh's
/// copies, the files directly in `to` whose name the env's `from` has
/// (verify-helpers.sh's vendored_files rule), on Windows only its DLLs.
const BaseDir = struct {
    to: []const u8,
    from: []const u8,
    vendored: bool = false,
    /// What may change a copy here, for its `changed:` line. A copy that
    /// differs from the env's file where this is null stops the build.
    how: ?[]const u8 = null,
};

/// The R tree's records (PHASE8 open points A a, B a, C a, F a; B33 a):
/// <top>/share/licenses/ (Windows: <top>/Library/share/licenses/) gets
/// SOURCES, written by conda.zig's writer as the groups' is, with a
/// `file:` line per file the tree has from the env (each `to` path
/// relative to the tree's top), and <package>/, each package's licence
/// texts (installLicenses). The files: the libraries vendor-libs.sh
/// copied, which zig-build.sh runs before this, and what build.zig's
/// installEnvRuntime installs, the CA bundle, fontconfig's configuration
/// and Tcl/Tk's runtime (BaseDir). A file the env has as a link (the
/// soname links in lib/, conf.d's links into conf.avail) is recorded as
/// the package's file it names. A copy that is not the package's file has
/// a `changed:` line (conda rewrote it at install, vendor-libs.sh stripped
/// or re-linked it, build.zig took the env's directories out of
/// fonts.conf), with the copy's sha256, which verify-tree.sh checks. An
/// earlier run's records go first, as vendor-libs.sh's copies do. The conda
/// build (the prefix is the env) has none: conda keeps every package's
/// licences in its info/.
fn installBase(b: *std.Build, io: std.Io, env: []const u8, prefix: []const u8, prefix_is_env: bool, os: std.Target.Os.Tag) !void {
    const arena = b.allocator;
    if (prefix_is_env) {
        std.debug.print("r-zig: the R tree's records: none (the prefix is the env, whose packages keep their own)\n", .{});
        return;
    }
    const share = if (os == .windows) "Library/share/licenses" else "share/licenses";
    std.Io.Dir.cwd().deleteTree(io, b.fmt("{s}/{s}", .{ prefix, share })) catch |err|
        return fail("cannot remove {s}/{s}, an earlier run's records ({t})", .{ prefix, share, err });
    const lib_how: ?[]const u8 = switch (os) {
        .linux => "strip --strip-debug (vendor-libs.sh)",
        .macos => "install_name_tool -change, codesign (vendor-libs.sh)",
        else => null,
    };
    const dirs: []const BaseDir = if (os == .windows) &.{
        .{ .to = "Library/lib/R/bin/x64", .from = "Library/bin", .vendored = true },
        .{ .to = "Library/lib/R/Tcl/bin", .from = "Library/bin" },
        .{ .to = "Library/lib/R/Tcl/lib", .from = "Library/lib" },
        .{ .to = "Library/lib/R/Tcl/include", .from = "Library/include" },
    } else &.{
        .{ .to = "lib", .from = "lib", .vendored = true, .how = lib_how },
        .{ .to = "ssl", .from = "ssl" },
        .{ .to = "etc/fonts", .from = "etc/fonts", .how = "fonts.conf without the env's directories (build.zig, installFontconfig)" },
        .{ .to = "lib/tcl8.6", .from = "lib/tcl8.6" },
        .{ .to = "lib/tk8.6", .from = "lib/tk8.6" },
        .{ .to = "lib/tcl8", .from = "lib/tcl8" },
    };
    const env_real = try realPath(b, io, env);

    // Each file: its path here, its package's path (the env's link
    // followed) and which directory it is in.
    const File = struct { to: []const u8, from: []const u8, dir: *const BaseDir };
    var files: std.ArrayList(File) = .empty;
    var wanted: std.StringHashMapUnmanaged(void) = .empty;
    for (dirs) |*d| {
        const top = b.fmt("{s}/{s}", .{ prefix, d.to });
        var dir = std.Io.Dir.cwd().openDir(io, top, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue, // not this variant's (fonts, Tcl/Tk)
            else => return fail("cannot read {s} ({t})", .{ top, err }),
        };
        defer dir.close(io);
        var rels: std.ArrayList([]const u8) = .empty;
        if (d.vendored) {
            var it = dir.iterate();
            while (try it.next(io)) |e| {
                // links (lib/libopenblas.so, vendor-libs.sh's) name a copy
                if (e.kind != .file) continue;
                if (os == .windows and !std.ascii.endsWithIgnoreCase(e.name, ".dll")) continue;
                if (!pathExists(io, b.fmt("{s}/{s}/{s}", .{ env, d.from, e.name }))) continue;
                try rels.append(arena, b.dupe(e.name));
            }
        } else {
            var it = try dir.walk(arena);
            defer it.deinit();
            while (try it.next(io)) |e| {
                if (e.kind != .file) continue;
                try rels.append(arena, try mem.replaceOwned(u8, arena, e.path, "\\", "/"));
            }
        }
        for (rels.items) |rel| {
            const real = try realPath(b, io, b.fmt("{s}/{s}/{s}", .{ env, d.from, rel }));
            if (!mem.startsWith(u8, real, env_real) or real.len <= env_real.len or real[env_real.len] != '/')
                return fail("{s}/{s}: the env's {s}/{s} is {s}, outside the env {s}", .{ d.to, rel, d.from, rel, real, env_real });
            const from = real[env_real.len + 1 ..];
            try files.append(arena, .{ .to = b.fmt("{s}/{s}", .{ d.to, rel }), .from = from, .dir = d });
            try wanted.put(arena, from, {});
        }
    }

    // The records that list one of those paths: findInEnv then sees every
    // owner of each (a clobber stops the build), and reads no other.
    var records: std.ArrayList(conda.Record) = .empty;
    for (try readRecords(b, io, env, null)) |r| {
        for (r.files) |f| {
            const path = try mem.replaceOwned(u8, arena, f, "\\", "/");
            if (!wanted.contains(path)) continue;
            try records.append(arena, r);
            break;
        }
    }

    var copies: std.ArrayList(conda.Copy) = .empty;
    var n_changed: usize = 0;
    for (files.items) |f| {
        const found = conda.findInEnv(records.items, f.from, f.to) catch |err| {
            const name = if (conda.owner(records.items, f.from)) |r| r.name else "";
            return switch (err) {
                error.NoOwner => fail("{s} (the env's {s}): no package of the env lists it in conda-meta, so its source and licence are unknown", .{ f.to, f.from }),
                error.TwoOwners => fail("{s} (the env's {s}): two packages of the env list it (a clobber), so which one installed it is unknown", .{ f.to, f.from }),
                error.NotInPathsData, error.NoSha256 => fail("{s} (the env's {s}): {s}'s conda-meta record has no sha256 for it (paths_data)", .{ f.to, f.from, name }),
                error.PrefixPlaceholder => unreachable,
            };
        };
        var copy = found.copy;
        const here = try sha256Hex(b, io, b.fmt("{s}/{s}", .{ prefix, f.to }));
        if (!mem.eql(u8, &here, copy.sha256)) {
            const in_env = try sha256Hex(b, io, b.fmt("{s}/{s}", .{ env, f.from }));
            var how: std.ArrayList(u8) = .empty;
            if (found.rewritten) {
                try how.appendSlice(arena, "conda's prefix at install");
            } else if (!mem.eql(u8, &in_env, copy.sha256)) {
                return fail("{s}: the env's file is not {s}'s (its sha256 differs, and conda does not rewrite it): reinstall the env (pixi reinstall)", .{ f.from, copy.record.name });
            }
            if (!mem.eql(u8, &here, &in_env)) {
                const by = f.dir.how orelse
                    return fail("{s}: not the env's {s}, and nothing that puts it in the tree changes it: rebuild the tree", .{ f.to, f.from });
                try how.print(arena, "{s}{s}", .{ if (how.items.len == 0) "" else "; ", by });
            }
            copy.changed = .{ .how = how.items, .sha256 = b.dupe(&here) };
            n_changed += 1;
        }
        try copies.append(arena, copy);
    }
    if (copies.items.len == 0) return fail("{s}: no file from the env in the tree (run pixi run build first)", .{prefix});

    const dest: std.Build.InstallDir = .{ .custom = share };
    var packages: std.ArrayList(*const conda.Record) = .empty;
    for (copies.items) |c| {
        if (mem.indexOfScalar(*const conda.Record, packages.items, c.record) != null) continue;
        try packages.append(arena, c.record);
    }
    for (records.items) |*r| {
        if (mem.indexOfScalar(*const conda.Record, packages.items, r) == null) continue;
        r.upstream = try readUpstream(b, io, r);
        try installLicenses(b, io, r, dest, r.name);
    }
    var sources: std.Io.Writer.Allocating = .init(arena);
    try conda.writeSources(arena, &sources.writer, copies.items);
    const wf = b.addWriteFiles();
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(wf.add("SOURCES", sources.written()), dest, "SOURCES").step);
    std.debug.print("r-zig: the R tree's records {s}/{s}: {d} files from the env ({d} changed), {d} packages\n", .{
        prefix, share, copies.items.len, n_changed, packages.items.len,
    });
}

fn realPath(b: *std.Build, io: std.Io, p: []const u8) ![]const u8 {
    const real = std.Io.Dir.cwd().realPathFileAlloc(io, p, b.allocator) catch |err|
        return fail("cannot resolve {s} ({t})", .{ p, err });
    return mem.replaceOwned(u8, b.allocator, real, "\\", "/");
}

fn sha256Hex(b: *std.Build, io: std.Io, p: []const u8) ![64]u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, p, b.allocator, .limited(1024 * 1024 * 1024)) catch |err|
        return fail("cannot read {s} ({t})", .{ p, err });
    defer b.allocator.free(data);
    var sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &sha, .{});
    return std.fmt.bytesToHex(sha, .lower);
}

/// zig/ from the wheel fetch-zig unpacked into `dir` (B4; PHASE5 open
/// points A, B, C): ziglang/zig (zig.exe) and ziglang/lib as the wheel has
/// them, the wheel's dist-info licences as LICENSES/ziglang/, and SOURCES,
/// one block in the shape of conda's (one writer, one checker): the
/// wheel's URL and sha256 (fetch-zig's marker), its tag as the build, the
/// version, licence and source repository (`feedstock:`) of its METADATA,
/// the source of its zig (the marker), and a file line per copy with the
/// wheel's sha256 of it (its RECORD). Left out: ziglang/'s Python files,
/// README.md and LICENSE, which LICENSES/ziglang/ has.
fn installZig(b: *std.Build, io: std.Io, dir: []const u8, tc: []const u8, os: std.Target.Os.Tag) !void {
    const arena = b.allocator;
    const dest: std.Build.InstallDir = .{ .custom = b.fmt("{s}/zig", .{tc}) };
    const fetch_how = b.fmt("remove {s} and run pixi run toolchain, whose fetch-zig unpacks the wheel again", .{dir});
    var missing: []const u8 = "";

    const marker_path = b.fmt("{s}/.complete", .{dir});
    const marker = wheel.parseMarker(try readWheelFile(b, io, marker_path), &missing) catch |err| return switch (err) {
        error.MissingField => fail("{s} has no `{s}:` line (fetch-zig.sh writes url, sha256 and source): {s}", .{ marker_path, missing, fetch_how }),
        else => fail("{s}: {t}", .{ marker_path, err }),
    };
    const tag = wheel.tag(marker.url[if (mem.lastIndexOfScalar(u8, marker.url, '/')) |i| i + 1 else 0..]) catch
        return fail("{s}: its url names no wheel ({s})", .{ marker_path, marker.url });

    // The wheel's one dist-info directory.
    var dist_info: ?[]const u8 = null;
    {
        var d = std.Io.Dir.cwd().openDir(io, dir, .{ .iterate = true }) catch |err|
            return fail("cannot read {s} ({t}): -Dziglang names fetch-zig.sh's unpacked wheel", .{ dir, err });
        defer d.close(io);
        var it = d.iterate();
        while (try it.next(io)) |e| {
            if (e.kind != .directory or !mem.startsWith(u8, e.name, "ziglang-") or !mem.endsWith(u8, e.name, ".dist-info")) continue;
            if (dist_info != null) return fail("{s}: two ziglang-*.dist-info directories; {s}", .{ dir, fetch_how });
            dist_info = b.fmt("{s}/{s}", .{ dir, e.name });
        }
    }
    const info = dist_info orelse return fail("{s}: no ziglang-*.dist-info directory; {s}", .{ dir, fetch_how });

    const metadata_path = b.fmt("{s}/METADATA", .{info});
    const metadata = wheel.parseMetadata(try readWheelFile(b, io, metadata_path), &missing) catch |err| return switch (err) {
        error.MissingField => fail("{s} has no {s} header", .{ metadata_path, missing }),
        else => fail("{s}: {t}", .{ metadata_path, err }),
    };
    const record_path = b.fmt("{s}/RECORD", .{info});
    const exe = if (os == .windows) "zig.exe" else "zig";
    const entries = wheel.parseRecord(arena, try readWheelFile(b, io, record_path), exe) catch |err|
        return fail("{s}: not the wheel's RECORD of ziglang/{s} and lib/ ({t})", .{ record_path, exe, err });

    // Every file RECORD lists is there (an unpack that went wrong stops
    // here); one that is there and not listed, verify-toolchain.sh names.
    for (entries) |e| {
        if (!pathExists(io, b.fmt("{s}/{s}", .{ dir, e.from })))
            return fail("{s}/{s} is missing, though the wheel's RECORD lists it; {s}", .{ dir, e.from, fetch_how });
    }

    // zig keeps its mode, as usr/bin/make does; lib/ is one step for its
    // 19,541 files, not one each.
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.graph.cwdRelativePath(b.fmt("{s}/ziglang/{s}", .{ dir, exe })), dest, exe).step);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = b.graph.cwdRelativePath(b.fmt("{s}/ziglang/lib", .{dir})),
        .install_dir = dest,
        .install_subdir = "lib",
    }).step);

    // LICENSES/ziglang/: the wheel's dist-info licences, zig's LICENSE and
    // those of the libraries lib/ bundles (libc++, libc++abi, libunwind,
    // the libcs), as upstream ships them (open point C). None stops the
    // build, as installLicenses does.
    const licenses = b.fmt("{s}/licenses/ziglang", .{info});
    var n: usize = 0;
    {
        var d = std.Io.Dir.cwd().openDir(io, licenses, .{ .iterate = true }) catch |err|
            return fail("ziglang: cannot read {s} ({t}); {s}", .{ licenses, err, fetch_how });
        defer d.close(io);
        var walker = try d.walk(arena);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            if (e.kind == .file) n += 1;
        }
    }
    if (n == 0) return fail("ziglang: no licence files in {s}; {s}", .{ licenses, fetch_how });
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = b.graph.cwdRelativePath(licenses),
        .install_dir = dest,
        .install_subdir = "LICENSES/ziglang",
    }).step);

    // SOURCES from a record of the wheel, by conda.zig's one writer.
    const record = try arena.create(conda.Record);
    record.* = .{
        .name = "ziglang",
        .version = metadata.version,
        .build = tag,
        .url = marker.url,
        .sha256 = marker.sha256,
        .license = metadata.license,
        .upstream = .{ .sources = try arena.dupe(conda.Source, &.{marker.source}), .feedstock = metadata.source_code },
    };
    const copies = try arena.alloc(conda.Copy, entries.len);
    for (entries, copies) |e, *c| c.* = .{ .record = record, .from = e.from, .to = e.to, .sha256 = e.sha256 };
    var sources: std.Io.Writer.Allocating = .init(arena);
    conda.writeSources(arena, &sources.writer, copies) catch |err|
        return fail("ziglang: cannot write zig/SOURCES ({t})", .{err});
    const wf = b.addWriteFiles();
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(wf.add("SOURCES", sources.written()), dest, "SOURCES").step);
}

fn readWheelFile(b: *std.Build, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, b.allocator, .limited(64 * 1024 * 1024)) catch |err|
        return fail("cannot read {s} ({t}): the toolchain tree's zig/ comes from fetch-zig's unpacked wheel", .{ path, err });
}

/// Prints a configure error of this build and returns the error that
/// stops it.
fn fail(comptime fmt: []const u8, args: anytype) error{ToolchainBuild} {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    return error.ToolchainBuild;
}

/// What readRecords looks for in the records, for the directories' files:
/// each file's name, quoted, at the end of a path, or for a tree its
/// `name` so, else the last component of its `from` anywhere (`flang`:
/// every record listing a file under it). No needle holds a separator, so
/// they match Windows' `\` paths and any JSON spacing, and every record
/// that lists a tree's file is read, so conda.find sees a second owner of
/// it (PHASE6 open point W, Cc10).
fn dirNeedles(b: *std.Build, dirs: []const Dir) ![]const []const u8 {
    const arena = b.allocator;
    var needles: std.ArrayList([]const u8) = .empty;
    for (dirs) |d| {
        for (d.copies) |c| {
            const base = c.from[if (mem.lastIndexOfScalar(u8, c.from, '/')) |i| i + 1 else 0..];
            try needles.append(arena, b.fmt("{s}\"", .{base}));
        }
        for (d.trees) |t| {
            if (t.name) |name| {
                try needles.append(arena, b.fmt("{s}\"", .{name}));
            } else {
                const from = mem.trimEnd(u8, t.from, "/");
                try needles.append(arena, from[if (mem.lastIndexOfScalar(u8, from, '/')) |i| i + 1 else 0..]);
            }
        }
    }
    return needles.items;
}

/// The env's conda-meta records whose JSON has one of `needles`, or every
/// record when `needles` is null. Reading only those keeps the toolchain
/// tree's configure step quick (zig's own record alone lists 19,546
/// files); conda.find then matches whole paths.
fn readRecords(b: *std.Build, io: std.Io, env: []const u8, needles: ?[]const []const u8) ![]conda.Record {
    const arena = b.allocator;
    const meta = b.fmt("{s}/conda-meta", .{env});
    var dir = std.Io.Dir.cwd().openDir(io, meta, .{ .iterate = true }) catch |err|
        return fail("cannot read {s} ({t}): the toolchain tree's records come from the env's conda-meta", .{ meta, err });
    defer dir.close(io);
    var records: std.ArrayList(conda.Record) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !mem.endsWith(u8, e.name, ".json")) continue;
        const json = try dir.readFileAlloc(io, e.name, arena, .limited(256 * 1024 * 1024));
        const wanted = if (needles) |ns| for (ns) |n| {
            if (mem.indexOf(u8, json, n) != null) break true;
        } else false else true;
        if (!wanted) continue;
        const r = conda.parse(arena, json) catch |err|
            return fail("{s}/{s}: not a conda-meta record ({t})", .{ meta, e.name, err });
        try records.append(arena, r);
    }
    return records.items;
}

const cache_how = "the toolchain tree copies the licence files and sources from the package cache the env was installed from: reinstall the env (pixi reinstall; in CI, setup-pixi with cache: false)";

/// Where the package's program comes from, as SOURCES says it (P3-C):
/// its recipe's sources, from the rendered recipe in the package cache
/// (rattler-build's info/recipe/rendered_recipe.yaml, else conda-build's
/// info/recipe/meta.yaml), and its feedstock, from info/about.json. A
/// rattler-build output built from a staging output has its sources under
/// finalized_cache_sources, its finalized_sources empty (libglib, which
/// conda-forge's pkg-config loaded until build 10). A GPL package (GPL, LGPL,
/// AGPL) whose recipe lists no source stops the build: its binaries ship
/// only with a pointer to their source.
fn readUpstream(b: *std.Build, io: std.Io, r: *const conda.Record) !conda.Upstream {
    const arena = b.allocator;
    if (r.extracted_package_dir.len == 0)
        return fail("{s}: its conda-meta record names no extracted_package_dir; {s}", .{ r.name, cache_how });
    const info = b.fmt("{s}/info", .{r.extracted_package_dir});
    const about_path = b.fmt("{s}/about.json", .{info});
    const about = std.Io.Dir.cwd().readFileAlloc(io, about_path, arena, .limited(16 * 1024 * 1024)) catch |err|
        return fail("{s}: cannot read {s} ({t}); {s}", .{ r.name, about_path, err, cache_how });
    var u = conda.parseAbout(arena, about) catch |err|
        return fail("{s}: {s} is not an about.json ({t})", .{ r.name, about_path, err });
    for ([_][]const u8{ "rendered_recipe.yaml", "meta.yaml" }) |f| {
        const yaml = std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/recipe/{s}", .{ info, f }), arena, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return fail("{s}: cannot read {s}/recipe/{s} ({t})", .{ r.name, info, f, err }),
        };
        if (mem.eql(u8, f, "meta.yaml")) {
            u.sources = try conda.recipeSources(arena, yaml, "source");
        } else {
            u.sources = try conda.recipeSources(arena, yaml, "finalized_sources");
            if (u.sources.len == 0) u.sources = try conda.recipeSources(arena, yaml, "finalized_cache_sources");
        }
        break;
    }
    if (u.sources.len == 0 and mem.indexOf(u8, r.license, "GPL") != null)
        return fail("{s} ({s}): its recipe in {s}/recipe lists no source, and SOURCES must name the source of a GPL package's binaries", .{ r.name, r.license, info });
    if (!try hasLicenseFiles(b, io, r))
        u.licenses_from = try ownLicenses(b, io, r);
    return u;
}

/// Whether the package's info/licenses/ in the package cache holds a file.
fn hasLicenseFiles(b: *std.Build, io: std.Io, r: *const conda.Record) !bool {
    const src = b.fmt("{s}/info/licenses", .{r.extracted_package_dir});
    var dir = std.Io.Dir.cwd().openDir(io, src, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return fail("{s}: cannot read {s} ({t}); {s}", .{ r.name, src, err, cache_how }),
    };
    defer dir.close(io);
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |e| {
        if (e.kind != .directory) return true;
    }
    return false;
}

/// The licence texts of a package that ships none, r-zig's (PHASE7 open
/// point E a, PHASE8 open point H a): licenses/<name>/ beside this file,
/// taken by hand from the package's source archive for the version its
/// VERSION names: `<version> <build>` (an m2 package: MSYS2's release is
/// in the build), or `<version>` alone where the build differs per
/// platform and the source does not (libgcc, libstdcxx, libfreetype6).
/// Returns the archive's URL, ORIGIN's `source:`, which SOURCES names as
/// where the texts come from. No such directory, or one for another
/// version (a re-lock moved the pin), stops the build.
fn ownLicenses(b: *std.Build, io: std.Io, r: *const conda.Record) ![]const u8 {
    const arena = b.allocator;
    const dir = licensesDir(b, r);
    const how = "its README says how to take them from the package's source archive";
    const version = std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/VERSION", .{dir}), arena, .limited(4096)) catch
        return fail("{s} {s} {s} ships no licence file, and zigbuild/toolchain/licenses/{s}/ does not hold its texts ({s})", .{ r.name, r.version, r.build, r.name, how });
    const got = mem.trim(u8, version, " \t\r\n");
    if (!mem.eql(u8, got, b.fmt("{s} {s}", .{ r.version, r.build })) and !mem.eql(u8, got, r.version))
        return fail("{s} {s} {s} ships no licence file, and zigbuild/toolchain/licenses/{s}/ does not hold its texts: its VERSION is {s} ({s})", .{ r.name, r.version, r.build, r.name, got, how });
    const origin = std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/ORIGIN", .{dir}), arena, .limited(64 * 1024)) catch |err|
        return fail("{s}: cannot read zigbuild/toolchain/licenses/{s}/ORIGIN ({t}); {s}", .{ r.name, r.name, err, how });
    var lines = mem.splitScalar(u8, origin, '\n');
    while (lines.next()) |raw| {
        const l = mem.trimEnd(u8, raw, " \r");
        if (!mem.startsWith(u8, l, "source: ")) continue;
        var words = mem.tokenizeScalar(u8, l["source: ".len..], ' ');
        if (words.next()) |url| return url;
    }
    return fail("{s}: zigbuild/toolchain/licenses/{s}/ORIGIN has no source: line; {s}", .{ r.name, r.name, how });
}

fn licensesDir(b: *std.Build, r: *const conda.Record) []const u8 {
    const root = buildRoot(b, b.graph.io) catch @panic("cannot resolve the build root");
    return b.fmt("{s}/licenses/{s}", .{ root, r.name });
}

/// This build file's directory, absolute, with `/`: zig 0.17's configure
/// step gets it relative to its own working directory (b.root).
fn buildRoot(b: *std.Build, io: std.Io) ![]const u8 {
    return realPath(b, io, b.root.root_dir.path orelse ".");
}

/// `sub` (LICENSES/<package> in a group directory, <package> in the R
/// tree's share/licenses): every file of the package's info/licenses/ in
/// the package cache, subdirectories kept (a link to a file arrives as
/// that file), or for a package that ships none r-zig's texts of it
/// (readUpstream set licenses_from): every file of licenses/<name>/ but
/// its VERSION and ORIGIN. None stops the build: pixi keeps the cache, but
/// an env restored from a CI cache (setup-pixi's `cache: true`) has a
/// record whose directory does not exist (PHASE3 C33, risk 2).
fn installLicenses(b: *std.Build, io: std.Io, r: *const conda.Record, dest: std.Build.InstallDir, sub: []const u8) !void {
    const arena = b.allocator;
    if (r.extracted_package_dir.len == 0)
        return fail("{s}: its conda-meta record names no extracted_package_dir; {s}", .{ r.name, cache_how });
    const own = if (r.upstream) |u| u.licenses_from != null else false;
    const src = if (own) licensesDir(b, r) else b.fmt("{s}/info/licenses", .{r.extracted_package_dir});
    var dir = std.Io.Dir.cwd().openDir(io, src, .{ .iterate = true }) catch |err|
        return fail("{s}: cannot read {s} ({t}); {s}", .{ r.name, src, err, cache_how });
    defer dir.close(io);
    var walker = try dir.walk(arena);
    defer walker.deinit();
    var n: usize = 0;
    while (try walker.next(io)) |e| {
        const from = b.fmt("{s}/{s}", .{ src, e.path });
        switch (e.kind) {
            .file => {},
            .sym_link => {
                const st = std.Io.Dir.cwd().statFile(io, from, .{}) catch continue;
                if (st.kind != .file) continue;
            },
            else => continue,
        }
        const rel = try mem.replaceOwned(u8, arena, e.path, "\\", "/");
        if (own and (mem.eql(u8, rel, "VERSION") or mem.eql(u8, rel, "ORIGIN"))) continue;
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.graph.cwdRelativePath(from), dest, b.fmt("{s}/{s}", .{ sub, rel })).step);
        n += 1;
    }
    if (n == 0) return fail("{s}: no licence files in {s}; {s}", .{ r.name, src, cache_how });
}

/// Whether two paths name the same directory, by real path (build.zig's
/// samePhysicalDir; env.sh's same_dir, which zig-toolchain.sh's fetch and
/// vendor-libs.sh test with, must agree). One that does not resolve, such
/// as a prefix not made yet, names another.
fn samePhysicalDir(io: std.Io, a: mem.Allocator, x: []const u8, y: []const u8) bool {
    const rx = std.Io.Dir.cwd().realPathFileAlloc(io, x, a) catch return false;
    const ry = std.Io.Dir.cwd().realPathFileAlloc(io, y, a) catch return false;
    return mem.eql(u8, rx, ry);
}

fn pathExists(io: std.Io, p: []const u8) bool {
    std.Io.Dir.cwd().access(io, p, .{}) catch return false;
    return true;
}
