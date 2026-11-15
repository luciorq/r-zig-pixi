//! `rzig config`: R CMD config without make and without sh. R's
//! src/scripts/config asks make for `$(VAR)` of etc${R_ARCH}/Makeconf, the
//! site's and the user's Makevars (`make -s -f Makeconf -f config.mk
//! [-f site] [-f user] print R_HOME=... VAR=...`, config.mk's recipe being
//! `@echo $($(VAR))`). This does the same with makefile.zig's evaluator
//! and shellwords.zig's reading of the echo line, so the query every build
//! helper runs first (pkgbuild, pak, a package's configure script) needs
//! neither the build-tools group nor sh. R CMD runs it on every OS (patch
//! 0010: Rcmd's dispatch on unix, rcmdfn.c on Windows); bin/config and
//! bin/config.sh are not installed (feat-config-rzig PLAN.md).
//!
//! It follows the script step by step: the options in order until the
//! first empty argument, the messages and exit codes, the variable lists
//! and the help text (config_usage.txt is the script's text, Windows' lines
//! after it when R_OSTYPE is windows), the files it reads and in which
//! order. scripts/config-parity.sh compares both on an installed tree.
//!
//! What make would have to run cannot be answered: `$(shell)` (and the
//! other functions makefile.zig lacks) in an `:=` or a conditional, a
//! `define`, `!=`, or a recursive value that needs one when it is printed.
//! Then it says which construct, in which file and line, and exits 2
//! (user's decision 2026-11-13, no fallback to make). A recursive value
//! that holds `$(shell)` but is not printed does no harm.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const stdio = @import("stdio.zig");
const makefile = @import("makefile.zig");
const shellwords = @import("shellwords.zig");

/// The script's `$Revision$`, which --version prints (R 4.6.2).
const revision = "89241";

const usage_text = @embedFile("config_usage.txt");
const usage_windows =
    \\
    \\Windows only:
    \\  COMPILED_BY   name and version of compiler used to build R
    \\  LOCAL_SOFT    absolute path to '/usr/local' software collection
    \\  R_TOOLS_SOFT  absolute path to 'R tools' software collection
    \\  OBJDUMP       command to dump objects
;
const usage_tail = "\n  \nReport bugs at <https://bugs.R-project.org>.";

// The script's variable lists, as it writes them.
const ok_c_vars = list("CC CFLAGS CPICFLAGS CPPFLAGS CC17 C17FLAGS CC23 C23FLAGS CC90 C90FLAGS CC99 C99FLAGS");
const ok_cxx_vars = list("CXX CXXFLAGS CXXPICFLAGS CXX17 CXX17STD CXX17FLAGS CXX17PICFLAGS CXX20 CXX20STD CXX20FLAGS CXX20PICFLAGS CXX23 CXX23STD CXX23FLAGS CXX23PICFLAGS CXX26 CXX26STD CXX26FLAGS CXX26PICFLAGS");
const ok_dylib_vars = list("DYLIB_EXT DYLIB_LD DYLIB_LDFLAGS");
const ok_objc_vars = list("OBJC OBJCFLAGS");
const ok_java_vars = list("JAVA JAVAC JAVAH JAR JAVA_HOME JAVA_LIBS JAVA_CPPFLAGS");
const ok_ftn_vars = list("FC FFLAGS FPICFLAGS FLIBS FCFLAGS SAFE_FFLAGS");
const ok_ld_vars = list("LDFLAGS");
const ok_shlib_vars = list("SHLIB_CFLAGS SHLIB_CXXFLAGS SHLIB_CXXLD SHLIB_CXXLDFLAGS SHLIB_CXX17LD SHLIB_CXX17LDFLAGS SHLIB_CXX20LD SHLIB_CXX20LDFLAGS SHLIB_CXX23LD SHLIB_CXX23LDFLAGS SHLIB_CXX26LD SHLIB_CXX26LDFLAGS SHLIB_EXT SHLIB_FFLAGS SHLIB_LD SHLIB_LDFLAGS");
const ok_tcltk_vars = list("TCLTK_CPPFLAGS TCLTK_LIBS");
const ok_other_vars = list("BLAS_LIBS LAPACK_LIBS MAKE LIBnn AR NM RANLIB LTO LTO_FC LTO_LD");
const defunct_text = "CPP CXXCPP CXX11 CXX11STD CXX11FLAGS CXX11PICFLAGS CXX14 CXX14STD CXX14FLAGS CXX14PICFLAGS SHLIB_CXX11LD SHLIB_CXX11LDFLAGS SHLIB_CXX14LD SHLIB_CXX14LDFLAGS";
const defunct_vars = list(defunct_text);
/// ok_win_vars: only when R_OSTYPE is windows.
const ok_win_vars = list("LOCAL_SOFT R_TOOLS_SOFT COMPILED_BY OBJDUMP");
/// In the order of the script's loops (--all prints them so).
const ok_vars = ok_c_vars ++ ok_cxx_vars ++ ok_dylib_vars ++ ok_ftn_vars ++ ok_objc_vars ++ ok_java_vars ++ ok_ld_vars ++ ok_shlib_vars ++ ok_tcltk_vars ++ ok_other_vars;

