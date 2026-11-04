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

/// Any -g option (-g, -g0 to -g3, -ggdb, -gdwarf-5, -gline-tables-only,
/// ...): the caller's choice of debug info.
pub fn debugOption(args: Args) bool {
    for (args) |x| if (mem.startsWith(u8, x, "-g")) return true;
    return false;
}

/// The value of the one-argument forms `-L<dir>` and `-l<name>`; the
/// two-argument `-L dir` is not one (the shims' `-L?*`).
pub fn flagValue(x: []const u8, comptime flag: []const u8) ?[]const u8 {
    return if (x.len > flag.len and mem.startsWith(u8, x, flag)) x[flag.len..] else null;
}

/// Whether args[i] is the value of `-Xarch_<arch>`: zig hands it to
/// clang's driver as it is, for that architecture only, so it is clang's
/// spelling (abseil's CMake on macOS: `-Xarch_arm64 -march=armv8-a+crypto`).
pub fn xarchValue(args: Args, i: usize) bool {
    return i > 0 and mem.startsWith(u8, args[i - 1], "-Xarch_");
}

/// The `-L<dir>` directories, in order.
pub fn libDirs(gpa: mem.Allocator, args: Args) !std.ArrayList([]const u8) {
    var dirs: std.ArrayList([]const u8) = .empty;
    for (args) |x| if (flagValue(x, "-L")) |d| try dirs.append(gpa, d);
    return dirs;
}

/// Options that read the next argument as their value (clang's separate
/// forms seen on compile and link lines, and flang's): a `-o` there is no
/// output flag, and no input file. zig-fc's split builds its commands
/// from `inputs` (fortran.zig), so a value read as an input would be
/// compiled or linked on its own and leave its option dangling: `-J mods`
/// (gfortran's module directory, which flang takes too), `-undefined
/// dynamic_lookup` on macOS's SHLIB line (feat-standalone-toolchain phase
/// 6, Cc2).
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
    .{"-dependency-file"}, .{"-undefined"},             .{"-force_load"},            .{"-multiply_defined"},
    .{"-Xflang"},          .{"-J"},                     .{"-module-dir"},            .{"-fintrinsic-modules-path"},
});

/// Whether `x` reads the next argument as its value (`takes_value`).
pub fn takesValue(x: []const u8) bool {
    return takes_value.has(x);
}

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

/// The positions of the input files: arguments that are no option and no
/// option's value (`-o`'s included). `-` (standard input) is none.
pub fn inputs(args: Args) Inputs {
    return .{ .args = args };
}

pub const Inputs = struct {
    args: Args,
    i: usize = 0,

    pub fn next(it: *Inputs) ?usize {
        while (it.i < it.args.len) {
            const i = it.i;
            const x = it.args[i];
            it.i += 1;
            if (mem.eql(u8, x, "-o") or takes_value.has(x)) {
                it.i += 1;
            } else if (x.len > 0 and x[0] != '-') {
                return i;
            }
        }
        return null;
    }
};

/// A file a compiler driver would compile, by its extension: Fortran's
/// (fixed and free form, preprocessed or not) and the C family's.
pub fn isSource(x: []const u8) bool {
    if (x.len == 0 or x[0] == '-') return false;
    const dot = mem.findScalarLast(u8, x, '.') orelse return false;
    if (mem.findAny(u8, x[dot..], "/\\") != null) return false;
    return source_ext.has(x[dot + 1 ..]);
}

const fortran_ext = std.StaticStringMap(void).initComptime(.{
    // flang's driver's
    .{"f"}, .{"for"}, .{"ftn"}, .{"fpp"}, .{"f77"}, .{"f90"}, .{"f95"}, .{"f03"}, .{"f08"}, .{"cuf"},
    .{"F"}, .{"FOR"}, .{"FTN"}, .{"FPP"}, .{"F77"}, .{"F90"}, .{"F95"}, .{"F03"}, .{"F08"}, .{"CUF"},
});

const source_ext = std.StaticStringMap(void).initComptime(.{
    // Fortran (flang's driver; fortran_ext)
    .{"f"},   .{"for"}, .{"ftn"}, .{"fpp"}, .{"f77"}, .{"f90"}, .{"f95"}, .{"f03"}, .{"f08"}, .{"cuf"},
    .{"F"},   .{"FOR"}, .{"FTN"}, .{"FPP"}, .{"F77"}, .{"F90"}, .{"F95"}, .{"F03"}, .{"F08"}, .{"CUF"},
    // the C family, assembler, LLVM IR (clang's)
    .{"c"},   .{"i"},   .{"cc"},  .{"cp"},  .{"cpp"}, .{"cxx"}, .{"c++"}, .{"C"},   .{"CC"},  .{"CPP"},
    .{"CXX"}, .{"ii"},  .{"m"},   .{"mi"},  .{"mm"},  .{"mii"}, .{"M"},   .{"s"},   .{"S"},   .{"sx"},
    .{"cu"},  .{"ll"},  .{"bc"},
});

