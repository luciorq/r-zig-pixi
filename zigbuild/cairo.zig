//! cairo for R's Windows cairo devices (grDevices/libs/<arch>/winCairo.dll:
//! svg(), cairo_pdf(), cairo_ps() and the bitmap devices' type = "cairo"),
//! built from upstream's source tarball with zig, without meson, and
//! linked statically into winCairo.dll, on both channels and both Windows
//! arches. conda-forge has no cairo for win-arm64 (feat-win-arm64/PLAN.md;
//! the user's decision of 2026-11-10: build it), and one cairo for x86_64
//! and aarch64 keeps the two Windows R's alike.
//!
//! What R's device uses (src/library/grDevices/src/cairo/cairoBM.c and
//! cairoFns.c, Win32, without pango): the image, PNG, PDF, PS and SVG
//! surfaces and the Win32 (GDI) font backend
//! (cairo_win32_font_face_create_for_logfontw). No FreeType or
//! fontconfig: cairoFns.c's FreeType branch is for !_WIN32, and R picks
//! its fonts through GDI. DirectWrite stays, as in conda-forge's win-64
//! cairo: cairo 1.18.6 does not build for Windows without it, and it is
//! cairo's default backend for toy font faces there. The features are
//! meson's for *-windows-gnu with fontconfig, freetype, tee, glib, lzo,
//! spectre and symbol-lookup off and dwrite, png and zlib on. config.h is what
//! meson's probes give for x86_64- and aarch64-windows-gnu with zig 0.17
//! (the same but for aarch64's ATOMIC_OP_NEEDS_MEMORY_BARRIER). The
//! sources are libcairo's for those features (src/meson.build). pixman,
//! libpng and zlib come from the env (conda-forge has all three for win-64
//! and win-arm64); winCairo.dll imports them (CAIRO_LIBS in the vendored
//! subst.txt).
//!
//! Every compile maps the source directory away (-ffile-prefix-map), so
//! __FILE__ is the path in the tarball. ReleaseFast: third-party C,
//! without the sanitizer traps that zig's ReleaseSafe adds to C.
//!
//! The tarball: `url` and `sha256` below. The standalone build fetches it
//! as build.zig.zon's lazy `cairo` dependency (zig checks its own hash of
//! the tree); the conda build takes it as a win source of
//! recipe/recipe.yaml (rattler-build checks the sha256) and passes the
//! unpacked directory as -Dcairo=<dir>. The tests (the toolchain build's
//! `test` step) check that the zon's URL and the recipe's URL and sha256
//! are these.
const std = @import("std");
const mem = std.mem;

pub const version = "1.18.6";
pub const url = "https://cairographics.org/releases/cairo-" ++ version ++ ".tar.xz";
pub const sha256 = "1c767308174337a74694da0f3ec069c271452163a1ef4540964c50c301f157d4";
/// COPYING: LGPL 2.1 or MPL 1.1, the user's choice.
pub const license = "LGPL-2.1-only OR MPL-1.1";
pub const repository = "https://gitlab.freedesktop.org/cairo/cairo";

