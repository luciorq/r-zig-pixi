//! `rzig build`: one source package's native library with zig build alone
//! (design record .github/devdocs/feat-zig-pkg-build/PLAN.md). Classifies
//! the package (pkgplan.zig), writes its plan, and runs zig build on the
//! root R ships in R_HOME/share/zig/rpkg (zigbuild/rpkg/): tier 1 reads the
//! plan, tier 2 adds the package's own src/build.zig as a path dependency.
//! install.R calls it before its make path (M3); exit 3 means "this
//! package needs make", and R goes on as it did.
//!
//!   rzig build --pkg <dir> --out <dir> [--src <dir>] [--flat] [--name <pkg>]
//!              [--linkingto <dir>]... [--cxx-std NN] [--c-std NN] [--use-lto yes|no]
//!              [--debug] [-j N] [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>]
//!              [--keep-root]
//!
//! The library goes to <out>/libs<R_ARCH>/<pkg>.so (a package's installed
//! layout), or with --flat to <out>/<pkg>.so, where make leaves it in
//! src/ and install.R's shlib_install takes it (patch 0013 runs
//! `rzig build --pkg .. --src . --out . --flat` from src/).
//!   rzig build --pkg <dir> --plan-only     the plan.zon to stdout
//!   rzig build --pkg <dir> --classify      the tier to stdout
//!
//! Exit 0 built (or nothing to build), 3 needs make (why, on stderr),
//! 2 usage, 1 failed, 127 no zig (the compilers group's text). A tier-2
//! package whose plan needs make is 1, not 3: make would ignore its
//! build.zig (`buildZigNeedsMake`). R_HOME from the environment, as
//! under R. `--classify` prints the decided tier (r_only, makevars, zig,
//! make: make also when the Makevars sends the package there), and for
//! that tier-2 package the same line and exit 1 as a build;
//! `--plan-only` the plan. The install preflight (check.zig's
//! --rzig-check=package) decides through `decide` below. Whatever the
//! exit, the build root <out>/.rzig is gone afterwards unless kept
//! (--keep-root, RZIG_KEEP_ROOT=1); zig build's cache, for tier 1 its
//! build runner alone, is shared in rzig's cache (`zigBuildDirs`).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const pkgplan = @import("pkgplan.zig");
const find_zig = @import("find_zig.zig");
const groups = @import("groups.zig");
const cache = @import("cache.zig");

pub const exit_needs_make: u8 = 3;

const usage =
    \\usage: rzig build --pkg <dir> --out <dir> [--src <dir>] [--flat] [--name <pkg>]
    \\                  [--linkingto <dir>]... [--cxx-std NN] [--c-std NN] [--use-lto yes|no]
    \\                  [--debug] [-j N] [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>]
    \\                  [--keep-root]
    \\       rzig build --pkg <dir> --plan-only | --classify
    \\
;

const Args = struct {
    pkg: ?[]const u8 = null,
    src: ?[]const u8 = null,
    out: ?[]const u8 = null,
    flat: bool = false,
    name: ?[]const u8 = null,
    linkingto: std.ArrayList([]const u8) = .empty,
    cxx_std: ?[]const u8 = null,
    c_std: ?[]const u8 = null,
    use_lto: ?bool = null,
    debug: bool = false,
    jobs: ?[]const u8 = null,
    r_home: ?[]const u8 = null,
    rpkg_dir: ?[]const u8 = null,
    cache_dir: ?[]const u8 = null,
    keep_root: bool = false,
    plan_only: bool = false,
    classify: bool = false,
};

fn parseArgs(ctx: *Ctx, argv: []const []const u8) !?Args {
    var a: Args = .{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const x = argv[i];
        const takes_value = mem.eql(u8, x, "--pkg") or mem.eql(u8, x, "--src") or mem.eql(u8, x, "--out") or mem.eql(u8, x, "--name") or mem.eql(u8, x, "--linkingto") or
            mem.eql(u8, x, "--cxx-std") or mem.eql(u8, x, "--c-std") or mem.eql(u8, x, "--use-lto") or mem.eql(u8, x, "-j") or
            mem.eql(u8, x, "--r-home") or mem.eql(u8, x, "--rpkg-dir") or mem.eql(u8, x, "--cache-dir");
        if (takes_value) {
            if (i + 1 >= argv.len) {
                ctx.warn("build: {s} needs a value", .{x});
                return null;
            }
            const v = argv[i + 1];
            i += 1;
            if (mem.eql(u8, x, "--pkg")) a.pkg = v else if (mem.eql(u8, x, "--src")) a.src = v else if (mem.eql(u8, x, "--out")) a.out = v else if (mem.eql(u8, x, "--name")) a.name = v else if (mem.eql(u8, x, "--linkingto")) try a.linkingto.append(ctx.arena, v) else if (mem.eql(u8, x, "--cxx-std")) a.cxx_std = v else if (mem.eql(u8, x, "--c-std")) a.c_std = v else if (mem.eql(u8, x, "--use-lto")) {
                a.use_lto = if (mem.eql(u8, v, "yes") or mem.eql(u8, v, "true") or mem.eql(u8, v, "TRUE")) true else if (mem.eql(u8, v, "no") or mem.eql(u8, v, "false") or mem.eql(u8, v, "FALSE")) false else {
                    ctx.warn("build: --use-lto takes yes or no, not '{s}'", .{v});
                    return null;
                };
            } else if (mem.eql(u8, x, "-j")) a.jobs = v else if (mem.eql(u8, x, "--r-home")) a.r_home = v else if (mem.eql(u8, x, "--rpkg-dir")) a.rpkg_dir = v else if (mem.eql(u8, x, "--cache-dir")) a.cache_dir = v;
        } else if (mem.startsWith(u8, x, "-j") and x.len > 2) {
            a.jobs = x[2..];
        } else if (mem.eql(u8, x, "--flat")) {
            a.flat = true;
        } else if (mem.eql(u8, x, "--debug")) {
            a.debug = true;
        } else if (mem.eql(u8, x, "--keep-root")) {
            a.keep_root = true;
        } else if (mem.eql(u8, x, "--plan-only")) {
            a.plan_only = true;
        } else if (mem.eql(u8, x, "--classify")) {
            a.classify = true;
        } else if (mem.eql(u8, x, "-h") or mem.eql(u8, x, "--help")) {
            std.debug.print("{s}", .{usage});
            return null;
        } else {
            ctx.warn("build: unknown argument '{s}'", .{x});
            return null;
        }
    }
    return a;
}

/// `path` absolute with `/` separators, as rzig keeps every path. When it
/// does not resolve, a line names it and why, after the caller's name
/// (`rzig build: `, or the check mode's `zig-cc: `) [phase3-P3-2].
pub fn canonical(ctx: *Ctx, path: []const u8) ![]const u8 {
    const real = Io.Dir.cwd().realPathFileAlloc(ctx.io, path, ctx.arena) catch |err| {
        ctx.warn("{s}: {t}", .{ path, err });
        return error.BadPath;
    };
    return slashes(ctx, real);
}

fn slashes(ctx: *Ctx, p: []const u8) ![]const u8 {
    if (builtin.os.tag != .windows) return p;
    return mem.replaceOwned(u8, ctx.arena, p, "\\", "/");
}

