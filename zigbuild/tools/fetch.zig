//! fetch: R's source tarball, for `zig build fetch` (build.zig; backlog
//! M-20, .github/devdocs/b13-build/PLAN.md). It replaced scripts/fetch-r.sh
//! with the same sources and checks:
//!
//!   fetch <tarball> <checksum-file> <src-dir> <url>...
//!
//! - <src-dir>/configure there: nothing to do.
//! - <tarball> missing: each url in turn (CRAN, then its CDN,
//!   cloud.r-project.org), three tries each, into <tarball>.part, renamed
//!   once complete. TLS with the system's roots (as zig's own package
//!   fetch), plus SSL_CERT_FILE when set; proxies from the environment
//!   (HTTPS_PROXY, ALL_PROXY, ...), as zig's fetch.
//! - Its sha256 against <checksum-file>'s first word ("<sha256>  R-<v>.tar.gz",
//!   scripts/checksums/). A mismatch stops, and the tarball is removed so
//!   the next run downloads it again. No checksum file: the sha256 is
//!   written there, to commit (a new R version).
//! - Extracted (gzip, then tar) into a new directory beside <src-dir>, whose
//!   one top directory is then renamed to <src-dir>: an interrupted run
//!   leaves no half tree. Any extraction failure stops, except, on
//!   Windows, a symbolic link std.tar cannot make (no developer mode).
//! - Windows: every symbolic link entry becomes a real copy of its target,
//!   a file or a whole directory, whether or not std.tar made the link
//!   (`materialize`), as Git's MSYS tar did for fetch-r.sh. R's tarball
//!   has 16: src/library/Recommended/<pkg>.tgz -> <pkg>_<ver>.tar.gz (15;
//!   no step reads them, the tree is fetch-r.sh's) and tests/Pkgs/pkgA ->
//!   xDir/pkg (`check` copies tests/ with `cp -R`, whose MSYS copy of a
//!   link to a directory failed: upstream-zig run 45447897929). A
//!   target is resolved against the link's directory and must stay inside
//!   the archive's top directory. The copies get their targets' tar times.
//!   linux and macOS keep real symbolic links.
//! - <src-dir>/.r-zig-patches, empty: the tree is pristine (zig-build.sh
//!   applies zigbuild/patches/ to a tree with this empty stamp only).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Sha256 = std.crypto.hash.sha2.Sha256;

