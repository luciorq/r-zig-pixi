//! rzig on its own: `zig build --build-file zigbuild/tools/rzig/build.zig`
//! needs no pixi env, R source or vendored config, and cross-builds with
//! -Dtarget (check-test.sh and smoke-test.sh use it). The repo's build.zig
//! reuses `add` to build the rzig it installs into R_HOME/bin/toolchain,
//! for R's own target, and for its `rzig`/`rzig-test` steps. Both install
//! rzig's link object beside it (`linkObject`), and on linux the
//! libstdc++ shim headers (`shim`).
const std = @import("std");
const floors = @import("floors.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.lang.Optimize, "optimize", "Default: " ++ @tagName(default_optimize)) orelse default_optimize;
    // the repo's build.zig passes R's own; a test build has none
    const r_version = b.option([]const u8, "r-version", "R's version, for the text that names a missing toolchain group (default: dev)") orelse "dev";
    const steps = add(b, b.path("."), target, optimize, r_version);
    b.getInstallStep().dependOn(&b.addInstallBinFile(steps.bin, if (target.result.os.tag == .windows) "rzig.exe" else "rzig").step);
    if (steps.object) |o| b.getInstallStep().dependOn(&b.addInstallBinFile(o.file, o.name).step);
    // the link object alone, for -Dtarget: link-objects-test.sh's Windows
    // links (a cross-build of rzig itself takes minutes)
    const ob = b.step("object", "Install rzig's link object for -Dtarget, without rzig");
    if (steps.object) |o| ob.dependOn(&b.addInstallBinFile(o.file, o.name).step);
    if (steps.shim) |d| b.getInstallStep().dependOn(&b.addInstallDirectory(.{ .source_dir = d, .install_dir = .bin, .install_subdir = shim_dir }).step);
    const t = b.step("test", "Run rzig's unit tests");
    t.dependOn(&b.addRunArtifact(steps.tests).step);
    // the unit tests as a program for -Dtarget, to copy to and run on
    // another OS (kappa, omicron): bin/rzig-test
    const tb = b.step("test-bin", "Install rzig's unit tests for -Dtarget as bin/rzig-test");
    tb.dependOn(&b.addInstallArtifact(addTests(b, b.path("."), target, r_version), .{}).step);
}

pub const Artifacts = struct {
    exe: *std.Build.Step.Compile,
    /// What to install: exe's binary, re-signed on a macOS host (see add).
    bin: std.Build.LazyPath,
    tests: *std.Build.Step.Compile,
    /// What to install beside it: the object rzig adds to links
    /// (`linkObject`); none on macOS.
    object: ?LinkObject,
    /// What to install beside it as `shim_dir`: on linux the two headers
    /// libstdc++'s need with zig's glibc headers (libstdcxx.zig); none
    /// on macOS and Windows.
    shim: ?std.Build.LazyPath,
};

/// The shims' directory name beside rzig, which libstdcxx.zig looks for.
pub const shim_dir = "libstdcxx-shim";

pub const LinkObject = struct { name: []const u8, file: std.Build.LazyPath };

/// Safety checks stay on: a bounds error in an argument rewrite should stop
/// the compile, not pass zig a wrong command line.
pub const default_optimize: std.lang.Optimize = .safe;

/// The rzig executable and its tests, from the sources in `dir`. No libc
/// on linux: a static binary that runs on any kernel, whatever glibc the
/// machine has (macOS links libSystem, Windows kernel32/ntdll, as every
/// program there does). Stripped in release modes: it ships as several
/// copies (a wheel has no symlinks, Windows needs gcc.exe and g++.exe).
/// `r_version` is R's: the text that names a missing toolchain group says
/// which R it is for (groups.zig); the platform there is the target's.
pub fn add(b: *std.Build, dir: std.Build.LazyPath, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize, r_version: []const u8) Artifacts {
    const options = b.addOptions();
    options.addOption([]const u8, "r_version", r_version);
    const mod = b.createModule(.{
        .root_source_file = dir.path(b, "main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .debug,
    });
    mod.addOptions("build_options", options);
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
        .tests = addTests(b, dir, b.graph.host, r_version),
        .object = linkObject(b, dir, target),
        .shim = if (target.result.os.tag == .linux) dir.path(b, "include/" ++ shim_dir) else null,
    };
}