/// A Fortran source, by its extension (flang's driver's).
pub fn isFortran(x: []const u8) bool {
    if (!isSource(x)) return false;
    const ext = x[mem.findScalarLast(u8, x, '.').? + 1 ..];
    return fortran_ext.has(ext);
}

/// The language the `-x` in force at args[i] names (`-x f95` or
/// `-xf95`, until `-x none`), or null: none in force, the input's
/// extension decides, as in gcc's, clang's and flang's drivers.
pub fn xLang(args: Args, i: usize) ?[]const u8 {
    const end = @min(i, args.len);
    var lang: ?[]const u8 = null;
    var j: usize = 0;
    while (j < end) : (j += 1) {
        const x = args[j];
        const v = if (mem.eql(u8, x, "-x")) blk: {
            j += 1;
            if (j >= end) break;
            break :blk args[j];
        } else if (mem.startsWith(u8, x, "-x")) x[2..] else {
            if (takes_value.has(x)) j += 1;
            continue;
        };
        lang = if (mem.eql(u8, v, "none")) null else v;
    }
    return lang;
}

/// A Fortran language for `-x`: flang's `f95` and `f95-cpp-input`, and
/// gfortran's `f77` and `f77-cpp-input` (which flang refuses, loudly).
pub fn isFortranLang(lang: []const u8) bool {
    for ([_][]const u8{ "f95", "f95-cpp-input", "f77", "f77-cpp-input" }) |l| if (mem.eql(u8, lang, l)) return true;
    return false;
}

/// The base name of a path, after its last `/` or `\`.
pub fn baseName(x: []const u8) []const u8 {
    return if (mem.findLastAny(u8, x, "/\\")) |i| x[i + 1 ..] else x;
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

test inputs {
    const args: Args = &.{ "-o", "out", "a.o", "-x", "c", "-Iinc", "-I", "dir", "b.c", "-", "", "-Wl,x", "-Xlinker", "y", "z" };
    var it = inputs(args);
    for ([_]usize{ 2, 8, 14 }) |want| try testing.expectEqual(@as(?usize, want), it.next());
    try testing.expectEqual(@as(?usize, null), it.next());
    // an option's value at the end
    var it2 = inputs(&.{ "a", "-MF" });
    try testing.expectEqual(@as(?usize, 0), it2.next());
    try testing.expectEqual(@as(?usize, null), it2.next());
}

test isSource {
    for ([_][]const u8{ "a.f", "a.FOR", "dir/a.f03", "a.b.F95", "x.cpp", "y.c", "z.S", "C:\\s\\a.f08" }) |x| try testing.expect(isSource(x));
    for ([_][]const u8{ "a.o", "a.so", "p.dll", "tmp.def", "-fa.f", "f", "dir.f/a", "liba.a", "x.mod", "" }) |x| try testing.expect(!isSource(x));
    try testing.expectEqualStrings("a.c", baseName("src\\sub/a.c"));
    try testing.expectEqualStrings("a.c", baseName("a.c"));
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

test "inputs: Fortran's and the link's options that take a value (Cc2)" {
    var it = inputs(&.{ "-J", "mods", "-module-dir", "m2", "-fintrinsic-modules-path", "/i", "-o", "p", "a.f90", "-Xflang", "-fno-automatic", "b.f" });
    for ([_]usize{ 8, 11 }) |want| try testing.expectEqual(@as(?usize, want), it.next());
    try testing.expectEqual(@as(?usize, null), it.next());
    // a macOS SHLIB-style line: only the source
    const mac: Args = &.{ "-dynamiclib", "-undefined", "dynamic_lookup", "-force_load", "l.a", "-multiply_defined", "suppress", "-framework", "Accelerate", "-o", "x.so", "a.f90" };
    var it2 = inputs(mac);
    try testing.expectEqual(@as(?usize, 11), it2.next());
    try testing.expectEqual(@as(?usize, null), it2.next());
    try testing.expect(takesValue("-J") and !takesValue("-Jmods"));
}

test isFortran {
    for ([_][]const u8{ "a.f", "a.F90", "d/x.f95", "C:\\s\\a.f08", "a.FOR" }) |x| try testing.expect(isFortran(x));
    for ([_][]const u8{ "a.c", "a.cpp", "a.o", "a", "a.mod", "-fa.f", "dir.f/a" }) |x| try testing.expect(!isFortran(x));
}

test xLang {
    const a: Args = &.{ "-x", "f95", "a", "-x", "none", "b.o" };
    try testing.expectEqualStrings("f95", xLang(a, 2).?);
    try testing.expect(xLang(a, 5) == null);
    const b: Args = &.{ "-o", "p", "-x", "f95-cpp-input", "a", "-xc", "g", "-Xlinker", "-xnone", "h" };
    try testing.expect(xLang(b, 1) == null);
    try testing.expectEqualStrings("f95-cpp-input", xLang(b, 4).?);
    try testing.expectEqualStrings("c", xLang(b, 6).?);
    // -Xlinker's value is no -x
    try testing.expectEqualStrings("c", xLang(b, 9).?);
    try testing.expect(isFortranLang("f95-cpp-input") and isFortranLang("f77") and !isFortranLang("c") and !isFortranLang("fortran"));
}
