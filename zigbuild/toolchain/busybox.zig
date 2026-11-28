//! busybox-w32 for Windows' native build tools (native/, the
//! r-zig-native-tools package; .github/devdocs/b14-l4/PLAN.md, user
//! decision U1 b): built from the release's source (GitHub's archive of
//! its tag: frippery.org's tarball of it refuses GitHub's hosted runners,
//! b14-review D-B1; the trees are the same but .frp_describe) by
//! zigbuild/busybox/build.zig (the toolchain build's r_zig_busybox path
//! dependency), with zig-built GNU make (zigbuild/make/build.zig) and
//! pkgconf beside it, in place of MSYS2's sh, make and coreutils when
//! R_ZIG_NATIVE_TOOLS is on (patch 0018).
//!
//! r-zig's patches to it (`patches`; zigbuild/busybox/patches/, applied by
//! zigbuild/busybox/build.zig) go into native/LICENSES/busybox-w32/
//! with LICENSE: with the tarball they are the exe's complete source.
//!
//! The tarball: `url` and `sha256` below, which native/SOURCES records.
//! The standalone build fetches it as build.zig.zon's lazy `busybox`
//! dependency (zig checks its own hash of the tree); the conda build takes
//! it as a source of recipe/recipe.yaml (rattler-build checks the sha256)
//! and passes the unpacked directory as -Dbusybox=<dir>. The `test` step
//! checks that the zon's URL and the recipe's URL and sha256 are these.
const std = @import("std");
const mem = std.mem;

/// busybox-w32's release name (its git tag; frippery.org's .frp_describe); the test
/// checks zigbuild/busybox/build.zig builds the same.
pub const version = "FRP-6354-g5f09fb446";
pub const url = "https://github.com/rmyorston/busybox-w32/archive/refs/tags/" ++ version ++ ".tar.gz";
pub const sha256 = "b076d55e4aca74d57d4e77c2ca77abc94dd4926f424fa752889414e1b68f6ebc";
/// LICENSE is its text (GPL version 2 only, as busybox states).
pub const license = "GPL-2.0-only";
/// busybox-w32's source repository (the tarball is its release tag's).
pub const repository = "https://github.com/rmyorston/busybox-w32";
/// zigbuild/busybox/build.zig's `patches`, the same files in the same
/// order (the test checks): MSYS2-style drive paths and make's flags
/// (b14-l4 PLAN.md, U5).
pub const patches = [_][]const u8{
    "patches/0001-msys-drive-paths.patch",
};

/// The names native/bin has busybox.exe under, each a copy: GNU make on
/// Windows starts a recipe line without a metacharacter itself
/// (CreateProcess, so a real <name>.exe), and R, cmake and configure
/// scripts start sh, bash and a few tools by name. Inside busybox's sh
/// every applet runs by name without one (FEATURE_PREFER_APPLETS and
/// FEATURE_SH_STANDALONE in config/<arch>.config). The list: what ran on
/// kappa under MSYS2 in 50 package installs (b13-build F11: basename,
/// cat, cp, cut, echo, rm, sed, sh, touch, tr), phase 7's names (awk,
/// grep, find, xargs, which), the configure-script and makefile commands
/// of R-exts and winshlib.mk (mkdir, mv, ln, chmod, test, expr, ...), and
/// the archive and patch tools configure scripts run (tar, gzip, unzip,
/// patch, diff). `busybox --install DIR` makes the rest (179 names).
pub const applets = [_][]const u8{
    "sh",   "bash",  "awk",   "basename", "cat",    "chmod", "cmp",   "cp",
    "cut",  "date",  "diff",  "dirname",  "echo",   "env",   "expr",  "false",
    "find", "grep",  "egrep", "fgrep",    "gunzip", "gzip",  "head",  "install",
    "ln",   "ls",    "mkdir", "mktemp",   "mv",     "od",    "patch", "printf",
    "pwd",  "rm",    "rmdir", "sed",      "sleep",  "sort",  "tail",  "tar",
    "tee",  "test",  "touch", "tr",       "true",   "uname", "uniq",  "unzip",
    "wc",   "which", "xargs", "xz",
};

test "build.zig.zon fetches this url" {
    const zon = @embedFile("build.zig.zon");
    try std.testing.expect(mem.indexOf(u8, zon, ".url = \"" ++ url ++ "\",") != null);
}

test "recipe.yaml's win source is this url and sha256" {
    const recipe_path = @import("paths").recipe;
    const io = std.testing.io;
    const yaml = try std.Io.Dir.cwd().readFileAlloc(io, recipe_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(yaml);
    const at = mem.indexOf(u8, yaml, "url: " ++ url ++ "\n") orelse return error.RecipeHasNoBusyboxUrl;
    var lines = mem.splitScalar(u8, yaml[at..], '\n');
    _ = lines.next();
    const next = mem.trim(u8, lines.next() orelse "", " \r");
    try std.testing.expectEqualStrings("sha256: " ++ sha256, next);
}

test "zigbuild/busybox builds this release" {
    const io = std.testing.io;
    const src = try std.Io.Dir.cwd().readFileAlloc(io, @import("paths").busybox, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(src);
    try std.testing.expect(mem.indexOf(u8, src, "pub const frp = \"" ++ version ++ "\";") != null);
    const zon = try std.Io.Dir.cwd().readFileAlloc(io, @import("paths").busybox_zon, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(zon);
    try std.testing.expect(mem.indexOf(u8, zon, ".url = \"" ++ url ++ "\",") != null);
}

test "zigbuild/busybox applies these patches, which exist" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    const src = try std.Io.Dir.cwd().readFileAlloc(io, @import("paths").busybox, a, .limited(1024 * 1024));
    defer a.free(src);
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    try list.appendSlice(a, "pub const patches = [_][]const u8{\n");
    for (patches) |p| try list.print(a, "    \"{s}\",\n", .{p});
    try list.appendSlice(a, "};\n");
    try std.testing.expect(mem.indexOf(u8, src, list.items) != null);
    const dir = std.fs.path.dirname(@import("paths").busybox).?;
    for (patches) |p| {
        const path = try std.fs.path.join(a, &.{ dir, p });
        defer a.free(path);
        try std.Io.Dir.cwd().access(io, path, .{});
    }
}

test "each applet once" {
    for (applets, 0..) |a, i| for (applets[i + 1 ..]) |c| try std.testing.expect(!mem.eql(u8, a, c));
}