/// src/meson.build's cairo_sources plus the png, svg, win32, win32-font,
/// script, ps and pdf feature sources (under src/, without .c).
const sources = [_][]const u8{
    "cairo-analysis-surface",            "cairo-arc",                         "cairo-array",
    "cairo-atomic",                      "cairo-base64-stream",               "cairo-base85-stream",
    "cairo-bentley-ottmann-rectangular", "cairo-bentley-ottmann-rectilinear", "cairo-bentley-ottmann",
    "cairo-botor-scan-converter",        "cairo-boxes-intersect",             "cairo-boxes",
    "cairo-cache",                       "cairo-clip-boxes",                  "cairo-clip-polygon",
    "cairo-clip-region",                 "cairo-clip-surface",                "cairo-clip-tor-scan-converter",
    "cairo-clip",                        "cairo-color",                       "cairo-composite-rectangles",
    "cairo-compositor",                  "cairo-contour",                     "cairo-damage",
    "cairo-debug",                       "cairo-default-context",             "cairo-device",
    "cairo-error",                       "cairo-fallback-compositor",         "cairo-fixed",
    "cairo-font-face-twin-data",         "cairo-font-face-twin",              "cairo-font-face",
    "cairo-font-options",                "cairo-freed-pool",                  "cairo-freelist",
    "cairo-gstate",                      "cairo-hash",                        "cairo-hull",
    "cairo-image-compositor",            "cairo-image-info",                  "cairo-image-source",
    "cairo-image-surface",               "cairo-line",                        "cairo-lzw",
    "cairo-mask-compositor",             "cairo-matrix",                      "cairo-mempool",
    "cairo-mesh-pattern-rasterizer",     "cairo-misc",                        "cairo-mono-scan-converter",
    "cairo-mutex",                       "cairo-no-compositor",               "cairo-observer",
    "cairo-output-stream",               "cairo-paginated-surface",           "cairo-path-bounds",
    "cairo-path-fill",                   "cairo-path-fixed",                  "cairo-path-in-fill",
    "cairo-path-stroke-boxes",           "cairo-path-stroke-polygon",         "cairo-path-stroke-traps",
    "cairo-path-stroke-tristrip",        "cairo-path-stroke",                 "cairo-path",
    "cairo-pattern",                     "cairo-pen",                         "cairo-polygon-intersect",
    "cairo-polygon-reduce",              "cairo-polygon",                     "cairo-raster-source-pattern",
    "cairo-recording-surface",           "cairo-rectangle",                   "cairo-rectangular-scan-converter",
    "cairo-region",                      "cairo-rtree",                       "cairo-scaled-font",
    "cairo-shape-mask-compositor",       "cairo-slope",                       "cairo-spans-compositor",
    "cairo-spans",                       "cairo-spline",                      "cairo-stroke-dash",
    "cairo-stroke-style",                "cairo-surface-clipper",             "cairo-surface-fallback",
    "cairo-surface-observer",            "cairo-surface-offset",              "cairo-surface-snapshot",
    "cairo-surface-subsurface",          "cairo-surface-wrapper",             "cairo-surface",
    "cairo-time",                        "cairo-tor-scan-converter",          "cairo-tor22-scan-converter",
    "cairo-toy-font-face",               "cairo-traps-compositor",            "cairo-traps",
    "cairo-tristrip",                    "cairo-unicode",                     "cairo-user-font",
    "cairo-version",                     "cairo-wideint",                     "cairo",
    "cairo-cff-subset",                  "cairo-scaled-font-subsets",         "cairo-truetype-subset",
    "cairo-type1-fallback",              "cairo-type1-glyph-names",           "cairo-type1-subset",
    "cairo-type3-glyph-surface",         "cairo-pdf-operators",               "cairo-pdf-shading",
    "cairo-tag-attributes",              "cairo-tag-stack",                   "cairo-deflate-stream",
    "cairo-png",                         "cairo-svg-surface",                 "win32/cairo-win32-debug",
    "win32/cairo-win32-device",          "win32/cairo-win32-gdi-compositor",  "win32/cairo-win32-system",
    "win32/cairo-win32-surface",         "win32/cairo-win32-display-surface", "win32/cairo-win32-printing-surface",
    "win32/cairo-win32-thread-data",     "win32/cairo-win32-font",            "cairo-script-surface",
    "cairo-ps-surface",                  "cairo-pdf-surface",                 "cairo-pdf-interchange",
};

