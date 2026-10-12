//! rzig on its own: `zig build --build-file zigbuild/tools/rzig/build.zig`
//! needs no pixi env, R source or vendored config, and cross-builds with
//! -Dtarget (parity-test.sh and smoke-test.sh use it). The repo's build.zig
//! reuses `add` to build the rzig it installs into R_HOME/bin/toolchain,
//! for R's own target, and for its `rzig`/`rzig-test` steps.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Default: " ++ @tagName(default_optimize)) orelse default_optimize;
    // the repo's build.zig passes R's own; a test build has none
    const r_version = b.option([]const u8, "r-version", "R's version, for the text that names a missing toolchain group (default: dev)") orelse "dev";
    const steps = add(b, b.path("."), target, optimize, r_version);
    b.getInstallStep().dependOn(&b.addInstallBinFile(steps.bin, if (target.result.os.tag == .windows) "rzig.exe" else "rzig").step);
    b.step("test", "Run rzig's unit tests").dependOn(&b.addRunArtifact(steps.tests).step);
}

pub const Artifacts = struct {
    exe: *std.Build.Step.Compile,
    /// What to install: exe's binary, re-signed on a macOS host (see add).
    bin: std.Build.LazyPath,
    tests: *std.Build.Step.Compile,
};

/// Safety checks stay on: a bounds error in an argument rewrite should stop
/// the compile, not pass zig a wrong command line.
pub const default_optimize: std.builtin.OptimizeMode = .ReleaseSafe;

/// The rzig executable and its tests, from the sources in `dir`. No libc
/// on linux: a static binary that runs on any kernel, whatever glibc the
/// machine has (macOS links libSystem, Windows kernel32/ntdll, as every
/// program there does). Stripped in release modes: it ships as several
/// copies (a wheel has no symlinks, Windows needs gcc.exe and g++.exe).
/// `r_version` is R's: the text that names a missing toolchain group says
/// which R it is for (groups.zig); the platform there is the target's.
pub fn add(b: *std.Build, dir: std.Build.LazyPath, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, r_version: []const u8) Artifacts {
    const options = b.addOptions();
    options.addOption([]const u8, "r_version", r_version);
    const mod = b.createModule(.{
        .root_source_file = dir.path(b, "main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    });
    const test_mod = b.createModule(.{
        .root_source_file = dir.path(b, "main.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    mod.addOptions("build_options", options);
    test_mod.addOptions("build_options", options);
    const exe = b.addExecutable(.{ .name = "rzig", .root_module = mod });
    var bin = exe.getEmittedBin();
    if (target.result.os.tag == .macos) {
        // Header room for install_name_tool, as R's own Mach-O files get
        // (build.zig macHeaderpad): rattler-build relinks every Mach-O it
        // packages and failed on rzig without it ("larger updated load
        // commands do not fit", osx-arm64 r-zig-toolchain, 2026-10-02).
        exe.headerpad_max_install_names = true;
        // A full ad-hoc signature from codesign, on a macOS host (always
        // there, as xcrun is; a cross-build from linux keeps zig's own).
        // zig only writes a linker signature (adhoc,linker-signed), and
        // only on arm64. On omicron (2026-10-02) CrowdStrike Falcon's
        // static analysis quarantined the x86_64 rzig within seconds of
        // it being written, unsigned or linker-signed alike, and left the
        // same binary signed by codesign alone: Intel Macs with such an
        // agent would lose the compiler. XProtect's YARA rules do not
        // match it (scanned).
        if (b.graph.host.result.os.tag == .macos) {
            const sign = b.addSystemCommand(&.{ "/bin/sh", "-c", "cp \"$1\" \"$2\" && chmod u+w \"$2\" && /usr/bin/codesign --force --sign - \"$2\"", "rzig-codesign" });
            sign.addFileArg(exe.getEmittedBin());
            bin = sign.addOutputFileArg("rzig");
        }
    }
    return .{
        .exe = exe,
        .bin = bin,
        .tests = b.addTest(.{ .name = "rzig-test", .root_module = test_mod }),
    };
}
