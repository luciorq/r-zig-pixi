//! cmake for the extras group's cmake/ (feat-extras-group): Kitware's own
//! release archive of cmake for this machine, a lazy dependency of
//! build.zig.zon per archive (zig checks its own hash of the tree; the
//! sha256 below is Kitware's, from cmake-<version>-SHA-256.txt beside the
//! archives, and SOURCES records it). One universal archive serves both
//! macOS arches. Kitware's cmake loads no library from a conda env, where
//! conda-forge's links a dozen of the env's: on linux it needs only
//! glibc's libraries (GLIBC_2.17 on x86_64, 2.28 on aarch64; libstdc++
//! and libgcc are linked in), on Windows only system DLLs, on macOS the
//! system's /usr/lib libcurl, libz, libiconv, libcharset and libc++ and
//! two frameworks (minos 10.13 for x86_64, 11.0 for arm64). PyPI's cmake
//! wheel was the first choice and was dropped: its linux cmake needs the
//! host's libstdc++.so.6 and libgcc_s.so.1 (manylinux policy). conda keeps
//! conda-forge's cmake (r-zig-extras); this file is the standalone tree's.
//!
//! What cmake/ installs from an archive (`wanted`): bin/cmake (cmake.exe)
//! and share/cmake-<major>.<minor>/Modules and Templates, which cmake finds
//! at ../share from its own place, and LICENSES/cmake/: the archive's
//! doc/cmake/ (cmake's LICENSE.rst, the CONTRIBUTORS.rst it names, the
//! licences of the libraries built into cmake) less its manual (html/,
//! CMake.qch, cmake.org.html). Left out: ctest, cpack, ccmake, cmake-gui,
//! cmcldeps, the macOS app bundle's GUI files, man/, the manual's sources
//! (share/cmake-<v>/Help/: no build reads them, and 24 of their names have
//! blanks, which SOURCES' `file:` lines cannot hold), Licenses/LGPLv3.txt
//! (Qt's, for cmake-gui) and the editors' and shells' files. No I/O here:
//! build.zig beside this file walks the archive's tree and installs, and
//! `test` (pixi run toolchain-test) runs the tests below.
const std = @import("std");
const mem = std.mem;

pub const version = "4.5.0";
/// The directory share/ holds the modules in: cmake-<major>.<minor>.
pub const data_dir = "share/cmake-4.5";
pub const release = "https://github.com/Kitware/CMake/releases/download/v" ++ version ++ "/";
/// cmake's source tarball, SOURCES' `source:` line (Kitware's sha256).
pub const source_url = release ++ "cmake-" ++ version ++ ".tar.gz";
pub const source_sha256 = "424352d6133e8455e020da787008e8dc67abb18820af3532572ab35657e49213";
/// LICENSE.rst's licence.
pub const license = "BSD-3-Clause";
/// What built the archives: Kitware's release of this tag (SOURCES'
/// `feedstock:` line).
pub const repository = "https://github.com/Kitware/CMake";
pub const tag = "v" ++ version;

/// One release archive.
pub const Archive = struct {
    /// Its build.zig.zon dependency.
    dep: []const u8,
    /// Its platform part (cmake-<version>-<platform>.<ext>), SOURCES'
    /// `build:` line.
    platform: []const u8,
    /// Its name, its top directory's name with the extension.
    file: []const u8,
    url: []const u8,
    /// Kitware's sha256 of it (cmake-<version>-SHA-256.txt).
    sha256: []const u8,
    /// Where bin/, share/ and doc/ are under its top directory: the macOS
    /// archive is an app bundle.
    root: []const u8 = "",

    /// Its top directory, which zig's fetch strips: the start of each
    /// SOURCES `file:` line's path in the archive.
    pub fn top(a: Archive) []const u8 {
        return a.file[0 .. mem.indexOf(u8, a.file, ".tar.gz") orelse mem.indexOf(u8, a.file, ".zip").?];
    }
};

