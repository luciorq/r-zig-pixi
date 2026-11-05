//! `rzig build`: one source package's native library without make
//! (design record .github/devdocs/feat-zig-pkg-build/PLAN.md). Classifies
//! the package (pkgplan.zig) and writes its plan. Tier 1: rzig compiles
//! and links the plan itself (tier1.zig, feat-tier1-engine). Tier 2: zig
//! build on the root R ships in R_HOME/share/zig/rpkg (zigbuild/rpkg/),
//! with the package's own src/build.zig as a path dependency.
//! install.R calls it before its make path (M3); exit 3 means "this
//! package needs make", and R goes on as it did.
//!
//!   rzig build --pkg <dir> --out <dir> [--src <dir>] [--flat] [--name <pkg>]
//!              [--linkingto <dir>]... [--cxx-std NN] [--c-std NN] [--use-lto yes|no]
//!              [--debug] [-j N] [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>]
//!              [--keep-root]
//!
//! --rpkg-dir (the root files' directory, default R_HOME/share/zig/rpkg)
//! and --cache-dir (zig build's cache) are tier 2's: tier 1 and --shlib
//! run no zig build, and take them and ignore them (Cc4: flags are added,
//! never removed).
//!
//! The library goes to <out>/libs<R_ARCH>/<pkg>.so (a package's installed
//! layout), or with --flat to <out>/<pkg>.so, where make leaves it in
//! src/ and install.R's shlib_install takes it (patch 0013 runs
//! `rzig build --pkg .. --src . --out . --flat` from src/).
//!   rzig build --pkg <dir> --plan-only     the plan.zon to stdout
//!   rzig build --pkg <dir> --classify      the tier to stdout
//!
//! Exit 0 built (or nothing to build), 3 needs make (why, on stderr),
//! 2 usage, 1 failed, 127 no zig (the compilers group's text); a crash
//! is never 3 (crash.zig: 70 on Windows, SIGABRT elsewhere). A tier-2
//! package whose plan needs make is 1, not 3: make would ignore its
//! build.zig (`buildZigNeedsMake`). R_HOME from the environment, as
//! under R. `--classify` prints the decided tier (r_only, makevars, zig,
//! make: make also when the Makevars sends the package there), and for
//! that tier-2 package the same line and exit 1 as a build;
//! `--plan-only` the plan. The install preflight (check.zig's
//! --rzig-check=package) decides through `decide` below. Whatever the
//! exit, the build root <out>/.rzig is gone afterwards unless kept
//! (--keep-root, RZIG_KEEP_ROOT=1). Tier 1 runs no zig build: rzig
//! compiles and links the plan itself (tier1.zig); tier 2's zig build
//! has a cache in the build root, gone with it.
//!
//!   rzig build --shlib --output <lib> [--pkg-libs <words>] [--use-lto yes|no] [--c-std NN]
//!              [--debug] [-j N] [--dry-run] [--plan-only]
//!              [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>] [--keep-root] -- <file>...
//!
//! SHLIB mode (feat-shlib-rzig-build): R CMD SHLIB's call from
//! .shlib_internal (patch 0013's .rzig_build), run in R's working
//! directory: the files R names, in argv order, the output as given
//! (-o), argv's other words as make's command-line PKG_LIBS, and the
//! working directory's Makevars (pkgplan.zig's `Shlib`). The library goes
//! to <lib>; nothing else is written beside the sources but the .mod
//! files flang writes there, as under make. The build root is
//! .rzig.<16 hex> in R's session directory (R_SESSION_TMPDIR), else beside
//! <lib>, unique per call and gone after it (open point M b); a kept one
//! (--keep-root, RZIG_KEEP_ROOT=1) is beside <lib>, since R CMD SHLIB's
//! own R removes its session directory when it exits [shlib-code-1].
//! Before the root, the compilers check the install preflight makes
//! (check.zig's shlibCompilers; R CMD SHLIB has no preflight): a missing
//! zig or flang exits 127 after the compilers group's text, and a zig
//! that is not R's exits 3 when
//! make is there (R's make path with zig-cc, as before), else 1
//! [shlib-r-2]. A call that
//! needs make exits 3, or, when a group it needs is missing (make, zig,
//! flang), 127 after every missing group's text, compilers first
//! (check.zig's groupsFor; open point F a), and R does not run make.
//! --dry-run prints the commands it would run, as `make -n` prints them,
//! with no zig and no build root (open point C a); a call that needs make
//! exits 3 there, and R runs `make -n`. There is no --clean or --preclean:
//! no object is written beside the sources (open point E a). TMB keeps an
//! R's .shlib_internal body, and with it the arguments .rzig_build passes:
//! flags are added, never removed or renamed (feat-shlib-rzig-build Cc4).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const pkgplan = @import("pkgplan.zig");
const find_zig = @import("find_zig.zig");
const groups = @import("groups.zig");
const cache = @import("cache.zig");
const check = @import("check.zig");
const shellwords = @import("shellwords.zig");
const tier1 = @import("tier1.zig");

pub const exit_needs_make: u8 = 3;

