//! The toolchain build's conda-meta reader and SOURCES writer
//! (feat-standalone-toolchain point 3, B30): which conda package each file
//! a group directory copies from the env comes from, found by its path in
//! the records (CRITIQUE.md C23: by path, never by a guessed package
//! name), and the SOURCES text that says so. No I/O here: build.zig beside
//! this file reads conda-meta and installs the files, and
//! `zig build --build-file zigbuild/toolchain/build.zig test` (pixi run
//! toolchain-test) runs the tests below on fixture records.
const std = @import("std");
const mem = std.mem;

/// A record of the env's conda-meta/, `<name>-<version>-<build>.json`, as
/// pixi (rattler) and rattler-build write it: the fields SOURCES and
/// LICENSES need. Every other field is ignored.
pub const Record = struct {
    name: []const u8,
    version: []const u8,
    build: []const u8,
    url: []const u8 = "",
    /// The package archive's.
    sha256: []const u8 = "",
    license: []const u8 = "",
    /// The package's directory in the package cache, whose info/licenses/
    /// LICENSES copies. A path of this machine: never written to SOURCES.
    extracted_package_dir: []const u8 = "",
    /// Every path the package installed, relative to the env.
    files: []const []const u8 = &.{},
    paths_data: PathsData = .{},

    pub const PathsData = struct {
        paths: []const Path = &.{},
    };

    /// One file of the package (its info/paths.json entry).
    pub const Path = struct {
        _path: []const u8,
        /// The file's, as the package has it.
        sha256: ?[]const u8 = null,
        /// Set when conda rewrites the file at install, replacing the build
        /// prefix with the env's: the env's file is then not the package's.
        prefix_placeholder: ?[]const u8 = null,
    };
};

/// A conda-meta record from its JSON. `arena` owns the result.
pub fn parse(arena: mem.Allocator, json: []const u8) !Record {
    return std.json.parseFromSliceLeaky(Record, arena, json, .{ .ignore_unknown_fields = true });
}

/// Paths as conda-meta writes them, with `/` (a Windows record may use
/// `\`): equal when they are equal with every `\` read as `/`.
fn samePath(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if ((if (x == '\\') '/' else x) != (if (y == '\\') '/' else y)) return false;
    }
    return true;
}

/// The record whose `files` lists `path` (relative to the env), if any.
pub fn owner(records: []const Record, path: []const u8) ?*const Record {
    for (records) |*r| {
        for (r.files) |f| {
            if (samePath(f, path)) return r;
        }
    }
    return null;
}

/// One file a group directory copies from the env, as SOURCES records it.
pub const Copy = struct {
    record: *const Record,
    /// Its path in the package, which is its path in the env.
    from: []const u8,
    /// Its path in the directory.
    to: []const u8,
    /// The package's sha256 of it, which the copy has: no prefix
    /// placeholder, so conda installed it unchanged.
    sha256: []const u8,
};

pub const Error = error{
    /// No record lists the file: it is not a conda package's.
    NoOwner,
    /// Two records list it (a clobber): which one installed it is unknown.
    TwoOwners,
    /// Its record lists it in `files` but has no paths_data entry for it.
    NotInPathsData,
    /// Its paths_data entry has no sha256.
    NoSha256,
    /// conda rewrote it at install (a prefix placeholder): the env's file
    /// names the env and is not the package's.
    PrefixPlaceholder,
};

/// The file `from` (relative to the env) copied as `to`: its owner, found
/// by path, and its sha256 from the owner's paths_data.
pub fn find(records: []const Record, from: []const u8, to: []const u8) Error!Copy {
    const r = owner(records, from) orelse return error.NoOwner;
    for (records) |*o| {
        if (o == r) continue;
        for (o.files) |f| {
            if (samePath(f, from)) return error.TwoOwners;
        }
    }
    for (r.paths_data.paths) |p| {
        if (!samePath(p._path, from)) continue;
        if (p.prefix_placeholder != null) return error.PrefixPlaceholder;
        return .{ .record = r, .from = from, .to = to, .sha256 = p.sha256 orelse return error.NoSha256 };
    }
    return error.NotInPathsData;
}