fn archive(comptime platform: []const u8, comptime ext: []const u8, sha256: []const u8, root: []const u8) Archive {
    const file = "cmake-" ++ version ++ "-" ++ platform ++ ext;
    const dep = comptime blk: {
        var d: [platform.len]u8 = platform[0..].*;
        mem.replaceScalar(u8, &d, '-', '_');
        const out = d;
        break :blk "cmake_" ++ out;
    };
    return .{ .dep = dep, .platform = platform, .file = file, .url = release ++ file, .sha256 = sha256, .root = root };
}

pub const linux_x86_64 = archive("linux-x86_64", ".tar.gz", "81f0d5b0960fb6adc8197030ffc827fba937640d51e73e39e0e9e40d88c66f6f", "");
pub const linux_aarch64 = archive("linux-aarch64", ".tar.gz", "0c8447e7bba9701467b5ac6155d157aa9e309e71af4981f78bd4b9176107f553", "");
pub const macos_universal = archive("macos-universal", ".tar.gz", "a645d69fd21e521759cc0c64e7c60462d43faf0c7214ac05f75c80f7c5037dde", "CMake.app/Contents/");
pub const windows_x86_64 = archive("windows-x86_64", ".zip", "301b1728317ccd84e984b02e366a8293735bc5ac618757d3d8f58b578f062411", "");
pub const windows_arm64 = archive("windows-arm64", ".zip", "7dba95db83ec1e8fa3f221c06454ebc692c8f06d93bf5fdf840113fa28018690", "");
pub const archives = [_]Archive{ linux_x86_64, linux_aarch64, macos_universal, windows_x86_64, windows_arm64 };

/// The archive for a machine, or null where Kitware publishes none.
pub fn archiveFor(os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) ?Archive {
    return switch (os) {
        .linux => switch (arch) {
            .x86_64 => linux_x86_64,
            .aarch64 => linux_aarch64,
            else => null,
        },
        .macos => macos_universal,
        .windows => switch (arch) {
            .x86_64 => windows_x86_64,
            .aarch64 => windows_arm64,
            else => null,
        },
        else => null,
    };
}

/// Where cmake/ puts the archive's file `rel` (its path under the
/// archive's top directory, `/`-separated), or null for a file left out
/// (above). `windows`: the program is bin/cmake.exe.
pub fn wanted(a: Archive, rel: []const u8, windows: bool) ?Placed {
    if (!mem.startsWith(u8, rel, a.root)) return null;
    const r = rel[a.root.len..];
    if (mem.eql(u8, r, if (windows) "bin/cmake.exe" else "bin/cmake")) return .{ .to = r, .kind = .program };
    for ([_][]const u8{ data_dir ++ "/Modules/", data_dir ++ "/Templates/" }) |t| {
        if (mem.startsWith(u8, r, t)) return .{ .to = r, .kind = .data };
    }
    const doc = "doc/cmake/";
    if (mem.startsWith(u8, r, doc)) {
        const l = r[doc.len..];
        if (mem.startsWith(u8, l, "html/") or mem.endsWith(u8, l, ".qch") or mem.endsWith(u8, l, ".html")) return null;
        return .{ .to = l, .kind = .license };
    }
    return null;
}

pub const Placed = struct {
    /// Under cmake/ (data, program) or LICENSES/cmake/ (license).
    to: []const u8,
    kind: enum { program, data, license },
};

test "build.zig.zon fetches each archive, by its dependency name" {
    const zon = @embedFile("build.zig.zon");
    for (archives) |a| {
        const entry = try std.fmt.allocPrint(std.testing.allocator, ".{s} = .{{\n            .url = \"{s}\",", .{ a.dep, a.url });
        defer std.testing.allocator.free(entry);
        try std.testing.expect(mem.indexOf(u8, zon, entry) != null);
    }
}

