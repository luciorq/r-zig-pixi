//! GNU make for the build-tools group's usr/bin/make on linux and macOS
//! (backlog L7; .github/devdocs/b13-build/PLAN.md D10-D12): built from
//! upstream's release tarball by zigbuild/make/build.zig (the toolchain
//! build's r_zig_make path dependency), in place of conda-forge's make.
//! Windows keeps MSYS2's m2-make (D12).
//!
//! The tarball: `url` and `sha256` below, which usr/SOURCES records. The
//! standalone build fetches it as build.zig.zon's lazy `make` dependency
//! (zig checks its own hash of the tree); the conda build takes it as a
//! source of recipe/recipe.yaml (rattler-build checks the sha256) and
//! passes the unpacked directory as -Dmake=<dir>. The `test` step checks
//! that the zon's URL and the recipe's URL and sha256 are these.
const std = @import("std");
const mem = std.mem;

pub const version = "4.4.1";
pub const url = "https://ftp.gnu.org/gnu/make/make-" ++ version ++ ".tar.gz";
pub const sha256 = "dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3";
/// COPYING is its text (GPL version 3; the sources say "or any later").
pub const license = "GPL-3.0-or-later";

test "build.zig.zon fetches this url" {
    const zon = @embedFile("build.zig.zon");
    try std.testing.expect(mem.indexOf(u8, zon, ".url = \"" ++ url ++ "\",") != null);
}

test "recipe.yaml's unix source is this url and sha256" {
    const recipe_path = @import("paths").recipe;
    const io = std.testing.io;
    const yaml = try std.Io.Dir.cwd().readFileAlloc(io, recipe_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(yaml);
    const at = mem.indexOf(u8, yaml, "url: " ++ url ++ "\n") orelse return error.RecipeHasNoMakeUrl;
    var lines = mem.splitScalar(u8, yaml[at..], '\n');
    _ = lines.next();
    const next = mem.trim(u8, lines.next() orelse "", " \r");
    try std.testing.expectEqualStrings("sha256: " ++ sha256, next);
}
