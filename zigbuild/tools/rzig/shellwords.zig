//! The words a POSIX shell would hand a program from one make recipe line,
//! without a shell: `'...'`, `"..."` and backslash quoting removed,
//! whitespace separating. Makeconf writes `-I"$(R_INCLUDE_DIR)"`,
//! install.R `-I'/lib/pkg/include'`; the result is what rzig gets in argv
//! under make. Anything a shell would interpret beyond quoting (a `$`, a
//! pipe, a redirect, a glob, a backquote) is refused: that package needs
//! the make path (pkgplan.zig).
//!
//! `splitWith` with `.shell` set reads the line as sh does for `echo`
//! (R CMD config, config.zig): `$NAME` and `${NAME}` from the environment
//! make gives its recipes, `~` at a word's start as HOME, `#` at a word's
//! start as a comment. An unquoted glob character is refused too: sh
//! would match it against the caller's directory. Command substitution,
//! special parameters and the other metacharacters are refused.
//!
//! `.msys_make` (R CMD config on a Windows host): MSYS's make runs a
//! recipe line with no unquoted shell metacharacter itself, without sh,
//! and keeps a backslash that does not precede `\`, `'`, whitespace or a
//! metacharacter (GNU make's HAVE_DOS_PATHS): `echo C:\jdk\x64` prints
//! `C:\jdk\x64` there, and `C:jdkx64` through sh. Checked on kappa with
//! R's toolchain make (GNU Make 4.4.1, MSYS), 2026-11-15.
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const Error = error{ Unsupported, OutOfMemory };

pub const Options = struct {
    /// Read as sh does; null: quoting only (split).
    shell: ?*const std.process.Environ.Map = null,
    /// The line is a recipe line of MSYS's make (see above).
    msys_make: bool = false,
};

/// GNU make's unix `sh_chars`: one of them, unquoted and unescaped, makes
/// make run the line through sh.
const sh_chars = "#;\"*?[]&|<>(){}$`^~!";

/// Whether make runs `text` through sh (GNU make's
/// construct_command_argv_internal, unix rules): an unescaped `sh_chars`
/// character outside single quotes. A double quote is one of them.
fn makeRunsShell(text: []const u8) bool {
    var in_single = false;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (in_single) {
            if (c == '\'') in_single = false;
        } else if (mem.findScalar(u8, sh_chars, c) != null) {
            return true;
        } else if (c == '\\' and i + 1 < text.len) {
            i += 1;
        } else if (c == '\'') {
            in_single = true;
        }
    }
    return false;
}

/// `text`'s words, or error.Unsupported with `reason` set.
pub fn split(a: Allocator, text: []const u8, reason: *[]const u8) Error![]const []const u8 {
    return splitWith(a, text, .{}, reason);
}