/// DESCRIPTION's `Package:` field.
pub fn packageName(ctx: *Ctx, pkg_dir: []const u8) ?[]const u8 {
    const text = Io.Dir.cwd().readFileAlloc(ctx.io, ctx.fmt("{s}/DESCRIPTION", .{pkg_dir}) catch return null, ctx.arena, .limited(1 << 20)) catch return null;
    var it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (mem.startsWith(u8, line, "Package:")) return mem.trim(u8, line["Package:".len..], " \t\r");
    }
    return null;
}

// R_MAKEVARS_SITE and R_MAKEVARS_USER are read with ctx.env.get, where
// ctx.getenv takes empty for unset: R reads them with
// Sys.getenv(name, NA), so a set but empty value is a file that does not
// exist, no Makevars, never the default file [preflight-PF-2].

/// install.R's makevars_site(): R_MAKEVARS_SITE when set, else
/// etc<R_ARCH>/Makevars.site.
fn makevarsSite(ctx: *Ctx, r_home: []const u8, r_arch: []const u8) !?[]const u8 {
    const f = ctx.env.get("R_MAKEVARS_SITE") orelse try ctx.fmt("{s}/etc{s}/Makevars.site", .{ r_home, r_arch });
    return if (ctx.isFile(f)) f else null;
}

/// install.R's makevars_user(): R_MAKEVARS_USER when set; else, on
/// Windows with R_ARCH /x64, ~/.R/Makevars.ucrt then ~/.R/Makevars.win64,
/// then ~/.R/Makevars.win; on unix ~/.R/Makevars-<R_PLATFORM>; then
/// ~/.R/Makevars.
fn makevarsUser(ctx: *Ctx, r_arch: []const u8) !?[]const u8 {
    if (ctx.env.get("R_MAKEVARS_USER")) |f| return if (ctx.isFile(f)) f else null;
    const home = (try userHome(ctx)) orelse return null;
    var names: std.ArrayList([]const u8) = .empty;
    if (ctx.os == .windows) {
        if (mem.eql(u8, r_arch, "/x64")) try names.appendSlice(ctx.arena, &.{ "Makevars.ucrt", "Makevars.win64" });
        try names.append(ctx.arena, "Makevars.win");
    } else if (ctx.getenv("R_PLATFORM")) |plat| {
        try names.append(ctx.arena, try ctx.fmt("Makevars-{s}", .{plat}));
    }
    try names.append(ctx.arena, "Makevars");
    for (names.items) |n| {
        const f = try ctx.fmt("{s}/.R/{s}", .{ home, n });
        if (ctx.isFile(f)) return f;
    }
    return null;
}

/// `~` as R's path.expand expands it [preflight-PF-2]: on Windows R_USER
/// (R sets it at startup, so rzig under R always has it), else HOME,
/// else HOMEDRIVE and HOMEPATH (R_ExpandFileName, src/gnuwin32/
/// sys-win32.c). unix: HOME only; R's passwd fallback (getpwuid when
/// HOME is unset or empty, src/unix/sys-unix.c) is not mirrored, and
/// under install.R the hook passes R's own choice, makevars_user(), as
/// R_MAKEVARS_USER (patch 0013) [code-5]. Empty counts as unset.
fn userHome(ctx: *Ctx) !?[]const u8 {
    if (ctx.os != .windows) return ctx.getenv("HOME");
    if (ctx.getenv("R_USER") orelse ctx.getenv("HOME")) |h| return h;
    const drive = ctx.getenv("HOMEDRIVE") orelse return null;
    const path = ctx.getenv("HOMEPATH") orelse return null;
    return try ctx.fmt("{s}{s}", .{ drive, path });
}

/// What `rzig build` decides for one package: its tier, why it needs make
/// (tier 3), and for tiers 1 and 2 the plan. The install preflight's
/// `--rzig-check=package` (check.zig, patch 0009) decides through this
/// same function, with the inputs install.R's hook (patch 0013) passes,
/// so the preflight's tier and the hook's tier come from one code path:
/// classify (the files), then plan (the Makevars and Makeconf, where the
/// rules, conditionals, $(shell) and foreign compilers are found).
pub const Decision = struct {
    tier: pkgplan.Tier,
    /// For `.make`: what sends the package there, as classify or plan
    /// word it ("a configure script", "src/Makefile", "src/Makevars has a
    /// rule or target line: '...'", "MAKEFLAGS sets NAME", ...).
    reason: []const u8 = "",
    class: pkgplan.Classification,
    /// Tiers 1 and 2.
    plan: ?pkgplan.Plan = null,
};

pub const Inputs = struct {
    /// Absolute, `/` separators (canonical).
    r_home: []const u8,
    pkg_dir: []const u8,
    src_dir: []const u8,
    name: []const u8,
    linkingto: ?[]const []const u8 = null,
    cxx_std: ?[]const u8 = null,
    c_std: ?[]const u8 = null,
    use_lto: ?bool = null,
    debug: bool = false,
    /// rzig's own path, for `rzig def` in the plan.
    rzig: []const u8,
};

pub fn decide(ctx: *Ctx, in: Inputs) error{OutOfMemory}!Decision {
    const r_arch = ctx.getenv("R_ARCH") orelse if (ctx.os == .windows) "/x64" else "";
    var planner: pkgplan.Planner = .{ .ctx = ctx };
    const class = planner.classify(in.pkg_dir, in.src_dir) catch |err| switch (err) {
        error.NeedsMake => return .{ .tier = .make, .reason = planner.reason, .class = .{ .tier = .make, .reason = planner.reason } },
        error.OutOfMemory => return error.OutOfMemory,
    };
    switch (class.tier) {
        .r_only => return .{ .tier = .r_only, .class = class },
        .make => return .{ .tier = .make, .reason = class.reason, .class = class },
        .makevars, .zig => {},
    }
    const plan = planner.plan(.{
        .r_home = in.r_home,
        .pkg_dir = in.pkg_dir,
        .src_dir = in.src_dir,
        .name = in.name,
        .linkingto = in.linkingto,
        .cxx_std = in.cxx_std,
        .c_std = in.c_std,
        .use_lto = in.use_lto,
        .debug = in.debug,
        .makevars_site = try makevarsSite(ctx, in.r_home, r_arch),
        .makevars_user = try makevarsUser(ctx, r_arch),
        .rzig = in.rzig,
    }, class) catch |err| switch (err) {
        error.NeedsMake => return .{ .tier = .make, .reason = planner.reason, .class = class },
        error.OutOfMemory => return error.OutOfMemory,
    };
    return .{ .tier = class.tier, .class = class, .plan = plan };
}

/// A tier-2 package (src/build.zig) whose plan needs make (a foreign
/// compiler from a site or user Makevars, an unreadable Makeconf, ...):
/// make would compile src/'s sources and ignore build.zig, a missing or
/// partial library, so there is nothing to fall back to
/// [preflight-PF-1]. `rzig build` and the preflight (check.zig) both
/// say so with this line and exit 1, not 3; the build tools would not
/// help, so no group's text follows. True when it said so.
pub fn buildZigNeedsMake(ctx: *Ctx, name: []const u8, d: Decision) bool {
    if (d.tier != .make or d.class.tier != .zig) return false;
    ctx.warn("{s}: src/build.zig cannot be built by make: {s}", .{ name, d.reason });
    return true;
}

