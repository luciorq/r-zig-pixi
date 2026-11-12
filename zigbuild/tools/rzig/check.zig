//! rzig's check mode (feat-standalone-toolchain B26 a, B32 a): whether a
//! toolchain group's tools are there, before anything is compiled. The
//! install preflight (patch 0009: `--rzig-check=package`, one call per
//! package) and R CMD config (patch 0010: `--rzig-check=build-tools`)
//! call it by CC's name, so the text that names a missing group comes
//! from one place on every channel: rzig. Any of rzig's names takes it,
//! as its only argument (zig-cc, or gcc.exe on Windows):
//!
//!   --rzig-check              the compile lookup: zig (zig-fc: also flang)
//!   --rzig-check=fortran      zig and flang
//!   --rzig-check=build-tools  make as R runs it, found as a shell's
//!                             `command -v` finds it: on unix the first
//!                             word of $MAKE (etc/Renviron sets it), else
//!                             make; on Windows make, whatever MAKE says
//!                             (install.R and R CMD config run make there),
//!                             and sh, which runs configure.win (the
//!                             binutils Makeconf.win names are rzig's own
//!                             names beside it, binutils.zig)
//!   --rzig-check=package      the install preflight for the package in
//!                             the working directory (patch 0009), decided
//!                             as `rzig build` decides (pkgbuild.decide: the
//!                             files, then the Makevars and Makeconf): the
//!                             compilers; flang when Fortran is compiled
//!                             (`packageIn`: tier 1 by the plan's sources,
//!                             tier 2 never, tier 3 and a configure script
//!                             R runs by src/'s top level, either case of
//!                             the f; Fortran a Makevars builds from a
//!                             subdirectory stops later, at zig-fc, with
//!                             the same text); and the build tools when the
//!                             package needs make or R runs a configure
//!                             script (R_ZIG_CONFIGURE=1, from install.R),
//!                             with rzig's own reason in the failing line
//!                             ("<pkg> needs make: <reason>; no make on
//!                             PATH"). Every group the package needs that
//!                             is missing, in one stop: with no compilers
//!                             either, their text first, then the build
//!                             tools' (PHASE4 open point H a). A tier-2
//!                             package whose plan needs make stops, as
//!                             `rzig build` does
//!                             (pkgbuild.buildZigNeedsMake). R_ZIG_C_STD is
//!                             install.R's use_C (the hook's --c-std);
//!                             R_ZIG_PKG_BUILDER=make forces make. Four
//!                             inputs differ from the hook's and are
//!                             recorded (feat-zig-pkg-build PLAN.md):
//!                             CLINK_CPPFLAGS is set after the preflight, a
//!                             user Makevars skips 0009, and use_LTO and
//!                             Windows' --debug are not passed.
//!
//! All there: one line on stdout, what it found, and exit 0. A tool
//! missing: a line that says which, then its group's text (groups.zig), on
//! stderr, and exit 127, as a compile that finds no zig. A build tool PATH
//! does not have that R's own environment has (an environment used
//! without activation) is named in that line as installed, not on PATH,
//! with how to put it there (PHASE4 open point I a). zig is also asked
//! its version: a major.minor other than R's, no version at all, or a zig
//! that did not run (it could not start, or a signal ended it; the line
//! says why), exits 1, after a line that says so and the compilers group's
//! text. R's zig is rzig's own (builtin.zig_version), since the same zig
//! builds both. Compiles do not check the version (`rzig build
//! --shlib` does, below). R_ZIG_NO_PREFLIGHT (non-empty, as the
//! preflight's nzchar test), which skips the preflight, skips this
//! comparison too. `=package` also exits 1 for a tier-2
//! package whose plan needs make, after "<pkg>: src/build.zig cannot be
//! built by make: <reason>" and "<pkg>: the r-zig toolchain is complete:
//! change what the line above names", no group's text, since no group
//! would help [preflight-PF-1, code-6]; 0009 then stops with "this package
//! cannot be built (see above)", as after any exit but 127 (PHASE4 open
//! point J a); and 2 when R_HOME is unset, or
//! R_HOME or the working directory does not resolve (a line names the
//! path and why).
//! Any other `--rzig-check=` value: a usage line and exit 2 (main.zig).
//!
//! `rzig build --shlib` (pkgbuild.zig) stops through `groupsFor`, the
//! check `=package` makes, when an R CMD SHLIB call needs make and a group
//! is missing (feat-shlib-rzig-build F a); and before it builds one, it
//! makes the compilers check through `shlibCompilers`, version included,
//! since R CMD SHLIB has no preflight: a zig that is not R's is make's
//! (exit 3) when the build tools are there [shlib-r-2].
//!
//! On Windows the paths in these lines have `/` only, as rzig's own path
//! has (main.zig's selfExe), where find_zig joins a directory and a name
//! with `\` and PATH's entries have Windows' own. Display only: what runs
//! is the path as found.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const environment = @import("environment.zig");
const find_zig = @import("find_zig.zig");
const flang_rt = @import("flang_rt.zig");
const groups = @import("groups.zig");
const pkgbuild = @import("pkgbuild.zig");
const pkgplan = @import("pkgplan.zig");

pub const flag = "--rzig-check";

pub const Kind = enum { compilers, fortran, build_tools, package };

/// The check `arg` asks for; null when it is none. zig-fc's (`fc`) plain
/// check is fortran's.
pub fn parse(arg: []const u8, fc: bool) error{UnknownCheck}!?Kind {
    if (mem.eql(u8, arg, flag)) return if (fc) .fortran else .compilers;
    if (!mem.startsWith(u8, arg, flag ++ "=")) return null;
    const v = arg[flag.len + 1 ..];
    if (mem.eql(u8, v, "fortran")) return .fortran;
    if (mem.eql(u8, v, "build-tools")) return .build_tools;
    if (mem.eql(u8, v, "package")) return .package;
    return error.UnknownCheck;
}

