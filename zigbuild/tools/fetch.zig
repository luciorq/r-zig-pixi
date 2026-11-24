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
//!   leaves no half tree. Symbolic links that cannot be made (Windows
//!   without developer mode: Recommended/*.tgz, tests' fixtures; none is
//!   built) are skipped there, as fetch-r.sh accepted; any other failure
//!   stops.
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
        var skipped: usize = 0;
        for (diagnostics.errors.items) |item| switch (item) {
            .unable_to_create_sym_link => |i| {
                if (builtin.os.tag != .windows) {
                    std.debug.print("error: cannot make the link {s} -> {s}: {t}\n", .{ i.file_name, i.link_name, i.code });
                    return 1;
                }
                skipped += 1;
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
        if (skipped > 0) std.debug.print("skipped {d} symbolic links (Windows cannot make them here; none is built)\n", .{skipped});
        if (diagnostics.root_dir.len == 0) {
            std.debug.print("error: {s} has no single top directory\n", .{tarball});
            return 1;
        }
        // The top directory must be the one src_dir names (R-<version>).
        if (!std.mem.eql(u8, diagnostics.root_dir, std.fs.path.basename(src_dir))) {
            std.debug.print("error: {s}'s top directory is {s}, not {s}\n", .{ tarball, diagnostics.root_dir, std.fs.path.basename(src_dir) });
            return 1;
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
    try setMtimes(arena, io, build_dir, tar);
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
/// last, deepest first, as their entries' creation changed them.
fn setMtimes(arena: std.mem.Allocator, io: Io, root: []const u8, tar: []const u8) !void {
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
            0, '0', '7' => setTime(io, dir, rel, ns) catch |err| {
                std.debug.print("error: cannot set the time of {s}: {t}\n", .{ rel, err });
                return err;
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