/// What meson's probes give (cairo 1.18.6, zig 0.17, *-windows-gnu).
const config_h =
    \\#pragma once
    \\#define CAIRO_HAS_INTERPRETER 1
    \\#define CAIRO_HAS_PTHREAD 1
    \\#define CAIRO_HAS_REAL_PTHREAD 1
    \\#define HAS_PIXMAN_GLYPHS 1
    \\#define HAS_PIXMAN_r8g8b8_sRGB 1
    \\#define HAVE_ALARM 1
    \\#define HAVE_CLOCK_GETTIME 1
    \\#define HAVE_D2D1_2_H 1
    \\#define HAVE_D2D1_3_H 1
    \\#define HAVE_FCNTL_H 1
    \\#define HAVE_FECLEAREXCEPT 1
    \\#define HAVE_FEDISABLEEXCEPT 1
    \\#define HAVE_FEENABLEEXCEPT 1
    \\#define HAVE_FENV_H 1
    \\#define HAVE_ID2D1DEVICECONTEXT2 1
    \\#define HAVE_ID2D1DEVICECONTEXT3 1
    \\#define HAVE_ID2D1DEVICECONTEXT4 1
    \\#define HAVE_ID2D1DEVICECONTEXT5 1
    \\#define HAVE_ID2D1DEVICECONTEXT6 1
    \\#define HAVE_IDWRITEFACTORY8 1
    \\#define HAVE_INTSAFE_H 1
    \\#define HAVE_INTTYPES_H 1
    \\#define HAVE_IO_H 1
    \\#define HAVE_LIBGEN_H 1
    \\#define HAVE_MKDIR 1
    \\#define HAVE_RAISE 1
    \\#define HAVE_SCHED_H 1
    \\#define HAVE_SETJMP_H 1
    \\#define HAVE_SIGNAL_H 1
    \\#define HAVE_STDINT_H 1
    \\#define HAVE_STRNDUP
    \\#define HAVE_SYS_STAT_H 1
    \\#define HAVE_TIME_H 1
    \\#define HAVE_UINT64_T 1
    \\#define HAVE_UNISTD_H 1
    \\#define HAVE_ZLIB 1
    \\#define HAVE___UINT128_T 1
    \\#define SIZEOF_INT 4
    \\#define SIZEOF_LONG 4
    \\#define SIZEOF_LONG_LONG 8
    \\#define SIZEOF_SIZE_T 8
    \\#define SIZEOF_VOID_P 8
    \\#define WARN_UNUSED_RESULT __attribute__((__warn_unused_result__))
    \\
;

/// meson's cairo-features.h for those features.
const features_h =
    \\#pragma once
    \\#define CAIRO_FEATURES_H
    \\#define CAIRO_HAS_DWRITE_FONT 1
    \\#define CAIRO_HAS_IMAGE_SURFACE 1
    \\#define CAIRO_HAS_MIME_SURFACE 1
    \\#define CAIRO_HAS_OBSERVER_SURFACE 1
    \\#define CAIRO_HAS_PDF_SURFACE 1
    \\#define CAIRO_HAS_PNG_FUNCTIONS 1
    \\#define CAIRO_HAS_PS_SURFACE 1
    \\#define CAIRO_HAS_RECORDING_SURFACE 1
    \\#define CAIRO_HAS_SCRIPT_SURFACE 1
    \\#define CAIRO_HAS_SVG_SURFACE 1
    \\#define CAIRO_HAS_USER_FONT 1
    \\#define CAIRO_HAS_WIN32_FONT 1
    \\#define CAIRO_HAS_WIN32_SURFACE 1
    \\
;

/// The Windows libraries libcairo needs (meson.build: gdi32 and msimg32,
/// DirectWrite's dwrite, d2d1 and windowscodecs, and ole32, one of the
/// libraries meson links by default for Windows: CoInitializeEx,
/// CoCreateInstance).
pub const system_libs = [_][]const u8{ "gdi32", "msimg32", "dwrite", "d2d1", "windowscodecs", "ole32" };

/// What a user of cairo's API compiles with: the static build's define
/// (cairo_public without dllimport).
pub const user_define = "-DCAIRO_WIN32_STATIC_BUILD";

/// The tarball's licence texts (COPYING names the other two), which R's
/// build installs into R_HOME/share/licenses/cairo/.
pub const license_files = [_][]const u8{ "COPYING", "COPYING-LGPL-2.1", "COPYING-MPL-1.1" };