pub const Result = struct {
    /// 0: all there; 127: a tool is missing; 1: zig is not R's zig, or
    /// a tier-2 package make cannot build; 2: `=package` with no R_HOME,
    /// or a path that does not resolve (the header).
    code: u8,
    /// What it found, for stdout, when code is 0.
    line: []const u8 = "",
};

pub fn run(ctx: *Ctx, kind: Kind) !Result {
    return switch (kind) {
        .compilers => compilers(ctx, false),
        .fortran => compilers(ctx, true),
        .build_tools => buildTools(ctx),
        .package => package(ctx),
    };
}

fn fail(ctx: *Ctx, code: u8, what: []const u8, g: groups.Group) !Result {
    try groups.report(ctx, what, g);
    return .{ .code = code };
}

fn compilers(ctx: *Ctx, fortran: bool) !Result {
    return switch (try compilersFound(ctx, fortran)) {
        .ok => |line| .{ .code = 0, .line = line },
        .missing => |what| fail(ctx, 127, what, .compilers),
        .not_r_zig => |what| fail(ctx, 1, try notRZig(ctx, what), .compilers),
    };
}

/// The compilers check, without its report: what it found (one line), a
/// tool that is missing (127), or a zig that is not R's (1: another
/// major.minor, no version, or it did not run), each as its line says it.
const CompilersFound = union(enum) { ok: []const u8, missing: []const u8, not_r_zig: []const u8 };

fn compilersFound(ctx: *Ctx, fortran: bool) !CompilersFound {
    const zig = (try find_zig.find(ctx)) orelse return .{ .missing = groups.no_zig };
    const fc: ?[]const u8 = if (fortran) (try flang_rt.flang(ctx)) orelse return .{ .missing = groups.no_flang } else null;
    // zig's command with the file found: python3's path for python3 -m ziglang
    const cmd = try mem.concat(ctx.arena, []const u8, &.{ &.{zig.file}, zig.argv[1..] });
    const shown = try display(ctx, try mem.join(ctx.arena, " ", cmd));
    const out = ctx.capture(try mem.concat(ctx.arena, []const u8, &.{ cmd, &.{"version"} }));
    const version = mem.trim(u8, out.stdout, " \t\r\n");
    const v: ?std.SemanticVersion = if (out.ok) std.SemanticVersion.parse(version) catch null else null;
    if (ctx.getenv("R_ZIG_NO_PREFLIGHT") == null) {
        const r = builtin.zig_version;
        if (out.not_run) |why| return .{ .not_r_zig = try ctx.fmt("{s} did not run: {s}", .{ shown, why }) };
        if (v == null) return .{ .not_r_zig = try ctx.fmt("{s} does not say its zig version", .{shown}) };
        if (v.?.major != r.major or v.?.minor != r.minor) {
            return .{ .not_r_zig = try ctx.fmt("{s} is zig {s}, not R's zig {s}", .{ shown, version, groups.this.zig }) };
        }
    }
    const line = try ctx.fmt("compilers ok: zig {s} at {s}", .{ if (v != null) version else "(version unknown)", shown });
    return .{ .ok = if (fc) |p| try ctx.fmt("{s}; flang at {s}", .{ line, try display(ctx, p) }) else line };
}

/// A zig that is not R's, as the failing line says it: with how to skip
/// the check.
fn notRZig(ctx: *Ctx, what: []const u8) ![]const u8 {
    return ctx.fmt("{s} (R_ZIG_NO_PREFLIGHT=1 skips this check)", .{what});
}

/// `rzig build --shlib`'s check before it builds an R CMD SHLIB call
/// (pkgbuild.zig): the compilers check the install preflight makes for a
/// package (patch 0009), which R CMD SHLIB has none of. Without it a zig
/// that is not R's (its flags are for R's zig), where make, with
/// zig-cc, built, and pkgbuild's probe turned FALSE [shlib-r-2]. 0: build;
/// 127 after the compilers group's text: zig or flang is missing; a zig
/// that is not R's: with the build tools there, "<label> needs make:
/// <why>" and 3, so R runs make as with no rzig build; without them, 1
/// after the line and the compilers group's text. R_ZIG_NO_PREFLIGHT
/// skips the version comparison, as for the preflight.
pub fn shlibCompilers(ctx: *Ctx, label: []const u8, fortran: bool) !u8 {
    return switch (try compilersFound(ctx, fortran)) {
        .ok => 0,
        .missing => |what| (try fail(ctx, 127, what, .compilers)).code,
        .not_r_zig => |what| if (try buildToolsFound(ctx) == .ok) blk: {
            ctx.warn("{s} needs make: {s}", .{ label, what });
            break :blk pkgbuild.exit_needs_make;
        } else (try fail(ctx, 1, try notRZig(ctx, what), .compilers)).code,
    };
}

fn buildTools(ctx: *Ctx) !Result {
    return switch (try buildToolsFound(ctx)) {
        .ok => |line| .{ .code = 0, .line = line },
        .missing => |what| fail(ctx, 127, what, .build_tools),
    };
}

const Found = union(enum) { ok: []const u8, missing: []const u8 };

