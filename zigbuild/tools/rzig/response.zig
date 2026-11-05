//! Response files: `@file` on a command line stands for the words in
//! file. rzig build's tier-1 and tier-2 links name their objects that way
//! (tier1.zig's objectsFile, feat-win-link-fixes item 1):
//! a package with a few hundred objects made a command line longer than
//! Windows' 32,767 characters, and `rzig def` and the link failed to start
//! (NameTooLong; libgeos with its unix Makevars, about 390 objects).
//!
//! zig cc reads `@file` itself, with both zigs, so the compilers pass it
//! on untouched. rzig reads it only where it reads the objects: `rzig def`
//! (def.zig), linux's debug-info test (strip.zig) and RZIG_TRACE's line
//! (main.zig), so a traced link shows its objects as make's does. The
//! words as zig cc splits them: std.process.Args.IteratorGeneral with
//! comments and single quotes, zig's own reader. `"` quotes, `\` is
//! literal unless before a quote, `#` at a word's start comments out the
//! line; tier1.zig writes no name it would not give back. One level: a
//! word inside the file that starts with `@` stays a word. A file that
//! cannot be read stays `@file`, as zig cc then takes it (an input named
//! so).
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const Args = @import("cmdline.zig").Args;

/// zig cc's reader of response files.
pub const Words = std.process.Args.IteratorGeneral(.{ .comments = true, .single_quotes = true });

/// `args` with each readable `@file` replaced by its words.
pub fn expand(ctx: *Ctx, args: Args) !Args {
    var out: ?std.ArrayList([]const u8) = null;
    for (args, 0..) |x, i| {
        const words = (try read(ctx, x)) orelse {
            if (out) |*o| try o.append(ctx.arena, x);
            continue;
        };
        if (out == null) {
            out = .empty;
            try out.?.appendSlice(ctx.arena, args[0..i]);
        }
        try out.?.appendSlice(ctx.arena, words);
    }
    return if (out) |o| o.items else args;
}

/// The words of `@file`, or null when `x` is no `@file` or the file
/// cannot be read.
fn read(ctx: *Ctx, x: []const u8) !?Args {
    if (x.len < 2 or x[0] != '@') return null;
    const text = Io.Dir.cwd().readFileAlloc(ctx.io, x[1..], ctx.arena, .limited(64 * 1024 * 1024)) catch return null;
    return try split(ctx.arena, text);
}

/// `text`'s words, as zig cc reads a response file. With a newline
/// after it: zig 0.16's IteratorGeneral reads past the end of a text that
/// ends inside a comment (an index out of bounds, `# x` with no newline
/// after it); the newline changes no word.
pub fn split(a: mem.Allocator, text: []const u8) ![]const []const u8 {
    var it = try Words.init(a, try mem.concat(a, u8, &.{ text, "\n" }));
    var out: std.ArrayList([]const u8) = .empty;
    while (it.next()) |w| try out.append(a, try a.dupe(u8, w));
    return out.items;
}

/// `obj` relative to `srcdir` (std.fs.path.relative), with `/` on
/// Windows, and `./` before a name that does not start with `.`, so a
/// name never starts with `-`, which zig cc would take for an option (a
/// build root under src/-tmp: `Unknown Clang option`). On another Windows
/// drive: the absolute path. Both paths absolute.
pub fn rspName(gpa: mem.Allocator, env: ?*const std.process.Environ.Map, srcdir: []const u8, obj: []const u8) ![]const u8 {
    var rel = try std.fs.path.relative(gpa, srcdir, env, srcdir, obj);
    if (!std.fs.path.isAbsolute(rel) and !mem.startsWith(u8, rel, ".")) rel = try std.fs.path.join(gpa, &.{ ".", rel });
    if (@import("builtin").os.tag == .windows) mem.replaceScalar(u8, rel, '\\', '/');
    return rel;
}