pub fn run(ctx: *Ctx, argv: []const []const u8) !u8 {
    ctx.name = "rzig build";
    const args = (try parseArgs(ctx, argv)) orelse return 2;
    const pkg_in = args.pkg orelse {
        ctx.warn("--pkg <dir> is required\n{s}", .{usage});
        return 2;
    };
    const r_home_in = args.r_home orelse ctx.getenv("R_HOME") orelse {
        ctx.warn("R_HOME is not set and no --r-home given", .{});
        return 2;
    };
    const r_home = canonical(ctx, r_home_in) catch return 2;
    const pkg_dir = canonical(ctx, pkg_in) catch return 2;
    const src_dir = if (args.src) |d| canonical(ctx, d) catch return 2 else try ctx.fmt("{s}/src", .{pkg_dir});
    const name = args.name orelse packageName(ctx, pkg_dir) orelse {
        ctx.warn("no --name and no Package: field in {s}/DESCRIPTION", .{pkg_dir});
        return 2;
    };
    const d = try decide(ctx, .{
        .r_home = r_home,
        .pkg_dir = pkg_dir,
        .src_dir = src_dir,
        .name = name,
        .linkingto = if (args.linkingto.items.len > 0) args.linkingto.items else null,
        .cxx_std = args.cxx_std,
        .c_std = args.c_std,
        .use_lto = args.use_lto,
        .debug = args.debug,
        .rzig = ctx.self_exe orelse "rzig",
    });
    // the decided tier: make also when the Makevars sends the package
    // there, as the preflight decides; a tier-2 package that make cannot
    // build is no tier to print, but the line and exit 1 that the hook and
    // the preflight give [preflight-PF-1, coverage-1]
    if (args.classify) {
        if (buildZigNeedsMake(ctx, name, d)) return 1;
        try stdoutPrint(ctx, "{t}\n", .{d.tier});
        return 0;
    }
    const class = d.class;
    switch (d.tier) {
        .r_only => {
            if (isSet(ctx, "RZIG_TRACE")) ctx.warn("{s}: no src/, nothing to compile", .{name});
            return 0;
        },
        .make => return if (buildZigNeedsMake(ctx, name, d)) 1 else needsMake(ctx, name, d.reason),
        .makevars, .zig => {},
    }
    var plan = d.plan.?;

    if (args.flat) plan.libs_dir = "";
    if (args.plan_only) {
        var buf: [4096]u8 = undefined;
        var w = Io.File.stdout().writerStreaming(ctx.io, &buf);
        try pkgplan.writeZon(&plan, &w.interface);
        try w.interface.flush();
        return 0;
    }
    const out_in = args.out orelse {
        ctx.warn("--out <dir> is required\n{s}", .{usage});
        return 2;
    };
    Io.Dir.cwd().createDirPath(ctx.io, out_in) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ out_in, err });
        return 1;
    };
    const out = canonical(ctx, out_in) catch return 1;

    // the build root: the plan, and for tier 2 the root files with the
    // package as a path dependency
    const rpkg_dir = args.rpkg_dir orelse try ctx.fmt("{s}/share/zig/rpkg", .{r_home});
    const root = try ctx.fmt("{s}/.rzig", .{out});
    Io.Dir.cwd().createDirPath(ctx.io, root) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ root, err });
        return 1;
    };
    // from here every return removes the root, a refusal, no zig or a
    // failed write as much as a build: under install.R it is the
    // package's src/.rzig, which R CMD build would ship [preflight-PF-3]
    const keep = args.keep_root or isSet(ctx, "RZIG_KEEP_ROOT");
    defer if (!keep) {
        Io.Dir.cwd().deleteTree(ctx.io, root) catch |err| ctx.warn("cannot remove {s}: {t}", .{ root, err });
    };
    const plan_path = try ctx.fmt("{s}/plan.zon", .{root});
    {
        var w: Io.Writer.Allocating = .init(ctx.arena);
        try pkgplan.writeZon(&plan, &w.writer);
        Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = plan_path, .data = w.written() }) catch |err| {
            ctx.warn("cannot write {s}: {t}", .{ plan_path, err });
            return 1;
        };
    }
    var build_file: []const u8 = undefined;
    switch (class.tier) {
        .makevars => build_file = try ctx.fmt("{s}/build_t1.zig", .{rpkg_dir}),
        .zig => {
            const files = [_][2][]const u8{ .{ "build_t2.zig", "build.zig" }, .{ "build_t1.zig", "build_t1.zig" }, .{ "rpkg.zig", "rpkg.zig" } };
            for (files) |f| {
                Io.Dir.cwd().copyFile(try ctx.fmt("{s}/{s}", .{ rpkg_dir, f[0] }), Io.Dir.cwd(), try ctx.fmt("{s}/{s}", .{ root, f[1] }), ctx.io, .{}) catch |err| {
                    ctx.warn("cannot copy {s}/{s} into {s}: {t} (is R_HOME/share/zig/rpkg installed?)", .{ rpkg_dir, f[0], root, err });
                    return 1;
                };
            }
            // tier 2 builds offline: a dependency the package's own manifest
            // fetches by URL is refused (exit 1, not 3: make would compile
            // src/ and ignore build.zig), and zig build runs with --system,
            // which disables fetching for the whole graph
            const zon_path = try ctx.fmt("{s}/build.zig.zon", .{src_dir});
            if (Io.Dir.cwd().readFileAlloc(ctx.io, zon_path, ctx.arena, .limited(1 << 20)) catch null) |zon_text| {
                if (urlDependency(zon_text)) |dep| {
                    ctx.warn("src/build.zig.zon: dependency {s} is a URL; tier 2 builds offline, vendor it as a .path dependency", .{dep});
                    return 1;
                }
            }
            const rel = try slashes(ctx, try std.fs.path.relative(ctx.arena, root, ctx.env, root, src_dir));
            if (rel.len == 0 or std.fs.path.isAbsolute(rel)) {
                ctx.warn("cannot name {s} relative to {s}", .{ src_dir, root });
                return 1;
            }
            const zon = try ctx.fmt(
                \\.{{
                \\    .name = .rpkg_root,
                \\    .version = "0.0.0",
                \\    .fingerprint = 0x85bf37cdc6a317b2,
                \\    .dependencies = .{{
                \\        .pkg = .{{ .path = "{s}" }},
                \\    }},
                \\    .paths = .{{""}},
                \\}}
                \\
            , .{rel});
            Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = try ctx.fmt("{s}/build.zig.zon", .{root}), .data = zon }) catch |err| {
                ctx.warn("cannot write build.zig.zon: {t}", .{err});
                return 1;
            };
            build_file = try ctx.fmt("{s}/build.zig", .{root});
        },
        else => unreachable,
    }
    if (!ctx.isFile(build_file)) {
        ctx.warn("{s} is missing: R_HOME/share/zig/rpkg is not installed", .{build_file});
        return 1;
    }

    const no_packages = try ctx.fmt("{s}/no-packages", .{root});
    if (class.tier == .zig) Io.Dir.cwd().createDirPath(ctx.io, no_packages) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ no_packages, err });
        return 1;
    };
    // no zig: 127 and the compilers group's text, as a compile says (main.zig)
    const zig = (try find_zig.find(ctx)) orelse {
        try groups.report(ctx, groups.no_zig, .compilers);
        return 127;
    };
    // zig build's build file and cache (zigBuildDirs): for tier 1 the
    // build runner's directory in rzig's cache, shared by every install;
    // the objects and the library are written in the build root and go
    // with it. zig's global cache is the other shared part: std and
    // compiler_rt, keyed by target, and zig cc's objects, keyed by the
    // source as named (relative to src/, as make names it: build_t1.zig)
    // and its contents, so a reinstall of the same sources adds none, as
    // on make's path [tests-T1].
    const dirs = try zigBuildDirs(ctx, args.cache_dir, class.tier, root, zig.argv, build_file);
    try reportCompilers(ctx, &plan, class.tier, zig.argv);
    // zig build makes an (empty) .zig-cache in a path dependency's directory,
    // the package's src/ here; leave src/ as it was found
    const dep_cache = try ctx.fmt("{s}/.zig-cache", .{src_dir});
    const dep_cache_existed = class.tier == .zig and ctx.exists(dep_cache);
    var cmd: std.ArrayList([]const u8) = .empty;
    try cmd.appendSlice(ctx.arena, zig.argv);
    try cmd.appendSlice(ctx.arena, &.{ "build", "--build-file", dirs.build_file, "--cache-dir", dirs.cache_dir, "--prefix", out, try ctx.fmt("-Dplan={s}", .{plan_path}) });
    if (class.tier == .zig) try cmd.appendSlice(ctx.arena, &.{ "--system", no_packages });
    if (args.jobs) |j| try cmd.append(ctx.arena, try ctx.fmt("-j{s}", .{j}));
    if (isSet(ctx, "RZIG_TRACE")) {
        ctx.warn("tier {s}, root {s}", .{ switch (class.tier) {
            .makevars => "1",
            .zig => "2",
            else => "?",
        }, root });
        ctx.warn("{s}", .{try mem.join(ctx.arena, " ", cmd.items)});
    }
    var child = std.process.spawn(ctx.io, .{ .argv = cmd.items }) catch |err| {
        ctx.warn("cannot run {s}: {t}", .{ cmd.items[0], err });
        return 1;
    };
    const term = child.wait(ctx.io) catch |err| {
        ctx.warn("waiting for zig build: {t}", .{err});
        return 1;
    };
    const code: u8 = switch (term) {
        .exited => |c| c,
        else => 1,
    };
    if (class.tier == .zig and !dep_cache_existed) Io.Dir.cwd().deleteTree(ctx.io, dep_cache) catch {};
    if (code != 0) {
        if (keep) ctx.warn("zig build failed ({d}); the build root is kept in {s}", .{ code, root }) else ctx.warn("zig build failed ({d})", .{code});
    }
    return if (code != 0) 1 else 0;
}

