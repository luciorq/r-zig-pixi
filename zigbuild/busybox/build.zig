//! busybox-w32 built with zig (.github/devdocs/b14-l4/PLAN.md; b13-design
//! L4, D3): sh, sed, awk, grep and the coreutils R's Windows package
//! builds run, one exe, for the native build-tools set
//! (R_HOME/bin/toolchain/native, zigbuild/toolchain/busybox.zig):
//!
//!   zig build --build-file zigbuild/busybox/build.zig [-Dtarget=<arch>-windows-gnu] [--prefix <dir>]
//!
//! installs <prefix>/bin/busybox.exe. Its source is build.zig.zon's lazy
//! `busybox` (GitHub's archive of the release tag; frippery.org's tarball
//! refuses GitHub's hosted runners, b14-review D-B1); the conda recipe can pass
//! its own unpacked copy as -Dsource=<dir>. Busybox's Kbuild does not run:
//! this file does its work, as zigbuild/make/build.zig does make's
//! configure.
//!   - The configuration is vendored (config/<arch>.config; how it was
//!     made is in its header), as R's and make's are.
//!   - include/autoconf.h is written from it, as kconfig's conf writes it
//!     (autoconfH); include/applets.h and include/usage.h are
//!     scripts/gen_build_files.sh's: every `//applet:` and `//usage:` line
//!     of the sources inserted at the INSERT line of the .src.h
//!     (insertH). BB_VER.h, common_bufsiz.h and embedded_scripts.h are
//!     what Kbuild writes for this configuration.
//!   - The objects are Kbuild's: the top Makefile's core-y and libs-y
//!     directories, each one's Kbuild (or Kbuild.src with its sources'
//!     `//kbuild:` lines at INSERT), whose lib-y and obj-y lists this file
//!     evaluates against the configuration (Kbuild below). lib-y objects go
//!     into a static library, as Kbuild's lib.a archives, obj-y objects
//!     into the exe.
//!   - applet_tables.h, NUM_APPLETS.h and usage_compressed.h come from
//!     busybox's own host programs (applets/applet_tables.c,
//!     applets/usage.c), built for this machine and run; usage_h.zig turns
//!     usage's output into the header, as applets/usage_compressed does
//!     without bzip2 (FEATURE_COMPRESS_USAGE is off).
//!   - win32/resources/resources.rc is compiled by zig's resource compiler.
//!   - r-zig's patches (patches/*.patch, `patches` below) are applied in
//!     Zig (patch.zig) to copies of the sources they change, which compile
//!     in place of the release's; a hunk that does not apply exactly
//!     stops the build. A patch may change .c files only (a header is
//!     found by its includer's "..." include, next to it).
//! The compile flags are Makefile.flags' for clang and mingw (CONFIG_
//! values as in config/<arch>.config), less warnings; the exe links
//! Windows system DLLs and the UCRT only, with --gc-sections as
//! scripts/trylink.
const std = @import("std");
const mem = std.mem;
const patch = @import("patch.zig");

/// busybox-w32's release: the tag build.zig.zon fetches, and
/// `.frp_describe` in frippery.org's tarball of it.
pub const frp = "FRP-6354-g5f09fb446";

/// r-zig's patches, applied in this order (each file's header says what
/// and why; zigbuild/toolchain/busybox.zig ships them with the exe's
/// licence as part of its source).
pub const patches = [_][]const u8{
    "patches/0001-msys-drive-paths.patch",
};

/// The top Makefile's core-y and libs-y: the directories whose Kbuild
/// lists objects.
const kbuild_dirs = [_][]const u8{
    "applets",       "win32/resources",       "archival",               "archival/libarchive",
    "console-tools", "coreutils",             "coreutils/libcoreutils", "debianutils",
    "klibc-utils",   "e2fsprogs",             "editors",                "findutils",
    "init",          "libbb",                 "libbb/yescrypt",         "libpwdgrp",
    "loginutils",    "mailutils",             "miscutils",              "modutils",
    "networking",    "networking/libiproute", "networking/udhcp",       "printutils",
    "procps",        "runit",                 "selinux",                "shell",
    "sysklogd",      "util-linux",            "util-linux/volume_id",   "win32",
};