const usage =
    \\usage: rzig build --pkg <dir> --out <dir> [--src <dir>] [--flat] [--name <pkg>]
    \\                  [--linkingto <dir>]... [--cxx-std NN] [--c-std NN] [--use-lto yes|no]
    \\                  [--debug] [-j N] [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>]
    \\                  [--keep-root]
    \\       rzig build --pkg <dir> --plan-only | --classify
    \\       rzig build --shlib --output <lib> [--pkg-libs <words>] [--use-lto yes|no] [--c-std NN]
    \\                  [--debug] [-j N] [--dry-run] [--plan-only]
    \\                  [--r-home <dir>] [--rpkg-dir <dir>] [--cache-dir <dir>] [--keep-root] -- <file>...
    \\--rpkg-dir and --cache-dir are tier 2's; tier 1 and --shlib ignore them.
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
    /// SHLIB mode: R CMD SHLIB's call (the header)
    shlib: bool = false,
    output: ?[]const u8 = null,
    pkg_libs: ?[]const u8 = null,
    dry_run: bool = false,
    /// after `--`
    files: std.ArrayList([]const u8) = .empty,
};

fn parseArgs(ctx: *Ctx, argv: []const []const u8) !?Args {
    var a: Args = .{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const x = argv[i];
        const takes_value = mem.eql(u8, x, "--pkg") or mem.eql(u8, x, "--src") or mem.eql(u8, x, "--out") or mem.eql(u8, x, "--name") or mem.eql(u8, x, "--linkingto") or
            mem.eql(u8, x, "--cxx-std") or mem.eql(u8, x, "--c-std") or mem.eql(u8, x, "--use-lto") or mem.eql(u8, x, "-j") or
            mem.eql(u8, x, "--r-home") or mem.eql(u8, x, "--rpkg-dir") or mem.eql(u8, x, "--cache-dir") or mem.eql(u8, x, "--output") or mem.eql(u8, x, "--pkg-libs");
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
            } else if (mem.eql(u8, x, "-j")) a.jobs = v else if (mem.eql(u8, x, "--r-home")) a.r_home = v else if (mem.eql(u8, x, "--rpkg-dir")) a.rpkg_dir = v else if (mem.eql(u8, x, "--cache-dir")) a.cache_dir = v else if (mem.eql(u8, x, "--output")) a.output = v else if (mem.eql(u8, x, "--pkg-libs")) a.pkg_libs = v;
        } else if (mem.eql(u8, x, "--")) {
            try a.files.appendSlice(ctx.arena, argv[i + 1 ..]);
            break;
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
        } else if (mem.eql(u8, x, "--shlib")) {
            a.shlib = true;
        } else if (mem.eql(u8, x, "--dry-run")) {
            a.dry_run = true;
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
    /// R CMD SHLIB's call (`rzig build --shlib`), in src_dir, the working
    /// directory. The install preflight (check.zig) never sets it.
    shlib: ?pkgplan.Shlib = null,
    /// pkgplan's Options.warn_cxx_std: the preflight's.
    warn_cxx_std: bool = false,
};

pub fn decide(ctx: *Ctx, in: Inputs) error{OutOfMemory}!Decision {
    const r_arch = ctx.getenv("R_ARCH") orelse if (ctx.os == .windows) "/x64" else "";
    var planner: pkgplan.Planner = .{ .ctx = ctx };
    const classified = if (in.shlib) |s| planner.classifyShlib(in.src_dir, s) else planner.classify(in.pkg_dir, in.src_dir);
    const class = classified catch |err| switch (err) {
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
        .shlib = in.shlib,
        .warn_cxx_std = in.warn_cxx_std,
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
    if (args.shlib) return runShlib(ctx, args);
    if (args.output != null or args.pkg_libs != null or args.dry_run or args.files.items.len > 0) {
        ctx.warn("--output, --pkg-libs, --dry-run and files after -- go with --shlib\n{s}", .{usage});
        return 2;
    }
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
    const rpkg_dir = args.rpkg_dir orelse try ctx.fmt("{s}/share/zig/rpkg", .{r_home});
    Io.Dir.cwd().createDirPath(ctx.io, out_in) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ out_in, err });
        return 1;
    };
    const out = canonical(ctx, out_in) catch return 1;

    // the build root: the plan, and for tier 2 the root files with the
    // package as a path dependency
    const root = try ctx.fmt("{s}/.rzig", .{out});
    Io.Dir.cwd().createDirPath(ctx.io, root) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ root, err });
        return 1;
    };
    // from here every return removes the root, a refusal, no zig or a
    // failed write as much as a build: under install.R it is the
    // package's src/.rzig, which R CMD build would ship [preflight-PF-3]
    const keep = keepRoot(ctx, args);
    defer if (!keep) {
        Io.Dir.cwd().deleteTree(ctx.io, root) catch |err| ctx.warn("cannot remove {s}: {t}", .{ root, err });
    };
    if (!try writePlan(ctx, &plan, root)) return 1;
    var build_file: []const u8 = undefined;
    switch (class.tier) {
        .makevars => return tier1Build(ctx, args, &plan, root, out, "tier 1"),
        .zig => {
            const files = [_][2][]const u8{ .{ "build_t2.zig", "build.zig" }, .{ "rpkg.zig", "rpkg.zig" } };
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
    return zigBuild(ctx, args, &plan, class.tier, root, build_file, out, "tier 2");
}

fn keepRoot(ctx: *const Ctx, args: Args) bool {
    return args.keep_root or isSet(ctx, "RZIG_KEEP_ROOT");
}

/// The plan as <root>/plan.zon; false (and why) when it cannot be written.
fn writePlan(ctx: *Ctx, plan: *const pkgplan.Plan, root: []const u8) !bool {
    const plan_path = try ctx.fmt("{s}/plan.zon", .{root});
    var w: Io.Writer.Allocating = .init(ctx.arena);
    try pkgplan.writeZon(plan, &w.writer);
    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = plan_path, .data = w.written() }) catch |err| {
        ctx.warn("cannot write {s}: {t}", .{ plan_path, err });
        return false;
    };
    return true;
}