/// The build tools: what was found (one line), or what is missing.
fn buildToolsFound(ctx: *Ctx) !Found {
    // R on Windows runs make whatever MAKE says (install.R, R CMD config)
    const make_var = if (ctx.os == .windows) null else ctx.getenv("MAKE");
    var words = mem.tokenizeScalar(u8, make_var orelse "make", ' ');
    const word = words.next() orelse "make";
    const make = (try command(ctx, word)) orelse {
        const what = if (isPath(word))
            try ctx.fmt("no {s} (MAKE={s})", .{ word, make_var.? })
        else if (make_var) |m|
            try ctx.fmt("no {s} on PATH (MAKE={s})", .{ word, m })
        else
            "no make on PATH";
        return .{ .missing = if (isPath(word)) what else try notOnPath(ctx, what, word) };
    };
    const line = try ctx.fmt("build-tools ok: make at {s}", .{try display(ctx, make)});
    // R runs configure.win and config.sh through sh (install.R, rcmdfn.c)
    if (ctx.os != .windows) return .{ .ok = line };
    const sh = (try find_zig.onPath(ctx, "sh")) orelse return .{ .missing = try notOnPath(ctx, "no sh on PATH", "sh") };
    return .{ .ok = try ctx.fmt("{s}; sh at {s}", .{ line, try display(ctx, sh) }) };
}

/// `what`, the line for a build tool PATH does not have, saying so when R's
/// own environment has it where r-zig-build-tools installs it (PHASE4 open
/// point I a): unix <dir>/bin (conda-forge's make), Windows m2's
/// <dir>/usr/bin (make and sh; <dir> is <root>/Library there). That is an
/// environment used without activation: an IDE pointed at <env>/bin/R, or
/// win-64's R.bat, which adds nothing to PATH. On Windows R itself puts
/// <dir>/usr/bin on PATH, after the group's usr/bin, under R CMD and in
/// sessions (PHASE7 F2 b), so there this line comes only from a check run
/// outside R. Finding the tool stays PATH's (B34's note); this only says
/// why it was not found. The standalone tree and the wheel have none
/// there.
fn notOnPath(ctx: *Ctx, what: []const u8, name: []const u8) ![]const u8 {
    const e = (try environment.own(ctx)) orelse return what;
    const bin = try ctx.fmt("{s}/{s}", .{ e.dir, if (ctx.os == .windows) "usr/bin" else "bin" });
    const p = (try find_zig.inDir(ctx, bin, name)) orelse return what;
    return ctx.fmt("{s}; {s} is installed in R's environment, which is not on PATH: activate it (pixi shell, conda activate) or start R with pixi run", .{ what, try display(ctx, p) });
}

/// A switch in the environment, as install.R sets it: set, not empty, not "0".
fn envSet(ctx: *const Ctx, name: []const u8) bool {
    const v = ctx.getenv(name) orelse return false;
    return v.len > 0 and !mem.eql(u8, v, "0");
}

/// A value in the environment, empty counting as unset.
fn envValue(ctx: *const Ctx, name: []const u8) ?[]const u8 {
    const v = ctx.getenv(name) orelse return null;
    return if (v.len == 0) null else v;
}

/// 0009's own test for Fortran, for a package make builds or a configure
/// script R runs: src/'s top level, either case of the f (R's default
/// OBJECTS rule compiles .f, .f90 and .f95; a package's own rules or its
/// configure script may compile .F too).
fn topLevelFortran(ctx: *Ctx, src_dir: []const u8) bool {
    var d = std.Io.Dir.cwd().openDir(ctx.io, src_dir, .{ .iterate = true }) catch return false;
    defer d.close(ctx.io);
    var it = d.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        if (entry.kind == .directory) continue;
        const n = entry.name;
        const exts = [_][]const u8{ ".f", ".F", ".f90", ".F90", ".f95", ".F95" };
        for (exts) |e| if (mem.endsWith(u8, n, e)) return true;
    }
    return false;
}

/// --rzig-check=package (the header): the preflight for the package in
/// the working directory.
fn package(ctx: *Ctx) !Result {
    const r_home_in = ctx.getenv("R_HOME") orelse {
        ctx.warn("{s}=package needs R_HOME in the environment", .{flag});
        return .{ .code = 2 };
    };
    const r_home = pkgbuild.canonical(ctx, r_home_in) catch return .{ .code = 2 };
    const pkg_dir = pkgbuild.canonical(ctx, ".") catch return .{ .code = 2 };
    return packageIn(ctx, r_home, pkg_dir);
}

