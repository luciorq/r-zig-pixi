//! GNU make 4.4.1 built with zig (backlog L7; feat-standalone-toolchain B7 b),
//! for the build-tools group's usr/bin/make:
//!
//!   zig build --build-file zigbuild/make/build.zig [-Dtarget=<triple>] [--prefix <dir>]
//!
//! installs <prefix>/bin/make (make.exe on Windows). Its source is
//! build.zig.zon's lazy `make` (ftp.gnu.org's release tarball); the conda
//! recipe can pass its own unpacked copy as -Dsource=<dir>. No configure
//! runs: the configuration is the one its configure gave, vendored
//! (config/<os>.h; Windows' is the release's own src/config.h.W32), as R's
//! is (zigbuild/config/). The sources are configure's and build_w32.bat's:
//! make_SRCS, then posixos.c with gnulib's concat-filename and
//! findprog-in on unix (plus fnmatch and glob on macOS, whose libc's are
//! not GNU's), the w32 sources with fnmatch, glob and getloadavg on
//! Windows; remote-stub.c everywhere (no Customs), no Guile, no NLS.
//!
//! The target's default is R's floors: linux glibc 2.17, macOS 13.0, and
//! the GNU ABI on Windows, at the baseline CPU. It links libc only: glibc
//! on linux (as R's binaries), libSystem on macOS, and kernel32, user32
//! and advapi32 on Windows.
const std = @import("std");

const make_version = "4.4.1";

/// configure's make_SRCS (Makefile.am), less headers.
const common_srcs = [_][]const u8{
    "src/ar.c",          "src/arscan.c",   "src/commands.c", "src/default.c",
    "src/dir.c",         "src/expand.c",   "src/file.c",     "src/function.c",
    "src/getopt.c",      "src/getopt1.c",  "src/guile.c",    "src/hash.c",
    "src/implicit.c",    "src/job.c",      "src/load.c",     "src/loadapi.c",
    "src/main.c",        "src/misc.c",     "src/output.c",   "src/read.c",
    "src/remake.c",      "src/rule.c",     "src/shuffle.c",  "src/signame.c",
    "src/strcache.c",    "src/variable.c", "src/version.c",  "src/vpath.c",
    "src/remote-stub.c",
};
/// unix: posixos.c and gnulib's libgnu.a as configure chose it on linux
/// (glibc has GNU glob and fnmatch, and getloadavg).
const unix_srcs = [_][]const u8{ "src/posixos.c", "lib/concat-filename.c", "lib/findprog-in.c" };
/// macOS: configure's make_cv_sys_gnu_glob=no adds gnulib's glob.
const macos_srcs = [_][]const u8{ "lib/fnmatch.c", "lib/glob.c" };
/// build_w32.bat's list (gcc: no compat/dirent.c, MinGW has dirent).
const windows_srcs = [_][]const u8{
    "src/w32/pathstuff.c",    "src/w32/w32os.c",            "src/w32/compat/posixfcn.c",
    "src/w32/subproc/misc.c", "src/w32/subproc/sub_proc.c", "src/w32/subproc/w32err.c",
    "lib/fnmatch.c",          "lib/glob.c",                 "lib/getloadavg.c",
};

