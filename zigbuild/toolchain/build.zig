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
//! (B17). `test` runs conda.zig's and wheel.zig's unit tests (pixi run
//! toolchain-test).
//!
//! What it installs, today's third-party files (phase 3's table, zig/ from
//! phase 5):
//!   zig/       compilers    upstream zig, PyPI's ziglang wheel as
//!                           fetch-zig pins it (B4, phase 5): zig and
//!                           lib/, LICENSES/ziglang/ from the wheel's
//!                           dist-info, SOURCES from its RECORD
//!   openmp/    compilers    llvm-openmp's omp.h and the headers beside it
//!                           (B22); Windows also libomp.lib
//!   usr/       build-tools  unix: conda-forge's GNU make as usr/bin/make
//!                           (B7, B23)
//!   binutils/  build-tools  Windows: conda-forge's MinGW nm, dlltool, as,
//!                           strip, windres and objdump (B24, B43), with
//!                           the conda DLLs they load
//! flang/ (compilers) comes in phase 6, Windows' usr/bin in phase 7.
//! Which group holds which directory: scripts/env.sh's group_dirs.
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
//! R's own build (build.zig) never reads the package cache. zig/'s files
//! are the wheel's, each with the wheel's own sha256 of it (its RECORD,
//! the counterpart of paths_data), in a SOURCES block of the same shape
//! (wheel.zig; PHASE5 open points A, B, C): the wheel's URL and sha256
//! and the source of its zig come from fetch-zig's marker, which
//! scripts/zig-toolchain.sh passes the directory of as -Dziglang=<dir>.
//!
//! The conda build (recipe/build.sh, from step 3) runs this into the env
//! itself, with R_TOOLCHAIN_PREFIX=$PREFIX: there conda's own packages
//! provide every file where it is looked for, except Windows' binutils,
//! which Makeconf.win names by path under R_HOME (B24): only those are
//! installed, with their records (B41). No zig/ there: conda keeps
//! conda-forge's zig, through r-zig-compilers (B30), and the conda build
//! fetches nothing (PHASE5 open point J; zig-toolchain.sh skips fetch-zig
//! by the same test as prefix_is_env below).
const std = @import("std");
const mem = std.mem;
const conda = @import("conda.zig");
const wheel = @import("wheel.zig");

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

    const test_step = b.step("test", "Run the conda-meta and wheel readers' and SOURCES writer's unit tests");
    for ([_][]const u8{ "conda.zig", "wheel.zig" }) |root| {
        const tests = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(root),
            .target = b.graph.host,
        }) });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
    const ziglang = b.option([]const u8, "ziglang", "PyPI's ziglang wheel, unpacked (scripts/fetch-zig.sh's directory): the compilers group's zig/");

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
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = b.fmt("{s}/ziglang/{s}", .{ dir, exe }) }, dest, exe).step);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = .{ .cwd_relative = b.fmt("{s}/ziglang/lib", .{dir}) },
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
        .source_dir = .{ .cwd_relative = licenses },
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