/// Tier 1 (a package's, and R CMD SHLIB's): rzig compiles and links the
/// plan in the build root `root` (tier1.zig), the library into `out`'s
/// libs_dir. No zig build, so no build runner to compile or cache: what
/// is shared across installs is zig's global cache (std, compiler_rt,
/// zig cc's objects keyed by the source as named and its contents, so a
/// reinstall of the same sources adds none, as on make's path [tests-T1]).
/// `label` names the build in RZIG_TRACE's line.
fn tier1Build(ctx: *Ctx, args: Args, plan: *const pkgplan.Plan, root: []const u8, out: []const u8, label: []const u8) !u8 {
    // no zig: 127 and the compilers group's text once, before any compile
    // says it (main.zig)
    const zig = (try find_zig.find(ctx)) orelse {
        try groups.report(ctx, groups.no_zig, .compilers);
        return 127;
    };
    try reportCompilers(ctx, plan, .makevars, zig.argv);
    if (isSet(ctx, "RZIG_TRACE")) ctx.warn("{s}, root {s}", .{ label, root });
    const dest = if (plan.libs_dir.len == 0) try ctx.fmt("{s}/{s}", .{ out, plan.output }) else try ctx.fmt("{s}/{s}/{s}", .{ out, plan.libs_dir, plan.output });
    const code = try tier1.build(ctx, plan, .{ .root = root, .dest = dest, .jobs = if (args.jobs) |j| tier1.jobCount(j) else 0 });
    if (code != 0 and keepRoot(ctx, args)) ctx.warn("the build root is kept in {s}", .{root});
    return code;
}

/// zig build on tier 2's build root `root`, which holds plan.zon and the
/// root files, installing into `out`. `label` names the build in
/// RZIG_TRACE's line.
fn zigBuild(ctx: *Ctx, args: Args, plan: *const pkgplan.Plan, tier: pkgplan.Tier, root: []const u8, build_file: []const u8, out: []const u8, label: []const u8) !u8 {
    const no_packages = try ctx.fmt("{s}/no-packages", .{root});
    if (tier == .zig) Io.Dir.cwd().createDirPath(ctx.io, no_packages) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ no_packages, err });
        return 1;
    };
    // no zig: 127 and the compilers group's text, as a compile says (main.zig)
    const zig = (try find_zig.find(ctx)) orelse {
        try groups.report(ctx, groups.no_zig, .compilers);
        return 127;
    };
    // zig build's cache: --cache-dir, else ZIG_LOCAL_CACHE_DIR (stress.R
    // points it at its run directory), else <build root>/zig-cache, gone
    // with the root. The root imports the package's build.zig from its
    // path in this install, so its runner is new in every install, and a
    // shared cache would only grow (feat-zig-pkg-build N3).
    const cache_dir = args.cache_dir orelse ctx.getenv("ZIG_LOCAL_CACHE_DIR") orelse try ctx.fmt("{s}/zig-cache", .{root});
    try reportCompilers(ctx, plan, tier, zig.argv);
    // zig build makes an (empty) .zig-cache in a path dependency's directory,
    // the package's src/ here; leave src/ as it was found
    const dep_cache = try ctx.fmt("{s}/.zig-cache", .{plan.srcdir});
    const dep_cache_existed = tier == .zig and ctx.exists(dep_cache);
    var cmd: std.ArrayList([]const u8) = .empty;
    try cmd.appendSlice(ctx.arena, zig.argv);
    try cmd.appendSlice(ctx.arena, &.{ "build", "--build-file", build_file, "--cache-dir", cache_dir, "--prefix", out, try ctx.fmt("-Dplan={s}/plan.zon", .{root}) });
    if (tier == .zig) try cmd.appendSlice(ctx.arena, &.{ "--system", no_packages });
    // -j for zig build's steps, and through rpkg.zig for `rzig t1`'s
    // compiles, which are one step
    if (args.jobs) |j| try cmd.appendSlice(ctx.arena, &.{ try ctx.fmt("-j{s}", .{j}), try ctx.fmt("-Djobs={d}", .{tier1.jobCount(j)}) });
    if (isSet(ctx, "RZIG_TRACE")) {
        ctx.warn("{s}, root {s}", .{ label, root });
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
    if (tier == .zig and !dep_cache_existed) Io.Dir.cwd().deleteTree(ctx.io, dep_cache) catch {};
    if (code != 0) {
        if (keepRoot(ctx, args)) ctx.warn("zig build failed ({d}); the build root is kept in {s}", .{ code, root }) else ctx.warn("zig build failed ({d})", .{code});
    }
    return if (code != 0) 1 else 0;
}