fn copyLess(_: void, a: Copy, b: Copy) bool {
    return switch (mem.order(u8, a.record.name, b.record.name)) {
        .lt => true,
        .gt => false,
        .eq => mem.lessThan(u8, a.to, b.to),
    };
}

/// SOURCES, plain text: one block per package (by name), its fields, then
/// a `file:` line per copy (by its path here), the path in the package, the
/// path here (relative to the directory SOURCES is in) and the sha256 of
/// both; a blank line between blocks. verify-toolchain.sh reads the `file:`
/// lines as five space-separated fields, so a path with a blank is refused.
pub fn writeSources(gpa: mem.Allocator, w: *std.Io.Writer, copies: []const Copy) !void {
    const sorted = try gpa.dupe(Copy, copies);
    defer gpa.free(sorted);
    std.mem.sort(Copy, sorted, {}, copyLess);
    var last: ?*const Record = null;
    for (sorted) |c| {
        if (mem.indexOfAny(u8, c.from, " \t\r\n") != null or mem.indexOfAny(u8, c.to, " \t\r\n") != null)
            return error.BlankInPath;
        if (last != c.record) {
            if (last != null) try w.writeByte('\n');
            const r = c.record;
            try w.print("package: {s}\nversion: {s}\nbuild: {s}\nurl: {s}\nsha256: {s}\nlicense: {s}\n", .{ r.name, r.version, r.build, r.url, r.sha256, r.license });
            last = r;
        }
        try w.print("file: {s} -> {s} {s}\n", .{ c.from, c.to, c.sha256 });
    }
}

// --- tests: fixture records, as pixi writes them (fields trimmed) -------

const make_json =
    \\{
    \\  "arch": "x86_64", "build": "hb03c661_3", "build_number": 3,
    \\  "depends": ["__glibc >=2.17,<3.0.a0", "libgcc >=14"],
    \\  "extracted_package_dir": "/home/u/.cache/rattler/cache/pkgs/make-4.4.1-hb03c661_3",
    \\  "files": ["bin/make", "include/gnumake.h", "share/info/make.info"],
    \\  "fn": "make-4.4.1-hb03c661_3.conda", "license": "GPL-3.0-or-later",
    \\  "link": {"source": "/home/u/.cache/rattler/cache/pkgs/make-4.4.1-hb03c661_3", "type": 1},
    \\  "name": "make",
    \\  "paths_data": {"paths_version": 1, "paths": [
    \\    {"_path": "bin/make", "path_type": "hardlink", "sha256": "8a9d", "size_in_bytes": 313656},
    \\    {"_path": "include/gnumake.h", "path_type": "hardlink", "sha256": "3e38", "size_in_bytes": 2913}
    \\  ]},
    \\  "sha256": "4c65", "url": "https://conda.anaconda.org/conda-forge/linux-64/make-4.4.1-hb03c661_3.conda",
    \\  "version": "4.4.1"
    \\}
;

const openmp_json =
    \\{
    \\  "build": "h7148c6a_0", "name": "llvm-openmp", "version": "23.1.2",
    \\  "license": "Apache-2.0 WITH LLVM-exception", "sha256": "2926",
    \\  "url": "https://conda.anaconda.org/conda-forge/linux-64/llvm-openmp-23.1.2-h7148c6a_0.conda",
    \\  "files": ["include\\omp.h", "include/ompx.h", "lib/libomp.so"],
    \\  "paths_data": {"paths": [
    \\    {"_path": "include/omp.h", "sha256": "4066"},
    \\    {"_path": "include/ompx.h", "sha256": "615f"},
    \\    {"_path": "lib/libomp.so", "file_mode": "binary", "prefix_placeholder": "/opt/conda-bld/placehold", "sha256": "aaaa"}
    \\  ]}
    \\}
;

fn fixtures(arena: mem.Allocator) ![2]Record {
    return .{ try parse(arena, make_json), try parse(arena, openmp_json) };
}

