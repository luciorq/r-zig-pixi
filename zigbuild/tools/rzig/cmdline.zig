//! Argument tests the way the bash shims wrote them.
const std = @import("std");
const mem = std.mem;

pub const Args = []const []const u8;

// The shims tested `[[ " $* " == *pattern* ]]`. For a pattern with no
// space inside that is "some argument contains it"; for " word ", "some
// argument has it as a space-separated word" (in practice: is it).

pub fn anyContains(args: Args, needle: []const u8) bool {
    for (args) |x| if (mem.find(u8, x, needle) != null) return true;
    return false;
}

pub fn anyWord(args: Args, word: []const u8) bool {
    for (args) |x| {
        var it = mem.splitScalar(u8, x, ' ');
        while (it.next()) |w| if (mem.eql(u8, w, word)) return true;
    }
    return false;
}

/// `-c`, `-S`, `-E`, `-M` or `-MM`: no link happens.
pub fn compileOnly(args: Args) bool {
    for (args) |x| {
        for ([_][]const u8{ "-c", "-S", "-E", "-M", "-MM" }) |f| if (mem.eql(u8, x, f)) return true;
    }
    return false;
}

/// The value of the one-argument forms `-L<dir>` and `-l<name>`; the
/// two-argument `-L dir` is not one (the shims' `-L?*`).
pub fn flagValue(x: []const u8, comptime flag: []const u8) ?[]const u8 {
    return if (x.len > flag.len and mem.startsWith(u8, x, flag)) x[flag.len..] else null;
}

/// The `-L<dir>` directories, in order.
pub fn libDirs(gpa: mem.Allocator, args: Args) !std.ArrayList([]const u8) {
    var dirs: std.ArrayList([]const u8) = .empty;
    for (args) |x| if (flagValue(x, "-L")) |d| try dirs.append(gpa, d);
    return dirs;
}

/// Options that read the next argument as their value (clang's separate
/// forms seen on compile and link lines): a `-o` there is no output flag.
const takes_value = std.StaticStringMap(void).initComptime(.{
    .{"-Xlinker"},         .{"-Xclang"},                .{"-Xpreprocessor"},         .{"-Xassembler"},
    .{"-Xanalyzer"},       .{"-Xopenmp-target"},        .{"-x"},                     .{"-MF"},
    .{"-MT"},              .{"-MQ"},                    .{"-MJ"},                    .{"-include"},
    .{"-imacros"},         .{"-include-pch"},           .{"-isystem"},               .{"-idirafter"},
    .{"-iquote"},          .{"-iprefix"},               .{"-iwithprefix"},           .{"-iwithprefixbefore"},
    .{"-isysroot"},        .{"-iframework"},            .{"-cxx-isystem"},           .{"-I"},
    .{"-L"},               .{"-D"},                     .{"-U"},                     .{"-l"},
    .{"-F"},               .{"-B"},                     .{"-framework"},             .{"-weak_framework"},
    .{"-arch"},            .{"-target"},                .{"-z"},                     .{"-u"},
    .{"-T"},               .{"-e"},                     .{"-rpath"},                 .{"-install_name"},
    .{"-current_version"}, .{"-compatibility_version"}, .{"-exported_symbols_list"}, .{"-unexported_symbols_list"},
    .{"-bundle_loader"},   .{"-mllvm"},                 .{"--param"},                .{"--sysroot"},
    .{"-dependency-file"},
});

/// Where the first standalone `-o` is: one that is not the value of
/// another option (`-Xlinker -o`, `-MF -o`). null when there is none (a
/// joined `-ofile`, a compile to the default name, `-E`).
pub fn outputIndex(args: Args) ?usize {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "-o")) return i;
        if (takes_value.has(args[i])) i += 1;
    }
    return null;
}

const testing = std.testing;

test outputIndex {
    try testing.expectEqual(@as(?usize, 2), outputIndex(&.{ "-shared", "-L/a", "-o", "p.so", "-o", "q" }));
    try testing.expectEqual(@as(?usize, 0), outputIndex(&.{ "-o", "conftest", "conftest.c" }));
    try testing.expectEqual(@as(?usize, 5), outputIndex(&.{ "-Xlinker", "-o", "-MF", "-o", "a.c", "-o", "a" }));
    try testing.expectEqual(@as(?usize, null), outputIndex(&.{ "-olibx.so", "x.o" }));
    try testing.expectEqual(@as(?usize, null), outputIndex(&.{ "-c", "a.c" }));
    try testing.expectEqual(@as(?usize, null), outputIndex(&.{"-Xclang"}));
    // the value of -o is the output's name, even when it is "-o"
    try testing.expectEqual(@as(?usize, 0), outputIndex(&.{ "-o", "-o" }));
}

test anyWord {
    try testing.expect(anyWord(&.{ "a", "-shared" }, "-shared"));
    try testing.expect(anyWord(&.{"-DX=a -shared b"}, "-shared"));
    try testing.expect(anyWord(&.{"-shared "}, "-shared"));
    try testing.expect(!anyWord(&.{"-Wl,-shared"}, "-shared"));
    try testing.expect(!anyWord(&.{}, "-shared"));
}

test anyContains {
    try testing.expect(anyContains(&.{ "a", "-fopenmp-simd" }, "-fopenmp"));
    try testing.expect(anyContains(&.{"-Wl,-soname,x"}, "-soname"));
    try testing.expect(!anyContains(&.{ "-fopen", "mp" }, "-fopenmp"));
}

test compileOnly {
    for ([_][]const u8{ "-c", "-S", "-E", "-M", "-MM" }) |f| try testing.expect(compileOnly(&.{ "a.c", f }));
    try testing.expect(!compileOnly(&.{ "-MD", "-MF", "a.d", "-o", "a", "a.c" }));
}

test libDirs {
    var dirs = try libDirs(testing.allocator, &.{ "-L/a", "-L", "/sep", "-l", "x", "-L/b", "-L" });
    defer dirs.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), dirs.items.len);
    try testing.expectEqualStrings("/a", dirs.items[0]);
    try testing.expectEqualStrings("/b", dirs.items[1]);
    try testing.expectEqualStrings("m", flagValue("-lm", "-l").?);
    try testing.expect(flagValue("-l", "-l") == null);
}