pub fn build(b: *std.Build) void {
    var query = b.standardTargetOptionsQueryOnly(.{});
    // R's floors when -Dtarget leaves the OS's version or ABI to the host.
    const os_tag = query.os_tag orelse b.graph.host.result.os.tag;
    switch (os_tag) {
        .linux => {
            if (query.abi == null) query.abi = .gnu;
            if (query.glibc_version == null) query.glibc_version = .{ .major = 2, .minor = 17, .patch = 0 };
        },
        .macos => {
            if (query.os_version_min == null) query.os_version_min = .{ .semver = .{ .major = 13, .minor = 0, .patch = 0 } };
        },
        .windows => {
            if (query.abi == null) query.abi = .gnu;
        },
        else => {},
    }
    if (query.cpu_model == .determined_by_arch_os) query.cpu_model = .baseline;
    const target = b.resolveTargetQuery(query);
    const t = target.result;
    const optimize = b.option(std.lang.Optimize, "optimize", "Default: fast") orelse .fast;
    const source = b.option([]const u8, "source", "make-" ++ make_version ++ "'s source, unpacked (the conda build's; else build.zig.zon's make)");

    // The source directory, absolute: every compile maps it away
    // (-ffile-prefix-map, below), so __FILE__ (job.c's assert) is the path
    // in the tarball, not the build machine's.
    const raw_dir: []const u8 = if (source) |s| s else blk: {
        const dep = b.lazyDependency("make", .{}) orelse return;
        break :blk dep.builder.root.root_dir.path orelse ".";
    };
    const src_dir = std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, raw_dir, b.allocator) catch |err| {
        std.debug.print("error: make: cannot resolve its source {s} ({t})\n", .{ raw_dir, err });
        b.getInstallStep().dependOn(&b.addFail("make's source").step);
        return;
    };
    const src: std.Build.LazyPath = .{ .cwd_relative = src_dir };

    // The generated headers: config.h, and gnulib's as its build makes
    // them (glob.h and fnmatch.h are copies; alloca.h substitutes
    // @HAVE_ALLOCA_H@).
    const gen = b.addWriteFiles();
    switch (t.os.tag) {
        .linux => _ = gen.addCopyFile(b.path("config/linux.h"), "config.h"),
        .macos => _ = gen.addCopyFile(b.path("config/macos.h"), "config.h"),
        .windows => _ = gen.addCopyFile(src.path(b, "src/config.h.W32"), "config.h"),
        else => {
            std.debug.print("error: make for {t}: no configuration (linux, macos, windows)\n", .{t.os.tag});
            b.getInstallStep().dependOn(&b.addFail("unsupported OS").step);
            return;
        },
    }
    _ = gen.addCopyFile(src.path(b, "lib/glob.in.h"), "glob.h");
    _ = gen.addCopyFile(src.path(b, "lib/fnmatch.in.h"), "fnmatch.h");
    const alloca_h = b.addConfigHeader(.{ .style = .{ .autoconf_at = src.path(b, "lib/alloca.in.h") }, .include_path = "alloca.h" }, .{ .HAVE_ALLOCA_H = 1 });

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = true,
        // make's C has its own idea of overflow and alignment (hash.c,
        // strcache.c); configure builds it without sanitizers.
        .sanitize_c = .off,
    });
    mod.addIncludePath(gen.getDirectory());
    mod.addConfigHeader(alloca_h);
    mod.addIncludePath(src.path(b, "src"));
    mod.addIncludePath(src.path(b, "lib"));
    if (t.os.tag == .windows) mod.addIncludePath(src.path(b, "src/w32/include"));

    var flags: std.ArrayList([]const u8) = .empty;
    flags.appendSlice(b.allocator, &.{ "-DHAVE_CONFIG_H", "-std=gnu99", b.fmt("-ffile-prefix-map={s}/=", .{src_dir}) }) catch @panic("OOM");
    if (t.os.tag != .windows) {
        // configure's defaults for a /usr/local prefix: the directories a
        // makefile's `include` and `load` search last; nothing from the build.
        flags.appendSlice(b.allocator, &.{
            "-DLIBDIR=\"/usr/local/lib\"",
            "-DINCLUDEDIR=\"/usr/local/include\"",
            "-DLOCALEDIR=\"/usr/local/share/locale\"",
            b.fmt("-DMAKE_HOST=\"{s}\"", .{makeHost(t)}),
        }) catch @panic("OOM");
    }
    mod.addCSourceFiles(.{ .root = src, .files = &common_srcs, .flags = flags.items });
    switch (t.os.tag) {
        .linux => mod.addCSourceFiles(.{ .root = src, .files = &unix_srcs, .flags = flags.items }),
        .macos => {
            mod.addCSourceFiles(.{ .root = src, .files = &unix_srcs, .flags = flags.items });
            mod.addCSourceFiles(.{ .root = src, .files = &macos_srcs, .flags = flags.items });
        },
        .windows => {
            mod.addCSourceFiles(.{ .root = src, .files = &windows_srcs, .flags = flags.items });
            for ([_][]const u8{ "kernel32", "user32", "advapi32" }) |l| mod.linkSystemLibrary(l, .{});
        },
        else => unreachable,
    }

    const exe = b.addExecutable(.{ .name = "make", .root_module = mod });
    // A `load`ed object calls make's gmk_* API (gnumake.h): its symbols
    // stay in the dynamic table, as configure's -Wl,--export-dynamic.
    if (t.os.tag == .linux) exe.rdynamic = true;
    b.installArtifact(exe);

    // `zig build test`: the built make runs a makefile (host targets only).
    const t_step = b.step("test", "Run the built make on a small makefile (native target only)");
    if (b.graph.host.result.os.tag == t.os.tag and b.graph.host.result.cpu.arch == t.cpu.arch) {
        const wf = b.addWriteFiles();
        const mk = wf.add("Makefile",
            \\x := $(patsubst %.c,%.o,a.c b.c)
            \\all: ; @echo "make $(MAKE_VERSION) $(x) $(words $(MAKEFLAGS))"
            \\
        );
        const run = b.addRunArtifact(exe);
        run.addArg("-f");
        run.addFileArg(mk);
        run.expectStdOutEqual("make " ++ make_version ++ " a.o b.o 0\n");
        t_step.dependOn(&run.step);
    }
}

/// configure's MAKE_HOST (config.guess' triple) for the target.
fn makeHost(t: std.Target) []const u8 {
    return switch (t.os.tag) {
        .macos => switch (t.cpu.arch) {
            .aarch64 => "aarch64-apple-darwin",
            else => "x86_64-apple-darwin",
        },
        else => switch (t.cpu.arch) {
            .aarch64 => "aarch64-unknown-linux-gnu",
            else => "x86_64-pc-linux-gnu",
        },
    };
}
