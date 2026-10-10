//! The toolchain tree (feat-standalone-toolchain B30; PHASE3 open point A
//! (a)): the toolchain groups' third-party files, copied unchanged from
//! the env R is built in (CONDA_PREFIX) into
//! <prefix>/lib/R/bin/toolchain/<dir>/ (Windows:
//! <prefix>/Library/lib/R/bin/toolchain/<dir>/), each directory with
//! SOURCES and LICENSES/ (point 3). Its own build root, as rzig's is:
//!   zig build --build-file zigbuild/toolchain/build.zig --prefix <tree>
//! needs no R source and runs no R configure. scripts/zig-toolchain.sh
//! (pixi run toolchain) installs dist/toolchain/R-<ver>-zig with it, and
//! package-standalone.sh's toolchain mode archives the groups from there
//! (B17). `test` runs conda.zig's unit tests (pixi run toolchain-test).
//!
//! What phase 3 installs, today's third-party files (the plan's table):
//!   openmp/    compilers    llvm-openmp's omp.h and the headers beside it
//!                           (B22); Windows also libomp.lib
//!   usr/       build-tools  unix: conda-forge's GNU make as usr/bin/make
//!                           (B7, B23)
//!   binutils/  build-tools  Windows: conda-forge's MinGW nm, dlltool, as,
//!                           strip, windres and objdump (B24, B43), with
//!                           the conda DLLs they load
//! zig/ and flang/ (compilers) come in phases 5 and 6, Windows' usr/bin
//! in phase 7. Which group holds which directory: scripts/env.sh's
//! group_dirs.
//!
//! Each file's package is the conda-meta record whose `files` lists its
//! path (conda.zig). SOURCES names the package, its URL and sha256, where
//! its program comes from (its recipe's sources, P3-C) and the feedstock
//! that built it, and each file with the package's sha256 of it;
//! LICENSES/<package>/ is the package's info/licenses/. Both come from the
//! package cache the env was installed from (the record's
//! extracted_package_dir). A file no record lists, one with a prefix
//! placeholder (conda rewrote it), a package with no licence files, or a
//! GPL one whose recipe lists no source stops this build and names it.
//! R's own build (build.zig) never reads the package cache.
//!
//! The conda build (recipe/build.sh, from step 3) runs this into the env
//! itself, with R_TOOLCHAIN_PREFIX=$PREFIX: there conda's own packages
//! provide every file where it is looked for, except Windows' binutils,
//! which Makeconf.win names by path under R_HOME (B24): only those are
//! installed, with their records (B41).
const std = @import("std");
const mem = std.mem;
const conda = @import("conda.zig");

/// A file a directory copies from the env.
const Copy = struct {
    /// In the env, relative to its prefix: the path in its package.
    from: []const u8,
    /// In the directory.
    to: []const u8,
    /// A missing file stops the build; an optional one is left out.
    required: bool = true,
    /// Installed when the prefix is the env too (the conda build, B41).
    in_conda: bool = false,
};

/// A group directory under R_HOME/bin/toolchain and what it copies.
const Dir = struct {
    name: []const u8,
    copies: []const Copy,
};

/// llvm-openmp's headers: omp.h, which makes rzig add -lomp to a -fopenmp
/// link, and the ones beside it where the env has them (win-64's
/// llvm-openmp ships only omp.h and ompx.h): build.zig's installOpenMP
/// list, into openmp/include, where rzig looks (B22, B40).
fn ompHeaders(comptime include: []const u8) [4]Copy {
    return .{
        .{ .from = include ++ "omp.h", .to = "include/omp.h" },
        .{ .from = include ++ "ompx.h", .to = "include/ompx.h", .required = false },
        .{ .from = include ++ "omp-tools.h", .to = "include/omp-tools.h", .required = false },
        .{ .from = include ++ "ompt.h", .to = "include/ompt.h", .required = false },
    };
}

const unix_dirs = [_]Dir{
    .{ .name = "openmp", .copies = &ompHeaders("include/") },
    .{ .name = "usr", .copies = &.{.{ .from = "bin/make", .to = "bin/make" }} },
};

/// The binutils Makeconf.win names (B24, B43), under their own names; ar
/// and ranlib are rzig's (B43), ld is named nowhere. They ship only under
/// the x86_64-w64-mingw32- prefix.
fn mingwTool(comptime t: []const u8) Copy {
    return .{ .from = "Library/bin/x86_64-w64-mingw32-" ++ t ++ ".exe", .to = t ++ ".exe", .in_conda = true };
}

