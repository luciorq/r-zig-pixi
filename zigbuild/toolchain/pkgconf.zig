//! pkgconf for Windows' build-tools group (feat-standalone-toolchain,
//! after phase 9; PHASE7 user decision D0 a, PHASE4 open point F a):
//! built from upstream's source tarball with zig, without meson, and
//! installed into usr/bin as pkgconf.exe and pkg-config.exe, one exe
//! under both names. Named either, it takes the default personality:
//! cli/main.c reads one from argv[0] only when the name has `-pkg`. It
//! replaces conda-forge's pkg-config 0.29.2 (MSVC, with glib), which
//! printed Libs.private without --static (ncdf4, RPostgres).
//!
//! The sources are libpkgconf's and the cli's (meson.build's lists, less
//! bomtool, spdxtool and pccritic), linked into one static exe, with
//! meson.build's project arguments and c_std, -DPKGCONFIG_IS_STATIC, and
//! a config.h with what meson's probes give for *-windows-gnu (probed
//! with zig 0.16 for x86_64 and aarch64: strdup, strcasecmp and
//! strncasecmp only; the same from 3.0.7 to 3.0.10). No path of the build
//! machine: on _WIN32 the search path is <exe dir>/../lib/pkgconfig and
//! <exe dir>/../share/pkgconfig (libpkgconf/personality.c), and
//! PKG_DEFAULT_PATH only its fallback, so it, SYSTEM_LIBDIR,
//! SYSTEM_INCLUDEDIR and PERSONALITY_PATH are empty (nothing filtered).
//! R's etc/Rcmd_environ gives PKG_CONFIG_PATH a default, its env's
//! Library/lib/pkgconfig and Library/share/pkgconfig (R's build.zig,
//! rcmdEnviron). Every compile maps the source directory away
//! (-ffile-prefix-map), so __FILE__ is the path in the tarball.
//!
//! The tarball: `url` and `sha256` below, which usr/SOURCES records. The
//! standalone build fetches it as build.zig.zon's lazy `pkgconf`
//! dependency (zig checks its own hash of the tree); the conda build
//! takes it as a source of recipe/recipe.yaml (rattler-build checks the
//! sha256) and passes the unpacked directory as -Dpkgconf=<dir>. The
//! `test` step checks that the zon's URL and the recipe's URL and sha256
//! are these.
const std = @import("std");
const mem = std.mem;

pub const version = "3.0.10";
pub const url = "https://distfiles.ariadne.space/pkgconf/pkgconf-" ++ version ++ ".tar.xz";
pub const sha256 = "9371b2f6372da574d4c6dc96fe9b1463037bcf6afcb6671c1555afde7b17e2de";
/// meson.build's `license`; COPYING is its text.
pub const license = "ISC";
pub const repository = "https://github.com/pkgconf/pkgconf";

const sources = [_][]const u8{
    "libpkgconf/argvsplit",  "libpkgconf/audit",    "libpkgconf/buffer",   "libpkgconf/bufferset",
    "libpkgconf/bytecode",   "libpkgconf/bsdstubs", "libpkgconf/cache",    "libpkgconf/client",
    "libpkgconf/dependency", "libpkgconf/fileio",   "libpkgconf/fragment", "libpkgconf/license",
    "libpkgconf/output",     "libpkgconf/parser",   "libpkgconf/path",     "libpkgconf/personality",
    "libpkgconf/pkg",        "libpkgconf/queue",    "libpkgconf/tuple",    "libpkgconf/variable",
    "libpkgconf/version",    "cli/main",            "cli/core",            "cli/getopt_long",
    "cli/renderer-msvc",
};

/// pkgconf's pkgconf.manifest.in less its assemblyIdentity (whose version
/// must have four parts): the UTF-8 code page and long paths.
const manifest =
    \\<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    \\<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
    \\  <application>
    \\    <windowsSettings>
    \\      <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
    \\      <longPathAware  xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    \\    </windowsSettings>
    \\  </application>
    \\</assembly>
    \\
;

pub const Error = error{PkgconfBuild};