/// package() for the package in `pkg_dir` (both paths canonical), where
/// the unit tests call it.
fn packageIn(ctx: *Ctx, r_home: []const u8, pkg_dir: []const u8) !Result {
    const src_dir = try ctx.fmt("{s}/src", .{pkg_dir});
    const name = pkgbuild.packageName(ctx, pkg_dir) orelse std.fs.path.basename(pkg_dir);
    const configure = envSet(ctx, "R_ZIG_CONFIGURE");
    const forced_make = if (ctx.getenv("R_ZIG_PKG_BUILDER")) |b| mem.eql(u8, b, "make") else false;
    const d: pkgbuild.Decision = if (forced_make)
        .{ .tier = .make, .reason = "R_ZIG_PKG_BUILDER=make", .class = .{ .tier = .make } }
    else
        try pkgbuild.decide(ctx, .{
            .r_home = r_home,
            .pkg_dir = pkg_dir,
            .src_dir = src_dir,
            .name = name,
            .c_std = envValue(ctx, "R_ZIG_C_STD"),
            .rzig = ctx.self_exe orelse "rzig",
            // before R's own parse, which says it under rzig build's hook
            // (patch 0013; feat-shlib-rzig-build Am7)
            .warn_cxx_std = true,
        });
    // a tier-2 package make cannot build: no tool would help, stop as
    // `rzig build` stops, before asking for any [preflight-PF-1]. One more
    // line says the toolchain is complete, and what to change: a site
    // Makevars, the Makeconf, a C or C++ standard [code-6]. 0009's stop
    // after an exit other than 127 says the package cannot be built
    // (PHASE4 open point J a)
    if (pkgbuild.buildZigNeedsMake(ctx, name, d)) {
        ctx.warn("{s}: the r-zig toolchain is complete: change what the line above names", .{name});
        return .{ .code = 1 };
    }
    // what the preflight is for: compiled code, or a configure R runs
    if (d.tier == .r_only and !configure) return .{ .code = 0, .line = try ctx.fmt("package ok: {s} has no src/, nothing to compile", .{name}) };
    // flang when Fortran is compiled [preflight-PF-5, records-REC-11]: a
    // configure script R runs may compile any of src/'s, so src/'s top
    // level, either case, whatever the tier (CONSENSUS B); otherwise tier 1
    // the plan's sources (R's default OBJECTS: .f, .f90, .f95); tier 2
    // never, rpkg compiles C and C++ only, so a stray .f is no reason to
    // stop; tier 3 src/'s top level, as 0009 tested before
    const fortran = if (configure) topLevelFortran(ctx, src_dir) else switch (d.tier) {
        .makevars => blk: {
            var any = false;
            for (d.plan.?.sources) |s| if (mem.eql(u8, s.lang, "f") or mem.eql(u8, s.lang, "f9x")) {
                any = true;
            };
            break :blk any;
        },
        .zig => false,
        .make, .r_only => topLevelFortran(ctx, src_dir),
    };
    // make, or a configure R runs: the build tools too, with the reason
    const needs_make = configure or d.tier == .make;
    const why: ?[]const u8 = if (configure) "a configure script R runs" else if (d.tier == .make) d.reason else null;
    const res = try groupsFor(ctx, name, why, fortran);
    if (res.code != 0) return res;
    const tier: []const u8 = switch (d.tier) {
        .r_only => "no src/",
        .makevars => "tier 1 (rzig build)",
        .zig => "tier 2 (rzig build)",
        .make => "needs make",
    };
    const line = try ctx.fmt("package ok: {s} {s}", .{ name, tier });
    if (needs_make) return .{ .code = 0, .line = try ctx.fmt("{s} ({s}); {s}", .{ line, why.?, res.line }) };
    return .{ .code = 0, .line = try ctx.fmt("{s}; {s}", .{ line, res.line }) };
}

/// The groups what `label` builds needs: the compilers (flang too when
/// `fortran`), and when `why` says it needs make, the build tools, whose
/// failing line is "<label> needs make: <why>; <what is missing>". Every
/// missing group in one stop, the compilers' text first, so the user
/// installs what is needed in one round (PHASE4 open point H a). 0 with
/// the found lines; 127 when a group is missing; 1 for a zig that is not
/// R's, where no group would help. The install preflight's check
/// (`packageIn`), and `rzig build --shlib` for an R CMD SHLIB call that
/// needs make (pkgbuild.zig; feat-shlib-rzig-build F a, Cg5, Cc9).
pub fn groupsFor(ctx: *Ctx, label: []const u8, why: ?[]const u8, fortran: bool) !Result {
    const comp = try compilers(ctx, fortran);
    if (comp.code != 0 and comp.code != 127) return comp;
    const bt: ?Found = if (why != null) try buildToolsFound(ctx) else null;
    if (bt) |b| switch (b) {
        .ok => {},
        .missing => |what| return fail(ctx, 127, try ctx.fmt("{s} needs make: {s}; {s}", .{ label, why.?, what }), .build_tools),
    };
    if (comp.code != 0) return comp;
    if (bt) |b| return .{ .code = 0, .line = try ctx.fmt("{s}; {s}", .{ comp.line, b.ok }) };
    return comp;
}

/// A path as the check's lines show it: with `/` only on Windows.
fn display(ctx: *Ctx, path: []const u8) ![]const u8 {
    if (ctx.os != .windows) return path;
    return mem.replaceOwned(u8, ctx.arena, path, "\\", "/");
}

/// `command -v word`: a path (a word with a separator) when it is an
/// executable, else the word on PATH.
fn command(ctx: *Ctx, word: []const u8) !?[]const u8 {
    if (isPath(word)) return find_zig.executable(ctx, word);
    return find_zig.onPath(ctx, word);
}