const windows_dirs = [_]Dir{
    .{ .name = "openmp", .copies = &(ompHeaders("Library/include/") ++ [_]Copy{
        .{ .from = "Library/lib/libomp.lib", .to = "lib/libomp.lib" },
    }) },
    .{
        .name = "binutils",
        .copies = &[_]Copy{
            mingwTool("nm"),
            mingwTool("dlltool"),
            mingwTool("as"),
            mingwTool("strip"),
            mingwTool("windres"),
            mingwTool("objdump"),
            // The conda DLLs those load, so that they load with nothing beside
            // them but the system (binutils_impl_win-64 2.46.1 and zstd 1.5.7,
            // read with objdump -p on 2026-10-10; every other import is
            // KERNEL32 or an API set): the six import zstd.dll, and zstd.dll
            // imports VCRUNTIME140.dll (vc14_runtime). verify-toolchain.sh
            // checks the closure. In the conda build their packages provide
            // them in Library/bin, on PATH.
            .{ .from = "Library/bin/zstd.dll", .to = "zstd.dll" },
            .{ .from = "Library/bin/vcruntime140.dll", .to = "vcruntime140.dll" },
        },
    },
};

pub fn build(b: *std.Build) !void {
    const arena = b.allocator;
    const io = b.graph.io;

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("conda.zig"),
        .target = b.graph.host,
    }) });
    b.step("test", "Run the conda-meta reader's and SOURCES writer's unit tests").dependOn(&b.addRunArtifact(tests).step);

    const env = b.graph.environ_map.get("CONDA_PREFIX") orelse
        return fail("CONDA_PREFIX is not set: run through pixi (pixi run toolchain)", .{});
    const os = b.graph.host.result.os.tag;
    const prefix = try mem.replaceOwned(u8, arena, b.install_prefix, "\\", "/");
    const prefix_is_env = samePhysicalDir(io, arena, prefix, env);
    const tc = if (os == .windows) "Library/lib/R/bin/toolchain" else "lib/R/bin/toolchain";
    const dirs: []const Dir = if (os == .windows) &windows_dirs else &unix_dirs;

    const records = try readRecords(b, io, env, dirs);
    var summary: std.ArrayList(u8) = .empty;
    for (dirs) |d| {
        const dest: std.Build.InstallDir = .{ .custom = b.fmt("{s}/{s}", .{ tc, d.name }) };
        var copies: std.ArrayList(conda.Copy) = .empty;
        for (d.copies) |c| {
            if (prefix_is_env and !c.in_conda) continue;
            const src = b.fmt("{s}/{s}", .{ env, c.from });
            if (!pathExists(io, src)) {
                if (!c.required) continue;
                return fail("{s} is missing from the env {s}: the toolchain tree's {s}/ copies it", .{ c.from, env, d.name });
            }
            const copy = conda.find(records, c.from, c.to) catch |err| {
                const name = if (conda.owner(records, c.from)) |r| r.name else "";
                return switch (err) {
                    error.NoOwner => fail("{s}: no package of the env lists it in conda-meta, so its source and licence are unknown", .{c.from}),
                    error.TwoOwners => fail("{s}: two packages of the env list it (a clobber), so which one installed it is unknown", .{c.from}),
                    error.NotInPathsData, error.NoSha256 => fail("{s}: {s}'s conda-meta record has no sha256 for it (paths_data)", .{ c.from, name }),
                    error.PrefixPlaceholder => fail("{s}: conda rewrote it at install ({s} has a prefix placeholder in it), so the env's file names the env and is not the package's", .{ c.from, name }),
                };
            };
            try copies.append(arena, copy);
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = src }, dest, c.to).step);
        }
        if (copies.items.len == 0) continue;
        for (records) |*r| {
            if (r.upstream != null) continue;
            for (copies.items) |c| {
                if (c.record == r) {
                    r.upstream = try readUpstream(b, io, r);
                    break;
                }
            }
        }

        var sources: std.Io.Writer.Allocating = .init(arena);
        try conda.writeSources(arena, &sources.writer, copies.items);
        const wf = b.addWriteFiles();
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(wf.add("SOURCES", sources.written()), dest, "SOURCES").step);

        try summary.print(arena, "{s}{s}/ (", .{ if (summary.items.len == 0) "" else ", ", d.name });
        var packages: std.ArrayList(*const conda.Record) = .empty;
        for (copies.items) |c| {
            if (mem.indexOfScalar(*const conda.Record, packages.items, c.record) != null) continue;
            if (packages.items.len > 0) try summary.appendSlice(arena, ", ");
            try installLicenses(b, io, c.record, dest);
            try summary.appendSlice(arena, c.record.name);
            try packages.append(arena, c.record);
        }
        try summary.appendSlice(arena, ")");
    }
    std.debug.print("r-zig: toolchain tree {s}: {s}{s}\n", .{
        prefix,
        if (summary.items.len == 0) "nothing to install" else summary.items,
        if (prefix_is_env) " (the prefix is the env)" else "",
    });
}