/// A space-separated list as an array, at compile time.
fn list(comptime text: []const u8) [std.mem.count(u8, text, " ") + 1][]const u8 {
    var out: [std.mem.count(u8, text, " ") + 1][]const u8 = undefined;
    var it = std.mem.splitScalar(u8, text, ' ');
    var k: usize = 0;
    while (it.next()) |w| : (k += 1) out[k] = w;
    return out;
}

/// What the run printed, and its exit code: unit tests read the buffers,
/// `run` writes them.
pub const Result = struct {
    out: std.ArrayList(u8) = .empty,
    err: std.ArrayList(u8) = .empty,
    code: u8 = 0,
};

pub fn run(ctx: *Ctx, args: []const []const u8) !u8 {
    var r: Result = .{};
    try answer(ctx, args, &r);
    stdio.writeAll(ctx.io, .stdout(), r.out.items) catch return 1;
    stdio.writeAll(ctx.io, .stderr(), r.err.items) catch {};
    return r.code;
}

/// The places the script takes from its environment.
const Setup = struct {
    windows: bool,
    r_home: []const u8,
    r_arch: []const u8,
    include_dir: []const u8,
    share_dir: []const u8,
    doc_dir: []const u8,
};

pub fn answer(ctx: *Ctx, args: []const []const u8, r: *Result) !void {
    const a = ctx.arena;
    const windows = if (ctx.env.get("R_OSTYPE")) |v| mem.eql(u8, v, "windows") else false;
    if (args.len == 0) {
        try usage(a, windows, &r.out);
        r.code = 1;
        return;
    }
    const s = try setup(ctx, windows) orelse {
        try r.err.appendSlice(a, "R CMD config: R_HOME is not set\n");
        r.code = 2;
        return;
    };

    var variable: ?[]const u8 = null;
    var personal = true;
    var site = true;
    var all = false;
    for (args) |arg| {
        if (arg.len == 0) break; // while test -n "${1}"
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
            try usage(a, windows, &r.out);
            return;
        } else if (mem.eql(u8, arg, "-v") or mem.eql(u8, arg, "--version")) {
            try r.out.print(a, "R configuration information retrieval script: {s} (r{s})\n\n" ++
                "Copyright (C) 2002-2022 The R Core Team.\n" ++
                "This is free software; see the GNU General Public License version 2\n" ++
                "or later for copying conditions.  There is NO warranty.\n", .{ ctx.env.get("R_VERSION") orelse "", revision });
            return;
        } else if (mem.eql(u8, arg, "--cppflags") or mem.eql(u8, arg, "--ldflags")) {
            return frontEndFlags(ctx, s, mem.eql(u8, arg, "--ldflags"), r);
        } else if (mem.eql(u8, arg, "--no-user-files")) {
            personal = false;
        } else if (mem.eql(u8, arg, "--no-site-files")) {
            site = false;
        } else if (mem.eql(u8, arg, "--all")) {
            all = true;
        } else if (variable == null) {
            variable = arg;
        } else {
            try r.err.appendSlice(a, "ERROR: cannot query more than one variable\n");
            r.code = 1;
            return;
        }
    }

    if (!all) {
        const v = variable orelse "";
        if (!isOk(v, windows)) {
            for (defunct_vars) |d| if (mem.eql(u8, v, d)) {
                try r.err.print(a, "'config' variable '{s}' is defunct\n", .{v});
                r.code = 2;
                return;
            };
            // on stdout, as the script prints it
            try r.out.print(a, "ERROR: no information for variable '{s}'\n", .{v});
            r.code = 1;
            return;
        }
    }

    var e = try evaluator(ctx, s, variable orelse "", if (all) "print-name-and-value" else "print");
    if (!try loadAll(ctx, &e, s, site, personal, r)) return;
    if (all) {
        // one make per variable in the script, each with its VAR
        var lines: std.ArrayList(u8) = .empty;
        for (ok_vars) |v| {
            try e.setCommandLine("VAR", v);
            try printVariable(ctx, &e, v, true, &lines, r) orelse return;
        }
        if (windows) for (ok_win_vars) |v| {
            try e.setCommandLine("VAR", v);
            try printVariable(ctx, &e, v, true, &lines, r) orelse return;
        };
        try r.out.appendSlice(a, lines.items);
        try r.out.appendSlice(a, "\n## The following variables are defunct\n");
        try r.out.appendSlice(a, defunct_text);
        try r.out.append(a, '\n');
        return;
    }
    try printVariable(ctx, &e, variable.?, false, &r.out, r) orelse return;
}