/// `split`, or with `opts.shell` the words sh hands `echo` (see above).
pub fn splitWith(a: Allocator, text: []const u8, opts: Options, reason: *[]const u8) Error![]const []const u8 {
    // MSYS make without sh: a backslash before an ordinary character stays
    const dos_backslash = opts.msys_make and !makeRunsShell(text);
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
                        if (opts.shell == null and (text[i + 1] == '$' or text[i + 1] == '`')) return refuse(reason, a, "a shell expansion in '{s}'", .{text});
                        try word.append(a, text[i + 1]);
                        i += 1;
                        continue;
                    }
                    if (d == '$') if (opts.shell) |env| {
                        const p = try parameter(a, text, i, env, reason);
                        try word.appendSlice(a, p.value);
                        i = p.end - 1;
                        continue;
                    };
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
                const n = text[i + 1];
                if (dos_backslash and mem.findScalar(u8, "\\' \t\r", n) == null and mem.findScalar(u8, sh_chars, n) == null)
                    try word.append(a, '\\');
                try word.append(a, n);
                i += 1;
            },
            '$' => {
                const env = opts.shell orelse return refuse(reason, a, "a shell metacharacter '{c}' in '{s}'", .{ c, text });
                // unquoted: the value's words (sh's field splitting)
                const p = try parameter(a, text, i, env, reason);
                if (mem.findAny(u8, p.value, "*?[") != null) return refuse(reason, a, "an unquoted expansion with a glob character in '{s}'", .{text});
                for (p.value) |v| switch (v) {
                    ' ', '\t', '\n' => if (in_word) {
                        try out.append(a, try word.toOwnedSlice(a));
                        in_word = false;
                    },
                    else => {
                        in_word = true;
                        try word.append(a, v);
                    },
                };
                i = p.end - 1;
            },
            '`', '*', '?', '[', '|', '&', ';', '<', '>', '(', ')' => return refuse(reason, a, "a shell metacharacter '{c}' in '{s}'", .{ c, text }),
            '#' => {
                if (!in_word) {
                    if (opts.shell == null) return refuse(reason, a, "a shell comment in '{s}'", .{text});
                    break; // the rest of the line is the comment
                }
                try word.append(a, c);
            },
            '~' => {
                if (!in_word) {
                    const env = opts.shell orelse return refuse(reason, a, "a tilde expansion in '{s}'", .{text});
                    const end = i + 1 == text.len or mem.findScalar(u8, "/ \t\n", text[i + 1]) != null;
                    if (!end) return refuse(reason, a, "a tilde expansion of a user's home in '{s}'", .{text});
                    try word.appendSlice(a, env.get("HOME") orelse "");
                    in_word = true;
                    continue;
                }
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

/// `$NAME` or `${NAME}` at `text[start]`: the variable's value ("" when
/// unset) and the index after it. A `$` that starts no parameter is
/// itself. Special parameters, `${...}` with an operator and `$(...)` are
/// refused.
fn parameter(a: Allocator, text: []const u8, start: usize, env: *const std.process.Environ.Map, reason: *[]const u8) Error!struct { value: []const u8, end: usize } {
    const i = start + 1;
    if (i >= text.len) return .{ .value = "$", .end = i };
    const c = text[i];
    if (c == '{') {
        const close = mem.findScalarPos(u8, text, i + 1, '}') orelse return refuse(reason, a, "an unclosed ${{ in '{s}'", .{text});
        const name = text[i + 1 .. close];
        if (!isName(name)) return refuse(reason, a, "a shell expansion ${{{s}}} in '{s}'", .{ name, text });
        return .{ .value = env.get(name) orelse "", .end = close + 1 };
    }
    if (c == '_' or std.ascii.isAlphabetic(c)) {
        var j = i;
        while (j < text.len and (text[j] == '_' or std.ascii.isAlphanumeric(text[j]))) j += 1;
        return .{ .value = env.get(text[i..j]) orelse "", .end = j };
    }
    if (std.ascii.isDigit(c) or mem.findScalar(u8, "@*#?-$!(", c) != null) return refuse(reason, a, "a shell expansion '${c}' in '{s}'", .{ c, text });
    return .{ .value = "$", .end = i };
}

fn isName(s: []const u8) bool {
    if (s.len == 0 or std.ascii.isDigit(s[0])) return false;
    for (s) |c| if (!(c == '_' or std.ascii.isAlphanumeric(c))) return false;
    return true;
}

/// `word` as a POSIX shell reads it back as that one word: itself when
/// it holds only characters no shell treats specially, else in single
/// quotes, each `'` written `'\''`. `rzig build --shlib --dry-run` prints
/// its commands so (pkgbuild.zig's printCommands): `split` of the line
/// gives the words back.
pub fn quote(a: Allocator, word: []const u8) error{OutOfMemory}![]const u8 {
    const plain = for (word) |c| {
        if (!(std.ascii.isAlphanumeric(c) or mem.findScalar(u8, "_@%+=:,./-", c) != null)) break false;
    } else word.len > 0;
    if (plain) return word;
    var out: std.ArrayList(u8) = .empty;
    try out.append(a, '\'');
    for (word) |c| if (c == '\'') try out.appendSlice(a, "'\\''") else try out.append(a, c);
    try out.append(a, '\'');
    return out.items;
}

fn refuse(reason: *[]const u8, a: Allocator, comptime f: []const u8, args: anytype) Error {
    reason.* = std.fmt.allocPrint(a, f, args) catch "out of memory";
    return error.Unsupported;
}

const testing = std.testing;
const testutil = @import("testutil.zig");

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

fn expectShellWords(expected: []const []const u8, text: []const u8, env: *const std.process.Environ.Map) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var reason: []const u8 = "";
    const got = try splitWith(arena.allocator(), text, .{ .shell = env }, &reason);
    try testutil.expectArgs(expected, got);
}