/// Prints a configure error of this build and returns the error that
/// stops it.
fn fail(comptime fmt: []const u8, args: anytype) error{ToolchainBuild} {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    return error.ToolchainBuild;
}

/// The env's conda-meta records that may own a file the directories copy:
/// those whose JSON has one of the files' names, quoted, at the end of a
/// path. Reading only those keeps the configure step quick (zig's own
/// record alone lists 19,546 files); conda.find then matches whole paths.
fn readRecords(b: *std.Build, io: std.Io, env: []const u8, dirs: []const Dir) ![]conda.Record {
    const arena = b.allocator;
    var needles: std.ArrayList([]const u8) = .empty;
    for (dirs) |d| {
        for (d.copies) |c| {
            const base = c.from[if (mem.lastIndexOfScalar(u8, c.from, '/')) |i| i + 1 else 0..];
            try needles.append(arena, b.fmt("{s}\"", .{base}));
        }
    }
    const meta = b.fmt("{s}/conda-meta", .{env});
    var dir = std.Io.Dir.cwd().openDir(io, meta, .{ .iterate = true }) catch |err|
        return fail("cannot read {s} ({t}): the toolchain tree's records come from the env's conda-meta", .{ meta, err });
    defer dir.close(io);
    var records: std.ArrayList(conda.Record) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !mem.endsWith(u8, e.name, ".json")) continue;
        const json = try dir.readFileAlloc(io, e.name, arena, .limited(256 * 1024 * 1024));
        for (needles.items) |n| {
            if (mem.indexOf(u8, json, n) == null) continue;
            const r = conda.parse(arena, json) catch |err|
                return fail("{s}/{s}: not a conda-meta record ({t})", .{ meta, e.name, err });
            try records.append(arena, r);
            break;
        }
    }
    return records.items;
}

const cache_how = "the toolchain tree copies the licence files and sources from the package cache the env was installed from: reinstall the env (pixi reinstall; in CI, setup-pixi with cache: false)";

/// Where the package's program comes from, as SOURCES says it (P3-C):
/// its recipe's sources, from the rendered recipe in the package cache
/// (rattler-build's info/recipe/rendered_recipe.yaml, else conda-build's
/// info/recipe/meta.yaml), and its feedstock, from info/about.json. A GPL
/// package (GPL, LGPL, AGPL) whose recipe lists no source stops the
/// build: its binaries ship only with a pointer to their source.
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
    for ([_][2][]const u8{ .{ "rendered_recipe.yaml", "finalized_sources" }, .{ "meta.yaml", "source" } }) |f| {
        const yaml = std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/recipe/{s}", .{ info, f[0] }), arena, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return fail("{s}: cannot read {s}/recipe/{s} ({t})", .{ r.name, info, f[0], err }),
        };
        u.sources = try conda.recipeSources(arena, yaml, f[1]);
        break;
    }
    if (u.sources.len == 0 and mem.indexOf(u8, r.license, "GPL") != null)
        return fail("{s} ({s}): its recipe in {s}/recipe lists no source, and SOURCES must name the source of a GPL package's binaries", .{ r.name, r.license, info });
    return u;
}

/// LICENSES/<package>/: every file of the package's info/licenses/ in the
/// package cache, subdirectories kept (a link to a file arrives as that
/// file). None stops the build: pixi keeps the cache, but an env restored
/// from a CI cache (setup-pixi's `cache: true`) has a record whose
/// directory does not exist (PHASE3 C33, risk 2).
fn installLicenses(b: *std.Build, io: std.Io, r: *const conda.Record, dest: std.Build.InstallDir) !void {
    const arena = b.allocator;
    if (r.extracted_package_dir.len == 0)
        return fail("{s}: its conda-meta record names no extracted_package_dir; {s}", .{ r.name, cache_how });
    const src = b.fmt("{s}/info/licenses", .{r.extracted_package_dir});
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
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = from }, dest, b.fmt("LICENSES/{s}/{s}", .{ r.name, rel })).step);
        n += 1;
    }
    if (n == 0) return fail("{s}: no licence files in {s}; {s}", .{ r.name, src, cache_how });
}

/// Whether two paths name the same directory, by real path (build.zig's
/// samePhysicalDir, the test vendor-libs.sh's `pwd -P` makes). One that
/// does not resolve, such as a prefix not made yet, names another.
fn samePhysicalDir(io: std.Io, a: mem.Allocator, x: []const u8, y: []const u8) bool {
    const rx = std.Io.Dir.cwd().realPathFileAlloc(io, x, a) catch return false;
    const ry = std.Io.Dir.cwd().realPathFileAlloc(io, y, a) catch return false;
    return mem.eql(u8, rx, ry);
}

fn pathExists(io: std.Io, p: []const u8) bool {
    std.Io.Dir.cwd().access(io, p, .{}) catch return false;
    return true;
}