fn usage(a: mem.Allocator, windows: bool, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(a, usage_text);
    if (windows) try out.appendSlice(a, usage_windows);
    try out.appendSlice(a, usage_tail);
    try out.append(a, '\n');
}

fn isOk(v: []const u8, windows: bool) bool {
    for (ok_vars) |o| if (mem.eql(u8, v, o)) return true;
    if (windows) for (ok_win_vars) |o| if (mem.eql(u8, v, o)) return true;
    return false;
}

/// R_HOME and the directories, as R CMD sets them (bin/R on unix,
/// etc/Rcmd_environ on Windows, where the script sets the directories
/// from R_HOME itself). Without R_HOME (rzig started by hand): the R_HOME
/// this rzig is in, R_HOME/bin/toolchain/rzig. null when neither.
fn setup(ctx: *Ctx, windows: bool) !?Setup {
    const r_home = ctx.getenv("R_HOME") orelse blk: {
        const self = ctx.self_exe orelse return null;
        const toolchain = std.fs.path.dirname(self) orelse return null;
        const bin = std.fs.path.dirname(toolchain) orelse return null;
        break :blk std.fs.path.dirname(bin) orelse return null;
    };
    const dir = struct {
        fn f(c: *Ctx, w: bool, rh: []const u8, name: []const u8, sub: []const u8) ![]const u8 {
            if (!w) if (c.getenv(name)) |v| return v;
            return c.fmt("{s}/{s}", .{ rh, sub });
        }
    }.f;
    return .{
        .windows = windows,
        .r_home = r_home,
        .r_arch = ctx.env.get("R_ARCH") orelse "",
        .include_dir = try dir(ctx, windows, r_home, "R_INCLUDE_DIR", "include"),
        .share_dir = try dir(ctx, windows, r_home, "R_SHARE_DIR", "share"),
        .doc_dir = try dir(ctx, windows, r_home, "R_DOC_DIR", "doc"),
    };
}

/// make as the script starts it: GNU make's built-in variables, the
/// environment, the variables make sets itself (`goal` is the target the
/// script asks for), then R_HOME and VAR on the command line.
fn evaluator(ctx: *Ctx, s: Setup, variable: []const u8, goal: []const u8) !makefile.Evaluator {
    var e = makefile.Evaluator.init(ctx.arena, ctx.io, ".");
    e.vars_only = true;
    // MAKE: the script runs ${MAKE} (unix: Renviron's, make by default;
    // Windows: MAKE=make, which reaches make only when MAKE was exported)
    try e.seedDefaults(if (s.windows) "make" else ctx.getenv("MAKE") orelse "make");
    try e.importEnvironment(ctx.env);
    if (s.windows) if (ctx.env.get("MAKE") != null) try e.setEnvironment("MAKE", "make");
    // CURDIR: make (also Windows' GNU make) writes it with forward slashes;
    // by the host too, since a backslash is an escape in sh's words
    const cwd = try Io.Dir.cwd().realPathFileAlloc(ctx.io, ".", ctx.arena);
    if (s.windows or builtin.os.tag == .windows) mem.replaceScalar(u8, cwd, '\\', '/');
    try e.seedMakeVariables(cwd, goal);
    // Windows: the script sets them from R_HOME; unix: R CMD's, or the
    // same defaults for rzig started by hand (Makeconf includes
    // $(R_SHARE_DIR)/make/vars.mk)
    try e.setEnvironment("R_DOC_DIR", s.doc_dir);
    try e.setEnvironment("R_INCLUDE_DIR", s.include_dir);
    try e.setEnvironment("R_SHARE_DIR", s.share_dir);
    try e.setCommandLine("R_HOME", s.r_home);
    try e.setCommandLine("VAR", variable);
    return e;
}

/// One file, as `make -f` reads it; false (and the message) when it
/// cannot be answered without make.
fn load(ctx: *Ctx, e: *makefile.Evaluator, path: []const u8, r: *Result) !bool {
    e.loadFile(path, .makeconf) catch |err| switch (err) {
        error.Unsupported => {
            try needsMake(ctx, e, null, r);
            return false;
        },
        else => |x| return x,
    };
    return true;
}

/// etc${R_ARCH}/Makeconf, then the site's file, then the user's, as the
/// script finds them (its rule, which is not install.R's).
fn loadAll(ctx: *Ctx, e: *makefile.Evaluator, s: Setup, site: bool, personal: bool, r: *Result) !bool {
    if (!try load(ctx, e, try makeconfPath(ctx, s), r)) return false;
    if (site) {
        // : ${R_MAKEVARS_SITE=...}: set, even empty, wins
        const f = ctx.env.get("R_MAKEVARS_SITE") orelse try ctx.fmt("{s}/etc{s}/Makevars.site", .{ s.r_home, s.r_arch });
        if (ctx.isFile(f)) if (!try load(ctx, e, f, r)) return false;
    }
    if (personal) if (try userMakevars(ctx, s)) |f| if (!try load(ctx, e, f, r)) return false;
    return true;
}