const usage = "usage: fetch <tarball> <checksum-file> <src-dir> <url>...\n";

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 5) {
        std.debug.print("{s}", .{usage});
        return 2;
    }
    const tarball = args[1];
    const checksum_file = args[2];
    const src_dir = args[3];
    const urls = args[4..];
    const cwd = Io.Dir.cwd();

    if (cwd.access(io, try std.fmt.allocPrint(arena, "{s}/configure", .{src_dir}), .{})) |_| {
        std.debug.print("R source already present at {s}\n", .{src_dir});
        return 0;
    } else |_| {}

    const build_dir = std.fs.path.dirname(tarball) orelse ".";
    try cwd.createDirPath(io, build_dir);

    if (cwd.access(io, tarball, .{})) |_| {} else |_| {
        if (!try download(arena, io, init.environ_map, tarball, urls)) {
            std.debug.print("error: could not download {s}\n", .{std.fs.path.basename(tarball)});
            return 1;
        }
    }

    const bytes = try cwd.readFileAlloc(io, tarball, arena, .limited(1 << 30));
    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    if (cwd.readFileAlloc(io, checksum_file, arena, .limited(4096))) |pinned| {
        var words = std.mem.tokenizeAny(u8, pinned, " \t\r\n");
        const expected = words.next() orelse "";
        if (!std.mem.eql(u8, expected, &actual)) {
            std.debug.print("error: checksum mismatch for {s}\n  expected: {s}\n  actual:   {s}\n", .{ tarball, expected, &actual });
            cwd.deleteFile(io, tarball) catch {};
            return 1;
        }
        std.debug.print("Checksum OK\n", .{});
    } else |err| switch (err) {
        error.FileNotFound => {
            if (std.fs.path.dirname(checksum_file)) |d| try cwd.createDirPath(io, d);
            try cwd.writeFile(io, .{
                .sub_path = checksum_file,
                .data = try std.fmt.allocPrint(arena, "{s}  {s}\n", .{ &actual, std.fs.path.basename(tarball) }),
            });
            std.debug.print("Pinned new checksum in {s}: commit this file.\n", .{checksum_file});
        },
        else => |e| return e,
    }

    std.debug.print("Extracting to {s}\n", .{src_dir});
    var tar: []u8 = &.{};
    var links: []const Link = &.{};
    const tmp = try std.fmt.allocPrint(arena, "{s}.extract", .{src_dir});
    cwd.deleteTree(io, tmp) catch {};
    try cwd.createDirPath(io, tmp);
    {
        var out = try cwd.openDir(io, tmp, .{});
        defer out.close(io);
        var in: Io.Reader = .fixed(bytes);
        var window: [std.compress.flate.max_window_len]u8 = undefined;
        var gz: std.compress.flate.Decompress = .init(&in, .gzip, &window);
        tar = try gz.reader.allocRemaining(arena, .limited(1 << 31));
        var tar_in: Io.Reader = .fixed(tar);
        var diagnostics: std.tar.Diagnostics = .{ .allocator = arena };
        try std.tar.extract(io, out, &tar_in, .{ .diagnostics = &diagnostics });
        for (diagnostics.errors.items) |item| switch (item) {
            // Windows: materialized below, link or not
            .unable_to_create_sym_link => |i| if (builtin.os.tag != .windows) {
                std.debug.print("error: cannot make the link {s} -> {s}: {t}\n", .{ i.file_name, i.link_name, i.code });
                return 1;
            },
            .unable_to_create_file => |i| {
                std.debug.print("error: cannot write {s}: {t}\n", .{ i.file_name, i.code });
                return 1;
            },
            .unsupported_file_type => |i| {
                std.debug.print("error: {s}: unsupported tar entry type {d}\n", .{ i.file_name, @backingInt(i.file_type) });
                return 1;
            },
            .components_outside_stripped_prefix => |i| {
                std.debug.print("error: {s}: outside the archive's top directory\n", .{i.file_name});
                return 1;
            },
        };
        if (diagnostics.root_dir.len == 0) {
            std.debug.print("error: {s} has no single top directory\n", .{tarball});
            return 1;
        }
        // The top directory must be the one src_dir names (R-<version>).
        if (!std.mem.eql(u8, diagnostics.root_dir, std.fs.path.basename(src_dir))) {
            std.debug.print("error: {s}'s top directory is {s}, not {s}\n", .{ tarball, diagnostics.root_dir, std.fs.path.basename(src_dir) });
            return 1;
        }
        if (builtin.os.tag == .windows) {
            links = try linkEntries(arena, tar);
            materialize(arena, io, out, links) catch |err| {
                std.debug.print("error: cannot copy the symbolic links' targets: {t}\n", .{err});
                return 1;
            };
            if (links.len > 0) std.debug.print("Copied the targets of {d} symbolic links (Windows)\n", .{links.len});
        }
    }
    cwd.deleteTree(io, src_dir) catch {};
    try cwd.rename(try std.fmt.allocPrint(arena, "{s}/{s}", .{ tmp, std.fs.path.basename(src_dir) }), cwd, src_dir, io);
    try cwd.deleteTree(io, tmp);
    // The entries' modification times, as tar sets them (std.tar leaves
    // the time of extraction): R's build records some (doc/NEWS.rds keeps
    // NEWS.Rd's in its srcref), so the tree must not depend on when it
    // was extracted. After the rename, which can change a moved
    // directory's time.
    // The archive's names are relative to src_dir's parent (the tarball
    // may be elsewhere).
    try setMtimes(arena, io, std.fs.path.dirname(src_dir) orelse ".", tar, links);
    try cwd.access(io, try std.fmt.allocPrint(arena, "{s}/configure", .{src_dir}), .{});
    // Pristine: no patches applied yet.
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}/.r-zig-patches", .{src_dir}), .data = "" });
    std.debug.print("Done.\n", .{});
    return 0;
}