/// `rzig build --shlib` (the header): R CMD SHLIB's call, in the working
/// directory.
fn runShlib(ctx: *Ctx, args: Args) !u8 {
    if (args.pkg != null or args.src != null or args.out != null or args.flat or args.name != null or args.linkingto.items.len > 0 or args.cxx_std != null or args.classify) {
        ctx.warn("--shlib takes none of --pkg, --src, --out, --flat, --name, --linkingto, --cxx-std, --classify\n{s}", .{usage});
        return 2;
    }
    if (args.output == null or args.files.items.len == 0) {
        ctx.warn("--shlib needs --output <lib> and the files after --\n{s}", .{usage});
        return 2;
    }
    const r_home_in = args.r_home orelse ctx.getenv("R_HOME") orelse {
        ctx.warn("R_HOME is not set and no --r-home given", .{});
        return 2;
    };
    const r_home = canonical(ctx, r_home_in) catch return 2;
    const cwd = canonical(ctx, ".") catch return 2;
    var buf: [4096]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(ctx.io, &buf);
    const code = try shlibIn(ctx, args, r_home, cwd, &w.interface);
    try w.interface.flush();
    return code;
}

/// runShlib's work in `cwd` (canonical), where the unit tests call it;
/// --plan-only's and --dry-run's text go to `stdout`.
fn shlibIn(ctx: *Ctx, args: Args, r_home: []const u8, cwd: []const u8, stdout: *Io.Writer) !u8 {
    const output = args.output.?;
    const files = args.files.items;
    const out_abs = if (std.fs.path.isAbsolute(output)) try slashes(ctx, output) else try ctx.fmt("{s}/{s}", .{ cwd, output });
    const out_dir = std.fs.path.dirname(out_abs) orelse cwd;
    const d = try decide(ctx, .{
        .r_home = r_home,
        .pkg_dir = cwd,
        .src_dir = cwd,
        .name = std.fs.path.stem(std.fs.path.basename(output)),
        .c_std = args.c_std,
        .use_lto = args.use_lto,
        .debug = args.debug,
        .rzig = ctx.self_exe orelse "rzig",
        .shlib = .{ .files = files, .output = output, .pkg_libs = args.pkg_libs },
    });
    var fortran = false;
    for (files) |f| if (pkgplan.langOf(f)) |l| {
        if (l == .f or l == .f9x) fortran = true;
    };
    if (d.tier == .make) {
        if (args.dry_run or args.plan_only) return needsMake(ctx, output, d.reason);
        // what make would need: when a group is missing, every missing
        // group's text, and R does not run make (open point F a)
        const res = try check.groupsFor(ctx, output, d.reason, fortran);
        if (res.code != 0) return res.code;
        return needsMake(ctx, output, d.reason);
    }
    var plan = d.plan.?;
    plan.libs_dir = "";
    if (args.plan_only) {
        try pkgplan.writeZon(&plan, stdout);
        return 0;
    }
    if (args.dry_run) {
        try printCommands(ctx, &plan, output, stdout);
        return 0;
    }
    // the compilers check the install preflight (patch 0009) makes for a
    // package, which R CMD SHLIB has none of [shlib-r-2]
    const comp = try check.shlibCompilers(ctx, output, fortran);
    if (comp != 0) return comp;
    Io.Dir.cwd().createDirPath(ctx.io, out_dir) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ out_dir, err });
        return 1;
    };
    // the build root: unique per call, as R CMD SHLIB runs in parallel in
    // one directory (SZ H2); in R's session directory, which R removes
    // when it exits, so a killed call leaves nothing beside the sources
    // (open point M b). A kept root goes beside the output: it has to
    // outlive the R that started rzig, and R CMD SHLIB's R removes its
    // session directory when it exits, before the user could look
    // [shlib-code-1]
    const keep = keepRoot(ctx, args);
    const root_parent = if (keep) out_dir else sessionDir(ctx) orelse out_dir;
    const root = try ctx.fmt("{s}/{s}", .{ root_parent, try cache.tempName(ctx, ".rzig", "") });
    Io.Dir.cwd().createDirPath(ctx.io, root) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ root, err });
        return 1;
    };
    defer if (!keep) {
        Io.Dir.cwd().deleteTree(ctx.io, root) catch |err| ctx.warn("cannot remove {s}: {t}", .{ root, err });
    };
    if (!try writePlan(ctx, &plan, root)) return 1;
    // not "tier 1, ...": pkg-parity's and verify-bundle's greps for a
    // package's tier never take a configure script's SHLIB for it
    return tier1Build(ctx, args, &plan, root, out_dir, "R CMD SHLIB, tier 1");
}