fn isPath(word: []const u8) bool {
    return mem.findAny(u8, word, if (builtin.os.tag == .windows) "/\\" else "/") != null;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

test parse {
    try testing.expectEqual(Kind.compilers, (try parse("--rzig-check", false)).?);
    try testing.expectEqual(Kind.fortran, (try parse("--rzig-check", true)).?);
    try testing.expectEqual(Kind.fortran, (try parse("--rzig-check=fortran", false)).?);
    try testing.expectEqual(Kind.build_tools, (try parse("--rzig-check=build-tools", true)).?);
    try testing.expectEqual(Kind.package, (try parse("--rzig-check=package", false)).?);
    for ([_][]const u8{ "--rzig-check=make", "--rzig-check=", "--rzig-check=Fortran" }) |x| {
        try testing.expectError(error.UnknownCheck, parse(x, false));
    }
    // anything else is a compile's argument
    for ([_][]const u8{ "-c", "--version", "--rzig-checks", "-rzig-check", "" }) |x| {
        try testing.expect(try parse(x, false) == null);
    }
}

/// A zig stand-in that answers `version` with `v` (a shell script).
fn fakeZig(f: *testutil.Fixture, sub: []const u8, v: []const u8) ![]const u8 {
    try f.write(sub, f.fmt("#!/bin/sh\n[ \"$1\" = version ] && echo '{s}'\nexit 0\n", .{v}), .fromMode(0o755));
    return f.path(sub);
}

/// R's zig as `zig version` prints it, with another patch level.
const same_zig = std.fmt.comptimePrint("{d}.{d}.9", .{ builtin.zig_version.major, builtin.zig_version.minor });

test "compilers: the zig found and its version, exit 0" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const zig = try fakeZig(&f, "bin/zig", same_zig);
    try f.env.put("ZIG_BIN", zig);
    var r = try run(c, .compilers);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}", .{ same_zig, zig }), r.line);
    // a dev build of R's major.minor
    const dev = std.fmt.comptimePrint("{d}.{d}.0-dev.2320+1e770dbef", .{ builtin.zig_version.major, builtin.zig_version.minor });
    _ = try fakeZig(&f, "bin/zig", dev);
    r = try run(c, .compilers);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}", .{ dev, zig }), r.line);
    // the compilers group's own zig (the lookup is find_zig's)
    _ = f.env.swapRemove("ZIG_BIN");
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    const tc = try fakeZig(&f, "tree/lib/R/bin/toolchain/zig/zig", same_zig);
    r = try run(c, .compilers);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}", .{ same_zig, tc }), r.line);
    // python3 -m ziglang, asked through the python3 found
    try f.tmp.dir.deleteFile(testing.io, "tree/lib/R/bin/toolchain/zig/zig");
    try f.write("py/python3", "#!/bin/sh\n[ \"$3\" = version ] && echo '" ++ same_zig ++ "'\nexit 0\n", .fromMode(0o755));
    try f.env.put("PATH", f.path("py"));
    r = try run(c, .compilers);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s} -m ziglang", .{ same_zig, f.path("py/python3") }), r.line);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "compilers: no zig, exit 127 and the compilers group's text" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("PATH", f.path("nothing"));
    const want = f.fmt("rzig-test: " ++ groups.no_zig ++ "\n{s}", .{try groups.text(c.arena, .compilers, groups.this)});
    for ([_]Kind{ .compilers, .fortran }) |k| {
        try testing.expectEqual(127, (try run(c, k)).code);
        try testing.expectEqualStrings(want, f.takeWarnings());
    }
    // R_ZIG_NO_PREFLIGHT does not make a missing zig pass
    try f.env.put("R_ZIG_NO_PREFLIGHT", "1");
    try testing.expectEqual(127, (try run(c, .compilers)).code);
    try testing.expectEqualStrings(want, f.takeWarnings());
}

test "compilers: another major.minor, exit 1, unless R_ZIG_NO_PREFLIGHT" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const text = try groups.text(c.arena, .compilers, groups.this);
    const other = std.fmt.comptimePrint("{d}.{d}.0", .{ builtin.zig_version.major, builtin.zig_version.minor + 1 });
    const zig = try fakeZig(&f, "bin/zig", other);
    try f.env.put("ZIG_BIN", zig);
    try testing.expectEqual(1, (try run(c, .compilers)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: {s} is zig {s}, not R's zig {s} (R_ZIG_NO_PREFLIGHT=1 skips this check)\n{s}", .{ zig, other, groups.this.zig, text }), f.takeWarnings());
    // a zig that does not say its version
    try f.write("bin/zig", "#!/bin/sh\nexit 3\n", .fromMode(0o755));
    try testing.expectEqual(1, (try run(c, .compilers)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: {s} does not say its zig version (R_ZIG_NO_PREFLIGHT=1 skips this check)\n{s}", .{ zig, text }), f.takeWarnings());
    // empty is unset, as R's nzchar() test in the preflight
    try f.env.put("R_ZIG_NO_PREFLIGHT", "");
    try testing.expectEqual(1, (try run(c, .compilers)).code);
    _ = f.takeWarnings();
    // skipped: what it found, and 0
    try f.env.put("R_ZIG_NO_PREFLIGHT", "1");
    var r = try run(c, .compilers);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig (version unknown) at {s}", .{zig}), r.line);
    _ = try fakeZig(&f, "bin/zig", other);
    r = try run(c, .compilers);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}", .{ other, zig }), r.line);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "fortran: zig and flang; no flang, exit 127 and the compilers group's text" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const zig = try fakeZig(&f, "bin/zig", same_zig);
    try f.env.put("ZIG_BIN", zig);
    try f.env.put("PATH", f.path("nothing"));
    try testing.expectEqual(127, (try run(c, .fortran)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: " ++ groups.no_flang ++ "\n{s}", .{try groups.text(c.arena, .compilers, groups.this)}), f.takeWarnings());
    // the plain check does not look for flang
    try testing.expectEqual(0, (try run(c, .compilers)).code);
    const fc = try f.touchProgram("fl/flang");
    try f.env.put("PATH", f.path("fl"));
    const r = try run(c, .fortran);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}; flang at {s}", .{ same_zig, zig, fc }), r.line);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "build-tools: make as R runs it; on Windows also sh" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const text = try groups.text(c.arena, .build_tools, groups.this);
    try f.env.put("PATH", f.path("p"));
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no make on PATH\n{s}", .{text}), f.takeWarnings());
    const make = try f.touchProgram("p/make");
    var r = try run(c, .build_tools);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}", .{make}), r.line);
    // MAKE's first word, on PATH
    try f.env.put("MAKE", "gmake -j4");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no gmake on PATH (MAKE=gmake -j4)\n{s}", .{text}), f.takeWarnings());
    const gmake = try f.touchProgram("p/gmake");
    r = try run(c, .build_tools);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}", .{gmake}), r.line);
    // a path: an absolute MAKE (MAKE=/opt/gnu/bin/make)
    try f.env.put("MAKE", f.path("gnu/bin/make"));
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no {s} (MAKE={s})\n{s}", .{ f.path("gnu/bin/make"), f.path("gnu/bin/make"), text }), f.takeWarnings());
    _ = try f.touchProgram("gnu/bin/make");
    r = try run(c, .build_tools);
    try testing.expectEqual(0, r.code);
    try testing.expect(mem.startsWith(u8, r.line, f.fmt("build-tools ok: make at {s}", .{f.path("gnu/bin/make")})));
    // empty is unset
    try f.env.put("MAKE", "");
    r = try run(c, .build_tools);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}", .{make}), r.line);
    // Windows: make whatever MAKE says, and sh
    c.os = .windows;
    c.self_exe = f.path("env/Library/lib/R/bin/toolchain/gcc.exe");
    try f.env.put("MAKE", "nosuchmake -j4");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no sh on PATH\n{s}", .{text}), f.takeWarnings());
    const sh = try f.touchProgram("p/sh");
    r = try run(c, .build_tools);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}; sh at {s}", .{ slashed(&f, make), slashed(&f, sh) }), r.line);
    // nothing beside rzig is asked for: its binutils are its own names
    c.self_exe = null;
    try testing.expectEqual(0, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings("", f.takeWarnings());
}