test "a record: the fields SOURCES and LICENSES need, the rest ignored" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const r = try parse(a.allocator(), make_json);
    try std.testing.expectEqualStrings("make", r.name);
    try std.testing.expectEqualStrings("hb03c661_3", r.build);
    try std.testing.expectEqualStrings("/home/u/.cache/rattler/cache/pkgs/make-4.4.1-hb03c661_3", r.extracted_package_dir);
    try std.testing.expectEqual(@as(usize, 3), r.files.len);
    try std.testing.expectEqual(@as(usize, 2), r.paths_data.paths.len);
    try std.testing.expectEqualStrings("8a9d", r.paths_data.paths[0].sha256.?);
    // a record without paths_data, licence or url parses (and finds nothing)
    const bare = try parse(a.allocator(), "{\"name\": \"x\", \"version\": \"1\", \"build\": \"0\", \"files\": [\"bin/x\"]}");
    try std.testing.expectEqual(@as(usize, 0), bare.paths_data.paths.len);
    try std.testing.expectError(error.NotInPathsData, find(&.{bare}, "bin/x", "bin/x"));
}

test "find: the owner by path, the sha256 from its paths_data" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const rs = try fixtures(a.allocator());
    const c = try find(&rs, "bin/make", "bin/make");
    try std.testing.expectEqualStrings("make", c.record.name);
    try std.testing.expectEqualStrings("8a9d", c.sha256);
    // a Windows record's `\` matches the `/` asked for
    const h = try find(&rs, "include/omp.h", "include/omp.h");
    try std.testing.expectEqualStrings("llvm-openmp", h.record.name);
    try std.testing.expectEqualStrings("4066", h.sha256);
}

test "find: a file in no record, one missing from paths_data, a prefix placeholder" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const rs = try fixtures(a.allocator());
    try std.testing.expectError(error.NoOwner, find(&rs, "bin/gmake", "bin/make"));
    try std.testing.expectEqual(@as(?*const Record, null), owner(&rs, "bin/gmake"));
    try std.testing.expectError(error.NotInPathsData, find(&rs, "share/info/make.info", "x"));
    try std.testing.expectError(error.PrefixPlaceholder, find(&rs, "lib/libomp.so", "lib/libomp.so"));
}

test "SOURCES: one block per package by name, its files by their path here" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const rs = try fixtures(a.allocator());
    const copies = [_]Copy{
        try find(&rs, "include/ompx.h", "include/ompx.h"),
        try find(&rs, "bin/make", "bin/make"),
        try find(&rs, "include/omp.h", "include/omp.h"),
    };
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeSources(std.testing.allocator, &aw.writer, &copies);
    try std.testing.expectEqualStrings(
        \\package: llvm-openmp
        \\version: 23.1.2
        \\build: h7148c6a_0
        \\url: https://conda.anaconda.org/conda-forge/linux-64/llvm-openmp-23.1.2-h7148c6a_0.conda
        \\sha256: 2926
        \\license: Apache-2.0 WITH LLVM-exception
        \\file: include/omp.h -> include/omp.h 4066
        \\file: include/ompx.h -> include/ompx.h 615f
        \\
        \\package: make
        \\version: 4.4.1
        \\build: hb03c661_3
        \\url: https://conda.anaconda.org/conda-forge/linux-64/make-4.4.1-hb03c661_3.conda
        \\sha256: 4c65
        \\license: GPL-3.0-or-later
        \\file: bin/make -> bin/make 8a9d
        \\
    , aw.written());
    // no path of this machine: extracted_package_dir is not written
    try std.testing.expect(mem.indexOf(u8, aw.written(), "/home/u") == null);
}

test "SOURCES: a path with a blank is refused" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const rs = try fixtures(a.allocator());
    const c = try find(&rs, "bin/make", "bin/g make");
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try std.testing.expectError(error.BlankInPath, writeSources(std.testing.allocator, &aw.writer, &.{c}));
}
