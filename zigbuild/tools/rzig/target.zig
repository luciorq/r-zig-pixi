//! What rzig compiles for, named on every command it runs, on every OS:
//! R's own platform, which is the one rzig itself was built for (the
//! repo's build.zig builds rzig for R's target, beside R's binaries). Not
//! zig's or flang's own: those are the platform their binary was built
//! for, and on Windows on ARM pixi installed a win-64 environment beside
//! an arm64 R, whose x64 zig, first on PATH and given no target, compiled
//! every package for x64 (stress run 43773932212; chore-release-11
//! PLAN.md findings 26 and 29). With the target named, that zig compiles
//! for R's arm64 (zig cross-compiles to every target it knows), and a
//! library of the other arch fails the link loudly instead.
const builtin = @import("builtin");
const Ctx = @import("Ctx.zig");
const floors = @import("floors.zig");

/// The CPU architectures R is built for (x86_64 and aarch64, on linux,
/// macOS and Windows). `own`: rzig's, which is R's.
pub const Arch = enum {
    x86_64,
    aarch64,

    pub const own: Arch = switch (builtin.cpu.arch) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        else => @compileError("rzig compiles for x86_64 and aarch64 only"),
    };
};

const glibc = floors.majorMinor(floors.glibc);
const macos = floors.majorMinor(floors.macos);

/// zig's -target for `os` on `arch`, the target build.zig builds R for:
/// linux, the glibc floor; macOS, the deployment floor as
/// "<arch>-native.<floor>" (darwin.zig says why that spelling); Windows,
/// the GNU (MinGW) ABI. null for another OS (zig's native target).
pub fn zig(os: Ctx.Os, arch: Arch) ?[]const u8 {
    return switch (arch) {
        inline else => |a| switch (os) {
            .linux => @tagName(a) ++ "-linux-gnu." ++ glibc,
            .macos => @tagName(a) ++ "-native." ++ macos,
            .windows => @tagName(a) ++ "-windows-gnu",
            .other => null,
        },
    };
}

/// flang's --target for `os` on `arch`: the default target triple of
/// flang-zig 23.1.5's flang for that platform (`flang --version` on
/// linux-64; the triple-named files and module directories of the other
/// five platforms' flang-zig and flang-rt-zig packages), so a flang built
/// for R's platform compiles exactly as without the flag, down to the
/// configuration file it reads (`<triple>-flang.cfg`, else flang.cfg;
/// linux-64's object byte-identical, 2026-11-15), and a flang built for
/// another platform compiles for R's (linux-64's flang-zig wrote an
/// aarch64 object for aarch64-conda-linux-gnu and aarch64-w64-windows-gnu).
/// macOS: the deployment floor comes from floors.macos_min_flag after it,
/// as before (`-triple arm64-apple-macosx13.0.0` either way). null for
/// another OS.
pub fn flang(os: Ctx.Os, arch: Arch) ?[]const u8 {
    return switch (os) {
        .linux => switch (arch) {
            inline else => |a| @tagName(a) ++ "-conda-linux-gnu",
        },
        .macos => switch (arch) {
            .x86_64 => "x86_64-apple-darwin13.4.0",
            .aarch64 => "arm64-apple-darwin20.0.0",
        },
        .windows => switch (arch) {
            inline else => |a| @tagName(a) ++ "-w64-windows-gnu",
        },
        .other => null,
    };
}

const std = @import("std");
const testing = std.testing;

test "zig's target: R's, every OS, each arch" {
    try testing.expectEqualStrings("x86_64-linux-gnu.2.17", zig(.linux, .x86_64).?);
    try testing.expectEqualStrings("aarch64-linux-gnu.2.17", zig(.linux, .aarch64).?);
    try testing.expectEqualStrings("x86_64-native.13.0", zig(.macos, .x86_64).?);
    try testing.expectEqualStrings("aarch64-native.13.0", zig(.macos, .aarch64).?);
    try testing.expectEqualStrings("x86_64-windows-gnu", zig(.windows, .x86_64).?);
    try testing.expectEqualStrings("aarch64-windows-gnu", zig(.windows, .aarch64).?);
    try testing.expect(zig(.other, .own) == null);
    try testing.expectEqualStrings(@tagName(builtin.cpu.arch), @tagName(Arch.own));
}

test "flang's target: flang-zig's default triple, every OS, each arch" {
    try testing.expectEqualStrings("x86_64-conda-linux-gnu", flang(.linux, .x86_64).?);
    try testing.expectEqualStrings("aarch64-conda-linux-gnu", flang(.linux, .aarch64).?);
    try testing.expectEqualStrings("x86_64-apple-darwin13.4.0", flang(.macos, .x86_64).?);
    try testing.expectEqualStrings("arm64-apple-darwin20.0.0", flang(.macos, .aarch64).?);
    try testing.expectEqualStrings("x86_64-w64-windows-gnu", flang(.windows, .x86_64).?);
    try testing.expectEqualStrings("aarch64-w64-windows-gnu", flang(.windows, .aarch64).?);
    try testing.expect(flang(.other, .own) == null);
}