test "splitWith: sh's words for echo" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var env: std.process.Environ.Map = .init(arena.allocator());
    try env.put("HOME", "/home/u");
    try env.put("R_HOME", "/opt/my R");
    try env.put("TWO", " a  b ");
    try expectShellWords(&.{ "-L/x y/lib", "-lR" }, "-L\"/x y/lib\" -lR", &env);
    try expectShellWords(&.{ "/home/u/x", "/opt/my", "R/y", "/opt/my R", "$", "a$" }, "$HOME/x ${R_HOME}/y \"$R_HOME\" $ a$", &env);
    try expectShellWords(&.{ "x", "a", "b", "y" }, "x$TWO\"\"y", &env);
    try expectShellWords(&.{ "/home/u/y", "/home/u", "a~", "x" }, "~/y ~ a~ x #c d", &env);
    try expectShellWords(&.{ "*.mk", "[a]", "?", "a#b" }, "'*.mk' \"[a]\" \\? a\\#b", &env);
    try expectShellWords(&.{ "a  b", "c", "d" }, "\"a  b\"   c\td", &env);
    try expectShellWords(&.{"-DX=\"q\""}, "-DX=\\\"q\\\"", &env);
    var reason: []const u8 = "";
    try env.put("GLOB", "a*");
    for ([_][]const u8{ "`uname`", "$(uname)", "a;b", "a|b", "$1", "${X:-y}", "~root/x", "\"$(x)\"", "*", "-I[a]", "x?", "$GLOB" }) |bad| {
        try testing.expectError(error.Unsupported, splitWith(arena.allocator(), bad, .{ .shell = &env }, &reason));
    }
}

test "splitWith: MSYS make's backslashes (Windows host)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var env: std.process.Environ.Map = .init(a);
    try env.put("HOME", "/c/Users/u");
    const T = struct { line: []const u8, words: []const []const u8 };
    // the outputs of `echo <line>` under R's toolchain make on kappa
    for ([_]T{
        .{ .line = "C:\\host\\windows\\jdk\\17\\x64", .words = &.{"C:\\host\\windows\\jdk\\17\\x64"} },
        .{ .line = "a\\\\b", .words = &.{"a\\b"} },
        .{ .line = "a\\ b", .words = &.{"a b"} },
        .{ .line = "a\\'b", .words = &.{"a'b"} },
        .{ .line = "a\\*b a\\#b a\\~b a\\!b a\\{b", .words = &.{ "a*b", "a#b", "a~b", "a!b", "a{b" } },
        .{ .line = "a\\=b a\\%b \\a x \\y", .words = &.{ "a\\=b", "a\\%b", "\\a", "x", "\\y" } },
        .{ .line = "a\\\\\\b", .words = &.{"a\\\\b"} },
        .{ .line = "'a\\\\b'", .words = &.{"a\\\\b"} },
        // through sh: a metacharacter in the line ($), or a double quote
        .{ .line = "C:\\x $HOME", .words = &.{ "C:x", "/c/Users/u" } },
        .{ .line = "\"C:\\q x\" C:\\y", .words = &.{ "C:\\q x", "C:y" } },
    }) |t| {
        var reason: []const u8 = "";
        const got = try splitWith(a, t.line, .{ .shell = &env, .msys_make = true }, &reason);
        try testutil.expectArgs(t.words, got);
    }
    // without .msys_make: sh's rules
    var reason: []const u8 = "";
    try testutil.expectArgs(&.{"C:hostx64"}, try splitWith(a, "C:\\host\\x64", .{ .shell = &env }, &reason));
}

test quote {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("-I/R/include", try quote(a, "-I/R/include"));
    try testing.expectEqualStrings("-Wl,-install_name,sub/x.so", try quote(a, "-Wl,-install_name,sub/x.so"));
    try testing.expectEqualStrings("'-L/a b'", try quote(a, "-L/a b"));
    try testing.expectEqualStrings("''", try quote(a, ""));
    try testing.expectEqualStrings("'it'\\''s'", try quote(a, "it's"));
    // split(join(quote(w))) gives the words back
    const words = [_][]const u8{ "/R/bin/toolchain/zig-cc", "-DX=\"a b\"", "-L/opt/my R/lib", "", "it's", "$(HOME)", "a\\b", "~x", "#c", "*.o", "-DY=1;2", "tab\there" };
    var line: std.ArrayList(u8) = .empty;
    for (words, 0..) |w, i| {
        if (i > 0) try line.append(a, ' ');
        try line.appendSlice(a, try quote(a, w));
    }
    var reason: []const u8 = "";
    const back = try split(a, line.items, &reason);
    try testing.expectEqual(words.len, back.len);
    for (words, back) |w, b| try testing.expectEqualStrings(w, b);
}
