//! Info-ZIP zip 3.0 built with zig (.github/devdocs/b14-l4/PLAN.md, user
//! decision U4): the `zip` R CMD INSTALL --build and utils::zip() run on
//! Windows (R_ZIPCMD, default "zip"), one exe, for the native build-tools
//! set and the build-tools group (R_HOME/bin/toolchain/{native,usr}/bin,
//! zigbuild/toolchain/zip.zig):
//!
//!   zig build --build-file zigbuild/zip/build.zig [-Dtarget=<arch>-windows-gnu] [--prefix <dir>]
//!
//! installs <prefix>/bin/zip.exe. Its source is build.zig.zon's lazy `zip`
//! (Info-ZIP's release tarball); the conda recipe can pass its own unpacked
//! copy as -Dsource=<dir>. No makefile runs: the sources and flags are
//! win32/makefile.gcc's for zip.exe (OBJZ and ziprc.o), with -DNO_ASM in
//! place of its x86 assembly (match.S, crc_i386.S: the C versions, which
//! aarch64 needs anyway). zipnote, zipsplit and zipcloak are not built.
//! The exe links kernel32, user32 and advapi32 (LIBS) and the UCRT.
const std = @import("std");

pub const version = "3.0";

/// win32/makefile.gcc's OBJZ (OBJZ1, OBJZ2 less OBJA, OBJZS).
const srcs = [_][]const u8{
    "zip.c",            "crypt.c",          "ttyio.c",    "zipfile.c",
    "zipup.c",          "fileio.c",         "util.c",     "crc32.c",
    "globals.c",        "deflate.c",        "trees.c",    "win32/win32.c",
    "win32/win32zip.c", "win32/win32i64.c", "win32/nt.c",
};

pub fn build(b: *std.Build) void {
    var query = b.standardTargetOptionsQueryOnly(.{});
    if (query.os_tag == null) query.os_tag = .windows;
    if (query.abi == null) query.abi = .gnu;
    if (query.cpu_model == .determined_by_arch_os) query.cpu_model = .baseline;
    const target = b.resolveTargetQuery(query);
    const t = target.result;
    if (t.os.tag != .windows or (t.cpu.arch != .x86_64 and t.cpu.arch != .aarch64)) {
        std.debug.print("error: zip is built for x86_64-windows-gnu and aarch64-windows-gnu, not {t}-{t}\n", .{ t.cpu.arch, t.os.tag });
        b.getInstallStep().dependOn(&b.addFail("unsupported target").step);
        return;
    }
    const source = b.option([]const u8, "source", "zip " ++ version ++ "'s source, unpacked (the conda build's; else build.zig.zon's zip)");

    const raw_dir: []const u8 = if (source) |s| s else blk: {
        const dep = b.lazyDependency("zip", .{}) orelse return;
        break :blk dep.builder.root.root_dir.path orelse ".";
    };
    // absolute: every compile maps it away (-ffile-prefix-map)
    const src_dir = std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, raw_dir, b.allocator) catch |err| {
        std.debug.print("error: zip: cannot resolve its source {s} ({t})\n", .{ raw_dir, err });
        b.getInstallStep().dependOn(&b.addFail("zip's source").step);
        return;
    };
    const src: std.Build.LazyPath = .{ .cwd_relative = src_dir };

    // zip.h's `#define CR 13` breaks mingw-w64's winnt.h (a struct member
    // named CR, IMAGE_ARM64_RUNTIME_FUNCTION_ENTRY_XDATA) in the sources
    // that include <windows.h> after it: each object is compiled from a
    // wrapper that includes <windows.h> first and then the source by its
    // absolute path (its own "..." includes still start from its
    // directory), as zigbuild/busybox's autoconf.h wrappers.
    const src_fwd = std.mem.replaceOwned(u8, b.allocator, src_dir, "\\", "/") catch @panic("OOM");
    const gen = b.addWriteFiles();
    for (srcs) |f| _ = gen.add(f, b.fmt("#include <windows.h>\n#include \"{s}/{s}\"\n", .{ src_fwd, f }));

    const mod = b.createModule(.{
        .target = target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .strip = true,
        // 1990s C: the makefile builds it without sanitizers
        .sanitize_c = .off,
    });
    mod.addIncludePath(src);
    mod.addIncludePath(src.path(b, "win32"));
    mod.addCSourceFiles(.{
        .root = gen.getDirectory(),
        .files = &srcs,
        .flags = &.{
            // makefile.gcc's CFLAGS and LOC
            "-O2",
            "-DWIN32",
            "-DFORCE_WIN32_OVER_UNIX",
            "-DNO_ASM",
            // K&R definitions and implicit declarations: C89 as zip was written
            "-std=gnu89",
            "-Wno-deprecated-non-prototype",
            "-Wno-implicit-function-declaration",
            "-Wno-int-conversion",
            "-Wno-incompatible-pointer-types",
            // reproducible: no build date in `zip -v` (win32.c's COMPILE_DATE
            // is empty without __DATE__)
            "-U__DATE__",
            "-Wno-builtin-macro-redefined",
            b.fmt("-ffile-prefix-map={s}/=", .{src_dir}),
        },
    });
    // ziprc.o: the version resource
    mod.addWin32ResourceFile(.{ .file = src.path(b, "win32/zip.rc"), .include_paths = &.{src.path(b, "win32")} });
    for ([_][]const u8{ "user32", "advapi32" }) |l| mod.linkSystemLibrary(l, .{});
    const exe = b.addExecutable(.{ .name = "zip", .root_module = mod });
    b.installArtifact(exe);
}