fn makeconfPath(ctx: *Ctx, s: Setup) ![]const u8 {
    return ctx.fmt("{s}/etc{s}/Makeconf", .{ s.r_home, s.r_arch });
}

/// R_MAKEVARS_USER, else ~/.R/Makevars-<R_PLATFORM> and ~/.R/Makevars
/// (Windows: Makevars.ucrt, .win64, .win, then Makevars), the first file.
fn userMakevars(ctx: *Ctx, s: Setup) !?[]const u8 {
    if (ctx.env.get("R_MAKEVARS_USER")) |f| if (ctx.isFile(f)) return f;
    const home = ctx.env.get("HOME") orelse "";
    const names: []const []const u8 = if (s.windows)
        &.{ "Makevars.ucrt", "Makevars.win64", "Makevars.win", "Makevars" }
    else
        &.{ try ctx.fmt("Makevars-{s}", .{ctx.env.get("R_PLATFORM") orelse ""}), "Makevars" };
    for (names) |n| {
        const f = try ctx.fmt("{s}/.R/{s}", .{ home, n });
        if (ctx.isFile(f)) return f;
    }
    return null;
}

/// The line config.mk's recipe echoes: `$($(VAR))`, or with `named`
/// `$(VAR) = $($(VAR))`, appended to `out` with its newline. null (and
/// the message) when it cannot be answered without make.
fn printVariable(ctx: *Ctx, e: *makefile.Evaluator, name: []const u8, named: bool, out: *std.ArrayList(u8), r: *Result) !?void {
    const a = ctx.arena;
    const v = e.value(name) catch |err| switch (err) {
        error.Unsupported => {
            try needsMake(ctx, e, null, r);
            return null;
        },
        else => |x| return x,
    };
    const line = if (named) try ctx.fmt("{s} = {s}", .{ name, v }) else v;
    const words = try echoed(ctx, e, line) orelse {
        try needsMake(ctx, e, if (e.raw(name)) |x| x.where else "", r);
        return null;
    };
    try out.appendSlice(a, words);
    try out.append(a, '\n');
}

/// What `echo <line>` prints under the shell make runs it with: its words
/// joined by one space. `$NAME` is what make exports (makefile.zig
/// `exported`), with make's values; SHELL is the environment's unless
/// exported by name, MAKELEVEL one more than make's. null with e.reason
/// set when sh would do more than expand and split, or when the name is
/// one only make knows (MAKEFLAGS, ...).
fn echoed(ctx: *Ctx, e: *makefile.Evaluator, line: []const u8) !?[]const u8 {
    const a = ctx.arena;
    var env: std.process.Environ.Map = .init(a);
    var names: std.ArrayList([]const u8) = .empty;
    try names.append(a, "HOME");
    var i: usize = 0;
    while (mem.findScalarPos(u8, line, i, '$')) |d| {
        i = d + 1;
        var j = i;
        if (j < line.len and line[j] == '{') j += 1;
        const start = j;
        while (j < line.len and (line[j] == '_' or std.ascii.isAlphanumeric(line[j]))) j += 1;
        if (j > start) try names.append(a, line[start..j]);
    }
    for (names.items) |n| {
        if (mem.eql(u8, n, "SHELL") and e.exports.get(n) != true) {
            if (ctx.env.get(n)) |v| try env.put(n, v);
            continue;
        }
        // make passes these whether or not they are exported
        const always = mem.eql(u8, n, "MAKEFLAGS") or mem.eql(u8, n, "MFLAGS") or
            mem.eql(u8, n, "MAKE_TERMOUT") or mem.eql(u8, n, "MAKE_TERMERR");
        if (!always and !e.exported(n)) continue;
        const v = e.value(n) catch |err| switch (err) {
            error.Unsupported => return null,
            else => |x| return x,
        };
        if (mem.eql(u8, n, "MAKELEVEL")) {
            const level = std.fmt.parseInt(u32, mem.trim(u8, v, " \t"), 10) catch {
                e.reason = try ctx.fmt("$MAKELEVEL from a MAKELEVEL of '{s}'", .{v});
                return null;
            };
            try env.put(n, try ctx.fmt("{d}", .{level + 1}));
            continue;
        }
        try env.put(n, v);
    }
    var reason: []const u8 = "";
    const words = shellwords.splitWith(a, line, .{ .shell = &env, .msys_make = builtin.os.tag == .windows }, &reason) catch |err| switch (err) {
        error.Unsupported => {
            e.reason = reason;
            return null;
        },
        else => |x| return x,
    };
    return try mem.join(a, " ", words);
}