/// zig build's --build-file and --cache-dir.
const ZigBuildDirs = struct { build_file: []const u8, cache_dir: []const u8 };

/// The build file as found (R_HOME's build_t1.zig, or for tier 2 the
/// build root's build.zig) with --cache-dir, else ZIG_LOCAL_CACHE_DIR
/// (stress.R points it at its run directory); else by tier.
///
/// Tier 1: the build runner's directory in rzig's cache (`sharedRunner`),
/// shared by every install. Compiling build_t1.zig's runner in every
/// install (a cache per install, feat-zig-pkg-build N3) added 3.3 s
/// (ubuntu-latest) to 12.8 s (windows-latest) per tier-1 install in stress
/// dispatch 38467907779, where make installs a small package in 1 to 2 s
/// (feat-standalone-toolchain TODO.md, "Depend less on make": the shared
/// tier-1 build runner) [stress-S1, records-REC-4]. build_t1.zig's steps
/// write into the build root, so the directory holds the runner and
/// nothing of an install. When it cannot be used, the build root's, as
/// for tier 2.
///
/// Tier 2: <build root>/zig-cache, gone with the root. The root imports the
/// package's build.zig from its path in this install, so its runner is
/// new in every install, and a shared cache would only grow (N3).
fn zigBuildDirs(ctx: *Ctx, given: ?[]const u8, tier: pkgplan.Tier, root: []const u8, zig: []const []const u8, build_file: []const u8) !ZigBuildDirs {
    if (given orelse ctx.getenv("ZIG_LOCAL_CACHE_DIR")) |d| return .{ .build_file = build_file, .cache_dir = d };
    if (tier == .makevars) {
        if (try sharedRunner(ctx, zig, build_file)) |dirs| return dirs;
    }
    return .{ .build_file = build_file, .cache_dir = try ctx.fmt("{s}/zig-cache", .{root}) };
}

/// A build-runner directory no install has used for this long goes at the
/// next tier-1 build (`sweepRunners`). A runner is about 45 MB on linux-64
/// and compiles again in 3 to 13 s (dispatch 38467907779): a week keeps
/// the runners in use and drops what an upgrade, a removed environment or
/// another zig left behind [code-runner-growth].
const runner_idle_days = 7;

/// <rzig's cache>/build-runner-<key>, the key made of build_t1.zig's
/// content, the zig command and what `zig version` says (as cache.zig's
/// `compiled` keys its entries), with a copy of build_t1.zig in it that
/// zig builds from. zig names the runner's manifest by its build file's
/// path, relative to the cache when the file is in it, and checks the
/// files' content against it. Built from R_HOME's own build_t1.zig, each
/// R installation (a conda env, a worktree's compile tree, a wheel) added
/// a runner of about 45 MB, and an upgrade in place a second one beside
/// the first, which stayed. Built from the copy, every R whose
/// build_t1.zig has that content shares the directory's one runner, and
/// an upgrade (R's build_t1.zig, or zig) makes another directory, which
/// the sweep removes whole once idle [code-runner-growth]. The zig
/// command keeps conda-forge's and upstream's zig, both 0.16.0 with
/// different std files, apart: the manifest's name is the same for both,
/// so in one directory they would replace each other's runner whenever
/// they alternate.
///
/// Each use writes the directory's `last-used` anew, which the sweep
/// reads. That is also the check that rzig can create files there, which
/// zig needs even on a hit (it opens the manifest for writing): an
/// existing directory on a read-only file system, or in another user's
/// cache, failed the build where the build root's cache works
/// [code-unwritable-cache]. null when the directory cannot be used.
fn sharedRunner(ctx: *Ctx, zig: []const []const u8, build_file: []const u8) !?ZigBuildDirs {
    const source = Io.Dir.cwd().readFileAlloc(ctx.io, build_file, ctx.arena, .limited(1 << 20)) catch return null;
    const command = try mem.join(ctx.arena, " ", zig);
    const version = ctx.capture(try mem.concat(ctx.arena, []const u8, &.{ zig, &.{"version"} }));
    const cache_root = try cache.root(ctx);
    const dir = try ctx.fmt("{s}/build-runner-{s}", .{ cache_root, &cache.key(&.{ source, command, version.stdout }) });
    const copy = try ctx.fmt("{s}/build_t1.zig", .{dir});
    useRunnerDir(ctx, dir, copy, source, try ctx.fmt("{s}\n{s}\n", .{ command, version.stdout })) catch return null;
    sweepRunners(ctx, cache_root) catch {};
    return .{ .build_file = copy, .cache_dir = dir };
}

