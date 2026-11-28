//! A unified diff (`diff -u`, `git diff`) applied in Zig, for build.zig's
//! patches of a release tarball (zigbuild/busybox/patches/): no patch(1),
//! no sed. Strict, as `patch -F0`: each hunk's old lines (context and
//! removed) must match exactly, at the line its header names (shifted by
//! the hunks before it) or else at one place in the file only; a hunk
//! that matches nowhere or more than once fails the build.
const std = @import("std");
const mem = std.mem;

pub const Hunk = struct {
    /// the header's old start line, 1-based
    old_start: usize,
    old: []const []const u8,
    new: []const []const u8,
};

pub const File = struct {
    /// the path under the source root (`--- a/<path>`)
    path: []const u8,
    hunks: []const Hunk,
};

pub const Error = error{ BadPatch, HunkFailed, OutOfMemory };

/// The files of a patch, in order. Text before the first `--- ` line
/// (the description) is skipped; a trailing '\r' on a line is ignored.
pub fn parse(arena: mem.Allocator, text: []const u8) Error![]const File {
    var files: std.ArrayList(File) = .empty;
    var hunks: std.ArrayList(Hunk) = .empty;
    var path: ?[]const u8 = null;
    var lines = mem.splitScalar(u8, text, '\n');
    var pending: ?[]const u8 = lines.next();
    while (pending) |raw| {
        pending = lines.next();
        const line = mem.trimEnd(u8, raw, "\r");
        // a file's header: `--- ` and then `+++ ` (else description text)
        const plus = mem.trimEnd(u8, pending orelse "", "\r");
        if (mem.startsWith(u8, line, "--- ") and mem.startsWith(u8, plus, "+++ ")) {
            pending = lines.next();
            if (path) |p| try files.append(arena, .{ .path = p, .hunks = try hunks.toOwnedSlice(arena) });
            path = stripPrefix(plus[4..]);
            continue;
        }
        if (!mem.startsWith(u8, line, "@@ -")) continue;
        if (path == null) return error.BadPatch;
        const h = try header(line);
        var old: std.ArrayList([]const u8) = .empty;
        var new: std.ArrayList([]const u8) = .empty;
        while (old.items.len < h.old_count or new.items.len < h.new_count) {
            const body_raw = pending orelse return error.BadPatch;
            pending = lines.next();
            const body = mem.trimEnd(u8, body_raw, "\r");
            if (body.len > 0 and body[0] == '\\') continue; // "\ No newline at end of file"
            const rest = if (body.len > 0) body[1..] else "";
            switch (if (body.len > 0) body[0] else ' ') {
                ' ' => {
                    try old.append(arena, rest);
                    try new.append(arena, rest);
                },
                '-' => try old.append(arena, rest),
                '+' => try new.append(arena, rest),
                else => return error.BadPatch,
            }
        }
        if (old.items.len != h.old_count or new.items.len != h.new_count) return error.BadPatch;
        try hunks.append(arena, .{ .old_start = h.old_start, .old = old.items, .new = new.items });
    }
    if (path) |p| try files.append(arena, .{ .path = p, .hunks = try hunks.toOwnedSlice(arena) });
    return files.items;
}

/// `a/x/y.c` (or a bare path) -> `x/y.c`; a tab and timestamp after it go.
fn stripPrefix(s: []const u8) []const u8 {
    const name = s[0 .. mem.indexOfScalar(u8, s, '\t') orelse s.len];
    const slash = mem.indexOfScalar(u8, name, '/') orelse return name;
    if (mem.eql(u8, name[0..slash], "a") or mem.eql(u8, name[0..slash], "b")) return name[slash + 1 ..];
    return name;
}

const Header = struct { old_start: usize, old_count: usize, new_count: usize };

/// `@@ -l,s +l,s @@` (a count of 1 may be left out)
fn header(line: []const u8) Error!Header {
    var it = mem.tokenizeScalar(u8, line, ' ');
    _ = it.next(); // @@
    const o = it.next() orelse return error.BadPatch;
    const n = it.next() orelse return error.BadPatch;
    if (o[0] != '-' or n[0] != '+') return error.BadPatch;
    const os = try range(o[1..]);
    const ns = try range(n[1..]);
    return .{ .old_start = os[0], .old_count = os[1], .new_count = ns[1] };
}

