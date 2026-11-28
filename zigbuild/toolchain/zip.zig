//! Info-ZIP zip for Windows' build tools (.github/devdocs/b14-l4/PLAN.md,
//! user decision U4): R CMD INSTALL --build and utils::zip() run `zip`
//! (R_ZIPCMD, default "zip"), which neither MSYS2's set (no m2-zip in
//! r-zig-build-tools) nor busybox-w32 (no zip applet) had. Built from
//! Info-ZIP's release tarball by zigbuild/zip/build.zig (the toolchain
//! build's r_zig_zip path dependency) into usr/bin/zip.exe
//! (r-zig-build-tools) and native/bin/zip.exe (r-zig-native-tools).
//!
//! The tarball: `url` and `sha256` below, which SOURCES records. The
//! standalone build fetches it as build.zig.zon's lazy `zip` dependency
//! from Debian's copy of the same tarball (`mirror`; zig keeps
//! SourceForge's redirect target's top directory, so the tree's hash
//! differs) and checks its own hash of the tree; the conda build takes it
//! as a source of recipe/recipe.yaml (rattler-build checks the sha256)
//! and passes the unpacked directory as -Dzip=<dir>. The `test` step
//! checks that the zon's URL and the recipe's URL and sha256 are these.
const std = @import("std");
const mem = std.mem;

pub const version = "3.0";
pub const url = "https://downloads.sourceforge.net/project/infozip/Zip%203.x%20%28latest%29/3.0/zip30.tar.gz";
/// The same tarball (sha256), as Debian ships it.
pub const mirror = "https://deb.debian.org/debian/pool/main/z/zip/zip_3.0.orig.tar.gz";
pub const sha256 = "f0e8bb1f9b7eb0b01285495a2699df3a4b766784c1765a8f1aeedf63c0806369";
/// LICENSE is its text (the Info-ZIP license, version 2007-Mar-4).
pub const license = "Info-ZIP";

test "build.zig.zon fetches the mirror" {
    const zon = @embedFile("build.zig.zon");
    try std.testing.expect(mem.indexOf(u8, zon, ".url = \"" ++ mirror ++ "\",") != null);
    const own = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, @import("paths").zip_zon, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(own);
    try std.testing.expect(mem.indexOf(u8, own, ".url = \"" ++ mirror ++ "\",") != null);
}

test "recipe.yaml's win source is this url, the mirror and sha256" {
    const recipe_path = @import("paths").recipe;
    const io = std.testing.io;
    const yaml = try std.Io.Dir.cwd().readFileAlloc(io, recipe_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(yaml);
    // `url:`, `- <url>`, `- <mirror>`, then `sha256:`
    const at = mem.indexOf(u8, yaml, "- " ++ url ++ "\n") orelse return error.RecipeHasNoZipUrl;
    try std.testing.expect(mem.endsWith(u8, mem.trimEnd(u8, yaml[0..at], " "), "url:\n"));
    var lines = mem.splitScalar(u8, yaml[at..], '\n');
    _ = lines.next();
    try std.testing.expectEqualStrings("- " ++ mirror, mem.trim(u8, lines.next() orelse "", " \r"));
    try std.testing.expectEqualStrings("sha256: " ++ sha256, mem.trim(u8, lines.next() orelse "", " \r"));
}