/// Each url, three tries each, until one gives the whole file with 200.
fn download(arena: std.mem.Allocator, io: Io, environ_map: *std.process.Environ.Map, tarball: []const u8, urls: []const []const u8) !bool {
    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();
    try client.initDefaultProxies(arena, environ_map);
    if (environ_map.get("SSL_CERT_FILE")) |extra| if (extra.len > 0) {
        // The system's roots first (what the client would scan itself),
        // then the file's; client.now set marks the bundle as loaded.
        const now = Io.Clock.real.now(io);
        client.ca_bundle.rescan(arena, io, now) catch {};
        client.ca_bundle.addCertsFromFilePath(arena, io, now, Io.Dir.cwd(), extra) catch |err|
            std.debug.print("warning: SSL_CERT_FILE={s}: {t}\n", .{ extra, err });
        client.now = now;
    };

    const part = try std.fmt.allocPrint(arena, "{s}.part", .{tarball});
    const cwd = Io.Dir.cwd();
    for (urls) |url| {
        var attempt: usize = 1;
        while (attempt <= 3) : (attempt += 1) {
            std.debug.print("Downloading {s} (try {d})\n", .{ url, attempt });
            if (get(&client, io, url, part)) |status| {
                if (status == .ok) {
                    try cwd.rename(part, cwd, tarball, io);
                    return true;
                }
                std.debug.print("  {d} {s}\n", .{ @backingInt(status), status.phrase() orelse "" });
                // A 4xx will not change on a retry: next url.
                if (@backingInt(status) >= 400 and @backingInt(status) < 500) break;
            } else |err| {
                std.debug.print("  failed: {t}\n", .{err});
            }
            cwd.deleteFile(io, part) catch {};
            if (attempt < 3) io.sleep(.fromSeconds(@intCast(2 * attempt)), .awake) catch {};
        }
    }
    return false;
}

fn get(client: *std.http.Client, io: Io, url: []const u8, part: []const u8) !std.http.Status {
    const file = try Io.Dir.cwd().createFile(io, part, .{});
    defer file.close(io);
    var buf: [64 * 1024]u8 = undefined;
    var fw = file.writer(io, &buf);
    const res = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &fw.interface });
    try fw.interface.flush();
    return res.status;
}

/// Sets each file's and directory's modification (and access) time to its
/// tar header's, for the entries under `root` (the archive's names are
/// relative to it). ustar names (prefix and name), GNU long names ('L')
/// and pax `path`/`mtime` records; symbolic links keep theirs. Directories
/// last, deepest first, as their entries' creation changed them. `links`
/// (Windows: materialized ones): a file at or under a link's target also
/// sets the time of its copy under the link (setCopies).
fn setMtimes(arena: std.mem.Allocator, io: Io, root: []const u8, tar: []const u8, links: []const Link) !void {
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    var dirs: std.ArrayList(struct { name: []const u8, ns: i96 }) = .empty;
    var long_name: ?[]const u8 = null;
    var pax_name: ?[]const u8 = null;
    var pax_mtime: ?i96 = null;
    var off: usize = 0;
    while (off + 512 <= tar.len) {
        const h = tar[off..][0..512];
        if (std.mem.allEqual(u8, h, 0)) break;
        const size = try octal(h[124..136]);
        const data = tar[off + 512 ..][0..@intCast(size)];
        off += 512 + std.mem.alignForward(usize, @intCast(size), 512);
        switch (h[156]) {
            'L' => {
                long_name = std.mem.sliceTo(data, 0);
                continue;
            },
            'x' => {
                var rest = data;
                while (std.mem.indexOfScalar(u8, rest, ' ')) |sp| {
                    const len = std.fmt.parseInt(usize, rest[0..sp], 10) catch break;
                    if (len > rest.len or len < sp + 2) break;
                    const rec = rest[sp + 1 .. len - 1];
                    if (std.mem.startsWith(u8, rec, "path=")) pax_name = rec["path=".len..];
                    if (std.mem.startsWith(u8, rec, "mtime=")) {
                        const v = rec["mtime=".len..];
                        const secs = v[0 .. std.mem.indexOfScalar(u8, v, '.') orelse v.len];
                        pax_mtime = @as(i96, std.fmt.parseInt(i64, secs, 10) catch 0) * std.time.ns_per_s;
                    }
                    rest = rest[len..];
                }
                continue;
            },
            'g' => continue,
            else => {},
        }
        const name = pax_name orelse long_name orelse blk: {
            const n = std.mem.sliceTo(h[0..100], 0);
            const prefix = std.mem.sliceTo(h[345..500], 0);
            break :blk if (prefix.len > 0) try std.fmt.allocPrint(arena, "{s}/{s}", .{ prefix, n }) else n;
        };
        const ns = pax_mtime orelse @as(i96, @intCast(try octal(h[136..148]))) * std.time.ns_per_s;
        long_name = null;
        pax_name = null;
        pax_mtime = null;
        const rel = std.mem.trimEnd(u8, name, "/");
        if (rel.len == 0 or rel[0] == '/' or hasDotDot(rel)) continue;
        switch (h[156]) {
            0, '0', '7' => {
                setTime(io, dir, rel, ns) catch |err| {
                    std.debug.print("error: cannot set the time of {s}: {t}\n", .{ rel, err });
                    return err;
                };
                if (links.len > 0) if (try normalize(arena, rel)) |n| try setCopies(arena, io, dir, links, n, ns);
            },
            '5' => try dirs.append(arena, .{ .name = rel, .ns = ns }),
            else => {}, // links: theirs stay
        }
    }
    // Windows: files only. A directory handle zig opens has no
    // FILE_WRITE_ATTRIBUTES, so directories keep their extraction time;
    // R's build reads files' times, not directories'.
    if (builtin.os.tag == .windows) return;
    var i = dirs.items.len;
    while (i > 0) {
        i -= 1;
        try setTime(io, dir, dirs.items[i].name, dirs.items[i].ns);
    }
}