/// `path` with `/` only, as the check shows it on Windows.
fn slashed(f: *testutil.Fixture, path: []const u8) []const u8 {
    return mem.replaceOwned(u8, f.ctx.arena, path, "\\", "/") catch @panic("OOM");
}

test "Windows: one separator in the lines, `/` (display only)" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    // a PATH entry in Windows' form, <root>/w\bin (on a unix host a
    // directory with `\` in its name stands in for one), and find_zig's
    // <entry>\make.exe on a Windows host
    const w = f.path("w\\bin");
    const make = try f.touchProgram("w\\bin/make");
    const sh = try f.touchProgram("w\\bin/sh");
    try testing.expect(mem.findScalar(u8, make, '\\') != null);
    try f.env.put("PATH", w);
    c.self_exe = f.path("env/Library/lib/R/bin/toolchain/gcc.exe");
    var r = try run(c, .build_tools);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}; sh at {s}", .{ slashed(&f, make), slashed(&f, sh) }), r.line);
    try testing.expect(mem.findScalar(u8, r.line, '\\') == null);
    // zig (a shell-script stand-in), its version and flang
    if (builtin.os.tag == .windows) return;
    const zig = try fakeZig(&f, "w\\bin/zig", same_zig);
    const fc = try f.touchProgram("w\\bin/flang");
    r = try run(c, .fortran);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}; flang at {s}", .{ same_zig, slashed(&f, zig), slashed(&f, fc) }), r.line);
    const other = std.fmt.comptimePrint("{d}.{d}.0", .{ builtin.zig_version.major, builtin.zig_version.minor + 1 });
    _ = try fakeZig(&f, "w\\bin/zig", other);
    try testing.expectEqual(1, (try run(c, .compilers)).code);
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), f.fmt("rzig-test: {s} is zig {s}, ", .{ slashed(&f, zig), other })));
    // other OSes keep the path as found
    c.os = .linux;
    _ = try fakeZig(&f, "w\\bin/zig", same_zig);
    r = try run(c, .compilers);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig {s} at {s}", .{ same_zig, zig }), r.line);
}