/// --cppflags and --ldflags: the flags for a front-end linked against
/// libR, from Makeconf alone (no Makevars), exit 0 either way.
fn frontEndFlags(ctx: *Ctx, s: Setup, ldflags: bool, r: *Result) !void {
    const a = ctx.arena;
    var e = try evaluator(ctx, s, "", "print");
    if (!try load(ctx, &e, try makeconfPath(ctx, s), r)) return;
    var vals: [5][]const u8 = undefined;
    for ([_][]const u8{ "LIBR", "STATIC_LIBR", "MAIN_LDFLAGS", "LIBS", "LDFLAGS" }, 0..) |name, k| {
        var line: std.ArrayList(u8) = .empty;
        try printVariable(ctx, &e, name, false, &line, r) orelse return;
        vals[k] = line.items[0 .. line.items.len - 1];
    }
    const libr, const static_libr, const main_ldflags, const libs, const ld = vals;
    if (libr.len == 0 and static_libr.len == 0) {
        try r.err.appendSlice(a, "R was not built as a library\n");
        return;
    }
    if (!ldflags) {
        if (s.r_arch.len > 0)
            try r.out.print(a, "-I{s} -I{s}{s}\n", .{ s.include_dir, s.include_dir, s.r_arch })
        else
            try r.out.print(a, "-I{s}\n", .{s.include_dir});
    } else if (libr.len == 0) {
        try r.out.print(a, "{s} {s} {s}\n", .{ main_ldflags, ld, static_libr });
    } else {
        try r.out.print(a, "{s} {s} {s} {s}\n", .{ main_ldflags, ld, libr, libs });
    }
}

/// Exit 2, naming the construct and where it is: R CMD config does not
/// run make (feat-config-rzig PLAN.md, the user's decision 4 A).
fn needsMake(ctx: *Ctx, e: *makefile.Evaluator, where: ?[]const u8, r: *Result) !void {
    const at = if (e.where.len > 0) e.where else where orelse "";
    try r.err.print(ctx.arena, "R CMD config: {s}{s}{s}: R CMD config reads these files without make, so it cannot answer\n", .{ at, if (at.len > 0) ": " else "", e.reason });
    r.code = 2;
}

// ----------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

const test_makeconf =
    \\include $(R_SHARE_DIR)/make/vars.mk
    \\CC = $(R_HOME)/bin/toolchain/zig-cc -std=gnu23
    \\CFLAGS = -O2 $(LTO)
    \\CXX = $(R_HOME)/bin/toolchain/zig-cxx -std=gnu++17
    \\LIBR = -L"$(R_HOME)/lib$(R_ARCH)" -lR
    \\STATIC_LIBR =
    \\MAIN_LDFLAGS = -Wl,--export-dynamic
    \\LIBS = -lm  -ldl
    \\LDFLAGS =
    \\SHLIB_LDFLAGS = -shared# $(CFLAGS)
    \\BLAS_LIBS = -L"$(R_HOME)/lib$(R_ARCH)" -lRblas
    \\
;

const Run = struct {
    out: []const u8,
    err: []const u8,
    code: u8,
};

fn runConfig(f: *testutil.Fixture, args: []const []const u8) !Run {
    var r: Result = .{};
    try answer(&f.ctx, args, &r);
    return .{ .out = r.out.items, .err = r.err.items, .code = r.code };
}

fn unixHome(f: *testutil.Fixture) ![]const u8 {
    try f.write("R/etc/Makeconf", test_makeconf, .default_file);
    try f.write("R/share/make/vars.mk", "R_PKGS_BASE = base tools\n", .default_file);
    const r = f.path("R");
    try f.env.put("R_HOME", r);
    try f.env.put("R_SHARE_DIR", f.path("R/share"));
    try f.env.put("R_INCLUDE_DIR", f.path("R/include"));
    try f.env.put("R_PLATFORM", "x86_64-pc-linux-gnu");
    try f.env.put("HOME", f.path("home"));
    try f.env.put("MAKE", "make");
    return r;
}