/// The time of each copy of the file `file` (normalized) under `links`,
/// and of the copies of those copies (a link to a link).
fn setCopies(arena: std.mem.Allocator, io: Io, dir: Io.Dir, links: []const Link, file: []const u8, ns: i96) !void {
    for (links) |l| {
        const copy = (try copyPath(arena, l, file)) orelse continue;
        setTime(io, dir, copy, ns) catch |err| {
            std.debug.print("error: cannot set the time of {s}: {t}\n", .{ copy, err });
            return err;
        };
        try setCopies(arena, io, dir, links, copy, ns);
    }
}

/// Sets `rel`'s modification and access time. Windows (files only):
/// through an open handle (GENERIC_WRITE carries FILE_WRITE_ATTRIBUTES),
/// as zig 0.17.1's Dir.setTimestamps is not implemented there (it
/// panics); File's is.
fn setTime(io: Io, dir: Io.Dir, rel: []const u8, ns: i96) !void {
    const t: Io.File.SetTimestamp = .{ .new = .fromNanoseconds(ns) };
    if (builtin.os.tag == .windows) {
        const f = try dir.openFile(io, rel, .{ .mode = .write_only });
        defer f.close(io);
        return f.setTimestamps(io, .{ .access_timestamp = t, .modify_timestamp = t });
    }
    return dir.setTimestamps(io, rel, .{ .access_timestamp = t, .modify_timestamp = t });
}

/// A symbolic link entry of the archive: its name and its target's, both
/// relative to the extraction directory, `/`-separated and normalized.
const Link = struct { name: []const u8, target: []const u8 };

/// The archive's symbolic link entries (std.tar's iterator: ustar, GNU
/// long names and pax records alike), each target resolved against the
/// link's directory (`resolveLink`). An entry whose name or target leaves
/// the archive's top directory is an error.
fn linkEntries(arena: std.mem.Allocator, tar: []const u8) ![]const Link {
    var name_buf: [Io.Dir.max_path_bytes]u8 = undefined;
    var link_buf: [Io.Dir.max_path_bytes]u8 = undefined;
    var in: Io.Reader = .fixed(tar);
    var it: std.tar.Iterator = .init(&in, .{ .file_name_buffer = &name_buf, .link_name_buffer = &link_buf });
    var out: std.ArrayList(Link) = .empty;
    while (try it.next()) |f| {
        if (f.kind != .sym_link) continue;
        const name = (try normalize(arena, f.name)) orelse {
            std.debug.print("error: the link {s} is outside the archive\n", .{f.name});
            return error.LinkOutsideTree;
        };
        const t = (try resolveLink(arena, name, f.link_name)) orelse {
            std.debug.print("error: the link {s} -> {s} leaves the archive's top directory\n", .{ f.name, f.link_name });
            return error.LinkOutsideTree;
        };
        try out.append(arena, .{ .name = name, .target = t });
    }
    return out.items;
}

/// `path` without empty and `.` components, each `..` removing the one
/// before it, `/`-separated (`\` counts as one too). null when it is
/// absolute (a leading separator or a drive letter) or a `..` would leave
/// it, or nothing is left.
fn normalize(arena: std.mem.Allocator, path: []const u8) !?[]const u8 {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\') return null;
    if (path.len >= 2 and path[1] == ':') return null;
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |c| {
        if (std.mem.eql(u8, c, ".")) continue;
        if (std.mem.eql(u8, c, "..")) {
            if (parts.items.len == 0) return null;
            _ = parts.pop();
            continue;
        }
        try parts.append(arena, c);
    }
    if (parts.items.len == 0) return null;
    return try std.mem.join(arena, "/", parts.items);
}