/// R's session directory, R_SESSION_TMPDIR, which unix R sets for its
/// children (src/main/sysutils.c) and patch 0013's .rzig_build for rzig
/// on Windows, whose R sets none, when it names one; canonical.
fn sessionDir(ctx: *Ctx) ?[]const u8 {
    const t = ctx.getenv("R_SESSION_TMPDIR") orelse return null;
    if (!ctx.isDir(t)) return null;
    return canonical(ctx, t) catch null;
}

/// What `make -n` would print for R CMD SHLIB's plan (open point C a;
/// feat-shlib-rzig-build Cc2): a compile line per source, in plan order,
/// `<toolchain>/<tool> <flags> -c <source> -o <object>`, the object named
/// as make names it; then the link inside the wrapper shlib.mk's recipe
/// has (winshlib.mk's, with the .def), as make -n prints it. Rcpp's macOS
/// OpenMP plugin reads the first line after "make would use", the first
/// compile; pkgload-style filters keep lines that start with a compiler
/// and expect one -c in each, so no line that runs the linker starts with
/// it. Each word is quoted for a shell (shellwords.quote).
pub fn printCommands(ctx: *Ctx, plan: *const pkgplan.Plan, output: []const u8, w: *Io.Writer) !void {
    const a = ctx.arena;
    const tool_path = struct {
        fn f(c: *Ctx, p: *const pkgplan.Plan, tool: []const u8) ![]const u8 {
            return shellwords.quote(c.arena, try c.fmt("{s}/{s}", .{ p.toolchain, tool }));
        }
    }.f;
    var objs: std.ArrayList([]const u8) = .empty;
    for (plan.sources) |s| {
        const lang = std.meta.stringToEnum(pkgplan.Lang, s.lang).?;
        const tool, const flags = switch (lang) {
            .c => .{ plan.cc_tool, plan.cc },
            .cxx => .{ plan.cxx_tool, plan.cxx },
            .f => .{ plan.fc_tool, plan.fc },
            .f9x => .{ plan.fc_tool, plan.f9x },
        };
        try w.writeAll(try tool_path(ctx, plan, tool));
        for (flags) |x| try w.print(" {s}", .{try shellwords.quote(a, x)});
        try w.print(" -c {s} -o {s}\n", .{ try shellwords.quote(a, s.path), try shellwords.quote(a, s.obj) });
        try objs.append(a, s.obj);
    }
    var link: std.ArrayList(u8) = .empty;
    try link.appendSlice(a, try tool_path(ctx, plan, plan.link_driver));
    for (plan.link) |x| try link.print(a, " {s}", .{try shellwords.quote(a, x)});
    try link.print(a, " -o {s}", .{try shellwords.quote(a, output)});
    const base = pkgplan.dllBase(output);
    if (plan.win_def.len > 0) try link.print(a, " {s}", .{try shellwords.quote(a, plan.win_def)});
    if (plan.def) try link.print(a, " {s}", .{try shellwords.quote(a, try ctx.fmt("{s}.def", .{base}))});
    var quoted_objs: std.ArrayList(u8) = .empty;
    for (objs.items) |o| try quoted_objs.print(a, " {s}", .{try shellwords.quote(a, o)});
    try link.appendSlice(a, quoted_objs.items);
    for (plan.libs) |x| try link.print(a, " {s}", .{try shellwords.quote(a, x)});
    try w.print("if test \"z{s}\" != \"z\"; then \\\n", .{try mem.join(a, " ", objs.items)});
    if (plan.def) try w.print("  {s} def -o {s}{s}; \\\n", .{ try shellwords.quote(a, plan.rzig), try shellwords.quote(a, try ctx.fmt("{s}.def", .{base})), quoted_objs.items });
    try w.print("  echo {s}; \\\n  {s}; \\\nfi\n", .{ link.items, link.items });
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
    for ([_][]const u8{ "build_t2.zig", "rpkg.zig" }) |n| try f.touch(f.fmt("rpkg/{s}", .{n}));
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

// R CMD SHLIB's calls, `rzig build --shlib` (feat-shlib-rzig-build)

/// shlibIn for `argv` (rzig build's arguments) in `cwd`; what it would
/// print on stdout goes to `out`.
fn shlibTest(f: *testutil.Fixture, r: []const u8, cwd: []const u8, argv: []const []const u8, out: *Io.Writer.Allocating) !u8 {
    const args = (try parseArgs(&f.ctx, argv)).?;
    return shlibIn(&f.ctx, args, r, cwd, &out.writer);
}

/// The names in `dir` that start with `.rzig.`.
fn roots(f: *testutil.Fixture, dir: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var d = Io.Dir.cwd().openDir(testing.io, dir, .{ .iterate = true }) catch return out.items;
    defer d.close(testing.io);
    var it = d.iterate();
    while (try it.next(testing.io)) |e| if (mem.startsWith(u8, e.name, ".rzig.")) try out.append(f.ctx.arena, try f.ctx.arena.dupe(u8, e.name));
    return out.items;
}

test "shlib: arguments" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const a = (try parseArgs(c, &.{ "--shlib", "--output", "sub/x.so", "--pkg-libs", "-lm -L\"/a b\"", "-j", "4", "--dry-run", "--", "a.c", "--", "-o" })).?;
    try testing.expect(a.shlib and a.dry_run);
    try testing.expectEqualStrings("sub/x.so", a.output.?);
    try testing.expectEqualStrings("-lm -L\"/a b\"", a.pkg_libs.?);
    try testing.expectEqualStrings("4", a.jobs.?);
    // after --, every word is a file
    try testutil.expectArgs(&.{ "a.c", "--", "-o" }, a.files.items);
    try f.env.put("R_HOME", f.root);
    // usage errors, 2: a package's flags, no --output, no file; and SHLIB's
    // flags without --shlib
    try testing.expectEqual(2, try run(c, &.{ "--shlib", "--pkg", "/p", "--output", "x.so", "--", "a.c" }));
    try testing.expectEqual(2, try run(c, &.{ "--shlib", "--classify", "--output", "x.so", "--", "a.c" }));
    try testing.expectEqual(2, try run(c, &.{ "--shlib", "--", "a.c" }));
    try testing.expectEqual(2, try run(c, &.{ "--shlib", "--output", "x.so" }));
    try testing.expectEqual(2, try run(c, &.{ "--shlib", "--output", "x.so", "--" }));
    try testing.expectEqual(2, try run(c, &.{ "--pkg", "/p", "--dry-run" }));
    try testing.expectEqual(2, try run(c, &.{ "--pkg", "/p", "--", "a.c" }));
    _ = f.takeWarnings();
}