test "one archive per machine; both macOS arches share the universal one" {
    try std.testing.expectEqualStrings("linux-x86_64", archiveFor(.linux, .x86_64).?.platform);
    try std.testing.expectEqualStrings("linux-aarch64", archiveFor(.linux, .aarch64).?.platform);
    try std.testing.expectEqualStrings("macos-universal", archiveFor(.macos, .x86_64).?.platform);
    try std.testing.expectEqualStrings("macos-universal", archiveFor(.macos, .aarch64).?.platform);
    try std.testing.expectEqualStrings("windows-arm64", archiveFor(.windows, .aarch64).?.platform);
    try std.testing.expectEqualStrings("cmake-4.5.0-windows-x86_64.zip", archiveFor(.windows, .x86_64).?.file);
    try std.testing.expectEqualStrings("cmake_macos_universal", macos_universal.dep);
    try std.testing.expectEqualStrings("cmake-4.5.0-macos-universal", macos_universal.top());
    try std.testing.expectEqualStrings("https://github.com/Kitware/CMake/releases/download/v4.5.0/cmake-4.5.0-linux-aarch64.tar.gz", linux_aarch64.url);
    try std.testing.expect(archiveFor(.linux, .riscv64) == null);
}

test "wanted: the program, Modules and Templates, the licences; nothing else" {
    const l = linux_x86_64;
    try std.testing.expectEqualStrings("bin/cmake", wanted(l, "bin/cmake", false).?.to);
    try std.testing.expect(wanted(l, "bin/cmake", false).?.kind == .program);
    try std.testing.expect(wanted(l, "bin/cmake", true) == null);
    for ([_][]const u8{ "bin/ctest", "bin/cpack", "bin/ccmake", "bin/cmake-gui", "man/man1/cmake.1", "share/aclocal/cmake.m4", "share/cmake-4.5/Help/generator/Unix Makefiles.rst", "share/cmake-4.5/Licenses/LGPLv3.txt", "doc/cmake/html/index.html", "doc/cmake/CMake.qch", "doc/cmake/cmake.org.html" }) |r|
        try std.testing.expect(wanted(l, r, false) == null);
    try std.testing.expectEqualStrings("share/cmake-4.5/Modules/FindZLIB.cmake", wanted(l, "share/cmake-4.5/Modules/FindZLIB.cmake", false).?.to);
    try std.testing.expectEqualStrings("share/cmake-4.5/Templates/Windows/Logo.png", wanted(l, "share/cmake-4.5/Templates/Windows/Logo.png", false).?.to);
    const lic = wanted(l, "doc/cmake/cmcurl/COPYING", false).?;
    try std.testing.expectEqualStrings("cmcurl/COPYING", lic.to);
    try std.testing.expect(lic.kind == .license);
    try std.testing.expectEqualStrings("LICENSE.rst", wanted(l, "doc/cmake/LICENSE.rst", false).?.to);
    // Windows' cmake.exe
    try std.testing.expectEqualStrings("bin/cmake.exe", wanted(windows_arm64, "bin/cmake.exe", true).?.to);
    try std.testing.expect(wanted(windows_arm64, "bin/cmcldeps.exe", true) == null);
    // macOS: under the app bundle only
    const m = macos_universal;
    try std.testing.expectEqualStrings("bin/cmake", wanted(m, "CMake.app/Contents/bin/cmake", false).?.to);
    try std.testing.expectEqualStrings("share/cmake-4.5/Modules/FindZLIB.cmake", wanted(m, "CMake.app/Contents/share/cmake-4.5/Modules/FindZLIB.cmake", false).?.to);
    for ([_][]const u8{ "CMake.app/Contents/MacOS/CMake", "CMake.app/Contents/Frameworks/QtCore.framework/QtCore", "bin/cmake", "CMake.app/Contents/Info.plist" }) |r|
        try std.testing.expect(wanted(m, r, false) == null);
}
