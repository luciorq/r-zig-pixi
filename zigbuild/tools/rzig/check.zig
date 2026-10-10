//! rzig's check mode (feat-standalone-toolchain B26 a, B32 a): whether a
//! toolchain group's tools are there, before anything is compiled. The
//! install preflight (patch 0009) and R CMD config (patch 0010) are to call
//! it (phase 3), so the text that names a missing group comes from one
//! place on every channel: rzig. Any of rzig's names takes it, as its only
//! argument (zig-cc, or gcc.exe on Windows):
//!
//!   --rzig-check              the compile lookup: zig (zig-fc: also flang)
//!   --rzig-check=fortran      zig and flang
//!   --rzig-check=build-tools  make as R runs it, found as a shell's
//!                             `command -v` finds it: on unix the first
//!                             word of $MAKE (etc/Renviron sets it), else
//!                             make; on Windows make, whatever MAKE says
//!                             (install.R and R CMD config run make there),
//!                             and sh, which runs configure.win
//!
//! All there: one line on stdout, what it found, and exit 0. A tool
//! missing: a line that says which, then its group's text (groups.zig), on
//! stderr, and exit 127, as a compile that finds no zig. zig is also asked
//! its version: a major.minor other than R's, or no version at all, exits
//! 1, after a line that says so and the compilers group's text. R's zig is
//! rzig's own (builtin.zig_version), since the same zig builds both.
//! Compiles do not check the version. R_ZIG_NO_PREFLIGHT (non-empty, as
//! the preflight's nzchar test), which skips the preflight, skips this
//! comparison too. Any other `--rzig-check=` value: a usage line and exit
//! 2 (main.zig).
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const find_zig = @import("find_zig.zig");
const flang_rt = @import("flang_rt.zig");
const groups = @import("groups.zig");

pub const flag = "--rzig-check";

pub const Kind = enum { compilers, fortran, build_tools };

/// The check `arg` asks for; null when it is none. zig-fc's (`fc`) plain
/// check is fortran's.
pub fn parse(arg: []const u8, fc: bool) error{UnknownCheck}!?Kind {
    if (mem.eql(u8, arg, flag)) return if (fc) .fortran else .compilers;
    if (!mem.startsWith(u8, arg, flag ++ "=")) return null;
    const v = arg[flag.len + 1 ..];
    if (mem.eql(u8, v, "fortran")) return .fortran;
    if (mem.eql(u8, v, "build-tools")) return .build_tools;
    return error.UnknownCheck;
}

pub const Result = struct {
    /// 0: all there; 127: a tool is missing; 1: zig is not R's zig.
    code: u8,
    /// What it found, for stdout, when code is 0.
    line: []const u8 = "",
};

pub fn run(ctx: *Ctx, kind: Kind) !Result {
    return switch (kind) {
        .compilers => compilers(ctx, false),
        .fortran => compilers(ctx, true),
        .build_tools => buildTools(ctx),
    };
}

fn fail(ctx: *Ctx, code: u8, what: []const u8, g: groups.Group) !Result {
    try groups.report(ctx, what, g);
    return .{ .code = code };
}

fn compilers(ctx: *Ctx, fortran: bool) !Result {
    const zig = (try find_zig.find(ctx)) orelse return fail(ctx, 127, groups.no_zig, .compilers);
    const fc: ?[]const u8 = if (fortran) (try flang_rt.flang(ctx)) orelse return fail(ctx, 127, groups.no_flang, .compilers) else null;
    // zig's command with the file found: python3's path for python3 -m ziglang
    const cmd = try mem.concat(ctx.arena, []const u8, &.{ &.{zig.file}, zig.argv[1..] });
    const shown = try mem.join(ctx.arena, " ", cmd);
    const out = ctx.capture(try mem.concat(ctx.arena, []const u8, &.{ cmd, &.{"version"} }));
    const version = mem.trim(u8, out.stdout, " \t\r\n");
    const v: ?std.SemanticVersion = if (out.ok) std.SemanticVersion.parse(version) catch null else null;
    if (ctx.getenv("R_ZIG_NO_PREFLIGHT") == null) {
        const r = builtin.zig_version;
        if (v == null) return fail(ctx, 1, try ctx.fmt("{s} does not say its zig version (R_ZIG_NO_PREFLIGHT=1 skips this check)", .{shown}), .compilers);
        if (v.?.major != r.major or v.?.minor != r.minor) {
            return fail(ctx, 1, try ctx.fmt("{s} is zig {s}, not R's zig {s} (R_ZIG_NO_PREFLIGHT=1 skips this check)", .{ shown, version, groups.this.zig }), .compilers);
        }
    }
    const line = try ctx.fmt("compilers ok: zig {s} at {s}", .{ if (v != null) version else "(version unknown)", shown });
    return .{ .code = 0, .line = if (fc) |p| try ctx.fmt("{s}; flang at {s}", .{ line, p }) else line };
}

fn buildTools(ctx: *Ctx) !Result {
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
        return fail(ctx, 127, what, .build_tools);
    };
    const line = try ctx.fmt("build-tools ok: make at {s}", .{make});
    // R runs configure.win and config.sh through sh (install.R, rcmdfn.c)
    if (ctx.os != .windows) return .{ .code = 0, .line = line };
    const sh = (try find_zig.onPath(ctx, "sh")) orelse return fail(ctx, 127, "no sh on PATH", .build_tools);
    return .{ .code = 0, .line = try ctx.fmt("{s}; sh at {s}", .{ line, sh }) };
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
    // a path (minimal's etc/Renviron: R_HOME/bin/toolchain/make)
    try f.env.put("MAKE", f.path("tc/make"));
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no {s} (MAKE={s})\n{s}", .{ f.path("tc/make"), f.path("tc/make"), text }), f.takeWarnings());
    _ = try f.touchProgram("tc/make");
    r = try run(c, .build_tools);
    try testing.expectEqual(0, r.code);
    try testing.expect(mem.startsWith(u8, r.line, f.fmt("build-tools ok: make at {s}", .{f.path("tc/make")})));
    // empty is unset
    try f.env.put("MAKE", "");
    r = try run(c, .build_tools);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}", .{make}), r.line);
    // Windows: make whatever MAKE says, and sh too
    c.os = .windows;
    try f.env.put("MAKE", "nosuchmake -j4");
    try testing.expectEqual(127, (try run(c, .build_tools)).code);
    try testing.expectEqualStrings(f.fmt("rzig-test: no sh on PATH\n{s}", .{text}), f.takeWarnings());
    const sh = try f.touchProgram("p/sh");
    r = try run(c, .build_tools);
    try testing.expectEqual(0, r.code);
    try testing.expectEqualStrings(f.fmt("build-tools ok: make at {s}; sh at {s}", .{ make, sh }), r.line);
    try testing.expectEqualStrings("", f.takeWarnings());
}