fn range(s: []const u8) Error![2]usize {
    const comma = mem.indexOfScalar(u8, s, ',');
    const start = std.fmt.parseInt(usize, s[0 .. comma orelse s.len], 10) catch return error.BadPatch;
    const count = if (comma) |c| std.fmt.parseInt(usize, s[c + 1 ..], 10) catch return error.BadPatch else 1;
    return .{ start, count };
}

/// `original` with the file's hunks applied. Lines keep their ending;
/// added lines end in '\n'.
pub fn apply(arena: mem.Allocator, original: []const u8, file: File) Error![]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var it = mem.splitScalar(u8, original, '\n');
    while (it.next()) |l| try lines.append(arena, l);
    // a final '\n' leaves an empty last element, which stays last
    var shift: isize = 0;
    for (file.hunks) |h| {
        const want: isize = @as(isize, @intCast(h.old_start)) - 1 + shift;
        const at = find(lines.items, h.old, want) orelse return error.HunkFailed;
        try lines.replaceRange(arena, at, h.old.len, h.new);
        shift += @as(isize, @intCast(h.new.len)) - @as(isize, @intCast(h.old.len));
    }
    return mem.join(arena, "\n", lines.items);
}

/// Where `old` matches: at `want` if it does there, else its one match.
fn find(lines: []const []const u8, old: []const []const u8, want: isize) ?usize {
    if (want >= 0 and matches(lines, old, @intCast(want))) return @intCast(want);
    var found: ?usize = null;
    var i: usize = 0;
    while (i + old.len <= lines.len) : (i += 1) {
        if (!matches(lines, old, i)) continue;
        if (found != null) return null; // ambiguous
        found = i;
    }
    return found;
}

fn matches(lines: []const []const u8, old: []const []const u8, at: usize) bool {
    if (at + old.len > lines.len) return false;
    for (old, 0..) |o, k| {
        if (!mem.eql(u8, mem.trimEnd(u8, lines[at + k], "\r"), o)) return false;
    }
    return true;
}

test "parse and apply a two-hunk patch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const text =
        \\A description, with a line
        \\--- not a diff line
        \\
        \\--- a/dir/x.c
        \\+++ b/dir/x.c
        \\@@ -1,3 +1,4 @@
        \\ one
        \\+one and a half
        \\ two
        \\ three
        \\@@ -5,2 +6,2 @@
        \\ five
        \\-six
        \\+SIX
        \\
    ;
    const files = try parse(arena, text);
    try std.testing.expectEqual(@as(usize, 1), files.len);
    try std.testing.expectEqualStrings("dir/x.c", files[0].path);
    try std.testing.expectEqual(@as(usize, 2), files[0].hunks.len);
    const out = try apply(arena, "one\ntwo\nthree\nfour\nfive\nsix\n", files[0]);
    try std.testing.expectEqualStrings("one\none and a half\ntwo\nthree\nfour\nfive\nSIX\n", out);
}

test "a hunk at another line applies where it matches once; nowhere or twice fails" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const files = try parse(arena,
        \\--- a/f
        \\+++ b/f
        \\@@ -1,1 +1,1 @@
        \\-b
        \\+B
        \\
    );
    try std.testing.expectEqualStrings("a\r\nB\nc", try apply(arena, "a\r\nb\r\nc", files[0]));
    try std.testing.expectError(error.HunkFailed, apply(arena, "a\nc\n", files[0]));
    try std.testing.expectError(error.HunkFailed, apply(arena, "x\nb\nb\n", files[0]));
}

test "a file name: a/ or b/ and a timestamp go" {
    try std.testing.expectEqualStrings("dir/x.c", stripPrefix("a/dir/x.c\t2026-01-01 00:00"));
    try std.testing.expectEqualStrings("x.c", stripPrefix("x.c"));
}

test "a broken patch is an error" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectError(error.BadPatch, parse(arena_state.allocator(), "@@ -1 +1 @@\n-a\n+b\n"));
    try std.testing.expectError(error.BadPatch, parse(arena_state.allocator(), "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n"));
}