test "a variable, --all, the options and the errors" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try unixHome(&f);

    var x = try runConfig(&f, &.{"CC"});
    try testing.expectEqualStrings(f.fmt("{s}/bin/toolchain/zig-cc -std=gnu23\n", .{r}), x.out);
    try testing.expectEqual(0, x.code);
    x = try runConfig(&f, &.{"SHLIB_LDFLAGS"});
    try testing.expectEqualStrings("-shared\n", x.out);
    x = try runConfig(&f, &.{"BLAS_LIBS"});
    try testing.expectEqualStrings(f.fmt("-L{s}/lib -lRblas\n", .{r}), x.out);
    x = try runConfig(&f, &.{"MAKE"});
    try testing.expectEqualStrings("make\n", x.out);
    // not in Makeconf: make's built-in value
    x = try runConfig(&f, &.{"OBJC"});
    try testing.expectEqualStrings("cc\n", x.out);
    x = try runConfig(&f, &.{"FFLAGS"});
    try testing.expectEqualStrings("\n", x.out);

    x = try runConfig(&f, &.{});
    try testing.expectEqual(1, x.code);
    try testing.expect(mem.startsWith(u8, x.out, "Usage: R CMD config [options] [VAR]\n"));
    try testing.expect(mem.endsWith(u8, x.out, "libraries\n\n  \nReport bugs at <https://bugs.R-project.org>.\n"));
    x = try runConfig(&f, &.{ "--no-user-files", "--help", "nonsense" });
    try testing.expectEqual(0, x.code);
    try testing.expect(mem.find(u8, x.out, "Windows only") == null);
    try f.env.put("R_VERSION", "4.6.2");
    x = try runConfig(&f, &.{"--version"});
    try testing.expect(mem.startsWith(u8, x.out, "R configuration information retrieval script: 4.6.2 (r89241)\n\nCopyright"));

    x = try runConfig(&f, &.{"NOPE"});
    try testing.expectEqualStrings("ERROR: no information for variable 'NOPE'\n", x.out);
    try testing.expectEqual(1, x.code);
    x = try runConfig(&f, &.{"--no-site-files"});
    try testing.expectEqualStrings("ERROR: no information for variable ''\n", x.out);
    x = try runConfig(&f, &.{ "", "CC" }); // stops at the empty one: no variable
    try testing.expectEqualStrings("ERROR: no information for variable ''\n", x.out);
    x = try runConfig(&f, &.{"CXX11"});
    try testing.expectEqualStrings("'config' variable 'CXX11' is defunct\n", x.err);
    try testing.expectEqual(2, x.code);
    x = try runConfig(&f, &.{ "CC", "CXX" });
    try testing.expectEqualStrings("ERROR: cannot query more than one variable\n", x.err);
    try testing.expectEqual(1, x.code);
    x = try runConfig(&f, &.{"COMPILED_BY"});
    try testing.expectEqual(1, x.code);

    x = try runConfig(&f, &.{"--all"});
    try testing.expect(mem.startsWith(u8, x.out, f.fmt("CC = {s}/bin/toolchain/zig-cc -std=gnu23\nCFLAGS = -O2\nCPICFLAGS =\n", .{r})));
    try testing.expect(mem.endsWith(u8, x.out, "LTO_LD =\n\n## The following variables are defunct\nCPP CXXCPP CXX11 CXX11STD CXX11FLAGS CXX11PICFLAGS CXX14 CXX14STD CXX14FLAGS CXX14PICFLAGS SHLIB_CXX11LD SHLIB_CXX11LDFLAGS SHLIB_CXX14LD SHLIB_CXX14LDFLAGS\n"));

    x = try runConfig(&f, &.{ "CC", "--cppflags" });
    try testing.expectEqualStrings(f.fmt("-I{s}/include\n", .{r}), x.out);
    x = try runConfig(&f, &.{"--ldflags"});
    try testing.expectEqualStrings(f.fmt("-Wl,--export-dynamic  -L{s}/lib -lR -lm -ldl\n", .{r}), x.out);
}

test "--cppflags and --ldflags without libR" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    _ = try unixHome(&f);
    try f.write("R/etc/Makeconf", "LIBR =\nSTATIC_LIBR =\n", .default_file);
    const x = try runConfig(&f, &.{"--cppflags"});
    try testing.expectEqualStrings("", x.out);
    try testing.expectEqualStrings("R was not built as a library\n", x.err);
    try testing.expectEqual(0, x.code);
}

