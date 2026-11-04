//! Response files: `@file` on a command line stands for the words in
//! file. rzig build's tier-1 and tier-2 links name their objects that way
//! (zigbuild/rpkg/build_t1.zig's objectsFile, feat-win-link-fixes item 1):
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
//! line; build_t1.zig writes no name it would not give back. One level: a
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

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test split {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // build_t1.zig's lines: a name in double quotes, LF or CRLF; a space,
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
