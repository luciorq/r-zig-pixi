//! What R's own makefiles say about the recommended packages, read from
//! their text (build.zig, beside this file, installs by it):
//!   share/make/vars.mk                    R_PKGS_RECOMMENDED, the names
//!   src/library/Recommended/Makefile.in   `<pkg>.ts: <dep>.ts ...`, which
//!                                         packages must be installed
//!                                         first, and INSTALL_OPTS, R CMD
//!                                         INSTALL's options
//! and the tarball of a package among the names of that directory. No
//! name, order or option is typed here: an R release that adds a package
//! or a dependency changes the build with its source.
const std = @import("std");
const mem = std.mem;

/// The words of `name`'s assignment in a makefile's text (`name = a b`,
/// on one line, as vars.mk and Makefile.in write the two read here), or
/// null when the text assigns no such name.
pub fn words(a: mem.Allocator, text: []const u8, name: []const u8) !?[]const []const u8 {
    var lines = mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        if (!mem.startsWith(u8, line, name)) continue;
        const rest = mem.trimStart(u8, line[name.len..], " \t");
        if (rest.len == 0 or rest[0] != '=') continue;
        var list: std.ArrayList([]const u8) = .empty;
        var it = mem.tokenizeAny(u8, rest[1..], " \t");
        while (it.next()) |w| try list.append(a, w);
        return try list.toOwnedSlice(a);
    }
    return null;
}

/// R CMD INSTALL's options for a recommended package: INSTALL_OPTS' words
/// that configure does not fill in (`@REC_INSTALL_OPT@`, macOS' --dsym,
/// and `@BUILD_LTO_TRUE@--use-LTO` are empty or off in every config of
/// this build), null without the line.
pub fn installOpts(a: mem.Allocator, makefile: []const u8) !?[]const []const u8 {
    const all = try words(a, makefile, "INSTALL_OPTS") orelse return null;
    var list: std.ArrayList([]const u8) = .empty;
    for (all) |w| {
        if (mem.indexOfScalar(u8, w, '@') == null) try list.append(a, w);
    }
    return try list.toOwnedSlice(a);
}

/// The packages `pkg` is installed after: the prerequisites of the
/// makefile's `<pkg>.ts:` lines, less their `.ts`. A package may have
/// several lines, or none.
pub fn deps(a: mem.Allocator, makefile: []const u8, pkg: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var lines = mem.tokenizeAny(u8, makefile, "\r\n");
    while (lines.next()) |line| {
        if (!mem.startsWith(u8, line, pkg)) continue;
        const rest = line[pkg.len..];
        if (!mem.startsWith(u8, rest, ".ts:")) continue;
        var it = mem.tokenizeAny(u8, rest[".ts:".len..], " \t");
        while (it.next()) |w| {
            if (mem.endsWith(u8, w, ".ts")) try list.append(a, w[0 .. w.len - ".ts".len]);
        }
    }
    return try list.toOwnedSlice(a);
}

/// The package's tarball among a directory's file names:
/// `<pkg>_<version>.tar.gz` (the `<pkg>.tgz` beside it is a link to it,
/// which a Windows extraction may not keep). Null with none; two are an
/// error, as R ships one version of each.
pub fn tarball(names: []const []const u8, pkg: []const u8) error{TwoTarballs}!?[]const u8 {
    var found: ?[]const u8 = null;
    for (names) |n| {
        if (!mem.startsWith(u8, n, pkg) or !mem.endsWith(u8, n, ".tar.gz")) continue;
        if (n.len <= pkg.len or n[pkg.len] != '_') continue;
        if (found != null) return error.TwoTarballs;
        found = n;
    }
    return found;
}

const testing = std.testing;

fn expectWords(expected: []const []const u8, actual: []const []const u8) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, x| try testing.expectEqualStrings(e, x);
}

// R 4.6.2's lines.
const test_makefile =
    \\OBJECTS = $(R_PKGS_RECOMMENDED:=.ts)
    \\INSTALL_OPTS = --pkglock --data-compress=xz --no-staged-install @REC_INSTALL_OPT@ @BUILD_LTO_TRUE@--use-LTO
    \\.tgz.ts:
++ "\n\t@touch $@\n" ++ // a recipe line (a tab, which a \\ line cannot hold)
    \\## Hardcoded dependencies (see '../../../share/make/vars.mk')
    \\Matrix.ts: lattice.ts
    \\mgcv.ts: nlme.ts MASS.ts Matrix.ts
    \\nlme.ts: lattice.ts
    \\class.ts: MASS.ts
    \\survival.ts: Matrix.ts
    \\## and for static html links
    \\boot.ts: MASS.ts survival.ts
    \\cluster.ts: MASS.ts
    \\
;

test "words: the names of vars.mk's line, and no other variable's" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const vars =
        \\R_PKGS_BASE = base tools utils
        \\R_PKGS_RECOMMENDED =  MASS lattice Matrix
        \\R_PKGS_RECOMMENDED_SOURCES = x
        \\
    ;
    try expectWords(&.{ "MASS", "lattice", "Matrix" }, (try words(a, vars, "R_PKGS_RECOMMENDED")).?);
    try expectWords(&.{ "base", "tools", "utils" }, (try words(a, vars, "R_PKGS_BASE")).?);
    try testing.expectEqual(null, try words(a, vars, "R_PKGS"));
    // CRLF, as a Windows checkout may have it
    try expectWords(&.{ "a", "b" }, (try words(a, "X = a b\r\nY = c\r\n", "X")).?);
}

test "installOpts: the words configure leaves alone" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectWords(&.{ "--pkglock", "--data-compress=xz", "--no-staged-install" }, (try installOpts(a, test_makefile)).?);
    try testing.expectEqual(null, try installOpts(a, "all:\n"));
}

test "deps: every line of a package, none for the others" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectWords(&.{ "nlme", "MASS", "Matrix" }, try deps(a, test_makefile, "mgcv"));
    try expectWords(&.{"lattice"}, try deps(a, test_makefile, "Matrix"));
    try expectWords(&.{ "MASS", "survival" }, try deps(a, test_makefile, "boot"));
    try expectWords(&.{}, try deps(a, test_makefile, "MASS"));
    // `class.ts:` is not `cluster`'s line, nor `nnet`'s a prefix's
    try expectWords(&.{"MASS"}, try deps(a, test_makefile, "class"));
    try expectWords(&.{}, try deps(a, test_makefile, "n"));
    try expectWords(&.{ "a", "b", "c" }, try deps(a, "p.ts: a.ts\np.ts: b.ts c.ts\n", "p"));
}

test "tarball: the package's own, by its whole name" {
    const names = [_][]const u8{ "Makefile.in", "MASS.tgz", "MASS_7.3-66.tar.gz", "Matrix_1.7-6.tar.gz", "nlme_3.1-171.tar.gz" };
    try testing.expectEqualStrings("MASS_7.3-66.tar.gz", (try tarball(&names, "MASS")).?);
    try testing.expectEqualStrings("Matrix_1.7-6.tar.gz", (try tarball(&names, "Matrix")).?);
    // no tarball of `M`, though two names start with it
    try testing.expectEqual(null, try tarball(&names, "M"));
    try testing.expectEqual(null, try tarball(&names, "mgcv"));
    try testing.expectError(error.TwoTarballs, tarball(&.{ "boot_1.3-31.tar.gz", "boot_1.3-32.tar.gz" }, "boot"));
}