/// The target of the link `name` (normalized) to `link`, relative to the
/// extraction directory: `link` against `name`'s directory. null when it
/// is absolute or leaves `name`'s top directory (the archive's).
fn resolveLink(arena: std.mem.Allocator, name: []const u8, link: []const u8) !?[]const u8 {
    if (link.len == 0 or link[0] == '/' or link[0] == '\\' or (link.len >= 2 and link[1] == ':')) return null;
    const dir = std.fs.path.dirnamePosix(name) orelse return null;
    const t = (try normalize(arena, try std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, link }))) orelse return null;
    const top = name[0 .. std.mem.indexOfScalar(u8, name, '/') orelse name.len];
    if (!under(t, top) or std.mem.eql(u8, t, top)) return null;
    return t;
}

/// `path` is `dir` or below it.
fn under(path: []const u8, dir: []const u8) bool {
    return std.mem.startsWith(u8, path, dir) and (path.len == dir.len or path[dir.len] == '/');
}

/// Where the file `file` (normalized) has a copy under the link `l`: at
/// `l.name` when it is the target, below it when it is under the target;
/// null otherwise.
fn copyPath(arena: std.mem.Allocator, l: Link, file: []const u8) !?[]const u8 {
    if (!under(file, l.target)) return null;
    return try std.fmt.allocPrint(arena, "{s}{s}", .{ l.name, file[l.target.len..] });
}

/// Replaces each link (whatever std.tar left at its name: a symbolic link
/// or nothing) by a copy of its target, a file or a directory tree. A link
/// whose target is or holds another link, or lies under one, waits until
/// that one is a copy; a link into itself, or a cycle, is an error.
fn materialize(arena: std.mem.Allocator, io: Io, dir: Io.Dir, links: []const Link) !void {
    var done = try arena.alloc(bool, links.len);
    @memset(done, false);
    var left = links.len;
    while (left > 0) {
        var progressed = false;
        for (links, 0..) |l, i| {
            if (done[i]) continue;
            if (under(l.target, l.name) or under(l.name, l.target)) {
                std.debug.print("error: the link {s} -> {s} contains itself\n", .{ l.name, l.target });
                return error.LinkCycle;
            }
            const waits = for (links, 0..) |o, j| {
                if (j != i and !done[j] and (under(l.target, o.name) or under(o.name, l.target))) break true;
            } else false;
            if (waits) continue;
            try removeLink(io, dir, l.name);
            const st = dir.statFile(io, l.target, .{}) catch |err| {
                std.debug.print("error: {s}, the target of {s}: {t}\n", .{ l.target, l.name, err });
                return err;
            };
            switch (st.kind) {
                .directory => try copyTree(arena, io, dir, l.target, l.name),
                .file => try dir.copyFile(l.target, dir, l.name, io, .{ .make_path = true }),
                else => {
                    std.debug.print("error: {s}, the target of {s}, is a {t}\n", .{ l.target, l.name, st.kind });
                    return error.UnsupportedLinkTarget;
                },
            }
            done[i] = true;
            left -= 1;
            progressed = true;
        }
        if (!progressed) {
            std.debug.print("error: the symbolic links form a cycle\n", .{});
            return error.LinkCycle;
        }
    }
}

/// Removes the link at `name`, if any: a file link, or a directory link
/// (Windows' kind for a target that is a directory), never what it points
/// to.
fn removeLink(io: Io, dir: Io.Dir, name: []const u8) !void {
    dir.deleteFile(io, name) catch |err| switch (err) {
        error.FileNotFound => {},
        error.IsDir => try dir.deleteDir(io, name),
        else => |e| return e,
    };
}