test "package: flang by tier, never for tier 2, by src/'s top level with a configure script" {
    // [preflight-PF-5, records-REC-11]
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    const zig = try fakeZig(&f, "bin/zig", same_zig);
    try f.env.put("ZIG_BIN", zig);
    try f.env.put("PATH", f.path("nothing"));
    const ok = f.fmt("compilers ok: zig {s} at {s}", .{ same_zig, zig });
    const no_flang = f.fmt("rzig-test: " ++ groups.no_flang ++ "\n{s}", .{try groups.text(c.arena, .compilers, groups.this)});
    const bt = try groups.text(c.arena, .build_tools, groups.this);
    // tier 2 with a stray top-level .f: rpkg compiles C and C++ only
    try f.touch("z/src/build.zig");
    try f.touch("z/src/x.f");
    var res = try packageIn(c, r, f.path("z"));
    try testing.expectEqual(0, res.code);
    try testing.expectEqualStrings(f.fmt("package ok: z tier 2 (rzig build); {s}", .{ok}), res.line);
    // tier 1: the plan's sources, R's default OBJECTS (no .F)
    try f.touch("t/src/a.c");
    try f.touch("t/src/x.F");
    res = try packageIn(c, r, f.path("t"));
    try testing.expectEqualStrings(f.fmt("package ok: t tier 1 (rzig build); {s}", .{ok}), res.line);
    try f.touch("t/src/y.f90");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("t"))).code);
    try testing.expectEqualStrings(no_flang, f.takeWarnings());
    // tier 3 (a Makevars rule): src/'s top level, either case; no make
    // either, so the build tools' text follows (PHASE4 open point H a)
    try f.write("m/src/Makevars", "all: $(SHLIB)\n", .default_file);
    try f.touch("m/src/x.F");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("m"))).code);
    try testing.expectEqualStrings(f.fmt("{s}rzig-test: m needs make: src/Makevars has a rule or target line: 'all: $(SHLIB)'; no make on PATH\n{s}", .{ no_flang, bt }), f.takeWarnings());
    // a configure script R runs: src/'s top level whatever the tier, so a
    // tier-2 package's .F too (CONSENSUS B)
    try f.touch("zF/src/build.zig");
    try f.touch("zF/src/x.F");
    res = try packageIn(c, r, f.path("zF"));
    try testing.expectEqual(0, res.code);
    try f.env.put("R_ZIG_CONFIGURE", "1");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("zF"))).code);
    try testing.expectEqualStrings(f.fmt("{s}rzig-test: zF needs make: a configure script R runs; no make on PATH\n{s}", .{ no_flang, bt }), f.takeWarnings());
    // with flang: then the build tools, a configure script's reason first
    const fc = try f.touchProgram("fl/flang");
    try f.env.put("PATH", f.path("fl"));
    try testing.expectEqual(127, (try packageIn(c, r, f.path("zF"))).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: zF needs make: a configure script R runs; no make on PATH\n{s}", .{bt}), f.takeWarnings());
    const make = try f.touchProgram("fl/make");
    res = try packageIn(c, r, f.path("zF"));
    try testing.expectEqual(0, res.code);
    try testing.expectEqualStrings(f.fmt("package ok: zF tier 2 (rzig build) (a configure script R runs); {s}; flang at {s}; build-tools ok: make at {s}", .{ ok, fc, make }), res.line);
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "package: every missing group in one stop, the compilers' text first" {
    // PHASE4 open point H (a)
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.env.put("PATH", f.path("nothing"));
    const no_zig = f.fmt("rzig-test: " ++ groups.no_zig ++ "\n{s}", .{try groups.text(c.arena, .compilers, groups.this)});
    const bt = try groups.text(c.arena, .build_tools, groups.this);
    // an R-only package with a configure script R runs, neither group:
    // both texts, one 127
    try f.write("cf/DESCRIPTION", "Package: cf\n", .default_file);
    try f.env.put("R_ZIG_CONFIGURE", "1");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("cf"))).code);
    try testing.expectEqualStrings(f.fmt("{s}rzig-test: cf needs make: a configure script R runs; no make on PATH\n{s}", .{ no_zig, bt }), f.takeWarnings());
    // the build tools there: the compilers' text alone
    _ = try f.touchProgram("mk/make");
    try f.env.put("PATH", f.path("mk"));
    try testing.expectEqual(127, (try packageIn(c, r, f.path("cf"))).code);
    try testing.expectEqualStrings(no_zig, f.takeWarnings());
    // a tier-1 package needs no make: the compilers' text alone, either way
    _ = f.env.swapRemove("R_ZIG_CONFIGURE");
    try f.touch("t/src/a.c");
    for ([_][]const u8{ "nothing", "mk" }) |p| {
        try f.env.put("PATH", f.path(p));
        try testing.expectEqual(127, (try packageIn(c, r, f.path("t"))).code);
        try testing.expectEqualStrings(no_zig, f.takeWarnings());
    }
    // a zig that is not R's (1): its line and the compilers' text alone,
    // since no group would help
    if (builtin.os.tag == .windows) return; // shell-script stand-ins below
    const other = std.fmt.comptimePrint("{d}.{d}.0", .{ builtin.zig_version.major, builtin.zig_version.minor + 1 });
    try f.env.put("ZIG_BIN", try fakeZig(&f, "bin/zig", other));
    try f.env.put("R_ZIG_CONFIGURE", "1");
    try f.env.put("PATH", f.path("nothing"));
    try testing.expectEqual(1, (try packageIn(c, r, f.path("cf"))).code);
    const w = f.takeWarnings();
    try testing.expect(mem.find(u8, w, "\nCompiling needs the r-zig compilers for R ") != null);
    try testing.expect(mem.find(u8, w, "Building packages needs") == null);
}

test "build-tools: installed in R's environment, not on PATH, named as such" {
    // PHASE4 open point I (a): an environment used without activation
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const text = try groups.text(c.arena, .build_tools, groups.this);
    const tail = "is installed in R's environment, which is not on PATH: activate it (pixi shell, conda activate) or start R with pixi run";
    try f.env.put("PATH", f.path("nothing"));
    try f.tmp.dir.createDirPath(testing.io, "env/lib/R/bin/toolchain");
    c.self_exe = f.path("env/lib/R/bin/toolchain/zig-cc");
    // in neither: today's line
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no make on PATH\n{s}", .{text}), f.takeWarnings());
    // conda-forge's make in <env>/bin
    const make = try f.touchProgram("env/bin/make");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no make on PATH; {s} {s}\n{s}", .{ make, tail, text }), f.takeWarnings());
    // MAKE's first word, as R runs it; a path is not PATH's matter
    try f.env.put("MAKE", "make -j4");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no make on PATH (MAKE=make -j4); {s} {s}\n{s}", .{ make, tail, text }), f.takeWarnings());
    try f.env.put("MAKE", f.path("gnu/make"));
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no {s} (MAKE={s})\n{s}", .{ f.path("gnu/make"), f.path("gnu/make"), text }), f.takeWarnings());
    _ = f.env.swapRemove("MAKE");
    // on PATH: found there, as before (B34's note)
    try f.env.put("PATH", f.path("env/bin"));
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}", .{make}), (try run(c, .build_tools)).line);
    try f.env.put("PATH", f.path("nothing"));
    // the preflight's line, after the package's reason
    if (builtin.os.tag != .windows) { // a shell-script stand-in for zig
        const r = try pkgplan.rHome(&f);
        try f.env.put("ZIG_BIN", try fakeZig(&f, "bin/zig", same_zig));
        try f.write("m/src/Makevars", "all: $(SHLIB)\n", .default_file);
        try f.touch("m/src/a.c");
        try testing.expectEqual(127, (try packageIn(c, r, f.path("m"))).code);
        try testing.expectEqualStrings(f.fmt("rzig-test: m needs make: src/Makevars has a rule or target line: 'all: $(SHLIB)'; no make on PATH; {s} {s}\n{s}", .{ make, tail, text }), f.takeWarnings());
    }
    // Windows: m2's make and sh in <root>/Library/usr/bin
    c.os = .windows;
    try f.tmp.dir.createDirPath(testing.io, "wenv/Library/lib/R/bin/toolchain");
    c.self_exe = f.path("wenv/Library/lib/R/bin/toolchain/gcc.exe");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no make on PATH\n{s}", .{text}), f.takeWarnings());
    const wmake = try f.touchProgram("wenv/Library/usr/bin/make");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no make on PATH; {s} {s}\n{s}", .{ slashed(&f, wmake), tail, text }), f.takeWarnings());
    // make on PATH, sh only in the environment
    _ = try f.touchProgram("p/make");
    try f.env.put("PATH", f.path("p"));
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no sh on PATH\n{s}", .{text}), f.takeWarnings());
    const wsh = try f.touchProgram("wenv/Library/usr/bin/sh");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no sh on PATH; {s} {s}\n{s}", .{ slashed(&f, wsh), tail, text }), f.takeWarnings());
}

