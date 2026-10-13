//! The words a POSIX shell would hand a program from one make recipe line,
//! without a shell: `'...'`, `"..."` and backslash quoting removed,
//! whitespace separating. Makeconf writes `-I"$(R_INCLUDE_DIR)"`,
//! install.R `-I'/lib/pkg/include'`; the result is what rzig gets in argv
//! under make. Anything a shell would interpret beyond quoting (a `$`, a
//! pipe, a redirect, a glob, a backquote) is refused: that package needs
//! the make path (pkgplan.zig).
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const Error = error{ Unsupported, OutOfMemory };

pub const Result = struct {
    words: []const []const u8,
    /// Why the split was refused (error.Unsupported), for the message.
    reason: []const u8 = "",
};

/// `text`'s words, or error.Unsupported with `reason` set.
pub fn split(a: Allocator, text: []const u8, reason: *[]const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var word: std.ArrayList(u8) = .empty;
    var in_word = false;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        switch (c) {
            ' ', '\t', '\n', '\r' => {
                if (in_word) {
                    try out.append(a, try word.toOwnedSlice(a));
                    in_word = false;
                }
            },
            '\'' => {
                in_word = true;
                const close = mem.findScalarPos(u8, text, i + 1, '\'') orelse return refuse(reason, a, "an unclosed single quote in '{s}'", .{text});
                try word.appendSlice(a, text[i + 1 .. close]);
                i = close;
            },
            '"' => {
                in_word = true;
                i += 1;
                while (true) : (i += 1) {
                    if (i >= text.len) return refuse(reason, a, "an unclosed double quote in '{s}'", .{text});
                    const d = text[i];
                    if (d == '"') break;
                    if (d == '\\' and i + 1 < text.len and mem.findScalar(u8, "\"\\$`\n", text[i + 1]) != null) {
                        if (text[i + 1] == '\n') {
                            i += 1;
                            continue;
                        }
                        if (text[i + 1] == '$' or text[i + 1] == '`') return refuse(reason, a, "a shell expansion in '{s}'", .{text});
                        try word.append(a, text[i + 1]);
                        i += 1;
                        continue;
                    }
                    if (d == '$' or d == '`') return refuse(reason, a, "a shell expansion in '{s}'", .{text});
                    try word.append(a, d);
                }
            },
            '\\' => {
                if (i + 1 >= text.len) return refuse(reason, a, "a trailing backslash in '{s}'", .{text});
                if (text[i + 1] == '\n') {
                    i += 1;
                    continue;
                }
                in_word = true;
                try word.append(a, text[i + 1]);
                i += 1;
            },
            '$', '`', '|', '&', ';', '<', '>', '(', ')', '*', '?', '[' => return refuse(reason, a, "a shell metacharacter '{c}' in '{s}'", .{ c, text }),
            '#' => {
                if (!in_word) return refuse(reason, a, "a shell comment in '{s}'", .{text});
                try word.append(a, c);
            },
            '~' => {
                if (!in_word) return refuse(reason, a, "a tilde expansion in '{s}'", .{text});
                try word.append(a, c);
            },
            else => {
                in_word = true;
                try word.append(a, c);
            },
        }
    }
    if (in_word) try out.append(a, try word.toOwnedSlice(a));
    return out.items;
}

fn refuse(reason: *[]const u8, a: Allocator, comptime f: []const u8, args: anytype) Error {
    reason.* = std.fmt.allocPrint(a, f, args) catch "out of memory";
    return error.Unsupported;
}

const testing = std.testing;

fn expectWords(expected: []const []const u8, text: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var reason: []const u8 = "";
    const got = try split(arena.allocator(), text, &reason);
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| try testing.expectEqualStrings(e, g);
}

test split {
    try expectWords(&.{ "/R/bin/toolchain/zig-cc", "-std=gnu23", "-I/R/include", "-DNDEBUG", "-I/lib/Rcpp/include", "-fpic", "-O2" }, "/R/bin/toolchain/zig-cc -std=gnu23  -I\"/R/include\" -DNDEBUG -I'/lib/Rcpp/include'   -fpic -O2 ");
    try expectWords(&.{ "-L/opt/my R/lib", "-lR" }, "-L\"/opt/my R/lib\" -lR");
    try expectWords(&.{ "-DX=\"a\"", "-DY=a b" }, "-DX='\"a\"' -DY=a\\ b");
    try expectWords(&.{ "", "x" }, "'' x");
    try expectWords(&.{"a\"b"}, "\"a\\\"b\"");
    try expectWords(&.{}, "   ");
    try expectWords(&.{ "a", "b" }, "a \\\n b");
    try expectWords(&.{"-DX=a#b"}, "-DX=a#b");

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var reason: []const u8 = "";
    for ([_][]const u8{ "$(shell x)", "`uname`", "a | b", "a > out", "*.o", "a; b", "\"$HOME\"", "'unclosed", "~/lib", "# comment", "a \\" }) |bad| {
        try testing.expectError(error.Unsupported, split(arena.allocator(), bad, &reason));
        try testing.expect(reason.len > 0);
    }
}