/// Copies the directory `src` to `dst` (absent), files and directories;
/// a symbolic link in it is an error (the archive's are copies by now).
fn copyTree(arena: std.mem.Allocator, io: Io, dir: Io.Dir, src: []const u8, dst: []const u8) !void {
    var from = try dir.openDir(io, src, .{ .iterate = true });
    defer from.close(io);
    try dir.createDirPath(io, dst);
    var to = try dir.openDir(io, dst, .{});
    defer to.close(io);
    var w = try from.walk(arena);
    defer w.deinit();
    while (try w.next(io)) |e| switch (e.kind) {
        .directory => try to.createDirPath(io, e.path),
        .file => try from.copyFile(e.path, to, e.path, io, .{ .make_path = true }),
        else => {
            std.debug.print("error: {s}/{s} is a {t}, not a file or directory\n", .{ src, e.path, e.kind });
            return error.UnsupportedLinkTarget;
        },
    };
}

/// Whether a path has a `..` component (outside the tree: not ours to touch).
fn hasDotDot(path: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |c| if (std.mem.eql(u8, c, "..")) return true;
    return false;
}

/// A tar header's octal number field (NUL- or space-terminated).
fn octal(field: []const u8) !u64 {
    const v = std.mem.trim(u8, std.mem.sliceTo(field, 0), " ");
    if (v.len == 0) return 0;
    return std.fmt.parseInt(u64, v, 8);
}

// ---------------------------------------------------------------------------
// `zig test zigbuild/tools/fetch.zig` (rzig's test.sh runs it)

const testing = std.testing;

test "normalize: separators, `.` and `..`; absolute or escaping paths are none" {
    const a = testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const ar = arena.allocator();
    try testing.expectEqualStrings("R/a/b", (try normalize(ar, "R//a/./b/")).?);
    try testing.expectEqualStrings("R/b", (try normalize(ar, "./R/a/../b")).?);
    try testing.expectEqualStrings("R/a/b", (try normalize(ar, "R\\a\\b")).?);
    try testing.expect((try normalize(ar, "/etc/passwd")) == null);
    try testing.expect((try normalize(ar, "\\x")) == null);
    try testing.expect((try normalize(ar, "C:/x")) == null);
    try testing.expect((try normalize(ar, "R/../..")) == null);
    try testing.expect((try normalize(ar, "./.")) == null);
}

test "resolveLink: against the link's directory, inside the archive's top directory" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const ar = arena.allocator();
    // R-4.6.2.tar.gz's two kinds
    try testing.expectEqualStrings("R-4.6.2/tests/Pkgs/xDir/pkg", (try resolveLink(ar, "R-4.6.2/tests/Pkgs/pkgA", "xDir/pkg")).?);
    try testing.expectEqualStrings("R-4.6.2/src/library/Recommended/MASS_7.3-65.tar.gz", (try resolveLink(ar, "R-4.6.2/src/library/Recommended/MASS.tgz", "MASS_7.3-65.tar.gz")).?);
    try testing.expectEqualStrings("R-4.6.2/doc/x", (try resolveLink(ar, "R-4.6.2/tests/y", "../doc/./x")).?);
    // out of the tree, absolute, the top directory itself, no directory
    try testing.expect((try resolveLink(ar, "R-4.6.2/tests/y", "../../etc")) == null);
    try testing.expect((try resolveLink(ar, "R-4.6.2/tests/y", "../../R-4.6.3/x")) == null);
    try testing.expect((try resolveLink(ar, "R-4.6.2/tests/y", "/etc/passwd")) == null);
    try testing.expect((try resolveLink(ar, "R-4.6.2/tests/y", "C:\\Windows")) == null);
    try testing.expect((try resolveLink(ar, "R-4.6.2/tests/y", "..")) == null);
    try testing.expect((try resolveLink(ar, "y", "x")) == null);
    try testing.expect((try resolveLink(ar, "R-4.6.2/y", "")) == null);
}

test "copyPath: the target and what is under it, not a name that only starts the same" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const ar = arena.allocator();
    const l: Link = .{ .name = "R/t/pkgA", .target = "R/t/xDir/pkg" };
    try testing.expectEqualStrings("R/t/pkgA", (try copyPath(ar, l, "R/t/xDir/pkg")).?);
    try testing.expectEqualStrings("R/t/pkgA/R/f.R", (try copyPath(ar, l, "R/t/xDir/pkg/R/f.R")).?);
    try testing.expect((try copyPath(ar, l, "R/t/xDir/pkg2/f")) == null);
}

