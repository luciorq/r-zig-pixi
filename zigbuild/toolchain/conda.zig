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
    /// Not conda-meta's: read from the package cache by build.zig
    /// (readUpstream), for SOURCES.
    upstream: ?Upstream = null,

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

/// Where a package's program comes from and the recipe that built it, as
/// the package cache has them (the package's info/): its recipe's sources
/// and the feedstock, the repository and commit of that recipe, whose
/// patches the sources take.
pub const Upstream = struct {
    sources: []const Source = &.{},
    /// about.json's extra.remote_url and extra.sha.
    feedstock: []const u8 = "",
    commit: []const u8 = "",
};

/// One source of a recipe: a URL (the first of its mirrors) and its
/// checksum, or a git repository and its revision.
pub const Source = struct {
    url: []const u8 = "",
    sha256: []const u8 = "",
    md5: []const u8 = "",
    git: []const u8 = "",
    rev: []const u8 = "",
};

/// The feedstock of a package's info/about.json. `arena` owns the result.
pub fn parseAbout(arena: mem.Allocator, json: []const u8) !Upstream {
    const About = struct {
        extra: ?struct {
            remote_url: ?[]const u8 = null,
            sha: ?[]const u8 = null,
        } = null,
    };
    const a = try std.json.parseFromSliceLeaky(About, arena, json, .{ .ignore_unknown_fields = true });
    const e = a.extra orelse return .{};
    return .{ .feedstock = e.remote_url orelse "", .commit = e.sha orelse "" };
}

/// The sources of a rendered recipe: the top-level block `key:` of
/// conda-build's info/recipe/meta.yaml (`source`) or rattler-build's
/// info/recipe/rendered_recipe.yaml (`finalized_sources`), one mapping or
/// a list of them. Both tools write that YAML themselves, in block style,
/// so a line scanner reads it: each entry's url (the first of a list of
/// mirrors), sha256 and md5, or git_url (git) and git_rev (rev, tag). An
/// entry with neither a url nor a repository (a path source) is left out.
pub fn recipeSources(arena: mem.Allocator, yaml: []const u8, key: []const u8) ![]const Source {
    var lines = mem.splitScalar(u8, yaml, '\n');
    while (lines.next()) |raw| {
        const l = mem.trimEnd(u8, raw, " \r");
        if (l.len == key.len + 1 and mem.startsWith(u8, l, key) and l[key.len] == ':') break;
    } else return &.{};
    var out: std.ArrayList(Source) = .empty;
    var cur: ?Source = null;
    // The column of an entry's keys, and of a list's `-`.
    var key_col: ?usize = null;
    var dash_col: ?usize = null;
    // The key whose value is the list that follows (url: its mirrors).
    var list_key: []const u8 = "";
    while (lines.next()) |raw| {
        const l = mem.trimEnd(u8, raw, " \r");
        const indent = mem.indexOfNone(u8, l, " ") orelse continue;
        if (indent == 0 and l[0] != '-') break;
        var s = l[indent..];
        if (s[0] == '-' and (s.len == 1 or s[1] == ' ')) {
            if (dash_col == null and key_col == null) dash_col = indent;
            if (dash_col == null or indent != dash_col.?) {
                if (mem.eql(u8, list_key, "url") and cur.?.url.len == 0)
                    cur.?.url = unquote(mem.trim(u8, s[1..], " "));
                continue;
            }
            if (cur) |c| try out.append(arena, c);
            cur = .{};
            s = mem.trimStart(u8, s[1..], " ");
            key_col = l.len - s.len;
            if (s.len == 0) continue;
        } else if (key_col == null) {
            key_col = indent;
            cur = .{};
        } else if (indent != key_col.?) continue;
        const colon = mem.indexOfScalar(u8, s, ':') orelse continue;
        const k = s[0..colon];
        const v = unquote(mem.trim(u8, s[colon + 1 ..], " "));
        list_key = if (v.len == 0) k else "";
        const c = &cur.?;
        if (mem.eql(u8, k, "url")) {
            c.url = v;
        } else if (mem.eql(u8, k, "sha256")) {
            c.sha256 = v;
        } else if (mem.eql(u8, k, "md5")) {
            c.md5 = v;
        } else if (mem.eql(u8, k, "git_url") or mem.eql(u8, k, "git")) {
            c.git = v;
        } else if (mem.eql(u8, k, "git_rev") or mem.eql(u8, k, "rev") or mem.eql(u8, k, "tag")) {
            c.rev = v;
        }
    }
    if (cur) |c| try out.append(arena, c);
    var n: usize = 0;
    for (out.items) |c| {
        if (c.url.len == 0 and c.git.len == 0) continue;
        out.items[n] = c;
        n += 1;
    }
    return out.items[0..n];
}

