//! The toolchain's groups and the text that names a missing one
//! (feat-standalone-toolchain B35, B38). Two groups: compilers (zig,
//! flang, the OpenMP files) and build-tools (make; on Windows also sh, the
//! binutils and the other tools R's makefiles run). rzig prints a group's
//! text when a compile finds no zig, when zig-fc finds no flang, when
//! `rzig build` finds no zig (pkgbuild.zig), and from its check mode
//! (check.zig), which the install preflight (patch 0009,
//! `--rzig-check=package`) and R CMD config (patch 0010,
//! `--rzig-check=build-tools`) call (B26 a) and show.
//!
//! One text per group, the same on every channel. It is built from R's
//! version (build.zig passes it, a build option) and the platform rzig is
//! built for, which is R's. Its first line says what is missing; the rest
//! says how to install the group on each channel.
//!
//! The text names what installs a group on the day it is printed, and this
//! file is the one place it lives, so each later phase edits only these
//! lines:
//! - conda and pip: today's r-zig-toolchain, one package with every group.
//!   Phase 4 names the per-group packages (r-zig-compilers,
//!   r-zig-build-tools).
//! - standalone: from phase 3 each group has an archive,
//!   R-<ver>-<plat>-<group>.tar.gz (.zip on Windows, B17), extracted where
//!   R was. The text names it for what it holds and the tools themselves
//!   for the rest. build-tools holds unix make, and on Windows the binutils
//!   (B24); phase 7 adds Windows' usr/bin, until then sh and make on PATH.
//!   compilers holds the OpenMP files (C19); phases 5 and 6 add zig and
//!   flang, until then on PATH (zig also in ZIG_BIN).
//!
//! rzig does not read R_ZIG_TOOLCHAIN_HINT. Until phase 4 the conda and
//! wheel builds still write it, naming their toolchain package, and the
//! preflight (patch 0009) and R CMD config (patch 0010) show it only where
//! R has no rzig, so that package is missing (PHASE3 C8). Where rzig is
//! there, the package is installed and the hint would name the wrong
//! remedy (the wheel's "pip install r-zig-toolchain" for a missing flang).
//! Phase 4 removes the writers and that branch; a user's own value is then
//! shown as a hint after rzig's text.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const floors = @import("floors.zig");

pub const Group = enum {
    compilers,
    build_tools,

    /// The group's name in archives and packages (B38).
    pub fn name(g: Group) []const u8 {
        return switch (g) {
            .compilers => "compilers",
            .build_tools => "build-tools",
        };
    }
};

/// What a text is built from.
pub const Platform = struct {
    /// R's version.
    r: []const u8,
    /// conda's name for the platform, as the archives use it (B17).
    name: []const u8,
    windows: bool,
    /// R's zig, major.minor: the zig that built rzig built R.
    zig: []const u8,
};

/// The platform rzig is built for, R's.
pub const this: Platform = .{
    .r = @import("build_options").r_version,
    .name = platformName(builtin.cpu.arch, builtin.os.tag),
    .windows = builtin.os.tag == .windows,
    .zig = floors.majorMinor(builtin.zig_version),
};

/// conda's subdir names: linux-64, linux-aarch64, osx-64, osx-arm64,
/// win-64. Any other: <os>-<arch>.
pub fn platformName(comptime arch: std.Target.Cpu.Arch, comptime os: std.Target.Os.Tag) []const u8 {
    return switch (os) {
        .linux => switch (arch) {
            .x86_64 => "linux-64",
            .aarch64 => "linux-aarch64",
            else => "linux-" ++ @tagName(arch),
        },
        .macos => switch (arch) {
            .x86_64 => "osx-64",
            .aarch64 => "osx-arm64",
            else => "osx-" ++ @tagName(arch),
        },
        .windows => switch (arch) {
            .x86_64 => "win-64",
            .aarch64 => "win-arm64",
            else => "win-" ++ @tagName(arch),
        },
        else => @tagName(os) ++ "-" ++ @tagName(arch),
    };
}

/// The group's text after its first line: what the group holds, then one
/// line per channel.
pub fn text(a: mem.Allocator, g: Group, p: Platform) ![]const u8 {
    const conda = "  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)\n";
    const pip = if (p.windows) "  pip:         no wheels for Windows\n" else switch (g) {
        .compilers => "  pip:         pip install r-zig-toolchain (no Fortran)\n",
        .build_tools => "  pip:         pip install r-zig-toolchain\n",
    };
    // the group's archive (B17), which the standalone line names
    const archive = try std.fmt.allocPrint(a, "R-{s}-{s}-{s}.{s}", .{ p.r, p.name, g.name(), if (p.windows) "zip" else "tar.gz" });
    const head = switch (g) {
        .compilers => try std.fmt.allocPrint(a, "Compiling needs the r-zig compilers for R {s} on {s}: zig {s}, and flang for Fortran.\n" ++
            "  standalone:  zig {s} on PATH or in ZIG_BIN, LLVM flang on PATH; for OpenMP, extract {s} where you extracted R\n", .{ p.r, p.name, p.zig, p.zig, archive }),
        .build_tools => if (p.windows)
            try std.fmt.allocPrint(a, "Building packages needs the r-zig build tools for R {s} on {s}: sh, make, binutils and the tools R's makefiles run.\n" ++
                "  standalone:  extract {s} where you extracted R (binutils), and put sh and make on PATH (for example Rtools45's usr/bin)\n", .{ p.r, p.name, archive })
        else
            try std.fmt.allocPrint(a, "Building packages needs the r-zig build tools for R {s} on {s}: make.\n" ++
                "  standalone:  extract {s} where you extracted R, or put GNU make on PATH\n", .{ p.r, p.name, archive }),
    };
    return mem.concat(a, u8, &.{ head, conda, pip });
}