pub fn build(b: *std.Build) void {
    const arena = b.allocator;
    const io = b.graph.io;
    var query = b.standardTargetOptionsQueryOnly(.{});
    if (query.os_tag == null) query.os_tag = .windows;
    if (query.abi == null) query.abi = .gnu;
    if (query.cpu_model == .determined_by_arch_os) query.cpu_model = .baseline;
    const target = b.resolveTargetQuery(query);
    const t = target.result;
    if (t.os.tag != .windows or (t.cpu.arch != .x86_64 and t.cpu.arch != .aarch64)) {
        std.debug.print("error: busybox-w32 is for x86_64-windows-gnu and aarch64-windows-gnu, not {t}-{t}\n", .{ t.cpu.arch, t.os.tag });
        b.getInstallStep().dependOn(&b.addFail("unsupported target").step);
        return;
    }
    const source = b.option([]const u8, "source", "busybox-w32 " ++ frp ++ "'s source, unpacked (the conda build's; else build.zig.zon's busybox)");

    // This configure step reads the source tree (Kbuild files, //applet:
    // lines), which zig's configure cache does not track.
    b.graph.poisonCache();
    const raw_dir: []const u8 = if (source) |s| s else blk: {
        const dep = b.lazyDependency("busybox", .{}) orelse return;
        break :blk dep.builder.root.root_dir.path orelse ".";
    };
    const src_dir = std.Io.Dir.cwd().realPathFileAlloc(io, raw_dir, arena) catch |err|
        return fail(b, "busybox: cannot resolve its source {s} ({t})", .{ raw_dir, err });
    const src: std.Build.LazyPath = .{ .cwd_relative = src_dir };
    // for #include lines (Windows: C:/...)
    const src_fwd = mem.replaceOwned(u8, arena, src_dir, "\\", "/") catch @panic("OOM");

    const config_path = b.root.joinString(arena, b.fmt("config/{t}.config", .{t.cpu.arch})) catch @panic("OOM");
    const config_text = std.Io.Dir.cwd().readFileAlloc(io, config_path, arena, .limited(1 << 20)) catch |err|
        return fail(b, "busybox: cannot read {s} ({t})", .{ config_path, err });
    const config = Config.parse(arena, config_text) catch @panic("OOM");
    // frippery.org's tarball names its release in .frp_describe; GitHub's
    // archive of the tag (build.zig.zon's) has no such file, and its URL
    // and hash pin the release instead.
    if (std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/.frp_describe", .{src_dir}), arena, .limited(1 << 10))) |text| {
        const describe = mem.trim(u8, text, " \r\n");
        if (!mem.eql(u8, describe, frp))
            return fail(b, "busybox: {s} is {s}, config/ is for {s}", .{ src_dir, describe, frp });
    } else |_| {}
    const makefile = readSrc(b, src_dir, "Makefile") orelse return;
    const ver = Version.of(makefile) orelse return fail(b, "busybox: no VERSION, PATCHLEVEL and SUBLEVEL in {s}/Makefile", .{src_dir});
    // The Makefile's EXTRAVERSION for a busybox-w32 release (Makefile:397,
    // `.$(subst FRP,git,...)`) is replaced as the prototype's make
    // EXTRAVERSION=-<describe> did: BB_VER 1.39.0-FRP-6354-g5f09fb446.
    const bb_ver = b.fmt("{s}.{s}.{s}-{s}", .{ ver.version, ver.patchlevel, ver.sublevel, frp });

    // --- the generated headers, written now (Kbuild's include/) -------------
    const gen = b.addWriteFiles();
    _ = gen.add("include/autoconf.h", autoconfH(arena, config, bb_ver) catch @panic("OOM"));
    const sources = SourceTree.scan(b, src_dir) catch |err| return fail(b, "busybox: cannot read {s} ({t})", .{ src_dir, err });
    _ = gen.add("include/applets.h", insertH(arena, readSrc(b, src_dir, "include/applets.src.h") orelse return, "/* DO NOT EDIT. This file is generated from applets.src.h */", sources.applet_lines) catch |err|
        return fail(b, "busybox: include/applets.src.h ({t})", .{err}));
    _ = gen.add("include/usage.h", insertH(arena, readSrc(b, src_dir, "include/usage.src.h") orelse return, "/* DO NOT EDIT. This file is generated from usage.src.h */", sources.usage_lines) catch |err|
        return fail(b, "busybox: include/usage.src.h ({t})", .{err}));
    _ = gen.add("include/BB_VER.h", b.fmt("#define BB_VER \"{s}\"\n", .{bb_ver}));
    // scripts/generate_BUFSIZ.sh's first pass, which Kbuild keeps on mingw
    _ = gen.add("include/common_bufsiz.h", "enum { COMMON_BUFSIZE = 1024 };\nextern char bb_common_bufsiz1[];\n#define setup_common_bufsiz() ((void)0)\n");
    // scripts/embedded_scripts with FEATURE_SH_EMBEDDED_SCRIPTS off
    _ = gen.add("include/embedded_scripts.h", "#define NUM_SCRIPTS 0\n");
    // applets/applet_tables.c includes "../include/autoconf.h": relative to
    // this directory it finds the generated one.
    _ = gen.add("applets/.include-base", "");
    const gen_include = gen.getDirectory().path(b, "include");

    // --- busybox's host programs, built for this machine and run -------------
    const host_tables = hostProgram(b, "applet_tables", src, gen);
    const tables = b.addRunArtifact(host_tables);
    const applet_tables_h = tables.addOutputFileArg("applet_tables.h");
    _ = tables.addOutputFileArg("NUM_APPLETS.h");
    const host_usage = hostProgram(b, "usage", src, gen);
    const usage_text = b.addRunArtifact(host_usage).captureStdOut(.{});
    const usage_h = b.addRunArtifact(b.addExecutable(.{ .name = "usage_h", .root_module = b.createModule(.{
        .root_source_file = b.path("usage_h.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    }) }));
    usage_h.addFileArg(usage_text);
    const usage_compressed_h = usage_h.addOutputFileArg("usage_compressed.h");

    // --- the objects: each directory's Kbuild, evaluated -------------------
    var lib_files: std.ArrayList([]const u8) = .empty;
    var obj_files: std.ArrayList([]const u8) = .empty;
    var resources = false;
    for (kbuild_dirs) |d| {
        const lists = Kbuild.objects(b, src_dir, d, config, sources) catch |err|
            return fail(b, "busybox: {s}'s Kbuild ({t})", .{ d, err });
        for ([_]struct { []const []const u8, *std.ArrayList([]const u8) }{ .{ lists.lib, &lib_files }, .{ lists.obj, &obj_files } }) |l| {
            for (l[0]) |o| {
                if (mem.eql(u8, d, "win32/resources") and mem.eql(u8, o, "resources.o")) {
                    resources = true;
                    continue;
                }
                if (!mem.endsWith(u8, o, ".o")) return fail(b, "busybox: {s}'s Kbuild lists {s}, not an object", .{ d, o });
                const stem = b.fmt("{s}/{s}", .{ d, o[0 .. o.len - 2] });
                const file = if (pathExists(io, b.fmt("{s}/{s}.c", .{ src_dir, stem }))) b.fmt("{s}.c", .{stem}) else if (pathExists(io, b.fmt("{s}/{s}.S", .{ src_dir, stem }))) b.fmt("{s}.S", .{stem}) else return fail(b, "busybox: {s}'s Kbuild lists {s}, which has no .c or .S", .{ d, o });
                l[1].append(arena, file) catch @panic("OOM");
            }
        }
    }

    var flags: std.ArrayList([]const u8) = .empty;
    flags.appendSlice(arena, &.{
        // Makefile.flags' CPPFLAGS
        "-std=gnu99",
        "-D_GNU_SOURCE",
        "-DNDEBUG",
        b.fmt("-DMINGW_VER=\"zig {s}\"", .{@import("builtin").zig_version_string}),
        // its CFLAGS that change code (STATICS_IN_BSS: no -fdata-sections)
        "-fno-builtin-strlen",
        "-fomit-frame-pointer",
        "-ffunction-sections",
        "-funsigned-char",
        "-falign-functions=1",
        "-fno-builtin-printf",
        "-Oz",
        // CONFIG_PLATFORM_MINGW32's, and clang's setjmp/longjmp choice
        "-DHAVE_STRING_H=1",
        "-DHAVE_CONFIG_H=0",
        "-fno-builtin-stpcpy",
        "-fno-builtin-stpncpy",
        "-fno-ident",
        "-fno-builtin-strndup",
        "-fno-builtin-memmove",
        b.fmt("-ffile-prefix-map={s}/=", .{src_dir}),
    }) catch @panic("OOM");
    if (config.on("LFS")) flags.appendSlice(arena, &.{ "-D_LARGEFILE_SOURCE", "-D_LARGEFILE64_SOURCE", "-D_FILE_OFFSET_BITS=64" }) catch @panic("OOM");
    if (config.on("TIME64")) flags.append(arena, "-D_TIME_BITS=64") catch @panic("OOM");
    flags.appendSlice(arena, if (config.on("UNWIND_TABLES"))
        &.{ "-funwind-tables", "-fasynchronous-unwind-tables", "-fexceptions" }
    else
        &.{ "-fno-unwind-tables", "-fno-asynchronous-unwind-tables", "-fsjlj-exceptions" }) catch @panic("OOM");

    // r-zig's patches: each changed source, patched now, as gen's
    // patched/<path>.
    var patched: std.StringHashMapUnmanaged(void) = .empty;
    for (patches) |pp| {
        const text = std.Io.Dir.cwd().readFileAlloc(io, b.root.joinString(arena, pp) catch @panic("OOM"), arena, .limited(1 << 20)) catch |err|
            return fail(b, "busybox: cannot read {s} ({t})", .{ pp, err });
        const files = patch.parse(arena, text) catch |err| return fail(b, "busybox: {s} ({t})", .{ pp, err });
        for (files) |f| {
            if (!mem.endsWith(u8, f.path, ".c")) return fail(b, "busybox: {s} changes {s}, not a .c file", .{ pp, f.path });
            if (patched.contains(f.path)) return fail(b, "busybox: {s} changes {s} again", .{ pp, f.path });
            if (!contains(lib_files.items, f.path) and !contains(obj_files.items, f.path)) return fail(b, "busybox: {s} changes {s}, which this configuration does not compile", .{ pp, f.path });
            const out = patch.apply(arena, readSrc(b, src_dir, f.path) orelse return, f) catch |err|
                return fail(b, "busybox: {s} does not apply to {s} ({t})", .{ pp, f.path, err });
            _ = gen.add(b.fmt("patched/{s}", .{f.path}), out);
            patched.put(arena, f.path, {}) catch @panic("OOM");
        }
    }

    // Makefile.flags' `-include include/autoconf.h`, as a wrapper per
    // source: zig's cache does not follow -include's file (a bare name
    // in its manifest), so each object is compiled from gen's src/<path>,
    // which includes autoconf.h and then the source by its absolute path
    // (its own "..." includes still start from its directory), or a
    // patched one, gen's patched/<path>, by a path relative to the
    // wrapper; that one finds its directory's headers by -iquote.
    for ([_][]const []const u8{ lib_files.items, obj_files.items }) |files| for (files) |f| {
        const included = if (patched.contains(f))
            b.fmt("{s}patched/{s}", .{ upDirs(arena, f), f })
        else
            b.fmt("{s}/{s}", .{ src_fwd, f });
        _ = gen.add(b.fmt("src/{s}", .{f}), b.fmt("#include \"autoconf.h\"\n#include \"{s}\"\n", .{included}));
    };
    const wrapped = gen.getDirectory().path(b, "src");

    const lib_mod = targetModule(b, target, src, gen_include, &.{ applet_tables_h, usage_compressed_h });
    addSources(b, lib_mod, wrapped, lib_files.items, flags.items, &patched, src_dir);
    const lib = b.addLibrary(.{ .name = "busybox_lib", .root_module = lib_mod });

    const exe_mod = targetModule(b, target, src, gen_include, &.{ applet_tables_h, usage_compressed_h });
    addSources(b, exe_mod, wrapped, obj_files.items, flags.items, &patched, src_dir);
    exe_mod.linkLibrary(lib);
    if (resources) exe_mod.addWin32ResourceFile(.{
        .file = src.path(b, "win32/resources/resources.rc"),
        // win32/resources/Kbuild.src's WRFLAGS
        .flags = &.{
            b.fmt("/dBB_VER={s}", .{bb_ver}),
            b.fmt("/dBB_VERSION={s}", .{ver.version}),
            b.fmt("/dBB_PATCHLEVEL={s}", .{ver.patchlevel}),
            b.fmt("/dBB_SUBLEVEL={s}", .{ver.sublevel}),
            b.fmt("/dBB_EXTRAVERSION={s}", .{frpCount()}),
        },
        .include_paths = &.{ gen_include, src.path(b, "win32/resources") },
    });
    // Makefile.flags' LDLIBS on mingw
    for ([_][]const u8{ "ws2_32", "bcrypt", "secur32" }) |l| exe_mod.linkSystemLibrary(l, .{});
    const exe = b.addExecutable(.{ .name = "busybox", .root_module = exe_mod });
    exe.link_gc_sections = true;
    b.installArtifact(exe);
}

/// The wrapped sources: the unpatched ones together, each patched one with
/// -iquote its own source directory.
fn addSources(b: *std.Build, mod: *std.Build.Module, wrapped: std.Build.LazyPath, files: []const []const u8, flags: []const []const u8, patched: *const std.StringHashMapUnmanaged(void), src_dir: []const u8) void {
    var plain: std.ArrayList([]const u8) = .empty;
    for (files) |f| {
        if (!patched.contains(f)) {
            plain.append(b.allocator, f) catch @panic("OOM");
            continue;
        }
        const dir = f[0 .. mem.lastIndexOfScalar(u8, f, '/') orelse 0];
        const own = mem.concat(b.allocator, []const u8, &.{ flags, &.{ "-iquote", b.fmt("{s}/{s}", .{ src_dir, dir }) } }) catch @panic("OOM");
        mod.addCSourceFiles(.{ .root = wrapped, .files = b.allocator.dupe([]const u8, &.{f}) catch @panic("OOM"), .flags = own });
    }
    mod.addCSourceFiles(.{ .root = wrapped, .files = plain.items, .flags = flags });
}

fn contains(list: []const []const u8, x: []const u8) bool {
    for (list) |y| if (mem.eql(u8, x, y)) return true;
    return false;
}

/// "../" once per directory of gen's src/<path>, back to gen's root.
fn upDirs(arena: mem.Allocator, path: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(arena, "../") catch @panic("OOM"); // src/
    for (path) |c| if (c == '/') out.appendSlice(arena, "../") catch @panic("OOM");
    return out.items;
}

/// A module for the target: busybox's include path, the generated
/// headers first (Kbuild's -Iinclude -Ilibbb ... -Iwin32).
fn targetModule(b: *std.Build, target: std.Build.ResolvedTarget, src: std.Build.LazyPath, gen_include: std.Build.LazyPath, generated: []const std.Build.LazyPath) *std.Build.Module {
    const mod = b.createModule(.{
        .target = target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .strip = true,
        .sanitize_c = .off,
    });
    mod.addIncludePath(gen_include);
    for (generated) |g| mod.addIncludePath(g.dirname());
    mod.addIncludePath(src.path(b, "include"));
    mod.addIncludePath(src.path(b, "libbb"));
    mod.addIncludePath(src.path(b, "win32"));
    return mod;
}

/// applets/<name>.c built for this machine (Kbuild's hostprogs-y, -O2)
/// against the generated include/.
fn hostProgram(b: *std.Build, name: []const u8, src: std.Build.LazyPath, gen: *std.Build.Step.WriteFile) *std.Build.Step.Compile {
    const mod = b.createModule(.{ .target = b.graph.host, .optimize = .ReleaseFast, .link_libc = true, .sanitize_c = .off });
    mod.addCSourceFile(.{ .file = src.path(b, b.fmt("applets/{s}.c", .{name})), .flags = &.{ "-O2", "-fomit-frame-pointer" } });
    mod.addIncludePath(gen.getDirectory().path(b, "applets"));
    mod.addIncludePath(gen.getDirectory().path(b, "include"));
    mod.addIncludePath(src.path(b, "include"));
    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// win32/resources/Kbuild.src's BB_EXTRAVERSION: the second dash-separated
/// word of EXTRAVERSION, the release's commit count.
fn frpCount() []const u8 {
    var it = mem.tokenizeScalar(u8, frp, '-');
    _ = it.next();
    return it.next() orelse "0";
}

const Version = struct {
    version: []const u8,
    patchlevel: []const u8,
    sublevel: []const u8,

    fn of(makefile: []const u8) ?Version {
        var v: Version = .{ .version = "", .patchlevel = "", .sublevel = "" };
        var lines = mem.splitScalar(u8, makefile, '\n');
        while (lines.next()) |raw| {
            const line = mem.trimEnd(u8, raw, "\r");
            inline for (.{ "VERSION", "PATCHLEVEL", "SUBLEVEL" }, .{ "version", "patchlevel", "sublevel" }) |key, field| {
                if (mem.startsWith(u8, line, key ++ " = ")) @field(v, field) = line[key.len + 3 ..];
            }
        }
        if (v.version.len == 0 or v.patchlevel.len == 0 or v.sublevel.len == 0) return null;
        return v;
    }
};

/// config/<arch>.config: every symbol in its order, set (`CONFIG_X=v`) or
/// not (`# CONFIG_X is not set`).
const Config = struct {
    symbols: []const Symbol,

    const Symbol = struct { name: []const u8, value: ?[]const u8 };

    fn parse(arena: mem.Allocator, text: []const u8) !Config {
        var list: std.ArrayList(Symbol) = .empty;
        var lines = mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            const line = mem.trimEnd(u8, raw, "\r");
            if (mem.startsWith(u8, line, "CONFIG_")) {
                const eq = mem.indexOfScalar(u8, line, '=') orelse continue;
                try list.append(arena, .{ .name = line["CONFIG_".len..eq], .value = line[eq + 1 ..] });
            } else if (mem.startsWith(u8, line, "# CONFIG_") and mem.endsWith(u8, line, " is not set")) {
                try list.append(arena, .{ .name = line["# CONFIG_".len .. line.len - " is not set".len], .value = null });
            }
        }
        return .{ .symbols = list.items };
    }

    fn get(c: Config, name: []const u8) ?[]const u8 {
        for (c.symbols) |s| if (mem.eql(u8, s.name, name)) return s.value;
        return null;
    }

    fn on(c: Config, name: []const u8) bool {
        const v = c.get(name) orelse return false;
        return mem.eql(u8, v, "y");
    }
};

/// include/autoconf.h as kconfig's conf writes it (scripts/kconfig/
/// confdata.c): per symbol CONFIG_X, ENABLE_X, IF_X and IF_NOT_X.
fn autoconfH(arena: mem.Allocator, config: Config, bb_ver: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena,
        \\/*
        \\ * Automatically generated C config: don't edit
        \\ * Busybox version: {s}
        \\ */
        \\#define AUTOCONF_TIMESTAMP "r-zig"
        \\
        \\
    , .{bb_ver});
    for (config.symbols) |s| {
        if (s.value) |v| {
            try out.print(arena, "#define CONFIG_{s} {s}\n#define ENABLE_{s} 1\n", .{ s.name, if (mem.eql(u8, v, "y")) "1" else v, s.name });
            try out.print(arena, "#ifdef MAKE_SUID\n# define IF_{s}(...) __VA_ARGS__ \"CONFIG_{s}\"\n#else\n# define IF_{s}(...) __VA_ARGS__\n#endif\n#define IF_NOT_{s}(...)\n", .{ s.name, s.name, s.name, s.name });
        } else {
            try out.print(arena, "#undef CONFIG_{s}\n#define ENABLE_{s} 0\n#define IF_{s}(...)\n#define IF_NOT_{s}(...) __VA_ARGS__\n", .{ s.name, s.name, s.name, s.name });
        }
    }
    return out.items;
}

/// scripts/gen_build_files.sh's generate(): the header line, the .src
/// file up to its INSERT line, the inserted lines, the rest after INSERT
/// (a file without one: all of it, then the inserted lines).
fn insertH(arena: mem.Allocator, src: []const u8, header: []const u8, inserted: []const u8) ![]const u8 {
    const at = mem.indexOf(u8, src, "\nINSERT\n") orelse return mem.concat(arena, u8, &.{ header, "\n", src, inserted });
    return mem.concat(arena, u8, &.{ header, "\n", src[0 .. at + 1], inserted, src[at + "\nINSERT\n".len ..] });
}

/// What gen_build_files.sh reads from the sources: the `//applet:` and
/// `//usage:` lines of `*/*.c` then `*/*/*.c` (each glob in C order), and
/// per directory its `*.c` files' `//kbuild:` lines.
const SourceTree = struct {
    applet_lines: []const u8,
    usage_lines: []const u8,
    /// directory -> its `//kbuild:` lines
    kbuild: std.StringHashMapUnmanaged([]const u8),

    fn scan(b: *std.Build, src_dir: []const u8) !SourceTree {
        const arena = b.allocator;
        const io = b.graph.io;
        var level1: std.ArrayList([]const u8) = .empty;
        var level2: std.ArrayList([]const u8) = .empty;
        var top = try std.Io.Dir.cwd().openDir(io, src_dir, .{ .iterate = true });
        defer top.close(io);
        var tops: std.ArrayList([]const u8) = .empty;
        var it = top.iterate();
        while (try it.next(io)) |e| {
            if (e.kind == .directory and e.name[0] != '.') try tops.append(arena, try arena.dupe(u8, e.name));
        }
        for (tops.items) |d| {
            var sub = try top.openDir(io, d, .{ .iterate = true });
            defer sub.close(io);
            var sit = sub.iterate();
            while (try sit.next(io)) |e| {
                if (e.kind == .file and mem.endsWith(u8, e.name, ".c")) try level1.append(arena, b.fmt("{s}/{s}", .{ d, e.name }));
                if (e.kind == .directory and e.name[0] != '.') {
                    var sub2 = try sub.openDir(io, e.name, .{ .iterate = true });
                    defer sub2.close(io);
                    var it2 = sub2.iterate();
                    while (try it2.next(io)) |f| {
                        if (f.kind == .file and mem.endsWith(u8, f.name, ".c")) try level2.append(arena, b.fmt("{s}/{s}/{s}", .{ d, e.name, f.name }));
                    }
                }
            }
        }
        const lessThan = struct {
            fn f(_: void, a: []const u8, c: []const u8) bool {
                return mem.lessThan(u8, a, c);
            }
        }.f;
        mem.sort([]const u8, level1.items, {}, lessThan);
        mem.sort([]const u8, level2.items, {}, lessThan);
        var applets: std.ArrayList(u8) = .empty;
        var usage: std.ArrayList(u8) = .empty;
        var kbuild: std.StringHashMapUnmanaged([]const u8) = .empty;
        for ([_][]const []const u8{ level1.items, level2.items }) |files| for (files) |f| {
            const text = try std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/{s}", .{ src_dir, f }), arena, .limited(16 << 20));
            const dir = f[0..mem.lastIndexOfScalar(u8, f, '/').?];
            const gop = try kbuild.getOrPut(arena, dir);
            if (!gop.found_existing) gop.value_ptr.* = "";
            var kb: std.ArrayList(u8) = .empty;
            try kb.appendSlice(arena, gop.value_ptr.*);
            var lines = mem.splitScalar(u8, text, '\n');
            while (lines.next()) |raw| {
                const line = mem.trimEnd(u8, raw, "\r");
                if (mem.startsWith(u8, line, "//applet:")) {
                    try applets.print(arena, "{s}\n", .{line["//applet:".len..]});
                } else if (mem.startsWith(u8, line, "//usage:")) {
                    // a line that does not start with a blank starts a new
                    // entry: an empty line before it; each ends in " \"
                    const rest = line["//usage:".len..];
                    if (rest.len == 0) continue; // sed's patterns need a character
                    if (rest[0] == ' ' or rest[0] == '\t')
                        try usage.print(arena, "{s} \\\n", .{rest})
                    else
                        try usage.print(arena, "\n{s} \\\n", .{rest});
                } else if (mem.startsWith(u8, line, "//kbuild:")) {
                    try kb.print(arena, "{s}\n", .{line["//kbuild:".len..]});
                }
            }
            gop.value_ptr.* = kb.items;
        };
        return .{ .applet_lines = applets.items, .usage_lines = usage.items, .kbuild = kbuild };
    }
};

/// A directory's Kbuild, evaluated as make would for the variables that
/// matter: assignments (`:=`, `=`, `+=`) with `$(VAR)` and `$(CONFIG_X)`
/// expanded, `ifeq`/`ifneq`/`else`/`endif`, continuation lines; recipe
/// lines (tab), rules and functions are left out. The result is lib-y and
/// obj-y, each object once, in order.
const Kbuild = struct {
    lib: []const []const u8,
    obj: []const []const u8,

    fn objects(b: *std.Build, src_dir: []const u8, dir: []const u8, config: Config, sources: SourceTree) !Kbuild {
        const arena = b.allocator;
        const io = b.graph.io;
        const text = blk: {
            if (std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/{s}/Kbuild.src", .{ src_dir, dir }), arena, .limited(1 << 20))) |t| {
                break :blk try insertH(arena, t, "# DO NOT EDIT. This file is generated from Kbuild.src", sources.kbuild.get(dir) orelse "");
            } else |_| break :blk try std.Io.Dir.cwd().readFileAlloc(io, b.fmt("{s}/{s}/Kbuild", .{ src_dir, dir }), arena, .limited(1 << 20));
        };
        var vars: std.StringHashMapUnmanaged([]const u8) = .empty;
        // conditional stack: each level active or not
        var active: std.ArrayList(bool) = .empty;
        var logical: std.ArrayList(u8) = .empty;
        var lines = mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            const piece = mem.trimEnd(u8, raw, "\r");
            if (mem.endsWith(u8, piece, "\\")) {
                try logical.appendSlice(arena, piece[0 .. piece.len - 1]);
                try logical.append(arena, ' ');
                continue;
            }
            try logical.appendSlice(arena, piece);
            const line_full = try arena.dupe(u8, logical.items);
            logical.clearRetainingCapacity();
            if (line_full.len > 0 and line_full[0] == '\t') continue; // a recipe
            // make's comments run from `#` to the end of the line
            const line = mem.trim(u8, line_full[0 .. mem.indexOfScalar(u8, line_full, '#') orelse line_full.len], " \t");
            if (line.len == 0) continue;
            const all_active = mem.indexOfScalar(bool, active.items, false) == null;
            if (mem.startsWith(u8, line, "ifeq ") or mem.startsWith(u8, line, "ifneq ")) {
                const neg = line[2] == 'n';
                const args = mem.trim(u8, line[if (neg) 6 else 5..], " ");
                if (args.len < 2 or args[0] != '(' or args[args.len - 1] != ')') return error.UnknownConditional;
                const inner = args[1 .. args.len - 1];
                const comma = topLevelComma(inner) orelse return error.UnknownConditional;
                const l = mem.trim(u8, try expand(arena, inner[0..comma], &vars, config), " ");
                const r = mem.trim(u8, try expand(arena, inner[comma + 1 ..], &vars, config), " ");
                try active.append(arena, mem.eql(u8, l, r) != neg);
                continue;
            }
            if (mem.eql(u8, line, "else")) {
                if (active.items.len == 0) return error.ElseWithoutIf;
                active.items[active.items.len - 1] = !active.items[active.items.len - 1];
                continue;
            }
            if (mem.eql(u8, line, "endif")) {
                if (active.pop() == null) return error.EndifWithoutIf;
                continue;
            }
            if (!all_active) continue;
            // an assignment: the first `=` with `:` or `+` or `?` before it
            const eq = mem.indexOfScalar(u8, line, '=') orelse continue; // a rule
            var name_end = eq;
            var op: u8 = '=';
            if (eq > 0 and (line[eq - 1] == ':' or line[eq - 1] == '+' or line[eq - 1] == '?')) {
                op = line[eq - 1];
                name_end = eq - 1;
            }
            const name_raw = mem.trim(u8, line[0..name_end], " \t");
            if (mem.indexOfAny(u8, name_raw, " :") != null) continue; // a target-specific variable or rule
            const name = try expand(arena, name_raw, &vars, config);
            const value = try expand(arena, mem.trim(u8, line[eq + 1 ..], " \t"), &vars, config);
            switch (op) {
                '+' => {
                    const old = vars.get(name) orelse "";
                    try vars.put(arena, name, if (old.len == 0) value else b.fmt("{s} {s}", .{ old, value }));
                },
                '?' => if (vars.get(name) == null) try vars.put(arena, name, value),
                else => try vars.put(arena, name, value),
            }
        }
        if (active.items.len != 0) return error.UnterminatedIf;
        return .{ .lib = try words(arena, vars.get("lib-y") orelse ""), .obj = try words(arena, vars.get("obj-y") orelse "") };
    }

    fn words(arena: mem.Allocator, s: []const u8) ![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        var it = mem.tokenizeAny(u8, s, " \t");
        while (it.next()) |w| {
            for (list.items) |x| {
                if (mem.eql(u8, x, w)) break;
            } else try list.append(arena, w);
        }
        return list.items;
    }

    fn topLevelComma(s: []const u8) ?usize {
        var depth: usize = 0;
        for (s, 0..) |c, i| switch (c) {
            '(' => depth += 1,
            ')' => depth -|= 1,
            ',' => if (depth == 0) return i,
            else => {},
        };
        return null;
    }

    /// `$(NAME)`: CONFIG_ symbols from the configuration (unset: empty),
    /// other names from the variables so far; a function call (a space or
    /// comma inside) is empty.
    fn expand(arena: mem.Allocator, s: []const u8, vars: *const std.StringHashMapUnmanaged([]const u8), config: Config) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '$' and i + 1 < s.len and s[i + 1] == '(') {
                var depth: usize = 1;
                var j = i + 2;
                while (j < s.len and depth > 0) : (j += 1) {
                    if (s[j] == '(') depth += 1;
                    if (s[j] == ')') depth -= 1;
                }
                if (depth != 0) return error.UnbalancedParenthesis;
                const inner = s[i + 2 .. j - 1];
                if (mem.indexOfAny(u8, inner, " ,$") == null) {
                    if (mem.startsWith(u8, inner, "CONFIG_")) {
                        if (config.get(inner["CONFIG_".len..])) |v| try out.appendSlice(arena, v);
                    } else if (vars.get(inner)) |v| try out.appendSlice(arena, v);
                }
                i = j;
            } else {
                try out.append(arena, s[i]);
                i += 1;
            }
        }
        return out.items;
    }
};

fn readSrc(b: *std.Build, src_dir: []const u8, sub: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(b.graph.io, b.fmt("{s}/{s}", .{ src_dir, sub }), b.allocator, .limited(16 << 20)) catch |err| {
        fail(b, "busybox: cannot read {s}/{s} ({t})", .{ src_dir, sub, err });
        return null;
    };
}

fn pathExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn fail(b: *std.Build, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    b.getInstallStep().dependOn(&b.addFail("busybox's configuration").step);
}