test "the site's and the user's Makevars, in the script's order" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const r = try unixHome(&f);
    try f.write("R/etc/Makevars.site", "CFLAGS += -DSITE\n", .default_file);
    try f.write("home/.R/Makevars", "CFLAGS += -g\nCXX17 = ccache $(CXX)\n", .default_file);
    var x = try runConfig(&f, &.{"CFLAGS"});
    try testing.expectEqualStrings("-O2 -DSITE -g\n", x.out);
    x = try runConfig(&f, &.{ "--no-site-files", "CFLAGS" });
    try testing.expectEqualStrings("-O2 -g\n", x.out);
    x = try runConfig(&f, &.{ "CFLAGS", "--no-user-files" });
    try testing.expectEqualStrings("-O2 -DSITE\n", x.out);
    x = try runConfig(&f, &.{"CXX17"});
    try testing.expectEqualStrings(f.fmt("ccache {s}/bin/toolchain/zig-cxx -std=gnu++17\n", .{r}), x.out);
    // the platform's file before Makevars
    try f.write("home/.R/Makevars-x86_64-pc-linux-gnu", "CFLAGS = -O0\n", .default_file);
    x = try runConfig(&f, &.{"CFLAGS"});
    try testing.expectEqualStrings("-O0\n", x.out);
    // R_MAKEVARS_USER first; R_MAKEVARS_SITE set but empty: no site file
    try f.write("mine.mk", "CFLAGS += -O3 \"-DQ=a b\" $$HOME ~\n", .default_file);
    try f.env.put("R_MAKEVARS_USER", f.path("mine.mk"));
    try f.env.put("R_MAKEVARS_SITE", "");
    x = try runConfig(&f, &.{"CFLAGS"});
    try testing.expectEqualStrings(f.fmt("-O2 -O3 -DQ=a b {s} {s}\n", .{ f.path("home"), f.path("home") }), x.out);
    // a user file that cannot be answered without make: exit 2, its line
    try f.write("mine.mk", "X = 1\nCFLAGS := $(shell echo -O1)\n", .default_file);
    x = try runConfig(&f, &.{"CC"});
    try testing.expectEqual(2, x.code);
    try testing.expectEqualStrings("", x.out);
    try testing.expect(mem.startsWith(u8, x.err, f.fmt("R CMD config: {s}:2: $(shell ...) is not supported", .{f.path("mine.mk")})));
    // lazy: a $(shell) nobody prints is no error; printed, it is
    try f.write("mine.mk", "LATER = $(shell date)\nCC17 = `ccache` gcc\n", .default_file);
    x = try runConfig(&f, &.{"CC"});
    try testing.expectEqual(0, x.code);
    try f.write("mine.mk", "CC = $(shell which cc)\n", .default_file);
    x = try runConfig(&f, &.{"CC"});
    try testing.expectEqual(2, x.code);
    try testing.expect(mem.startsWith(u8, x.err, f.fmt("R CMD config: {s}:1: $(shell ...)", .{f.path("mine.mk")})));
    try f.write("mine.mk", "CC17 = `ccache` gcc\n", .default_file);
    x = try runConfig(&f, &.{"CC17"});
    try testing.expectEqual(2, x.code);
    try testing.expect(mem.startsWith(u8, x.err, f.fmt("R CMD config: {s}:1: a shell metacharacter '`'", .{f.path("mine.mk")})));
    x = try runConfig(&f, &.{"--all"});
    try testing.expectEqual(2, x.code);
    try testing.expectEqualStrings("", x.out);
}

test "Windows: etc/x64/Makeconf, the directories from R_HOME, its variables and help" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.write("R/etc/x64/Makeconf", "BINPREF = $(R_HOME)/bin/toolchain/\nCC = $(BINPREF)gcc.exe\nOBJDUMP = $(BINPREF)objdump\nLIBR = -L\"$(R_HOME)/bin/x64\" -lR\nLIBS = -lm\n", .default_file);
    const r = f.path("R");
    try f.env.put("R_HOME", r);
    try f.env.put("R_ARCH", "/x64");
    try f.env.put("R_OSTYPE", "windows");
    try f.env.put("R_INCLUDE_DIR", "/elsewhere/include");
    try f.env.put("HOME", f.path("home"));
    try f.env.put("MAKE", "mingw32-make");
    try f.write("home/.R/Makevars", "CC = never\n", .default_file);
    try f.write("home/.R/Makevars.win", "CC += -DWIN\n", .default_file);
    var x = try runConfig(&f, &.{"CC"});
    try testing.expectEqualStrings(f.fmt("{s}/bin/toolchain/gcc.exe -DWIN\n", .{r}), x.out);
    x = try runConfig(&f, &.{"OBJDUMP"});
    try testing.expectEqualStrings(f.fmt("{s}/bin/toolchain/objdump\n", .{r}), x.out);
    x = try runConfig(&f, &.{"MAKE"});
    try testing.expectEqualStrings("make\n", x.out);
    x = try runConfig(&f, &.{"--cppflags"});
    try testing.expectEqualStrings(f.fmt("-I{s}/include -I{s}/include/x64\n", .{ r, r }), x.out);
    x = try runConfig(&f, &.{"--ldflags"});
    try testing.expectEqualStrings(f.fmt("  -L{s}/bin/x64 -lR -lm\n", .{r}), x.out);
    x = try runConfig(&f, &.{"--help"});
    try testing.expect(mem.endsWith(u8, x.out, "libraries\n\nWindows only:\n  COMPILED_BY   name and version of compiler used to build R\n  LOCAL_SOFT    absolute path to '/usr/local' software collection\n  R_TOOLS_SOFT  absolute path to 'R tools' software collection\n  OBJDUMP       command to dump objects\n  \nReport bugs at <https://bugs.R-project.org>.\n"));
    x = try runConfig(&f, &.{"--all"});
    try testing.expect(mem.find(u8, x.out, "\nCOMPILED_BY =\nOBJDUMP = ") != null);
}