test "shlib: the build root, in R's session directory, else beside the output; unique, gone after; a kept one beside the output" {
    // open point M (b); SZ H2; [shlib-code-1, shlib-tests-1]
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.touch("w/foo.c");
    try f.tmp.dir.createDirPath(testing.io, "sess");
    try f.env.put("R_SESSION_TMPDIR", f.path("sess"));
    // a zig that zig build cannot run (an empty program), past the version
    // check (R_ZIG_NO_PREFLIGHT): each call fails, 1, after the root was made
    try f.env.put("ZIG_BIN", try f.touchProgram("bin/zig"));
    try f.env.put("R_ZIG_NO_PREFLIGHT", "1");
    var out: Io.Writer.Allocating = .init(c.arena);
    const call = struct {
        fn go(fx: *testutil.Fixture, rh: []const u8, o: *Io.Writer.Allocating, output: []const u8) !void {
            try testing.expectEqual(1, try shlibTest(fx, rh, fx.path("w"), &.{ "--shlib", "--output", output, "--rpkg-dir", fx.path("rpkg"), "--cache-dir", fx.path("zc"), "--", "foo.c" }, o));
            try testing.expect(mem.startsWith(u8, fx.takeWarnings(), "rzig-test: cannot run "));
        }
    }.go;
    // in R's session directory, gone after
    try call(&f, r, &out, "foo.so");
    try testing.expectEqual(0, (try roots(&f, f.path("sess"))).len);
    try testing.expectEqual(0, (try roots(&f, f.path("w"))).len);
    // kept (RZIG_KEEP_ROOT): .rzig.<16 hex> beside the output, with the
    // plan, never in R's session directory, which R CMD SHLIB's R removes
    // when it exits; another call, another root
    try f.env.put("RZIG_KEEP_ROOT", "1");
    try call(&f, r, &out, "foo.so");
    try call(&f, r, &out, "foo.so");
    const kept = try roots(&f, f.path("w"));
    try testing.expectEqual(2, kept.len);
    try testing.expect(!mem.eql(u8, kept[0], kept[1]));
    for (kept) |k| {
        try testing.expectEqual(".rzig.".len + 16, k.len);
        try testing.expect(c.isFile(f.fmt("{s}/{s}/plan.zon", .{ f.path("w"), k })));
        try f.tmp.dir.deleteTree(testing.io, f.fmt("w/{s}", .{k}));
    }
    try testing.expectEqual(0, (try roots(&f, f.path("sess"))).len);
    _ = f.env.swapRemove("RZIG_KEEP_ROOT");
    // no session directory (unset, or one that does not exist): beside the
    // output, which is made, and gone after
    for ([_]?[]const u8{ null, f.path("no-such-dir") }) |sess| {
        if (sess) |s| try f.env.put("R_SESSION_TMPDIR", s) else _ = f.env.swapRemove("R_SESSION_TMPDIR");
        try f.tmp.dir.deleteTree(testing.io, "w/sub");
        try call(&f, r, &out, "sub/foo.so");
        try testing.expect(c.isDir(f.path("w/sub")));
        try testing.expectEqual(0, (try roots(&f, f.path("w/sub"))).len);
    }
    // and kept there
    try f.env.put("RZIG_KEEP_ROOT", "1");
    try call(&f, r, &out, "sub/foo.so");
    try testing.expectEqual(1, (try roots(&f, f.path("w/sub"))).len);
    _ = f.env.swapRemove("RZIG_KEEP_ROOT");
    try testing.expectEqual(0, (try roots(&f, f.path("w"))).len);
    // --plan-only and --dry-run make none
    try f.tmp.dir.deleteTree(testing.io, "w/sub");
    try testing.expectEqual(0, try shlibTest(&f, r, f.path("w"), &.{ "--shlib", "--output", "sub/foo.so", "--dry-run", "--", "foo.c" }, &out));
    try testing.expectEqual(0, try shlibTest(&f, r, f.path("w"), &.{ "--shlib", "--output", "sub/foo.so", "--plan-only", "--", "foo.c" }, &out));
    try testing.expect(!c.exists(f.path("w/sub")));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "shlib: a zig that is not R's: make's (3) with the build tools, else 1 and the compilers' text; zig build never runs" {
    // [shlib-r-2]: R CMD SHLIB has no install preflight to say so
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.touch("w/foo.c");
    try f.env.put("PATH", f.path("nothing"));
    // another minor version, and a mark when zig build runs
    const other = std.fmt.comptimePrint("{d}.{d}.0", .{ builtin.zig_version.major, builtin.zig_version.minor + 1 });
    try f.write("bin/zig", f.fmt("#!/bin/sh\n[ \"$1\" = version ] && echo '{s}' && exit 0\n[ \"$1\" = build ] && : > '{s}'\nexit 0\n", .{ other, f.path("built") }), .fromMode(0o755));
    const zig = f.path("bin/zig");
    try f.env.put("ZIG_BIN", zig);
    const argv = [_][]const u8{ "--shlib", "--output", "foo.so", "--rpkg-dir", f.path("rpkg"), "--cache-dir", f.path("zc"), "--", "foo.c" };
    var out: Io.Writer.Allocating = .init(c.arena);
    const what = f.fmt("{s} is zig {s}, not R's zig {s}", .{ zig, other, groups.this.zig });
    // no make: 1, the line and the compilers group's text
    try testing.expectEqual(1, try shlibTest(&f, r, f.path("w"), &argv, &out));
    try testing.expectEqualStrings(f.fmt("rzig-test: {s} (R_ZIG_NO_PREFLIGHT=1 skips this check)\n{s}", .{ what, try groups.text(c.arena, .compilers, groups.this) }), f.takeWarnings());
    // make: 3, and R's make path compiles with zig-cc, as before
    _ = try f.touchProgram("mk/make");
    try f.env.put("PATH", f.path("mk"));
    try testing.expectEqual(exit_needs_make, try shlibTest(&f, r, f.path("w"), &argv, &out));
    try testing.expectEqualStrings(f.fmt("rzig-test: foo.so needs make: {s}\n", .{what}), f.takeWarnings());
    try testing.expect(!c.exists(f.path("built")));
    try testing.expectEqual(0, (try roots(&f, f.path("w"))).len);
    // R_ZIG_NO_PREFLIGHT skips the comparison: rzig compiles, with the
    // toolchain's zig-cc (here a file that is no program: 1); zig build
    // never runs, tier 1 has none (tier1.zig)
    try f.env.put("R_ZIG_NO_PREFLIGHT", "1");
    try testing.expectEqual(1, try shlibTest(&f, r, f.path("w"), &argv, &out));
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), f.fmt("rzig-test: cannot run {s}/bin/toolchain/zig-cc: ", .{r})));
    try testing.expect(!c.exists(f.path("built")));
    try testing.expectEqual(0, (try roots(&f, f.path("w"))).len);
    try testing.expectEqualStrings("", out.written());
    _ = f.takeWarnings();
}