/// An archive as R's: a directory link, file links, and a link to a link.
fn testArchive(a: std.mem.Allocator) ![]u8 {
    var buf: Io.Writer.Allocating = .init(a);
    var w: std.tar.Writer = .{ .underlying_writer = &buf.writer };
    const t: std.tar.Writer.Options = .{ .mode = 0o644, .mtime = 1_700_000_000 };
    try w.writeDir("R", t);
    try w.writeDir("R/tests/Pkgs/xDir/pkg/R", t);
    try w.writeFileBytes("R/tests/Pkgs/xDir/pkg/DESCRIPTION", "Package: pkg\n", .{ .mode = 0o644, .mtime = 1_600_000_000 });
    try w.writeFileBytes("R/tests/Pkgs/xDir/pkg/R/f.R", "f <- 1\n", t);
    try w.writeLink("R/tests/Pkgs/pkgA", "xDir/pkg", t);
    try w.writeFileBytes("R/lib/A_1.tar.gz", "gz", .{ .mode = 0o644, .mtime = 1_500_000_000 });
    try w.writeLink("R/lib/A.tgz", "A_1.tar.gz", t);
    try w.writeLink("R/lib/B.tgz", "A.tgz", t);
    try w.finishPedantically();
    return buf.toOwnedSlice();
}

test "materialize: each link becomes a copy of its target, a link std.tar made replaced; copies get their targets' times" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const ar = arena.allocator();
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const tar = try testArchive(ar);
    var in: Io.Reader = .fixed(tar);
    // std.tar makes the links where it can (here, unless a Windows host
    // without developer mode): materialize replaces them
    var diagnostics: std.tar.Diagnostics = .{ .allocator = ar };
    try std.tar.extract(io, tmp.dir, &in, .{ .diagnostics = &diagnostics });
    const links = try linkEntries(ar, tar);
    try testing.expectEqual(@as(usize, 3), links.len);
    try testing.expectEqualStrings("R/tests/Pkgs/pkgA", links[0].name);
    try testing.expectEqualStrings("R/tests/Pkgs/xDir/pkg", links[0].target);
    try testing.expectEqualStrings("R/lib/A.tgz", links[2].target);
    try materialize(ar, io, tmp.dir, links);
    // real files and directories now, not links
    for ([_][]const u8{ "R/tests/Pkgs/pkgA", "R/lib/A.tgz", "R/lib/B.tgz" }) |p| {
        const st = try tmp.dir.statFile(io, p, .{ .follow_symlinks = false });
        try testing.expect(st.kind != .sym_link);
    }
    try testing.expectEqual(Io.File.Kind.directory, (try tmp.dir.statFile(io, "R/tests/Pkgs/pkgA", .{ .follow_symlinks = false })).kind);
    try testing.expectEqualStrings("Package: pkg\n", try tmp.dir.readFileAlloc(io, "R/tests/Pkgs/pkgA/DESCRIPTION", ar, .limited(100)));
    try testing.expectEqualStrings("f <- 1\n", try tmp.dir.readFileAlloc(io, "R/tests/Pkgs/pkgA/R/f.R", ar, .limited(100)));
    try testing.expectEqualStrings("gz", try tmp.dir.readFileAlloc(io, "R/lib/A.tgz", ar, .limited(100)));
    try testing.expectEqualStrings("gz", try tmp.dir.readFileAlloc(io, "R/lib/B.tgz", ar, .limited(100)));
    // the copies' times: their targets' tar times
    const root = try tmp.dir.realPathFileAlloc(io, ".", ar);
    try setMtimes(ar, io, root, tar, links);
    for ([_]struct { []const u8, i96 }{
        .{ "R/tests/Pkgs/pkgA/DESCRIPTION", 1_600_000_000 },
        .{ "R/tests/Pkgs/pkgA/R/f.R", 1_700_000_000 },
        .{ "R/lib/A.tgz", 1_500_000_000 },
        .{ "R/lib/B.tgz", 1_500_000_000 },
    }) |c| {
        const st = try tmp.dir.statFile(io, c[0], .{});
        try testing.expectEqual(c[1] * std.time.ns_per_s, st.mtime.toNanoseconds());
    }
}

test "materialize: a link into itself is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "R/a");
    try testing.expectError(error.LinkCycle, materialize(arena.allocator(), testing.io, tmp.dir, &.{.{ .name = "R/a/self", .target = "R/a" }}));
    try testing.expectError(error.LinkCycle, materialize(arena.allocator(), testing.io, tmp.dir, &.{ .{ .name = "R/x", .target = "R/y" }, .{ .name = "R/y", .target = "R/x" } }));
}