test "R_HOME from rzig's own place" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try f.write("R/etc/Makeconf", "include $(R_SHARE_DIR)/make/vars.mk\nCC = $(R_HOME)/bin/toolchain/zig-cc\n", .default_file);
    try f.write("R/share/make/vars.mk", "R_PKGS_BASE = base\n", .default_file);
    f.ctx.self_exe = f.path("R/bin/toolchain/rzig");
    const x = try runConfig(&f, &.{"CC"});
    try testing.expectEqualStrings(f.fmt("{s}/bin/toolchain/zig-cc\n", .{f.path("R")}), x.out);
}

test "what make exports to the echo, and the variables make sets itself" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    _ = try unixHome(&f);
    try f.env.put("SHELL", "/bin/bash");
    try f.env.put("R_MAKEVARS_USER", f.path("mine.mk"));
    const cases = [_]struct { mk: []const u8, out: []const u8 }{
        .{ .mk = "export FOO = bar\nCFLAGS = -D$$FOO\n", .out = "-Dbar\n" },
        .{ .mk = "FOO = bar\nexport FOO BAZ\nBAZ = q\nCFLAGS = -D$$FOO $${BAZ}\n", .out = "-Dbar q\n" },
        .{ .mk = "FOO = bar\nCFLAGS = -D$$FOO\n", .out = "-D\n" },
        .{ .mk = "export\nFOO = bar\nCFLAGS = -D$$FOO $$OBJC\n", .out = "-Dbar\n" },
        .{ .mk = ".EXPORT_ALL_VARIABLES:\nFOO = bar\nCFLAGS = -D$$FOO\n", .out = "-Dbar\n" },
        .{ .mk = "export FOO = bar\nunexport FOO\nunexport HOME\nCFLAGS = -D$$FOO $$HOME\n", .out = "-D\n" },
        .{ .mk = "export\nunexport\nFOO = bar\nCFLAGS = -D$$FOO\n", .out = "-D\n" },
        .{ .mk = "HOME = /x\nCFLAGS = $$HOME\n", .out = "/x\n" },
        .{ .mk = "CFLAGS = $(MAKELEVEL) $$MAKELEVEL $(origin MAKELEVEL) $(origin CURDIR) $(flavor CURDIR)\n", .out = "0 1 environment file simple\n" },
        .{ .mk = "CFLAGS = $(SHELL) $$SHELL $(.SHELLFLAGS) $(MAKECMDGOALS)\n", .out = "/bin/sh /bin/bash -c print\n" },
        .{ .mk = "export SHELL\nCFLAGS = $$SHELL\n", .out = "/bin/sh\n" },
        .{ .mk = "vpath %.c src\nCFLAGS = ok\n", .out = "ok\n" },
    };
    for (cases) |c| {
        try f.write("mine.mk", c.mk, .default_file);
        const x = try runConfig(&f, &.{"CFLAGS"});
        try testing.expectEqualStrings("", x.err);
        try testing.expectEqualStrings(c.out, x.out);
    }
    try f.write("mine.mk", "CFLAGS = $(CURDIR)\n", .default_file);
    var x = try runConfig(&f, &.{"CFLAGS"});
    // the host's working directory, with forward slashes (C:/... on Windows)
    try testing.expect(x.out.len > 2 and mem.indexOfScalar(u8, x.out, '\\') == null and
        std.fs.path.isAbsolute(x.out[0 .. x.out.len - 1]));
    try f.env.put("MAKELEVEL", "3");
    try f.write("mine.mk", "CFLAGS = $(MAKELEVEL) $$MAKELEVEL\n", .default_file);
    x = try runConfig(&f, &.{"CFLAGS"});
    try testing.expectEqualStrings("3 4\n", x.out);
    // what only make knows, and globs sh would match: exit 2, the line
    for ([_][]const u8{ "CFLAGS = $(MAKEFLAGS)\n", "CFLAGS = $$MAKEFLAGS\n", "CFLAGS = $(MAKEFILE_LIST)\n", "CFLAGS = $(origin MAKE_VERSION)\n", "CFLAGS = *.c\n" }) |mk| {
        try f.write("mine.mk", mk, .default_file);
        x = try runConfig(&f, &.{"CFLAGS"});
        try testing.expectEqual(2, x.code);
        try testing.expectEqualStrings("", x.out);
        try testing.expect(mem.startsWith(u8, x.err, f.fmt("R CMD config: {s}:1: ", .{f.path("mine.mk")})));
    }
}
