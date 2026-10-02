//! The oldest systems R and the packages compiled for it support, in one
//! place: the repo's build.zig builds R (and rzig) for them, and rzig pins
//! every package compile to them. Raising one is a decision about who can
//! run R, so it is made here once.
const std = @import("std");

/// glibc floor on linux (RHEL/CentOS 7 era, also conda-forge's baseline).
/// glibc is backward compatible, so a floor, not a restriction: packages
/// are often compiled on a newer login node than the compute nodes that
/// load them.
pub const glibc: std.SemanticVersion = .{ .major = 2, .minor = 17, .patch = 0 };

/// macOS deployment target: every Mach-O's LC_BUILD_VERSION minos. zig
/// 0.16's own supported floor; ziglang, the wheel's compiler, needs 12.
pub const macos: std.SemanticVersion = .{ .major = 13, .minor = 0, .patch = 0 };

/// "MAJOR.MINOR", as zig's target triples and `-mmacosx-version-min` take it.
pub fn majorMinor(comptime v: std.SemanticVersion) []const u8 {
    return std.fmt.comptimePrint("{d}.{d}", .{ v.major, v.minor });
}