/// R_HOME/share/licenses/cairo/SOURCE: the fields of a SOURCES block
/// (zigbuild/toolchain/conda.zig) for a library no file of which ships on
/// its own: what it is, where it came from, how it was built and where
/// it went.
pub fn record(b: *std.Build, arch: std.Target.Cpu.Arch) []const u8 {
    return b.fmt(
        \\package: cairo
        \\version: {s}
        \\build: zig{s}_{t}-windows-gnu
        \\url: {s}
        \\sha256: {s}
        \\license: {s}
        \\source: {s} sha256:{s}
        \\feedstock: https://github.com/luciorq/r-zig-pixi zigbuild/cairo.zig
        \\linked: statically into library/grDevices/libs/x64/winCairo.dll
        \\
    , .{ version, @import("builtin").zig_version_string, arch, url, sha256, license, url, sha256 });
}

pub const Error = error{CairoBuild};

pub const Built = struct {
    lib: *std.Build.Step.Compile,
    /// cairo.h and its siblings (the tarball's src/).
    include: std.Build.LazyPath,
    /// The generated cairo-features.h (and config.h).
    generated: std.Build.LazyPath,
};

/// libcairo.a for `target` (a *-windows-gnu) from the unpacked tarball
/// `dir` (absolute), whose src/cairo-version.h must be this version's.
/// `includes`: the directories of pixman.h, png.h and zlib.h (absolute).
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, dir: []const u8, includes: []const []const u8) Error!Built {
    const vh = std.Io.Dir.cwd().readFileAlloc(b.graph.io, b.fmt("{s}/src/cairo-version.h", .{dir}), b.allocator, .limited(64 * 1024)) catch |err|
        return fail("cairo: cannot read {s}/src/cairo-version.h ({t}): -Dcairo names cairo {s}'s unpacked tarball", .{ dir, err, version });
    const v = versionOf(vh) orelse return fail("cairo: {s}/src/cairo-version.h names no version", .{dir});
    if (!v.is(version))
        return fail("cairo: {s} is cairo {s}.{s}.{s}, not {s} (zigbuild/cairo.zig's)", .{ dir, v.major, v.minor, v.micro, version });

    const gen = b.addWriteFiles();
    _ = gen.add("config.h", if (target.result.cpu.arch == .aarch64)
        config_h ++ "#define ATOMIC_OP_NEEDS_MEMORY_BARRIER 1\n"
    else
        config_h);
    _ = gen.add("cairo-features.h", features_h);
    const mod = b.createModule(.{
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    mod.addIncludePath(gen.getDirectory());
    mod.addIncludePath(b.graph.cwdRelativePath(b.fmt("{s}/src", .{dir})));
    for (includes) |inc| mod.addIncludePath(b.graph.cwdRelativePath(inc));
    // meson.build's project arguments (with DirectWrite's SDK version:
    // Windows 10, the NTDDI that its headers need; zig itself defines
    // _WIN32_WINNT, 0x0a00 for Windows 10), src/meson.build's c_args and
    // the static build's define, for the C++ file too (else its
    // cairo_public functions are dllexport). -fno-file-reproducible keeps
    // the mapped path's `/` (once a map applies, clang otherwise writes
    // the target's `\`).
    const common = [_][]const u8{
        "-O2",                             "-fvisibility=hidden",    "-fno-strict-aliasing",
        "-fno-common",                     "-D_FILE_OFFSET_BITS=64", "-D_GNU_SOURCE",
        "-DWIN32_LEAN_AND_MEAN",           "-DNOMINMAX",             "-DWINVER=0x0A00",
        "-DNTDDI_VERSION=0x0A000010",      user_define,              "-D_REENTRANT",
        "-DCAIRO_COMPILATION",             "-Wno-attributes",        "-Wno-unused-but-set-variable",
        "-Wno-missing-field-initializers", "-Wno-unused-parameter",  "-Wno-long-long",
        "-Wno-enum-conversion",            "-fno-file-reproducible",
    };
    const map = b.fmt("-ffile-prefix-map={s}/=", .{dir});
    const c_flags = mem.concat(b.allocator, []const u8, &.{ &.{"-std=gnu11"}, &common, &.{map} }) catch @panic("OOM");
    const cpp_flags = mem.concat(b.allocator, []const u8, &.{ &.{"-std=gnu++11"}, &common, &.{map} }) catch @panic("OOM");
    for (sources) |s| mod.addCSourceFile(.{ .file = b.graph.cwdRelativePath(b.fmt("{s}/src/{s}.c", .{ dir, s })), .flags = c_flags });
    // the DirectWrite font backend, C++ (src/meson.build's dwrite
    // feature); win32/cairo-win32-system.c calls it unconditionally
    // (cairo_win32_dwrite_finalize), so cairo 1.18.6 does not build for
    // Windows without it
    mod.addCSourceFile(.{ .file = b.graph.cwdRelativePath(b.fmt("{s}/src/win32/cairo-dwrite-font.cpp", .{dir})), .flags = cpp_flags });
    mod.link_libcpp = true;
    return .{
        .lib = b.addLibrary(.{ .name = "cairo", .linkage = .static, .root_module = mod }),
        .include = b.graph.cwdRelativePath(b.fmt("{s}/src", .{dir})),
        .generated = gen.getDirectory(),
    };
}

const Version = struct {
    major: []const u8,
    minor: []const u8,
    micro: []const u8,

    fn is(v: Version, want: []const u8) bool {
        var it = mem.splitScalar(u8, want, '.');
        return mem.eql(u8, it.next() orelse "", v.major) and
            mem.eql(u8, it.next() orelse "", v.minor) and
            mem.eql(u8, it.next() orelse "", v.micro) and it.next() == null;
    }
};

/// cairo-version.h's CAIRO_VERSION_MAJOR, _MINOR and _MICRO.
fn versionOf(h: []const u8) ?Version {
    return .{
        .major = define(h, "#define CAIRO_VERSION_MAJOR ") orelse return null,
        .minor = define(h, "#define CAIRO_VERSION_MINOR ") orelse return null,
        .micro = define(h, "#define CAIRO_VERSION_MICRO ") orelse return null,
    };
}

fn define(h: []const u8, key: []const u8) ?[]const u8 {
    const at = mem.indexOf(u8, h, key) orelse return null;
    const rest = h[at + key.len ..];
    return mem.trim(u8, rest[0 .. mem.indexOfScalar(u8, rest, '\n') orelse rest.len], " \r\t");
}

fn fail(comptime fmt: []const u8, args: anytype) error{CairoBuild} {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    return error.CairoBuild;
}

// --- tests: the pins agree --------------------------------------------
// The toolchain build's test step passes the paths (paths.zon is R's
// build.zig.zon, paths.recipe the recipe).

fn readPinned(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(1024 * 1024));
}

test "build.zig.zon fetches this url" {
    const zon = try readPinned(@import("paths").zon);
    defer std.testing.allocator.free(zon);
    try std.testing.expect(mem.indexOf(u8, zon, ".url = \"" ++ url ++ "\",") != null);
}

test "recipe.yaml's win source is this url and sha256" {
    const yaml = try readPinned(@import("paths").recipe);
    defer std.testing.allocator.free(yaml);
    const at = mem.indexOf(u8, yaml, "url: " ++ url ++ "\n") orelse return error.RecipeHasNoCairoUrl;
    var lines = mem.splitScalar(u8, yaml[at..], '\n');
    _ = lines.next();
    const next = mem.trim(u8, lines.next() orelse "", " \r");
    try std.testing.expectEqualStrings("sha256: " ++ sha256, next);
}

test "cairo-version.h's version" {
    const v = versionOf("#define CAIRO_VERSION_MAJOR 1\n#define CAIRO_VERSION_MINOR 18\r\n#define CAIRO_VERSION_MICRO 6\n").?;
    try std.testing.expect(v.is("1.18.6"));
    try std.testing.expect(!v.is("1.18.4"));
    try std.testing.expect(!v.is("1.18.6.1"));
    try std.testing.expect(versionOf("nothing") == null);
}
