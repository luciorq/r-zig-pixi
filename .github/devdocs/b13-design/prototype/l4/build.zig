//! L4 prototype (b13-design PLAN.md): GNU make 4.4.1 for Windows, built
//! with zig from the upstream tarball, without its build_w32.bat. Not
//! wired into R's build; the shape follows zigbuild/toolchain/pkgconf.zig
//! so it can move there as one more build-tools member (backlog L7).
//!
//!   zig build -Dmake=<unpacked make-4.4.1> [-Darch=x86_64|aarch64]
//!
//! The sources and flags are build_w32.bat's gcc branch (`:GccCompile`,
//! `:GccLink`), less Guile, -g and -mthreads; config.h is the tarball's
//! src/config.h.W32 and glob.h/fnmatch.h its lib/*.in.h, copied as the
//! batch file does. The result is one static exe that imports only
//! Windows system DLLs and the UCRT.
const std = @import("std");

pub const version = "4.4.1";
pub const url = "https://ftp.gnu.org/gnu/make/make-" ++ version ++ ".tar.gz";
pub const sha256 = "dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3";

const sources = [_][]const u8{
    "src/ar",              "src/arscan",                "src/commands",          "src/default",
    "src/dir",             "src/expand",                "src/file",              "src/function",
    "src/getopt",          "src/getopt1",               "src/guile",             "src/hash",
    "src/implicit",        "src/job",                   "src/load",              "src/loadapi",
    "src/main",            "src/misc",                  "src/output",            "src/read",
    "src/remake",          "src/remote-stub",           "src/rule",              "src/shuffle",
    "src/signame",         "src/strcache",              "src/variable",          "src/version",
    "src/vpath",           "src/w32/pathstuff",         "src/w32/w32os",         "src/w32/compat/posixfcn",
    "src/w32/subproc/misc", "src/w32/subproc/sub_proc", "src/w32/subproc/w32err", "lib/fnmatch",
    "lib/glob",            "lib/getloadavg",
};

const system_libs = [_][]const u8{
    "kernel32", "user32", "gdi32", "winspool", "comdlg32", "advapi32", "shell32", "ole32", "oleaut32", "uuid",
};

pub fn build(b: *std.Build) void {
    const dir = b.option([]const u8, "make", "the unpacked make-" ++ version ++ " tarball (absolute)") orelse
        @panic("-Dmake=<dir> is required");
    const arch_name = b.option([]const u8, "arch", "x86_64 (default) or aarch64") orelse "x86_64";
    const arch: std.Target.Cpu.Arch = if (std.mem.eql(u8, arch_name, "aarch64")) .aarch64 else .x86_64;

    const gen = b.addWriteFiles();
    _ = gen.addCopyFile(b.graph.cwdRelativePath(b.fmt("{s}/src/config.h.W32", .{dir})), "src/config.h");
    _ = gen.addCopyFile(b.graph.cwdRelativePath(b.fmt("{s}/lib/glob.in.h", .{dir})), "lib/glob.h");
    _ = gen.addCopyFile(b.graph.cwdRelativePath(b.fmt("{s}/lib/fnmatch.in.h", .{dir})), "lib/fnmatch.h");

    const mod = b.createModule(.{
        .target = b.resolveTargetQuery(.{ .cpu_arch = arch, .os_tag = .windows, .abi = .gnu }),
        .optimize = .ReleaseFast,
        .strip = true,
        .link_libc = true,
    });
    mod.addIncludePath(gen.getDirectory().path(b, "src"));
    mod.addIncludePath(b.graph.cwdRelativePath(b.fmt("{s}/src", .{dir})));
    mod.addIncludePath(gen.getDirectory().path(b, "lib"));
    mod.addIncludePath(b.graph.cwdRelativePath(b.fmt("{s}/lib", .{dir})));
    mod.addIncludePath(b.graph.cwdRelativePath(b.fmt("{s}/src/w32/include", .{dir})));
    const flags: []const []const u8 = &.{
        "-std=gnu99",              "-O2", "-Wall", "-DHAVE_CONFIG_H", "-fno-file-reproducible",
        b.fmt("-ffile-prefix-map={s}/=", .{dir}),
    };
    for (sources) |s| mod.addCSourceFile(.{ .file = b.graph.cwdRelativePath(b.fmt("{s}/{s}.c", .{ dir, s })), .flags = flags });
    for (system_libs) |l| mod.linkSystemLibrary(l, .{});

    const exe = b.addExecutable(.{ .name = "make", .root_module = mod });
    const install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = arch_name } } });
    b.getInstallStep().dependOn(&install.step);
}