/// pkgconf.exe for `arch`-windows-gnu (baseline CPU: it ships) from the
/// unpacked tarball `dir` (absolute), whose meson.build must be this
/// version's.
pub fn add(b: *std.Build, arch: std.Target.Cpu.Arch, dir: []const u8) Error!*std.Build.Step.Compile {
    const meson = std.Io.Dir.cwd().readFileAlloc(b.graph.io, b.fmt("{s}/meson.build", .{dir}), b.allocator, .limited(1024 * 1024)) catch |err|
        return fail("pkgconf: cannot read {s}/meson.build ({t}): -Dpkgconf names pkgconf {s}'s unpacked tarball", .{ dir, err, version });
    const got = mesonString(meson, "version : '") orelse
        return fail("pkgconf: {s}/meson.build names no version", .{dir});
    if (!mem.eql(u8, got, version))
        return fail("pkgconf: {s} is pkgconf {s}, not {s} (zigbuild/toolchain/pkgconf.zig's, which SOURCES records)", .{ dir, got, version });
    const bugreport = mesonString(meson, "cdata.set_quoted('PACKAGE_BUGREPORT', '") orelse
        return fail("pkgconf: {s}/meson.build sets no PACKAGE_BUGREPORT", .{dir});

    const gen = b.addWriteFiles();
    _ = gen.add("libpkgconf/config.h", b.fmt(
        \\#define HAVE_DECL_STRNDUP 0
        \\#define HAVE_DECL_REALLOCARRAY 0
        \\#define HAVE_DECL_PLEDGE 0
        \\#define HAVE_DECL_UNVEIL 0
        \\#define HAVE_DECL_READLINKAT 0
        \\#define HAVE_DECL_MKDTEMP 0
        \\#define HAVE_DECL_GETC_UNLOCKED 0
        \\#define HAVE_DECL_NL_LANGINFO_L 0
        \\#define PACKAGE_BUGREPORT "{s}"
        \\#define PACKAGE_NAME "pkgconf"
        \\#define PACKAGE_VERSION "{s}"
        \\#define PKG_DEFAULT_PATH ""
        \\#define SYSTEM_INCLUDEDIR ""
        \\#define SYSTEM_LIBDIR ""
        \\#define PERSONALITY_PATH ""
        \\
    , .{ bugreport, version }));
    const mod = b.createModule(.{
        .target = b.resolveTargetQuery(.{ .cpu_arch = arch, .os_tag = .windows, .abi = .gnu }),
        .optimize = .ReleaseFast,
        .strip = true,
        .link_libc = true,
    });
    mod.addIncludePath(gen.getDirectory());
    mod.addIncludePath(.{ .cwd_relative = dir });
    mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/libpkgconf", .{dir}) });
    mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/cli", .{dir}) });
    // -fno-file-reproducible keeps the mapped path's `/` (once a map
    // applies, clang otherwise writes the target's `\`).
    const flags: []const []const u8 = &.{
        "-std=c99",                               "-O2",               "-D_ATFILE_SOURCE",          "-D_BSD_SOURCE",
        "-D_DARWIN_C_SOURCE",                     "-D_DEFAULT_SOURCE", "-D_POSIX_C_SOURCE=200809L", "-D_XOPEN_SOURCE=700",
        "-DPKGCONFIG_IS_STATIC",                  "-Wall",             "-Wextra",                   "-fno-file-reproducible",
        b.fmt("-ffile-prefix-map={s}/=", .{dir}),
    };
    for (sources) |s| mod.addCSourceFile(.{ .file = .{ .cwd_relative = b.fmt("{s}/{s}.c", .{ dir, s }) }, .flags = flags });
    mod.linkSystemLibrary("advapi32", .{});
    return b.addExecutable(.{
        .name = "pkgconf",
        .root_module = mod,
        .win32_manifest = b.addWriteFiles().add("pkgconf.manifest", manifest),
    });
}

/// The single-quoted value after `key` in meson.build.
fn mesonString(meson: []const u8, key: []const u8) ?[]const u8 {
    const at = mem.indexOf(u8, meson, key) orelse return null;
    const rest = meson[at + key.len ..];
    return rest[0 .. mem.indexOfScalar(u8, rest, '\'') orelse return null];
}

fn fail(comptime fmt: []const u8, args: anytype) error{PkgconfBuild} {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    return error.PkgconfBuild;
}

// --- tests: the pins agree --------------------------------------------

test "build.zig.zon fetches this url" {
    const zon = @embedFile("build.zig.zon");
    try std.testing.expect(mem.indexOf(u8, zon, ".url = \"" ++ url ++ "\",") != null);
}

test "recipe.yaml's win source is this url and sha256" {
    // build.zig's test step passes the recipe's path (the conda build
    // runs no test, and its sources hold no recipe/)
    const recipe_path = @import("paths").recipe;
    const io = std.testing.io;
    const yaml = try std.Io.Dir.cwd().readFileAlloc(io, recipe_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(yaml);
    const at = mem.indexOf(u8, yaml, "url: " ++ url ++ "\n") orelse return error.RecipeHasNoPkgconfUrl;
    var lines = mem.splitScalar(u8, yaml[at..], '\n');
    _ = lines.next();
    const next = mem.trim(u8, lines.next() orelse "", " \r");
    try std.testing.expectEqualStrings("sha256: " ++ sha256, next);
}

test "meson.build's strings" {
    const meson = "project(\n  'pkgconf',\n  'c',\n  version : '3.0.10',\n  license : 'ISC',\n";
    try std.testing.expectEqualStrings("3.0.10", mesonString(meson, "version : '").?);
    try std.testing.expect(mesonString(meson, "nothing '") == null);
}