/// `what`, the first line (what is missing, or a zig that is not R's),
/// then the group's text, on stderr.
pub fn report(ctx: *const Ctx, what: []const u8, g: Group) !void {
    // ctx.warn adds the newline
    const t = try text(ctx.arena, g, this);
    ctx.warn("{s}\n{s}", .{ what, t[0 .. t.len - 1] });
}

/// What a compile says when it finds no zig (find_zig.zig). This and
/// no_flang, after `zig-cc: `, are what verify-bundle.sh asserts.
pub const no_zig = "no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the environment's bin, PATH, python3 -m ziglang)";
/// What zig-fc says when it finds no flang (flang_rt.flang).
pub const no_flang = "no flang (R_HOME/bin/toolchain/flang/bin, the environment's bin, PATH)";

// ---------------------------------------------------------------------------

const testing = std.testing;

test platformName {
    try testing.expectEqualStrings("linux-64", platformName(.x86_64, .linux));
    try testing.expectEqualStrings("linux-aarch64", platformName(.aarch64, .linux));
    try testing.expectEqualStrings("osx-64", platformName(.x86_64, .macos));
    try testing.expectEqualStrings("osx-arm64", platformName(.aarch64, .macos));
    try testing.expectEqualStrings("win-64", platformName(.x86_64, .windows));
    // R's own: what rzig is built for; its zig is the one that built it
    try testing.expectEqualStrings(platformName(builtin.cpu.arch, builtin.os.tag), this.name);
    try testing.expect(this.r.len > 0);
    try testing.expectEqualStrings(std.fmt.comptimePrint("{d}.{d}", .{ builtin.zig_version.major, builtin.zig_version.minor }), this.zig);
    try testing.expectEqualStrings("build-tools", Group.build_tools.name());
}

test "one text per group, the same on every channel" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const linux: Platform = .{ .r = "4.6.1", .name = "linux-64", .windows = false, .zig = "0.16" };
    const mac: Platform = .{ .r = "4.6.1", .name = "osx-arm64", .windows = false, .zig = "0.16" };
    const win: Platform = .{ .r = "4.6.1", .name = "win-64", .windows = true, .zig = "0.16" };
    // other scripts grep these: verify-bundle.sh and hermetic-check.sh the
    // first lines' beginnings, wheel-test.sh "LLVM flang on PATH" and the
    // pip line, parity-test.sh the first lines and unix's standalone lines
    try testing.expectEqualStrings(
        \\Compiling needs the r-zig compilers for R 4.6.1 on linux-64: zig 0.16, and flang for Fortran.
        \\  standalone:  zig 0.16 on PATH or in ZIG_BIN, LLVM flang on PATH; for OpenMP, extract R-4.6.1-linux-64-compilers.tar.gz where you extracted R
        \\  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
        \\  pip:         pip install r-zig-toolchain (no Fortran)
        \\
    , try text(a, .compilers, linux));
    try testing.expectEqualStrings(
        \\Compiling needs the r-zig compilers for R 4.6.1 on win-64: zig 0.16, and flang for Fortran.
        \\  standalone:  zig 0.16 on PATH or in ZIG_BIN, LLVM flang on PATH; for OpenMP, extract R-4.6.1-win-64-compilers.zip where you extracted R
        \\  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
        \\  pip:         no wheels for Windows
        \\
    , try text(a, .compilers, win));
    try testing.expectEqualStrings(
        \\Building packages needs the r-zig build tools for R 4.6.1 on linux-64: make.
        \\  standalone:  extract R-4.6.1-linux-64-build-tools.tar.gz where you extracted R, or put GNU make on PATH
        \\  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
        \\  pip:         pip install r-zig-toolchain
        \\
    , try text(a, .build_tools, linux));
    try testing.expectEqualStrings(
        \\Building packages needs the r-zig build tools for R 4.6.1 on osx-arm64: make.
        \\  standalone:  extract R-4.6.1-osx-arm64-build-tools.tar.gz where you extracted R, or put GNU make on PATH
        \\  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
        \\  pip:         pip install r-zig-toolchain
        \\
    , try text(a, .build_tools, mac));
    try testing.expectEqualStrings(
        \\Building packages needs the r-zig build tools for R 4.6.1 on win-64: sh, make, binutils and the tools R's makefiles run.
        \\  standalone:  extract R-4.6.1-win-64-build-tools.zip where you extracted R (binutils), and put sh and make on PATH (for example Rtools45's usr/bin)
        \\  conda, pixi: pixi add r-zig-toolchain (or conda install r-zig-toolchain)
        \\  pip:         no wheels for Windows
        \\
    , try text(a, .build_tools, win));
}

test report {
    var f: @import("testutil.zig").Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try report(&f.ctx, no_zig, .compilers);
    const w = f.takeWarnings();
    try testing.expect(mem.startsWith(u8, w, "rzig-test: no zig (ZIG_BIN, R_HOME/bin/toolchain/zig, the environment's bin, PATH, python3 -m ziglang)\nCompiling needs the r-zig compilers for R "));
    try testing.expect(mem.endsWith(u8, w, "\n  pip:         " ++ (if (this.windows) "no wheels for Windows" else "pip install r-zig-toolchain (no Fortran)") ++ "\n"));
}