/// The object rzig adds to every link of its kind, for `target`, which
/// rzig finds in its own directory (compiler.zig's linkObject), so both
/// build.zigs install it beside rzig: on linux dso_fini.o, the
/// finalization object of shared libraries (dso_fini.zig), on x86_64
/// Windows cfguard.o, the Control Flow Guard stub (cfguard.zig), and on
/// aarch64 Windows clear_cache.o, the instruction-cache flush
/// (clear_cache.zig). aarch64 Windows needs no CFG object: clang's ARM64
/// CFG calls only __guard_check_icall_fptr, and zig's libmingw32 defines
/// it there (link-objects-test.sh). None on macOS, which needs none. Each is compiled
/// from objects/<name>.zig with the zig that runs this build, for the
/// baseline CPU, ReleaseSmall and stripped: no debug information, so no
/// build path (C compiled for Windows carries CodeView's object-name
/// record, the build machine's path, even at -g0; chore-release-11).
pub fn linkObject(b: *std.Build, dir: std.Build.LazyPath, target: std.Build.ResolvedTarget) ?LinkObject {
    const t = target.result;
    const stem: []const u8, const triple: []const u8 = switch (t.os.tag) {
        // compiler.zig's linux_target: the glibc floor packages link for
        .linux => .{ "dso_fini", b.fmt("{t}-linux-gnu." ++ floors.majorMinor(floors.glibc), .{t.cpu.arch}) },
        .windows => switch (t.cpu.arch) {
            .x86_64 => .{ "cfguard", "x86_64-windows-gnu" },
            .aarch64 => .{ "clear_cache", "aarch64-windows-gnu" },
            else => return null,
        },
        else => return null,
    };
    const query = std.Target.Query.parse(.{ .arch_os_abi = triple, .cpu_features = "baseline" }) catch |e|
        std.debug.panic("rzig: link object target {s}: {t}", .{ triple, e });
    const obj = b.addObject(.{
        .name = stem,
        .root_module = b.createModule(.{
            .root_source_file = dir.path(b, b.fmt("objects/{s}.zig", .{stem})),
            .target = b.resolveTargetQuery(query),
            .optimize = .ReleaseSmall,
            .strip = true,
            // linux: the object goes into shared libraries
            .pic = if (t.os.tag == .linux) true else null,
        }),
    });
    return .{ .name = b.fmt("{s}.o", .{stem}), .file = obj.getEmittedBin() };
}

/// rzig's unit tests for `target`: the host's, to run here (`add`), or
/// another's, to run on that machine (test-bin).
pub fn addTests(b: *std.Build, dir: std.Build.LazyPath, target: std.Build.ResolvedTarget, r_version: []const u8) *std.Build.Step.Compile {
    const options = b.addOptions();
    options.addOption([]const u8, "r_version", r_version);
    const mod = b.createModule(.{
        .root_source_file = dir.path(b, "main.zig"),
        .target = target,
        .optimize = .debug,
    });
    mod.addOptions("build_options", options);
    // tier1.zig's scheduler tests run this compiler and linker stand-in
    // (testdata/fake_cc.zig), embedded: a program, not a shell script, so
    // they run on Windows too, and wherever the test binary is copied
    const fake_cc = b.addExecutable(.{ .name = "fake-cc", .root_module = b.createModule(.{
        .root_source_file = dir.path(b, "testdata/fake_cc.zig"),
        .target = target,
        .optimize = .safe,
        .strip = true,
    }) });
    mod.addAnonymousImport("fake_cc", .{ .root_source_file = fake_cc.getEmittedBin() });
    // and this program, which crashes with rzig's crash handling
    // (testdata/crash.zig, crash.zig), built as rzig is
    const crash_mod = b.createModule(.{
        .root_source_file = dir.path(b, "testdata/crash.zig"),
        .target = target,
        .optimize = default_optimize,
        .strip = true,
    });
    crash_mod.addAnonymousImport("crash", .{ .root_source_file = dir.path(b, "crash.zig") });
    const crash = b.addExecutable(.{ .name = "crash", .root_module = crash_mod });
    mod.addAnonymousImport("crash_program", .{ .root_source_file = crash.getEmittedBin() });
    return b.addTest(.{ .name = "rzig-test", .root_module = mod });
}