/// `dir` made, its `last-used` written (the zig it is for, for whoever
/// looks), and the copy of build_t1.zig in place, written once.
fn useRunnerDir(ctx: *Ctx, dir: []const u8, copy: []const u8, source: []const u8, stamp: []const u8) !void {
    try Io.Dir.cwd().createDirPath(ctx.io, dir);
    try writeWhole(ctx, try ctx.fmt("{s}/last-used", .{dir}), stamp);
    if (!ctx.isFile(copy)) try writeWhole(ctx, copy, source);
}

/// `data` written under a temporary name in `path`'s directory, then
/// renamed into place, as cache.zig makes its entries: parallel installs
/// see the file whole or not at all. Making the temporary file is the
/// check that rzig can create files there. A rename that fails while the
/// file is there is no failure: another install renamed its own at the
/// same moment (Windows refuses one of two such renames).
fn writeWhole(ctx: *Ctx, path: []const u8, data: []const u8) !void {
    var af = try Io.Dir.cwd().createFileAtomic(ctx.io, path, .{ .replace = true });
    defer af.deinit(ctx.io);
    try af.file.writeStreamingAll(ctx.io, data);
    af.replace(ctx.io) catch |err| if (!ctx.isFile(path)) return err;
}

/// Removes from rzig's cache each build-runner directory whose
/// `last-used` is `runner_idle_days` old (this build's was just written),
/// and what an earlier sweep left half removed. A directory is renamed
/// out of its name first, so an install finds it whole or not at all;
/// one with no `last-used` (being made, or not rzig's to write) stays. An
/// install that takes up a week-idle directory in the instant between
/// the stat and the rename fails once; it takes another R or zig
/// sweeping at that moment. The caller ignores errors: the sweep never
/// fails a build.
fn sweepRunners(ctx: *Ctx, cache_root: []const u8) !void {
    var dir = try Io.Dir.cwd().openDir(ctx.io, cache_root, .{ .iterate = true });
    defer dir.close(ctx.io);
    const now = Io.Timestamp.now(ctx.io, .real);
    // listed first, removed after: renaming entries while listing them
    // could skip some
    var gone: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |e| {
        if (!mem.startsWith(u8, e.name, "build-runner-")) continue;
        if (!mem.endsWith(u8, e.name, ".old")) {
            const st = dir.statFile(ctx.io, try ctx.fmt("{s}/last-used", .{e.name}), .{}) catch continue;
            if (st.mtime.durationTo(now).toSeconds() < runner_idle_days * std.time.s_per_day) continue;
        }
        try gone.append(ctx.arena, try ctx.arena.dupe(u8, e.name));
    }
    for (gone.items) |name| {
        var old = name;
        if (!mem.endsWith(u8, name, ".old")) {
            old = try cache.tempName(ctx, name, ".old");
            dir.rename(name, dir, old, ctx.io) catch continue;
        }
        dir.deleteTree(ctx.io, old) catch {};
    }
}

/// install.R's "using C compiler: '...'" lines (R CMD check greps them from
/// the install log), from the toolchain compilers' --version; and the zig
/// of a tier-2 build.
fn reportCompilers(ctx: *Ctx, plan: *const pkgplan.Plan, tier: pkgplan.Tier, zig: []const []const u8) !void {
    var langs = std.EnumSet(pkgplan.Lang).initEmpty();
    for (plan.sources) |s| if (std.meta.stringToEnum(pkgplan.Lang, s.lang)) |l| langs.insert(l);
    const report = [_]struct { lang: pkgplan.Lang, what: []const u8, tool: []const u8 }{
        .{ .lang = .c, .what = "C", .tool = plan.cc_tool },
        .{ .lang = .cxx, .what = "C++", .tool = plan.cxx_tool },
        .{ .lang = .f, .what = "Fortran", .tool = plan.fc_tool },
    };
    for (report) |r| {
        if (!(langs.contains(r.lang) or (r.lang == .f and langs.contains(.f9x)))) continue;
        const out = ctx.capture(&.{ try ctx.fmt("{s}/{s}", .{ plan.toolchain, r.tool }), "--version" });
        if (!out.ok) continue;
        const first = out.stdout[0 .. mem.findScalar(u8, out.stdout, '\n') orelse out.stdout.len];
        try stdoutPrint(ctx, "using {s} compiler: '{s}'\n", .{ r.what, mem.trimEnd(u8, first, "\r") });
    }
    if (tier == .zig) {
        const v = ctx.capture(try mem.concat(ctx.arena, []const u8, &.{ zig, &.{"version"} }));
        if (v.ok) try stdoutPrint(ctx, "using zig: '{s}'\n", .{v.stdout});
    }
}

/// The name of the first dependency in a build.zig.zon `text` that has a
/// `.url` field, or null. A scan of the manifest, not a parse: the
/// `.dependencies = .{ ... }` block, its entries one brace level down
/// (`.name = .{ ... }`), and a `.url` field in an entry; strings and
/// comments are skipped.
pub fn urlDependency(text: []const u8) ?[]const u8 {
    var i: usize = 0;
    var depth: usize = 0;
    var deps_depth: ?usize = null; // the brace depth inside .dependencies
    var entry: ?[]const u8 = null; // the entry (depth deps_depth + 1) being scanned
    var pending: ?[]const u8 = null; // a field name seen, before its `=` and `.{`
    while (i < text.len) {
        const c = text[i];
        if (c == '/' and i + 1 < text.len and text[i + 1] == '/') {
            i = mem.indexOfScalarPos(u8, text, i, '\n') orelse text.len;
            continue;
        }
        if (c == '"') {
            i += 1;
            while (i < text.len and text[i] != '"') : (i += 1) if (text[i] == '\\') {
                i += 1;
            };
            i += 1;
            continue;
        }
        if (c == '{') {
            depth += 1;
            if (pending) |name| {
                if (deps_depth == null and mem.eql(u8, name, "dependencies")) deps_depth = depth;
                if (deps_depth != null and depth == deps_depth.? + 1) entry = name;
                pending = null;
            }
            i += 1;
            continue;
        }
        if (c == '}') {
            if (deps_depth) |dd| {
                if (depth == dd + 1) entry = null;
                if (depth == dd) deps_depth = null;
            }
            if (depth > 0) depth -= 1;
            i += 1;
            continue;
        }
        if (c == '.' and i + 1 < text.len) {
            // .name, .@"name"
            const start = i + 1;
            var end = start;
            if (text[start] == '@' and start + 1 < text.len and text[start + 1] == '"') {
                end = (mem.indexOfScalarPos(u8, text, start + 2, '"') orelse text.len) + 1;
            } else {
                while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) : (end += 1) {}
            }
            if (end > start) {
                var name = text[start..end];
                if (name.len > 3 and name[0] == '@') name = name[2 .. name.len - 1];
                if (deps_depth != null and entry != null and depth == deps_depth.? + 1 and mem.eql(u8, name, "url")) return entry;
                // a field name is followed by `=`; an enum literal or a
                // nested `.{` is not
                var j = end;
                while (j < text.len and (text[j] == ' ' or text[j] == '\t' or text[j] == '\n' or text[j] == '\r')) : (j += 1) {}
                pending = if (j < text.len and text[j] == '=') name else null;
            }
            i = if (end > start) end else i + 1;
            continue;
        }
        i += 1;
    }
    return null;
}