test "package: a tier-2 package whose plan needs make, 1 and why, no group's text" {
    // [preflight-PF-1]: make would ignore src/build.zig
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.env.put("PATH", f.path("nothing"));
    try f.write("z/DESCRIPTION", "Package: zpkg\n", .default_file);
    try f.touch("z/src/build.zig");
    try f.write("ccache.mk", "CC = ccache gcc\n", .default_file);
    try f.env.put("R_MAKEVARS_USER", f.path("ccache.mk"));
    try testing.expectEqual(1, (try packageIn(c, r, f.path("z"))).code);
    // and that the toolchain is complete, which 0009's stop after it does
    // not say [code-6]
    try testing.expectEqualStrings(f.fmt("rzig-test: zpkg: src/build.zig cannot be built by make: CC = ccache is not a compiler of R's toolchain ({s}/bin/toolchain)\n" ++
        "rzig-test: zpkg: the r-zig toolchain is complete: change what the line above names\n", .{r}), f.takeWarnings());
    // a tier-1 package with that Makevars needs make, as before
    try f.touch("t/src/a.c");
    if (builtin.os.tag == .windows) return; // shell-script stand-ins below
    try f.env.put("ZIG_BIN", try fakeZig(&f, "bin/zig", same_zig));
    try testing.expectEqual(127, (try packageIn(c, r, f.path("t"))).code);
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), f.fmt("rzig-test: t needs make: CC = ccache is not a compiler of R's toolchain ({s}/bin/toolchain); no make on PATH\n", .{r})));
}

test "package on Windows: a configure.win script needs make, its reason before the missing make" {
    // [preflight-PF-8]
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const r = try pkgplan.rHome(&f);
    try f.env.put("ZIG_BIN", try fakeZig(&f, "bin/zig", same_zig));
    _ = try f.touchProgram("p/sh");
    try f.env.put("PATH", f.path("p"));
    c.os = .windows;
    c.self_exe = f.path("env/Library/lib/R/bin/toolchain/gcc.exe");
    const text = try groups.text(c.arena, .build_tools, groups.this);
    try f.touch("w/configure.win");
    try f.touch("w/src/a.c");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("w"))).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: w needs make: a configure.win script; no make on PATH\n{s}", .{text}), f.takeWarnings());
    // configure.ucrt first, as R runs it
    try f.touch("w/configure.ucrt");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("w"))).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: w needs make: a configure.ucrt script; no make on PATH\n{s}", .{text}), f.takeWarnings());
    // R_ZIG_CONFIGURE=1 (0009 runs it): that reason
    try f.env.put("R_ZIG_CONFIGURE", "1");
    try testing.expectEqual(127, (try packageIn(c, r, f.path("w"))).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: w needs make: a configure script R runs; no make on PATH\n{s}", .{text}), f.takeWarnings());
}

test "compilers: a zig that does not run, exit 1 and why" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const text = try groups.text(c.arena, .compilers, groups.this);
    const tail = f.fmt(" (R_ZIG_NO_PREFLIGHT=1 skips this check)\n{s}", .{text});
    // an executable file that is no program: it cannot start
    const zig = try f.touchProgram("bin/zig");
    try f.env.put("ZIG_BIN", zig);
    try testing.expectEqual(1, (try run(c, .compilers)).code);
    const w = f.takeWarnings();
    try testing.expect(mem.startsWith(u8, w, f.fmt("rzig-test: {s} did not run: ", .{zig})));
    try testing.expect(mem.endsWith(u8, w, tail));
    // R_ZIG_NO_PREFLIGHT skips it, as the version check
    try f.env.put("R_ZIG_NO_PREFLIGHT", "1");
    const r = try run(c, .compilers);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("compilers ok: zig (version unknown) at {s}", .{zig}), r.line);
    _ = f.env.swapRemove("R_ZIG_NO_PREFLIGHT");
    if (builtin.os.tag == .windows) return; // shell-script stand-ins below
    try testing.expectEqualStrings(f.fmt("rzig-test: {s} did not run: InvalidExe{s}", .{ zig, tail }), w);
    // one a signal ends
    try f.write("bin/zig", "#!/bin/sh\nkill -9 $$\n", .fromMode(0o755));
    try testing.expectEqual(1, (try run(c, .compilers)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: {s} did not run: killed by signal 9{s}", .{ zig, tail }), f.takeWarnings());
    // one that ran and printed nothing, whatever its exit code: no version
    for ([_][]const u8{ "exit 0", "exit 3" }) |body| {
        try f.write("bin/zig", f.fmt("#!/bin/sh\n{s}\n", .{body}), .fromMode(0o755));
        try testing.expectEqual(1, (try run(c, .compilers)).code);
        try testing.expectEqualStrings(f.fmt("rzig-test: {s} does not say its zig version{s}", .{ zig, tail }), f.takeWarnings());
    }
}