test "shlib: --dry-run prints make -n's commands" {
    // open point C (a); feat-shlib-rzig-build Cc2
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.touchExe("R/bin/toolchain/zig-cxx");
    try f.touch("w/a.c");
    try f.touch("w/b.cpp");
    try f.write("w/Makevars", "PKG_CPPFLAGS = -I'/inc dir' -DX=\"a b\"\n", .default_file);
    var out: Io.Writer.Allocating = .init(c.arena);
    try testing.expectEqual(0, try shlibTest(&f, r, f.path("w"), &.{ "--shlib", "--output", "sub/x.so", "--pkg-libs", "-lm", "--dry-run", "--", "b.cpp", "a.c" }, &out));
    const tc = f.fmt("{s}/bin/toolchain", .{r});
    const inc = f.fmt("-I{s}/include", .{r});
    const lib = f.fmt("-L{s}/lib", .{r});
    try testing.expectEqualStrings(f.fmt(
        \\{s}/zig-cxx -std=gnu++20 {s} -DNDEBUG '-I/inc dir' '-DX=a b' -fpic -O2 -c b.cpp -o b.o
        \\{s}/zig-cc -std=gnu23 {s} -DNDEBUG '-I/inc dir' '-DX=a b' -fpic -O2 -c a.c -o a.o
        \\if test "zb.o a.o" != "z"; then \
        \\  echo {s}/zig-cxx -std=gnu++20 -shared {s} -o sub/x.so b.o a.o -lm {s} -lR; \
        \\  {s}/zig-cxx -std=gnu++20 -shared {s} -o sub/x.so b.o a.o -lm {s} -lR; \
        \\fi
        \\
    , .{ tc, inc, tc, inc, tc, lib, lib, tc, lib, lib }), out.written());
    // pkgload's filter (lines that start with a compiler) and its -c
    // extraction count the same lines, one per source
    var it = mem.splitScalar(u8, out.written(), '\n');
    var kept: usize = 0;
    var with_c: usize = 0;
    while (it.next()) |line| {
        if (!(mem.startsWith(u8, line, f.fmt("{s}/zig-cc -std=gnu23", .{tc})) or mem.startsWith(u8, line, f.fmt("{s}/zig-cxx -std=gnu++20", .{tc})))) continue;
        kept += 1;
        if (mem.indexOf(u8, line, " -c ") != null) with_c += 1;
    }
    try testing.expectEqual(2, kept);
    try testing.expectEqual(kept, with_c);
    // a call that needs make: 3, and R runs make -n; nothing on stdout
    out.clearRetainingCapacity();
    try testing.expectEqual(exit_needs_make, try shlibTest(&f, r, f.path("w"), &.{ "--shlib", "--output", "x.so", "--pkg-libs", "' --always-make IGNORED='", "--dry-run", "--", "a.c" }, &out));
    try testing.expectEqualStrings("", out.written());
    try testing.expectEqualStrings("rzig-test: x.so needs make: a single quote in the linker words ('' --always-make IGNORED=''): it changes make's own command line\n", f.takeWarnings());
    // Windows: rzig def's .def, winshlib.mk's BASE
    _ = try pkgplan.winHome(&f);
    c.os = .windows;
    out.clearRetainingCapacity();
    try testing.expectEqual(0, try shlibTest(&f, r, f.path("w"), &.{ "--shlib", "--output", "x.dll", "--dry-run", "--", "a.c" }, &out));
    try testing.expect(mem.indexOf(u8, out.written(), "\n  rzig def -o x.def a.o; \\\n  echo ") != null);
    try testing.expect(mem.indexOf(u8, out.written(), f.fmt(" -o x.dll x.def a.o {s} -lR; \\\nfi\n", .{lib})) != null);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "shlib: a call that needs make, with no make: every missing group, 127; with both, 3" {
    // open point F (a); feat-shlib-rzig-build Cg5, Cc9
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.write("w/Makevars", "all: $(SHLIB) extra\n", .default_file);
    try f.touch("w/x.c");
    try f.env.put("PATH", f.path("nothing"));
    const argv = [_][]const u8{ "--shlib", "--output", "x.so", "--rpkg-dir", f.path("rpkg"), "--", "x.c" };
    var out: Io.Writer.Allocating = .init(c.arena);
    const why = "x.so needs make: Makevars has a rule or target line: 'all: $(SHLIB) extra'";
    const comp = f.fmt("rzig-test: " ++ groups.no_zig ++ "\n{s}", .{try groups.text(c.arena, .compilers, groups.this)});
    const bt = f.fmt("rzig-test: {s}; no make on PATH\n{s}", .{ why, try groups.text(c.arena, .build_tools, groups.this) });
    // no zig, no make: the compilers' text, then the line and the build
    // tools' text
    try testing.expectEqual(127, try shlibTest(&f, r, f.path("w"), &argv, &out));
    try testing.expectEqualStrings(f.fmt("{s}{s}", .{ comp, bt }), f.takeWarnings());
    // R's zig, no make: the build tools' text alone
    const zig = f.path("bin/zig");
    try f.write("bin/zig", f.fmt("#!/bin/sh\n[ \"$1\" = version ] && echo '{d}.{d}.0'\nexit 0\n", .{ builtin.zig_version.major, builtin.zig_version.minor }), .fromMode(0o755));
    try f.env.put("ZIG_BIN", zig);
    try testing.expectEqual(127, try shlibTest(&f, r, f.path("w"), &argv, &out));
    try testing.expectEqualStrings(bt, f.takeWarnings());
    // and make: 3, the line, and R runs make
    _ = try f.touchProgram("mk/make");
    try f.env.put("PATH", f.path("mk"));
    try testing.expectEqual(exit_needs_make, try shlibTest(&f, r, f.path("w"), &argv, &out));
    try testing.expectEqualStrings("rzig-test: " ++ why ++ "\n", f.takeWarnings());
    // Fortran asks for flang too
    try f.touch("w/y.f90");
    try testing.expectEqual(127, try shlibTest(&f, r, f.path("w"), &.{ "--shlib", "--output", "x.so", "--", "x.c", "y.f90" }, &out));
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), "rzig-test: " ++ groups.no_flang ++ "\n"));
    try testing.expectEqualStrings("", out.written());
}