test urlDependency {
    const t = std.testing;
    try t.expect(urlDependency("") == null);
    try t.expect(urlDependency(".{ .name = .x, .version = \"0.0.0\", .paths = .{\"\"} }") == null);
    try t.expect(urlDependency(
        \\.{ .name = .x, .version = "0.0.0",
        \\  .dependencies = .{ .a = .{ .path = "../a" }, .@"b-c" = .{ .path = "vendor/b" } },
        \\  .paths = .{""} }
    ) == null);
    try t.expectEqualStrings("b", urlDependency(
        \\.{ .name = .x,
        \\  .dependencies = .{
        \\    .a = .{ .path = "../a" },
        \\    // .url = "in a comment" does not count
        \\    .b = .{ .url = "https://example.invalid/b.tar.gz", .hash = "..." },
        \\  }, .paths = .{""} }
    ).?);
    try t.expectEqualStrings("quoted-name", urlDependency(".{ .dependencies = .{ .@\"quoted-name\" = .{ .url = \"x\" } } }").?);
    // a string holding ".url" or braces, and a .url outside .dependencies
    try t.expect(urlDependency(".{ .dependencies = .{ .a = .{ .path = \"{.url}\" } }, .url = \"x\" }") == null);
    try t.expect(urlDependency(".{ .url = \"x\", .dependencies = .{ .a = .{ .path = \"p\", .lazy = true } } }") == null);
}

fn needsMake(ctx: *Ctx, name: []const u8, reason: []const u8) u8 {
    ctx.warn("{s} needs make: {s}", .{ name, reason });
    return exit_needs_make;
}

fn isSet(ctx: *const Ctx, name: []const u8) bool {
    const v = ctx.getenv(name) orelse return false;
    return !mem.eql(u8, v, "0");
}

fn stdoutPrint(ctx: *Ctx, comptime f: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(ctx.io, &buf);
    try w.interface.print(f, args);
    try w.interface.flush();
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

test "arguments" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const a = (try parseArgs(&f.ctx, &.{ "--pkg", "/p", "--out", "/o", "--linkingto", "/l1", "--linkingto", "/l2", "-j", "4", "--use-lto", "no", "--cxx-std", "17", "--plan-only" })).?;
    try std.testing.expectEqualStrings("/p", a.pkg.?);
    try std.testing.expectEqualStrings("/o", a.out.?);
    try std.testing.expectEqual(2, a.linkingto.items.len);
    try std.testing.expectEqualStrings("4", a.jobs.?);
    try std.testing.expectEqual(false, a.use_lto.?);
    try std.testing.expectEqualStrings("17", a.cxx_std.?);
    try std.testing.expect(a.plan_only);
    const b = (try parseArgs(&f.ctx, &.{ "--pkg", "/p", "-j8", "--src", "/p/src-x64", "--flat" })).?;
    try std.testing.expectEqualStrings("8", b.jobs.?);
    try std.testing.expectEqualStrings("/p/src-x64", b.src.?);
    try std.testing.expect(b.flat);
    try std.testing.expect((try parseArgs(&f.ctx, &.{"--bogus"})) == null);
    try std.testing.expect((try parseArgs(&f.ctx, &.{"--pkg"})) == null);
    // no R_HOME: usage, exit 2
    try std.testing.expectEqual(2, try run(&f.ctx, &.{ "--pkg", f.root }));
}