fn unquote(v: []const u8) []const u8 {
    if (v.len >= 2 and (v[0] == '\'' or v[0] == '"') and v[v.len - 1] == v[0]) return v[1 .. v.len - 1];
    return v;
}

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
/// where its program comes from (its upstream, when read): a `source:`
/// line per source of its recipe, the URL and `sha256:`/`md5:` checksum
/// or the repository and `rev:`, and a `feedstock:` line, the recipe's
/// repository and commit (`unknown` when the package has none); then a
/// `file:` line per copy (by its path here), the path in the package, the
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
            if (r.upstream) |u| try writeUpstream(w, u);
            last = r;
        }
        try w.print("file: {s} -> {s} {s}\n", .{ c.from, c.to, c.sha256 });
    }
}

fn writeUpstream(w: *std.Io.Writer, u: Upstream) !void {
    for (u.sources) |s| {
        if (s.url.len > 0) {
            try w.print("source: {s}", .{s.url});
            if (s.sha256.len > 0) {
                try w.print(" sha256:{s}", .{s.sha256});
            } else if (s.md5.len > 0) {
                try w.print(" md5:{s}", .{s.md5});
            }
        } else {
            try w.print("source: {s}", .{s.git});
            if (s.rev.len > 0) try w.print(" rev:{s}", .{s.rev});
        }
        try w.writeByte('\n');
    }
    if (u.sources.len == 0) try w.writeAll("source: unknown (the package's recipe lists none)\n");
    if (u.feedstock.len == 0) {
        try w.writeAll("feedstock: unknown (the package's about.json names none)\n");
    } else {
        try w.print("feedstock: {s}{s}{s}\n", .{ u.feedstock, if (u.commit.len == 0) "" else " ", u.commit });
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

test "SOURCES: one block per package by name, its upstream, its files by their path here" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    var rs = try fixtures(a.allocator());
    rs[0].upstream = .{
        .sources = &.{.{ .url = "https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz", .sha256 = "dd16" }},
        .feedstock = "https://github.com/conda-forge/make-feedstock",
        .commit = "1060",
    };
    rs[1].upstream = .{};
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
        \\source: unknown (the package's recipe lists none)
        \\feedstock: unknown (the package's about.json names none)
        \\file: include/omp.h -> include/omp.h 4066
        \\file: include/ompx.h -> include/ompx.h 615f
        \\
        \\package: make
        \\version: 4.4.1
        \\build: hb03c661_3
        \\url: https://conda.anaconda.org/conda-forge/linux-64/make-4.4.1-hb03c661_3.conda
        \\sha256: 4c65
        \\license: GPL-3.0-or-later
        \\source: https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz sha256:dd16
        \\feedstock: https://github.com/conda-forge/make-feedstock 1060
        \\file: bin/make -> bin/make 8a9d
        \\
    , aw.written());
    // no path of this machine: extracted_package_dir is not written
    try std.testing.expect(mem.indexOf(u8, aw.written(), "/home/u") == null);
}

test "SOURCES: each kind of source, the first mirror" {
    const u: Upstream = .{ .sources = &.{
        .{ .url = "https://a/x.tar.gz", .md5 = "9e10" },
        .{ .git = "https://github.com/o/r.git", .rev = "v1.2" },
        .{ .url = "https://a/y.zip" },
    }, .feedstock = "https://github.com/conda-forge/x-feedstock" };
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeUpstream(&aw.writer, u);
    try std.testing.expectEqualStrings(
        \\source: https://a/x.tar.gz md5:9e10
        \\source: https://github.com/o/r.git rev:v1.2
        \\source: https://a/y.zip
        \\feedstock: https://github.com/conda-forge/x-feedstock
        \\
    , aw.written());
}

// The recipe shapes of the package cache, trimmed: conda-build's
// meta.yaml (make 4.4.1, a mapping; binutils and gcc, lists, url mirrors,
// patches before the url) and rattler-build's rendered_recipe.yaml
// (adwaita-icon-theme 51.0's finalized_sources, at column 0).
test "recipe sources: a mapping, lists with mirrors and patches, column 0, git" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const make =
        \\package:
        \\  name: make
        \\source:
        \\  url: https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz
        \\  sha256: dd16fb1d
        \\build:
        \\  number: '3'
    ;
    var s = try recipeSources(arena, make, "source");
    try std.testing.expectEqual(@as(usize, 1), s.len);
    try std.testing.expectEqualStrings("https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz", s[0].url);
    try std.testing.expectEqualStrings("dd16fb1d", s[0].sha256);

    const gcc =
        \\source:
        \\  - patches:
        \\      - patches/0001-fallback-sysroot.diff
        \\    sha256: 324ed40a
        \\    url:
        \\      - https://ftp.gnu.org/gnu/binutils/binutils-2.46.1.tar.bz2
        \\      - https://mirrors.ocf.berkeley.edu/gnu/binutils/binutils-2.46.1.tar.bz2
        \\  - url: 'https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz'
        \\    sha256: 9a93b2b7
        \\    folder: zlib2
        \\  - git_url: https://github.com/o/r.git
        \\    git_rev: v1.2
        \\  - path: ../src
        \\requirements:
        \\  build:
        \\    - url: not-a-source
    ;
    s = try recipeSources(arena, gcc, "source");
    try std.testing.expectEqual(@as(usize, 3), s.len);
    try std.testing.expectEqualStrings("https://ftp.gnu.org/gnu/binutils/binutils-2.46.1.tar.bz2", s[0].url);
    try std.testing.expectEqualStrings("324ed40a", s[0].sha256);
    try std.testing.expectEqualStrings("https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz", s[1].url);
    try std.testing.expectEqualStrings("9a93b2b7", s[1].sha256);
    try std.testing.expectEqualStrings("https://github.com/o/r.git", s[2].git);
    try std.testing.expectEqualStrings("v1.2", s[2].rev);

    const rattler =
        \\recipe:
        \\  source:
        \\  - url: https://download.gnome.org/sources/adwaita-icon-theme/51/adwaita-icon-theme-51.0.tar.xz
        \\    sha256: ba561cf3
        \\finalized_sources:
        \\- url:
        \\  - https://download.gnome.org/sources/adwaita-icon-theme/51/adwaita-icon-theme-51.0.tar.xz
        \\  - https://mirror/adwaita-icon-theme-51.0.tar.xz
        \\  sha256: ba561cf3
        \\- git: https://github.com/o/r.git
        \\  rev: 0a1b2c
        \\system_tools:
        \\  rattler-build: 0.76.1
    ;
    s = try recipeSources(arena, rattler, "finalized_sources");
    try std.testing.expectEqual(@as(usize, 2), s.len);
    try std.testing.expectEqualStrings("https://download.gnome.org/sources/adwaita-icon-theme/51/adwaita-icon-theme-51.0.tar.xz", s[0].url);
    try std.testing.expectEqualStrings("ba561cf3", s[0].sha256);
    try std.testing.expectEqualStrings("https://github.com/o/r.git", s[1].git);
    try std.testing.expectEqualStrings("0a1b2c", s[1].rev);

    // no block, an empty one
    try std.testing.expectEqual(@as(usize, 0), (try recipeSources(arena, make, "finalized_sources")).len);
    try std.testing.expectEqual(@as(usize, 0), (try recipeSources(arena, "finalized_sources: null\nsystem_tools:\n", "finalized_sources")).len);
}

test "about.json: the feedstock and its commit, or none" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const u = try parseAbout(a.allocator(),
        \\{"home": "https://www.gnu.org/software/make/", "extra": {"final": true,
        \\ "remote_url": "https://github.com/conda-forge/make-feedstock", "sha": "1060ed0e"}}
    );
    try std.testing.expectEqualStrings("https://github.com/conda-forge/make-feedstock", u.feedstock);
    try std.testing.expectEqualStrings("1060ed0e", u.commit);
    const none = try parseAbout(a.allocator(), "{\"home\": \"x\"}");
    try std.testing.expectEqualStrings("", none.feedstock);
    const nulls = try parseAbout(a.allocator(), "{\"extra\": {\"remote_url\": null}}");
    try std.testing.expectEqualStrings("", nulls.feedstock);
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