/// A response file's text: `"<name>"` and a newline per name; null when a
/// name holds a `'`, `"` or `\`, which zig's reader cannot give back
/// (it pairs `'` with `"`). rzig build's objects.rsp (tier1.zig): each
/// object relative to srcdir (rspName), where the link runs, so a
/// directory every name shares, as C:/Users/O'Brien/..., drops out.
pub fn rspText(gpa: mem.Allocator, names: []const []const u8) !?[]const u8 {
    var out = std.ArrayList(u8).empty;
    for (names) |n| {
        if (mem.findAny(u8, n, "'\"\\") != null) return null;
        try out.print(gpa, "\"{s}\"\n", .{n});
    }
    return out.items;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test split {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // tier1.zig's lines: a name in double quotes, LF or CRLF; a space,
    // UTF-8, a `#` inside a quoted word
    try expectArgs(
        &.{ "../obj/0/a.o", "C:/rz wf ção/obj/1/b c.o", "../#x/obj/2/d.o", "e.o" },
        try split(a, "\"../obj/0/a.o\"\n\"C:/rz wf ção/obj/1/b c.o\"\r\n\"../#x/obj/2/d.o\"\r\n\"e.o\""),
    );
    // bare words, tabs, a comment line, a `#` that starts a word
    try expectArgs(&.{ "-shared", "-o", "p.dll", "x#y" }, try split(a, "# objects\n-shared\t-o p.dll\n#c.o\nx#y\n"));
    // `\` literal unless before a quote; an escaped quote
    try expectArgs(&.{ "C:\\a\\b.o", "a\"b" }, try split(a, "C:\\a\\b.o \"a\\\"b\""));
    try expectArgs(&.{}, try split(a, ""));
    try expectArgs(&.{}, try split(a, "\n\r\n# only a comment"));
}

test expand {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    try f.write("objs.rsp", "\"../obj/0/a.o\"\r\n\"sp ace/ção.o\"\n\"@nested.rsp\"\n", .default_file);
    try f.write("nested.rsp", "\"never.o\"\n", .default_file);
    try f.write("empty.rsp", "", .default_file);
    const at = f.fmt("@{s}", .{f.path("objs.rsp")});
    // the words in place, the rest kept; one level only
    try expectArgs(
        &.{ "-shared", "-o", "p.dll", "first.o", "../obj/0/a.o", "sp ace/ção.o", "@nested.rsp", "-lR" },
        try expand(c, &.{ "-shared", "-o", "p.dll", "first.o", at, "-lR" }),
    );
    // an empty file: no words; a missing file, `@` alone: kept
    try expectArgs(&.{ "a.o", "b.o" }, try expand(c, &.{ "a.o", f.fmt("@{s}", .{f.path("empty.rsp")}), "b.o" }));
    const kept: Args = &.{ "@", f.fmt("@{s}", .{f.path("nowhere.rsp")}), "x@y.o" };
    try expectArgs(kept, try expand(c, kept));
    // no `@file`: the same slice
    const plain: Args = &.{ "-c", "a.c" };
    try testing.expectEqual(plain.ptr, (try expand(c, plain)).ptr);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "rspText: every name back from zig's reader, LF or CRLF; none for a ', \" or \\" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // relative names as tier1.zig's objectsFile writes them: a space,
    // UTF-8, a `#` at a part's start and at the name's, an `@`
    const names = [_][]const u8{ "../../tmp/RtmpX/R.INSTALL1/.rzig/obj/0/a.o", "../rz wf ção/obj/1/b c.o", "../#x/obj/2/d.o", "#e.o", "../@f/obj/3/g.o", "C:/Users/a b/obj/4/h.o" };
    const text = (try rspText(a, &names)).?;
    try testing.expectEqualStrings("\"../../tmp/RtmpX/R.INSTALL1/.rzig/obj/0/a.o\"\n", text[0 .. mem.indexOfScalar(u8, text, '\n').? + 1]);
    try expectArgs(&names, try split(a, text));
    try expectArgs(&names, try split(a, try mem.replaceOwned(u8, a, text, "\n", "\r\n")));
    try expectArgs(&.{}, try split(a, (try rspText(a, &.{})).?));
    for ([_][]const u8{ "../O'Brien/obj/0/a.o", "a\"b.o", "dir\\a.o" }) |bad| try testing.expect(try rspText(a, &.{ "ok.o", bad }) == null);
}

test "rspName: relative to srcdir, wherever the root is; never a leading -" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (@import("builtin").os.tag == .windows) {
        // `/` between the parts; a `'` the two share drops out; another
        // drive: absolute
        try testing.expectEqualStrings("../.rzig/obj/0/a.o", try rspName(a, null, "C:\\Users\\O'Brien\\pkg\\src", "C:/Users/O'Brien/pkg/.rzig/obj/0/a.o"));
        try testing.expectEqualStrings("../../Temp/RtmpX/.rzig.0123/obj/0/f.o", try rspName(a, null, "C:\\Users\\me\\proj\\src", "C:/Users/me/Temp/RtmpX/.rzig.0123/obj/0/f.o"));
        try testing.expectEqualStrings("D:/t/.rzig/obj/0/a.o", try rspName(a, null, "C:\\pkg\\src", "D:/t/.rzig/obj/0/a.o"));
        try testing.expectEqualStrings("./-tmp/.rzig/obj/0/a.o", try rspName(a, null, "C:\\pkg\\src", "C:/pkg/src/-tmp/.rzig/obj/0/a.o"));
    } else {
        try testing.expectEqualStrings("../.rzig/obj/0/a.o", try rspName(a, null, "/home/O'Brien/pkg/src", "/home/O'Brien/pkg/.rzig/obj/0/a.o"));
        try testing.expectEqualStrings("../../tmp/RtmpX/.rzig.0123/obj/0/f.o", try rspName(a, null, "/home/me/src", "/home/tmp/RtmpX/.rzig.0123/obj/0/f.o"));
        // a `'` the two do not share: kept, so no response file (rspText)
        try testing.expectEqualStrings("../O'Brien/t/obj/0/a.o", try rspName(a, null, "/home/me", "/home/O'Brien/t/obj/0/a.o"));
        // a root below srcdir: `./` first, so `-tmp` is not an option; a
        // `.` name as it is
        try testing.expectEqualStrings("./-tmp/RtmpX/.rzig.0123/obj/0/f.o", try rspName(a, null, "/home/me/src", "/home/me/src/-tmp/RtmpX/.rzig.0123/obj/0/f.o"));
        try testing.expectEqualStrings("./obj/0/a.o", try rspName(a, null, "/home/me/src", "/home/me/src/obj/0/a.o"));
        try testing.expectEqualStrings(".rzig/obj/0/a.o", try rspName(a, null, "/home/me/src", "/home/me/src/.rzig/obj/0/a.o"));
    }
}