test "site and user Makevars as R finds them; set but empty is none" {
    // [preflight-PF-2]
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // unix: ~/.R/Makevars-<R_PLATFORM>, then ~/.R/Makevars, ~ from HOME
    try f.touch("home/.R/Makevars");
    try f.env.put("HOME", f.path("home"));
    try testing.expectEqualStrings(f.path("home/.R/Makevars"), (try makevarsUser(c, "")).?);
    try f.env.put("R_PLATFORM", "x86_64-pc-linux-gnu");
    try f.touch("home/.R/Makevars-x86_64-pc-linux-gnu");
    try testing.expectEqualStrings(f.path("home/.R/Makevars-x86_64-pc-linux-gnu"), (try makevarsUser(c, "")).?);
    // R_MAKEVARS_USER: that file or none, and set but empty is none, never
    // ~/.R's (R's Sys.getenv(, NA) and file.exists(""))
    try f.touch("mine.mk");
    try f.env.put("R_MAKEVARS_USER", f.path("mine.mk"));
    try testing.expectEqualStrings(f.path("mine.mk"), (try makevarsUser(c, "")).?);
    try f.env.put("R_MAKEVARS_USER", f.path("no-such.mk"));
    try testing.expect(try makevarsUser(c, "") == null);
    try f.env.put("R_MAKEVARS_USER", "");
    try testing.expect(try makevarsUser(c, "") == null);
    _ = f.env.swapRemove("R_MAKEVARS_USER");
    // unix's ~ is HOME alone
    _ = f.env.swapRemove("HOME");
    try f.env.put("R_USER", f.path("home"));
    try testing.expect(try makevarsUser(c, "") == null);
    // Windows: ~ is R_USER (R sets it), else HOME, else HOMEDRIVE and
    // HOMEPATH; with R_ARCH /x64 Makevars.ucrt, then .win64, then .win
    c.os = .windows;
    try f.touch("ruser/.R/Makevars.win");
    try f.touch("home/.R/Makevars.win");
    try f.env.put("R_USER", f.path("ruser"));
    try f.env.put("HOME", f.path("home"));
    try testing.expectEqualStrings(f.path("ruser/.R/Makevars.win"), (try makevarsUser(c, "/x64")).?);
    try f.touch("ruser/.R/Makevars.win64");
    try testing.expectEqualStrings(f.path("ruser/.R/Makevars.win64"), (try makevarsUser(c, "/x64")).?);
    try f.touch("ruser/.R/Makevars.ucrt");
    try testing.expectEqualStrings(f.path("ruser/.R/Makevars.ucrt"), (try makevarsUser(c, "/x64")).?);
    try testing.expectEqualStrings(f.path("ruser/.R/Makevars.win"), (try makevarsUser(c, "")).?);
    _ = f.env.swapRemove("R_USER");
    try testing.expectEqualStrings(f.path("home/.R/Makevars.win"), (try makevarsUser(c, "/x64")).?);
    _ = f.env.swapRemove("HOME");
    try f.env.put("HOMEDRIVE", f.root);
    try f.env.put("HOMEPATH", "/ruser");
    try testing.expectEqualStrings(f.path("ruser/.R/Makevars.ucrt"), (try makevarsUser(c, "/x64")).?);
    // the site file: R_MAKEVARS_SITE when set, set but empty none; else
    // etc<R_ARCH>/Makevars.site
    c.os = .linux;
    try f.touch("R/etc/Makevars.site");
    try testing.expectEqualStrings(f.path("R/etc/Makevars.site"), (try makevarsSite(c, f.path("R"), "")).?);
    try f.env.put("R_MAKEVARS_SITE", f.path("mine.mk"));
    try testing.expectEqualStrings(f.path("mine.mk"), (try makevarsSite(c, f.path("R"), "")).?);
    try f.env.put("R_MAKEVARS_SITE", "");
    try testing.expect(try makevarsSite(c, f.path("R"), "") == null);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "decide: an empty R_MAKEVARS_USER leaves ~/.R/Makevars out, as R does" {
    // [preflight-PF-2]: a foreign CC there sent a tier-1 package to make
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try pkgplan.rHome(&f);
    try f.touch("p/src/a.c");
    try f.write("home/.R/Makevars", "CC = ccache gcc\n", .default_file);
    try f.env.put("HOME", f.path("home"));
    const in: Inputs = .{ .r_home = r, .pkg_dir = f.path("p"), .src_dir = f.path("p/src"), .name = "p", .rzig = "rzig" };
    var d = try decide(&f.ctx, in);
    try testing.expectEqual(pkgplan.Tier.make, d.tier);
    try testing.expect(mem.startsWith(u8, d.reason, "CC = ccache is not a compiler of R's toolchain"));
    try f.env.put("R_MAKEVARS_USER", "");
    d = try decide(&f.ctx, in);
    try testing.expectEqual(pkgplan.Tier.makevars, d.tier);
}

test "a tier-2 package whose plan needs make: 1 and why, never make" {
    // [preflight-PF-1]: make would compile src/ and ignore build.zig
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.env.put("R_HOME", r);
    try f.write("z/DESCRIPTION", "Package: z\n", .default_file);
    try f.touch("z/src/build.zig");
    try f.write("ccache.mk", "CC = ccache gcc\n", .default_file);
    try f.env.put("R_MAKEVARS_USER", f.path("ccache.mk"));
    const d = try decide(c, .{ .r_home = r, .pkg_dir = f.path("z"), .src_dir = f.path("z/src"), .name = "z", .rzig = "rzig" });
    try testing.expectEqual(pkgplan.Tier.make, d.tier);
    try testing.expectEqual(pkgplan.Tier.zig, d.class.tier);
    try testing.expectEqual(1, try run(c, &.{ "--pkg", f.path("z"), "--out", f.path("out") }));
    const why = f.fmt("CC = ccache is not a compiler of R's toolchain ({s}/bin/toolchain)", .{r});
    try testing.expectEqualStrings(f.fmt("rzig build: z: src/build.zig cannot be built by make: {s}\n", .{why}), f.takeWarnings());
    try testing.expect(!c.exists(f.path("out")));
    // --classify says the same, exit 1, no tier (make would be wrong)
    // [coverage-1]
    try testing.expectEqual(1, try run(c, &.{ "--pkg", f.path("z"), "--classify" }));
    try testing.expectEqualStrings(f.fmt("rzig build: z: src/build.zig cannot be built by make: {s}\n", .{why}), f.takeWarnings());
    // a tier-1 package: needs make, 3, as before
    try f.write("t/DESCRIPTION", "Package: t\n", .default_file);
    try f.touch("t/src/a.c");
    try testing.expectEqual(exit_needs_make, try run(c, &.{ "--pkg", f.path("t"), "--out", f.path("out") }));
    try testing.expectEqualStrings(f.fmt("rzig build: t needs make: {s}\n", .{why}), f.takeWarnings());
}

test "the build root goes on every return, unless kept" {
    // [preflight-PF-3]: under install.R it is the package's src/.rzig
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.env.put("R_HOME", r);
    // the root's files, as R_HOME/share/zig/rpkg holds them
    for ([_][]const u8{ "build_t1.zig", "build_t2.zig", "rpkg.zig" }) |n| try f.touch(f.fmt("rpkg/{s}", .{n}));
    // tier 2 with a URL dependency: refused after the root is written, 1
    try f.write("u/DESCRIPTION", "Package: u\n", .default_file);
    try f.touch("u/src/build.zig");
    try f.write("u/src/build.zig.zon", ".{ .dependencies = .{ .x = .{ .url = \"https://example.invalid/x.tar.gz\" } } }", .default_file);
    const u_args = [_][]const u8{ "--pkg", f.path("u"), "--out", f.path("out-u"), "--rpkg-dir", f.path("rpkg") };
    try testing.expectEqual(1, try run(c, &u_args));
    try testing.expectEqualStrings("rzig build: src/build.zig.zon: dependency x is a URL; tier 2 builds offline, vendor it as a .path dependency\n", f.takeWarnings());
    try testing.expect(c.isDir(f.path("out-u")) and !c.exists(f.path("out-u/.rzig")));
    // tier 1 and no zig: 127, the compilers group's text
    try f.write("t/DESCRIPTION", "Package: t\n", .default_file);
    try f.touch("t/src/a.c");
    const t_args = [_][]const u8{ "--pkg", f.path("t"), "--out", f.path("out-t"), "--rpkg-dir", f.path("rpkg") };
    try testing.expectEqual(127, try run(c, &t_args));
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), "rzig build: " ++ groups.no_zig ++ "\n"));
    try testing.expect(c.isDir(f.path("out-t")) and !c.exists(f.path("out-t/.rzig")));
    // kept: --keep-root, RZIG_KEEP_ROOT=1
    try testing.expectEqual(127, try run(c, &(t_args ++ [_][]const u8{"--keep-root"})));
    try testing.expect(c.isFile(f.path("out-t/.rzig/plan.zon")));
    try f.env.put("RZIG_KEEP_ROOT", "1");
    try testing.expectEqual(1, try run(c, &u_args));
    try testing.expect(c.isFile(f.path("out-u/.rzig/build.zig")) and c.isFile(f.path("out-u/.rzig/plan.zon")));
    _ = f.takeWarnings();
}

