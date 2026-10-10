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
//! 2 usage, 1 failed. R_HOME from the environment, as under R.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const pkgplan = @import("pkgplan.zig");
const find_zig = @import("find_zig.zig");
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

/// `path` absolute with `/` separators, as rzig keeps every path.
fn canonical(ctx: *Ctx, path: []const u8) ![]const u8 {
    const real = Io.Dir.cwd().realPathFileAlloc(ctx.io, path, ctx.arena) catch |err| {
        ctx.warn("build: {s}: {t}", .{ path, err });
        return error.BadPath;
    };
    return slashes(ctx, real);
}

fn slashes(ctx: *Ctx, p: []const u8) ![]const u8 {
    if (builtin.os.tag != .windows) return p;
    return mem.replaceOwned(u8, ctx.arena, p, "\\", "/");
}

/// DESCRIPTION's `Package:` field.
fn packageName(ctx: *Ctx, pkg_dir: []const u8) ?[]const u8 {
    const text = Io.Dir.cwd().readFileAlloc(ctx.io, ctx.fmt("{s}/DESCRIPTION", .{pkg_dir}) catch return null, ctx.arena, .limited(1 << 20)) catch return null;
    var it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (mem.startsWith(u8, line, "Package:")) return mem.trim(u8, line["Package:".len..], " \t\r");
    }
    return null;
}

/// install.R's makevars_site(): R_MAKEVARS_SITE, else etc<R_ARCH>/Makevars.site.
fn makevarsSite(ctx: *Ctx, r_home: []const u8, r_arch: []const u8) !?[]const u8 {
    const f = ctx.getenv("R_MAKEVARS_SITE") orelse try ctx.fmt("{s}/etc{s}/Makevars.site", .{ r_home, r_arch });
    return if (ctx.isFile(f)) f else null;
}

/// install.R's makevars_user(): R_MAKEVARS_USER; else, on Windows with
/// R_ARCH /x64, ~/.R/Makevars.ucrt then ~/.R/Makevars.win64, then
/// ~/.R/Makevars.win; on unix ~/.R/Makevars-<R_PLATFORM>; then
/// ~/.R/Makevars. `~` as R expands it: HOME, else R_USER, else USERPROFILE.
fn makevarsUser(ctx: *Ctx, r_arch: []const u8) !?[]const u8 {
    if (ctx.getenv("R_MAKEVARS_USER")) |f| return if (ctx.isFile(f)) f else null;
    const home = ctx.getenv("HOME") orelse ctx.getenv("R_USER") orelse ctx.getenv("USERPROFILE") orelse return null;
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
    const r_arch = ctx.getenv("R_ARCH") orelse if (ctx.os == .windows) "/x64" else "";

    var planner: pkgplan.Planner = .{ .ctx = ctx };
    const class = planner.classify(pkg_dir, src_dir) catch |err| switch (err) {
        error.NeedsMake => return needsMake(ctx, name, planner.reason),
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (args.classify) {
        try stdoutPrint(ctx, "{t}\n", .{class.tier});
        return 0;
    }
    switch (class.tier) {
        .r_only => {
            if (isSet(ctx, "RZIG_TRACE")) ctx.warn("{s}: no src/, nothing to compile", .{name});
            return 0;
        },
        .make => return needsMake(ctx, name, class.reason),
        .makevars, .zig => {},
    }

    const rzig_path = ctx.self_exe orelse "rzig";
    var plan = planner.plan(.{
        .r_home = r_home,
        .pkg_dir = pkg_dir,
        .src_dir = src_dir,
        .name = name,
        .linkingto = if (args.linkingto.items.len > 0) args.linkingto.items else null,
        .cxx_std = args.cxx_std,
        .c_std = args.c_std,
        .use_lto = args.use_lto,
        .debug = args.debug,
        .makevars_site = try makevarsSite(ctx, r_home, r_arch),
        .makevars_user = try makevarsUser(ctx, r_arch),
        .rzig = rzig_path,
    }, class) catch |err| switch (err) {
        error.NeedsMake => return needsMake(ctx, name, planner.reason),
        error.OutOfMemory => return error.OutOfMemory,
    };

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

    const cache_dir = args.cache_dir orelse try ctx.fmt("{s}/zig-build", .{try cache.root(ctx)});
    const zig = find_zig.find(ctx) catch |err| {
        ctx.warn("no zig to build with: {t}", .{err});
        return 1;
    };
    try reportCompilers(ctx, &plan, class.tier, zig);
    // zig build makes an (empty) .zig-cache in a path dependency's directory,
    // the package's src/ here; leave src/ as it was found
    const dep_cache = try ctx.fmt("{s}/.zig-cache", .{src_dir});
    const dep_cache_existed = class.tier == .zig and ctx.exists(dep_cache);
    var cmd: std.ArrayList([]const u8) = .empty;
    try cmd.appendSlice(ctx.arena, zig);
    try cmd.appendSlice(ctx.arena, &.{ "build", "--build-file", build_file, "--cache-dir", cache_dir, "--prefix", out, try ctx.fmt("-Dplan={s}", .{plan_path}) });
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
    const keep = args.keep_root or isSet(ctx, "RZIG_KEEP_ROOT");
    if (code != 0) {
        if (keep) ctx.warn("zig build failed ({d}); the build root is kept in {s}", .{ code, root }) else ctx.warn("zig build failed ({d})", .{code});
    }
    if (!keep) Io.Dir.cwd().deleteTree(ctx.io, root) catch |err| ctx.warn("cannot remove {s}: {t}", .{ root, err });
    return if (code != 0) 1 else 0;
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

test "arguments" {
    const testutil = @import("testutil.zig");
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