test "zig build's build file and cache: tier 1 the build runner's directory in rzig's cache, tier 2 the build root's" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("xdg"));
    const root = f.path("out/.rzig");
    // two R installations with one build_t1.zig, and an upgraded one
    try f.write("r1/build_t1.zig", "// t1\n", .default_file);
    try f.write("r2/build_t1.zig", "// t1\n", .default_file);
    try f.write("r3/build_t1.zig", "// t1, upgraded\n", .default_file);
    const t1 = f.path("r1/build_t1.zig");
    // no zig there: `zig version` says nothing, in the key all the same
    const zig = [_][]const u8{f.path("a/zig")};
    const other = [_][]const u8{f.path("b/zig")};
    // tier 1: build-runner-<key of build_t1.zig's content, the zig
    // command and its version>, made, with build_t1.zig's copy and
    // last-used (the zig command and its version) in it
    const dir = f.fmt("{s}/r-zig/build-runner-{s}", .{ f.path("xdg"), &cache.key(&.{ "// t1\n", f.path("a/zig"), "" }) });
    const shared = try zigBuildDirs(c, null, .makevars, root, &zig, t1);
    try testing.expectEqualStrings(dir, shared.cache_dir);
    try testing.expectEqualStrings(f.fmt("{s}/build_t1.zig", .{dir}), shared.build_file);
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings("// t1\n", try Io.Dir.cwd().readFile(testing.io, shared.build_file, &buf));
    try testing.expectEqualStrings(f.fmt("{s}\n\n", .{f.path("a/zig")}), try Io.Dir.cwd().readFile(testing.io, f.fmt("{s}/last-used", .{dir}), &buf));
    // another install, from another R with the same build_t1.zig: the same
    const again = try zigBuildDirs(c, null, .makevars, f.path("again/.rzig"), &zig, f.path("r2/build_t1.zig"));
    try testing.expectEqualStrings(shared.cache_dir, again.cache_dir);
    try testing.expectEqualStrings(shared.build_file, again.build_file);
    // an upgraded build_t1.zig, another zig: other directories
    const up = try zigBuildDirs(c, null, .makevars, root, &zig, f.path("r3/build_t1.zig"));
    try testing.expectEqualStrings(f.fmt("{s}/r-zig/build-runner-{s}", .{ f.path("xdg"), &cache.key(&.{ "// t1, upgraded\n", f.path("a/zig"), "" }) }), up.cache_dir);
    try testing.expectEqualStrings("// t1, upgraded\n", try Io.Dir.cwd().readFile(testing.io, up.build_file, &buf));
    const oz = try zigBuildDirs(c, null, .makevars, root, &other, t1);
    try testing.expectEqualStrings(f.fmt("{s}/r-zig/build-runner-{s}", .{ f.path("xdg"), &cache.key(&.{ "// t1\n", f.path("b/zig"), "" }) }), oz.cache_dir);
    // tier 2: the build root's, the build file as given
    const t2 = try zigBuildDirs(c, null, .zig, root, &zig, f.path("out/.rzig/build.zig"));
    try testing.expectEqualStrings(f.path("out/.rzig/zig-cache"), t2.cache_dir);
    try testing.expectEqualStrings(f.path("out/.rzig/build.zig"), t2.build_file);
    // ZIG_LOCAL_CACHE_DIR for both tiers (empty is unset), --cache-dir
    // over it; R_HOME's build_t1.zig then
    try f.env.put("ZIG_LOCAL_CACHE_DIR", f.path("zlc"));
    const zlc = try zigBuildDirs(c, null, .makevars, root, &zig, t1);
    try testing.expectEqualStrings(f.path("zlc"), zlc.cache_dir);
    try testing.expectEqualStrings(t1, zlc.build_file);
    try testing.expectEqualStrings(f.path("zlc"), (try zigBuildDirs(c, null, .zig, root, &zig, t1)).cache_dir);
    try testing.expectEqualStrings(f.path("given"), (try zigBuildDirs(c, f.path("given"), .makevars, root, &zig, t1)).cache_dir);
    try f.env.put("ZIG_LOCAL_CACHE_DIR", "");
    try testing.expectEqualStrings(dir, (try zigBuildDirs(c, null, .makevars, root, &zig, t1)).cache_dir);
    // no rzig cache to make (here a file in its place): the build root's,
    // R_HOME's build_t1.zig
    try f.touch("file");
    try f.env.put("XDG_CACHE_HOME", f.path("file"));
    const none = try zigBuildDirs(c, null, .makevars, root, &zig, t1);
    try testing.expectEqualStrings(f.path("out/.rzig/zig-cache"), none.cache_dir);
    try testing.expectEqualStrings(t1, none.build_file);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "a build-runner directory rzig cannot write: the build root's cache" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // no mode bits to take write access away
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("xdg"));
    try f.write("r/build_t1.zig", "// t1\n", .default_file);
    const t1 = f.path("r/build_t1.zig");
    const zig = [_][]const u8{f.path("a/zig")};
    const first = try zigBuildDirs(c, null, .makevars, f.path("out/.rzig"), &zig, t1);
    // read-only now, as on a read-only file system or in another user's
    // cache, where zig could not write its manifests
    var d = try Io.Dir.cwd().openDir(testing.io, first.cache_dir, .{ .iterate = true });
    defer d.close(testing.io);
    try d.setPermissions(testing.io, .fromMode(0o555));
    defer d.setPermissions(testing.io, .fromMode(0o755)) catch {};
    // root writes there all the same: nothing to test
    if (Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = f.fmt("{s}/probe", .{first.cache_dir}), .data = "" })) |_| return error.SkipZigTest else |_| {}
    const ro = try zigBuildDirs(c, null, .makevars, f.path("out/.rzig"), &zig, t1);
    try testing.expectEqualStrings(f.path("out/.rzig/zig-cache"), ro.cache_dir);
    try testing.expectEqualStrings(t1, ro.build_file);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "build-runner directories idle for a week go, renamed out of their names first; the others stay" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("XDG_CACHE_HOME", f.path("xdg"));
    // rzig's cache: a runner last used 8 days ago, one 6 days ago, one
    // with no last-used (being made), one an earlier sweep left half
    // removed, and another kind of entry
    const idle = "build-runner-" ++ "1" ** 32;
    const recent = "build-runner-" ++ "2" ** 32;
    const making = "build-runner-" ++ "3" ** 32;
    const half = "build-runner-" ++ "4" ** 32 ++ ".0123456789abcdef.old";
    const dso = "dso-fini-" ++ "5" ** 32;
    try f.write("xdg/r-zig/" ++ idle ++ "/last-used", "zig\n", .default_file);
    try f.write("xdg/r-zig/" ++ idle ++ "/o/x/build", "runner", .default_file);
    try f.write("xdg/r-zig/" ++ recent ++ "/last-used", "zig\n", .default_file);
    try f.write("xdg/r-zig/" ++ making ++ "/build_t1.zig", "", .default_file);
    try f.write("xdg/r-zig/" ++ half ++ "/o/x/build", "runner", .default_file);
    try f.write("xdg/r-zig/" ++ dso ++ "/dso_fini.o", "", .default_file);
    const now = Io.Timestamp.now(testing.io, .real);
    const day: i64 = std.time.s_per_day;
    try setMtime(f.path("xdg/r-zig/" ++ idle ++ "/last-used"), now.subDuration(.fromSeconds(8 * day)));
    try setMtime(f.path("xdg/r-zig/" ++ recent ++ "/last-used"), now.subDuration(.fromSeconds(6 * day)));
    // a tier-1 build: its own directory, and the sweep
    try f.write("r/build_t1.zig", "// t1\n", .default_file);
    const zig = [_][]const u8{f.path("a/zig")};
    const dirs = try zigBuildDirs(c, null, .makevars, f.path("out/.rzig"), &zig, f.path("r/build_t1.zig"));
    var names: std.ArrayList([]const u8) = .empty;
    var d = try Io.Dir.cwd().openDir(testing.io, f.path("xdg/r-zig"), .{ .iterate = true });
    defer d.close(testing.io);
    var it = d.iterate();
    while (try it.next(testing.io)) |e| try names.append(c.arena, try c.arena.dupe(u8, e.name));
    mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return mem.lessThan(u8, a, b);
        }
    }.lt);
    const own = std.fs.path.basename(dirs.cache_dir);
    var want = [_][]const u8{ own, recent, making, dso };
    mem.sort([]const u8, &want, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return mem.lessThan(u8, a, b);
        }
    }.lt);
    try testutil.expectArgs(&want, names.items);
    try testing.expectEqualStrings("", f.takeWarnings());
}

/// Through the open file: Dir.setTimestamps is not implemented on Windows
/// in zig 0.16.
fn setMtime(path: []const u8, t: Io.Timestamp) !void {
    var file = try Io.Dir.cwd().openFile(testing.io, path, .{ .mode = .write_only });
    defer file.close(testing.io);
    try file.setTimestamps(testing.io, .{ .modify_timestamp = .{ .new = t } });
}
