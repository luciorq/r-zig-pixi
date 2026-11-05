//! rzig: R's compiler toolchain front, one binary for every OS (phase F3
//! of feat-no-host-paths). It replaces the bash shims toolchain/zig-cc,
//! zig-cxx, zig-ar, zig-ranlib and the Windows gcc.exe/g++.exe forwarders
//! (zigbuild/tools/win-exec-forward.c, which ran the shims through bash),
//! and dispatches on its own name, like busybox:
//!
//!   zig-cc, gcc       zig cc   with the shims' argument rewriting
//!   zig-cxx, g++      zig c++  likewise
//!   zig-fc            flang for compiles (macOS: the floor; the
//!                              modules path); every link through zig cc
//!                              as zig-cc, with the static Fortran
//!                              runtime; sources and a link: a flang
//!                              compile each, then that link (F3c,
//!                              fortran.zig)
//!   zig-ar, gcc-ar,   zig ar   (macOS: seeds a missing archive)
//!     ar
//!   zig-ranlib,       zig ranlib
//!     gcc-ranlib, ranlib
//!   rzig <name> ...   the same, naming the tool explicitly
//!   rzig build ...    one package's library with zig build alone
//!                     (pkgbuild.zig; install.R's hook, patch 0013)
//!   rzig def ...      a package DLL's .def from its objects (def.zig)
//!
//! gcc-ar and gcc-ranlib are the names Makeconf.win's LTO lines use
//! (feat-standalone-toolchain B43); Windows has those copies from phase 3.
//! ar and ranlib are the names CMake looks for beside the C compiler
//! before PATH (CMakeFindBinUtils): Windows has ar.exe and ranlib.exe
//! beside gcc.exe, R CMD config CC, where MinGW's were before phase 3.
//!
//! zig is found by find_zig.zig: ZIG_BIN, the compilers group's zig/ in
//! rzig's own directory, the environment's bin, PATH, python3 -m ziglang.
//! None: rzig names the compilers group and how to install it (groups.zig)
//! and exits 127. `<name> --rzig-check[=fortran|build-tools|package]`
//! checks a group's tools instead of compiling (check.zig): the install
//! preflight calls `=package` (patch 0009), R CMD config `=build-tools`
//! (patch 0010).
//!
//! build.zig installs it under those names into R_HOME/bin/toolchain, the
//! directory Makeconf names (Windows: gcc.exe and g++.exe, Makeconf.win's
//! $(BINPREF)gcc and g++, zig-fc.exe, its FC, zig-ar.exe and
//! zig-ranlib.exe, its AR and RANLIB, gcc-ar.exe and gcc-ranlib.exe, and
//! ar.exe and ranlib.exe for CMake).
//! On unix rzig replaces itself with the program it runs, zig or flang
//! (execve); on Windows it runs it and exits with its exit code. A
//! command of several steps (zig-fc's split) is run step by step on every
//! OS, rzig waiting for each, so it can remove the steps' objects after.
//!
//! The compilers own the compile environment (F3b): zig-cc and zig-cxx
//! add the include/ and lib/ (and, for a conda env on unix, an rpath into
//! lib/) of the environment R is installed in, which rzig finds from its
//! own path, and of R_ZIG_EXTRA_ENV; Makeconf's CPPFLAGS and LDFLAGS are
//! empty (environment.zig, compiler.zig). CONDA_PREFIX is never read.
//!
//!   R_ZIG_EXTRA_ENV=<root>  one more environment to compile against: a
//!                      conda env's root, as an absolute path (rzig adds
//!                      /Library on Windows).
//!                      pixi.toml sets it to the pixi env for dev and test
//!                      runs; a standalone R plus an env of libraries is
//!                      the other use.
//!   RZIG_TRACE=1       print the command rzig runs to stderr (one line,
//!                      shell-quoted, a response file's words in place of
//!                      its @file), then run it: R CMD INSTALL's log
//!                      then shows every flag rzig added. Under `rzig
//!                      build`, the compiles and the link are rzig's own
//!                      children (tier1.zig, also tier 2's `rzig t1`), so
//!                      the line shows after the command rzig build echoed,
//!                      as under make.
//!   RZIG_KEEP_ROOT=1   rzig build: keep the build root (the plan, the
//!                      objects, the library) after the build, whatever
//!                      its exit: <out>/.rzig for a package; for R CMD
//!                      SHLIB a .rzig.<16 hex> beside the output, not in R's
//!                      session directory, which that R removes when it
//!                      exits [shlib-code-1]
//!
//! Test hooks (not for builds):
//!   RZIG_PRINT_ARGV=1  print what would run instead of running it: the
//!                      child's ZIG_LIB_DIR as `ZIG_LIB_DIR=<value>` when
//!                      it has one, then the argv, one per line; for a
//!                      command of several steps each step's so, a line
//!                      `&&` between two, ZIG_LIB_DIR before the first
//!                      zig step's (the only ones it applies to). Side
//!                      effects of preparing the call still happen (the
//!                      libc++ mirror, ar's archive seed, asking flang and
//!                      xcrun, compiling a linux shared library's
//!                      finalization object or a Windows link's CFG stub,
//!                      copying an archive to an .a name).
//!   RZIG_OS=linux|macos|windows  with RZIG_PRINT_ARGV only: apply that
//!                      OS's rewriting (what the shims' `uname -s` chose),
//!                      so every OS's branches can be checked from one
//!                      machine. Ignored otherwise.
//!   RZIG_XCRUN=<path>  with RZIG_PRINT_ARGV only: what to run in place of
//!                      /usr/bin/xcrun for the macOS SDK.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const compiler = @import("compiler.zig");
const fortran = @import("fortran.zig");
const ar = @import("ar.zig");
const find_zig = @import("find_zig.zig");
const environment = @import("environment.zig");
const libcxx_mirror = @import("libcxx_mirror.zig");
const pkgbuild = @import("pkgbuild.zig");
const def = @import("def.zig");
const response = @import("response.zig");
const check = @import("check.zig");
const groups = @import("groups.zig");
const testutil = @import("testutil.zig");
const crash = @import("crash.zig");

/// A crash never exits 3, rzig build's "needs make" (crash.zig).
pub const panic = crash.panic;
pub const debug = crash.debug;

const Tool = enum {
    cc,
    cxx,
    fc,
    ar,
    ranlib,

    fn fromName(name: []const u8) ?Tool {
        const map = std.StaticStringMap(Tool).initComptime(.{
            .{ "zig-cc", .cc },         .{ "gcc", .cc },
            .{ "zig-cxx", .cxx },       .{ "g++", .cxx },
            .{ "zig-fc", .fc },         .{ "zig-ar", .ar },
            .{ "zig-ranlib", .ranlib }, .{ "gcc-ar", .ar },
            .{ "gcc-ranlib", .ranlib }, .{ "ar", .ar },
            .{ "ranlib", .ranlib },
        });
        return map.get(name);
    }

    /// The shim it stands for, in messages (zig-fc has no bash shim).
    fn shimName(t: Tool) []const u8 {
        return switch (t) {
            .cc => "zig-cc",
            .cxx => "zig-cxx",
            .fc => "zig-fc",
            .ar => "zig-ar",
            .ranlib => "zig-ranlib",
        };
    }
};

/// rzig's own commands, when it is started as itself (`rzig build`): never
/// through a compiler's name, where `build` could be a source file.
const Subcommand = enum {
    build,
    def,
    t1,

    fn fromName(name: []const u8) ?Subcommand {
        return std.meta.stringToEnum(Subcommand, name);
    }
};

const usage =
    \\usage: zig-cc|zig-cxx|zig-fc|zig-ar|zig-ranlib|gcc|g++|gcc-ar|gcc-ranlib|ar|ranlib [args...]
    \\       <one of those names> --rzig-check[=fortran|build-tools|package]
    \\       rzig <one of those names> [args...]
    \\       rzig build --pkg <dir> --out <dir> [options]   (rzig build --help)
    \\       rzig build --shlib --output <lib> [options] -- <file>...
    \\       rzig def -o <file>.def <object>|@<file>...
    \\       rzig t1 --plan <plan.zon> --root <dir> --out <lib> [--object <o>]... [--c|--cxx <source>]... [-j N]
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    var args: []const []const u8 = try init.minimal.args.toSlice(arena);
    if (args.len == 0) {
        std.debug.print("{s}", .{usage});
        return 2;
    }

    const arg0 = args[0];
    // the name without directory or extension (gcc.exe is gcc)
    var tool = Tool.fromName(toolName(args[0]));
    // R on Windows starts programs by the 8.3 short form of their path
    // (system(), system2()), and g++.exe has a short name of its own
    // (G__~1.EXE: + is no 8.3 character), so argv[0] names no tool there:
    // R CMD INSTALL's `g++ --version` printed this usage and every C++ log
    // said `using C++ compiler: 'NA'` (stress round 1, R1). The long form
    // of this binary's path names it (zig-ranlib.exe's ZIG-RA~1.EXE too).
    if (tool == null and builtin.os.tag == .windows) {
        if (selfExe(io, arena, arg0)) |p| tool = Tool.fromName(toolName(p));
    }
    if (tool == null and args.len > 1) {
        if (Subcommand.fromName(args[1])) |sub| {
            var ctx: Ctx = .{
                .io = io,
                .arena = arena,
                .env = init.environ_map,
                .os = Ctx.Os.host,
                .name = "rzig",
                .self_exe = selfExe(io, arena, arg0),
            };
            return switch (sub) {
                .build => pkgbuild.run(&ctx, args[2..]),
                .def => def.run(&ctx, args[2..]),
                .t1 => @import("tier1.zig").run(&ctx, args[2..]),
            };
        }
        tool = Tool.fromName(toolName(args[1]));
        args = args[1..];
    }
    const t = tool orelse {
        std.debug.print("{s}", .{usage});
        return 2;
    };

    const env = init.environ_map;
    const dry_run = isSet(env, "RZIG_PRINT_ARGV");
    var ctx: Ctx = .{
        .io = io,
        .arena = arena,
        .env = env,
        .os = Ctx.Os.host,
        .name = t.shimName(),
        .self_exe = selfExe(io, arena, arg0),
    };
    ctx.dry_run = dry_run;
    if (dry_run) {
        if (env.get("RZIG_OS")) |v| ctx.os = std.meta.stringToEnum(Ctx.Os, v) orelse {
            std.debug.print("rzig: RZIG_OS must be linux, macos or windows, not '{s}'\n", .{v});
            return 2;
        };
        if (env.get("RZIG_XCRUN")) |v| ctx.xcrun = v;
    }

    const caller = args[1..];
    if (caller.len == 1) {
        const kind = check.parse(caller[0], t == .fc) catch {
            std.debug.print("{s}: {s} checks the compilers (no value), fortran, build-tools or package, not '{s}'\n", .{ ctx.name, check.flag, caller[0] });
            return 2;
        };
        if (kind) |k| {
            const r = try check.run(&ctx, k);
            if (r.code == 0) try printLine(io, .stdout(), ctx.name, r.line);
            return r.code;
        }
    }
    // zig, found first: compiler.zig may compile with it (dso_fini.zig,
    // cfguard.zig). zig-fc's compiles run flang alone, so a missing zig
    // stops only a command that runs zig (below).
    ctx.zig = if (try find_zig.find(&ctx)) |z| z.argv else null;
    const cmd: Ctx.Command = switch (t) {
        .cc, .cxx => .{ .zig = try compiler.argv(&ctx, if (t == .cc) .c else .cxx, caller) },
        // no flang: 127, as a shell gives for a command it cannot find
        .fc => fortran.command(&ctx, caller) catch |err| switch (err) {
            error.NoFlang => return 127,
            else => |e| return e,
        },
        .ar => .{ .zig = try ar.argv(&ctx, caller) },
        .ranlib => .{ .zig = try mem.concat(arena, []const u8, &.{ &.{"ranlib"}, caller }) },
    };
    // zig, when the command is zig's: for a compile or link with the
    // libc++ mirror prepared (a flang command needs neither)
    var blocks: std.ArrayList(Block) = .empty;
    switch (cmd) {
        .program => |p| try blocks.append(arena, .{ .argv = p, .zig = false }),
        .zig => |z| try blocks.append(arena, .{ .argv = z, .zig = true }),
        .steps => |st| for (st.steps) |step| try blocks.append(arena, switch (step) {
            .program => |p| .{ .argv = p, .zig = false },
            .zig => |z| .{ .argv = z, .zig = true },
        }),
    }
    var env_changed = false;
    var mirrored = false;
    for (blocks.items) |*b| {
        if (!b.zig) continue;
        // no zig: 127, as a shell gives for a command it cannot find,
        // before any step runs
        const zig = ctx.zig orelse {
            try groups.report(&ctx, groups.no_zig, .compilers);
            return 127;
        };
        if (!mirrored and (t == .cc or t == .cxx or t == .fc) and ctx.os != .windows) env_changed = try libcxx_mirror.apply(&ctx, zig[0]);
        mirrored = true;
        b.argv = try mem.concat(arena, []const u8, &.{ zig, b.argv });
    }

    if (dry_run) return printArgv(io, .stdout(), env, blocks.items);
    if (isSet(env, "RZIG_TRACE")) {
        // what the environment rule saw: this binary's path, and the
        // environments it chose (environment.zig)
        ctx.warn("self {s}", .{ctx.self_exe orelse "(unknown)"});
        for (try environment.list(&ctx)) |e| ctx.warn("environment {s}{s}", .{ e.dir, if (e.conda) " (conda)" else "" });
        for (blocks.items) |b| {
            const lib_dir = if (env_changed and b.zig) try ctx.fmt("ZIG_LIB_DIR={f} ", .{shellQuoted(env.get("ZIG_LIB_DIR") orelse "")}) else "";
            // a response file's words in its place, as zig reads it: rzig
            // build's links name their objects in one (response.zig), and
            // the line shows them as make's link does
            ctx.warn("{s}{f}", .{ lib_dir, shellCommand(try response.expand(&ctx, b.argv)) });
        }
    }
    return switch (cmd) {
        .steps => |st| runSteps(&ctx, blocks.items, st.tmp, if (env_changed) env else null),
        else => run(&ctx, blocks.items[0].argv, if (env_changed) env else null),
    };
}

/// One command rzig runs or prints: its argv, and whether it is zig's,
/// the only kind the libc++ mirror's ZIG_LIB_DIR is for.
const Block = struct { argv: []const []const u8, zig: bool };

/// A switch in the environment: set, not empty, not "0".
fn isSet(env: *const std.process.Environ.Map, name: []const u8) bool {
    const v = env.get(name) orelse return false;
    return v.len > 0 and !mem.eql(u8, v, "0");
}

/// `argv` as one shell command line, for RZIG_TRACE.
fn shellCommand(argv: []const []const u8) std.fmt.Alt([]const []const u8, struct {
    fn f(xs: []const []const u8, w: *Io.Writer) Io.Writer.Error!void {
        for (xs, 0..) |x, i| try w.print("{s}{f}", .{ if (i == 0) "" else " ", shellQuoted(x) });
    }
}.f) {
    return .{ .data = argv };
}

/// One word for a POSIX shell: as is when it needs no quoting, else in
/// single quotes (a quote inside as '\'').
fn shellQuoted(x: []const u8) std.fmt.Alt([]const u8, struct {
    fn f(s: []const u8, w: *Io.Writer) Io.Writer.Error!void {
        const plain = s.len > 0 and for (s) |c| {
            if (!(std.ascii.isAlphanumeric(c) or mem.findScalar(u8, "%+,-./:=@_", c) != null)) break false;
        } else true;
        if (plain) return w.writeAll(s);
        try w.writeByte('\'');
        for (s) |c| if (c == '\'') try w.writeAll("'\\''") else try w.writeByte(c);
        try w.writeByte('\'');
    }
}.f) {
    return .{ .data = x };
}

/// A tool name from argv[0] (or rzig's first argument): the base name,
/// without `.exe`.
fn toolName(arg: []const u8) []const u8 {
    const base = std.fs.path.basename(arg);
    if (base.len > 4 and std.ascii.eqlIgnoreCase(base[base.len - 4 ..], ".exe")) return base[0 .. base.len - 4];
    return base;
}

/// This binary's path, for environment.zig: the OS's answer (symlinks
/// resolved), else argv[0] when it is a path. `/` separators throughout,
/// as the shims' `${BASH_SOURCE[0]//\\//}`.
fn selfExe(io: Io, arena: mem.Allocator, arg0: []const u8) ?[]const u8 {
    const p: []const u8 = std.process.executablePathAlloc(io, arena) catch blk: {
        if (mem.findAny(u8, arg0, if (builtin.os.tag == .windows) "/\\" else "/") == null) return null;
        break :blk arg0;
    };
    if (builtin.os.tag != .windows) return p;
    // R starts programs on Windows by the 8.3 short form of the whole path
    // (system()/system2(): .../lib/R/bin/TOOLCH~1/gcc.exe), which the
    // environment rule's /lib/R/bin/toolchain suffix would not match:
    // expand it to the long form first (found on kappa, 2026-10-02: the
    // conda package's test called gcc.exe that way; Zig's realpath keeps
    // the short names).
    const long = longPathName(arena, p) orelse p;
    return mem.replaceOwned(u8, arena, long, "\\", "/") catch null;
}

extern "kernel32" fn GetLongPathNameW(short: [*:0]const u16, long: [*]u16, len: u32) callconv(.winapi) u32;

/// Windows: `p` with every 8.3 short component in its long form, or null.
fn longPathName(arena: mem.Allocator, p: []const u8) ?[]const u8 {
    const w = std.unicode.utf8ToUtf16LeAllocZ(arena, p) catch return null;
    const buf = arena.alloc(u16, 32768) catch return null;
    const n = GetLongPathNameW(w.ptr, buf.ptr, @intCast(buf.len));
    if (n == 0 or n > buf.len) return null;
    return std.unicode.utf16LeToUtf8Alloc(arena, buf[0..n]) catch null;
}

/// RZIG_PRINT_ARGV's output, to `out_file` (main's: stdout). Through a
/// streaming writer, which writes at the file's own offset, as `echo`
/// does: the positional one (File.writer) writes from offset 0 of a
/// regular file, over whatever the shell had written to it before, as in
/// `{ echo x; zig-cc ...; } > file` (E4, fix-rzig-baseline-cpu's
/// follow-ups). On Windows that write also left the shared handle's file
/// pointer after the argv, so later output to the same redirect
/// overwrote what followed (kappa, 2026-10-08).
/// Each block's argv, one per line, a line `&&` between two blocks (the
/// shell's "then", which no argument rzig prints alone can be).
/// `ZIG_LIB_DIR=<value>`, when the environment has one, goes before the
/// first block that is zig's, else on top: on top for a single command,
/// as before; after flang's blocks in a split, so its first line is still
/// flang's (phase 6, Cc6).
fn printArgv(io: Io, out_file: Io.File, env: *const std.process.Environ.Map, blocks: []const Block) !u8 {
    var buf: [4096]u8 = undefined;
    var w = out_file.writerStreaming(io, &buf);
    const out = &w.interface;
    const first_zig = for (blocks, 0..) |b, i| {
        if (b.zig) break i;
    } else 0;
    for (blocks, 0..) |b, i| {
        if (i > 0) try out.writeAll("&&\n");
        if (i == first_zig) if (env.get("ZIG_LIB_DIR")) |v| try out.print("ZIG_LIB_DIR={s}\n", .{v});
        for (b.argv) |x| try out.print("{s}\n", .{x});
    }
    try out.flush();
    return 0;
}

/// The check mode's line: `<name>: <line>`, on stdout (main's).
fn printLine(io: Io, out_file: Io.File, name: []const u8, line: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var w = out_file.writerStreaming(io, &buf);
    try w.interface.print("{s}: {s}\n", .{ name, line });
    try w.interface.flush();
}

/// Exit codes as the shell gives for a command it cannot run: 127 not
/// found, 126 found but not runnable.
fn run(ctx: *Ctx, argv: []const []const u8, env: ?*const std.process.Environ.Map) u8 {
    if (builtin.os.tag == .windows) {
        // No exec on Windows: run zig (or flang) with our standard handles
        // and pass its exit code on, as the forwarder did. The command
        // line is quoted by std (Microsoft's argv rules), so arguments
        // with embedded quotes, -DX='"a.h"', arrive intact (F7.7).
        var child = std.process.spawn(ctx.io, .{ .argv = argv, .environ_map = env }) catch |err| return cannotRun(ctx, argv[0], err);
        // what it wrote that nobody keeps (windows.implib), once it is done
        defer for (ctx.discard.items) |p| Io.Dir.cwd().deleteFile(ctx.io, p) catch {};
        const term = child.wait(ctx.io) catch |err| {
            ctx.warn("waiting for {s}: {t}", .{ argv[0], err });
            return 1;
        };
        return switch (term) {
            .exited => |code| code,
            else => 1,
        };
    }
    const err = std.process.replace(ctx.io, .{ .argv = argv, .environ_map = env });
    return cannotRun(ctx, argv[0], err);
}

/// A command of several steps (zig-fc's split): `tmp` created, then each
/// step spawned and waited for, on unix too (exec would leave no one to
/// remove the objects), until one fails; then `tmp` and ctx.discard
/// removed, whatever happened. The exit code is the failing step's: its
/// own, 128+n for one killed by signal n on unix (the shell's, and what a
/// single exec'd command gives; Cc15), 1 for another end on Windows, as
/// run has it; cannotRun's for a step that would not start. `env` is for
/// zig's steps only (the libc++ mirror's ZIG_LIB_DIR).
fn runSteps(ctx: *Ctx, blocks: []const Block, tmp: []const u8, env: ?*const std.process.Environ.Map) u8 {
    defer for (ctx.discard.items) |p| Io.Dir.cwd().deleteFile(ctx.io, p) catch {};
    Io.Dir.cwd().createDirPath(ctx.io, tmp) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ tmp, err });
        return 1;
    };
    defer Io.Dir.cwd().deleteTree(ctx.io, tmp) catch |err| ctx.warn("cannot remove {s}: {t}", .{ tmp, err });
    for (blocks) |b| {
        var child = std.process.spawn(ctx.io, .{ .argv = b.argv, .environ_map = if (b.zig) env else null }) catch |err| return cannotRun(ctx, b.argv[0], err);
        const term = child.wait(ctx.io) catch |err| {
            ctx.warn("waiting for {s}: {t}", .{ b.argv[0], err });
            return 1;
        };
        const code: u8 = switch (term) {
            .exited => |c| c,
            .signal => |sig| if (builtin.os.tag == .windows) 1 else 128 +| @as(u8, @truncate(@intFromEnum(sig))),
            else => 1,
        };
        if (code != 0) return code;
    }
    return 0;
}

fn cannotRun(ctx: *Ctx, cmd: []const u8, err: anyerror) u8 {
    ctx.warn("cannot run {s}: {t}", .{ cmd, err });
    return switch (err) {
        error.FileNotFound, error.NotDir => 127,
        else => 126,
    };
}

test toolName {
    try std.testing.expectEqualStrings("gcc", toolName("C:/env/Library/lib/R/bin/toolchain/gcc.exe"));
    try std.testing.expectEqualStrings("g++", toolName("g++.EXE"));
    try std.testing.expectEqualStrings("zig-cc", toolName("/p/lib/R/bin/toolchain/zig-cc"));
    try std.testing.expectEqualStrings("zig-cc.sh", toolName("zig-cc.sh"));
    try std.testing.expect(Tool.fromName(toolName("x/g++.exe")) == .cxx);
    try std.testing.expect(Tool.fromName(toolName("rzig")) == null);
    // every name build.zig installs (installRzig)
    for ([_][]const u8{ "zig-cc", "gcc.exe" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .cc);
    for ([_][]const u8{ "zig-cxx", "g++.exe" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .cxx);
    for ([_][]const u8{ "zig-fc", "zig-fc.exe", "C:/env/Library/lib/R/bin/toolchain/zig-fc.EXE" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .fc);
    // Makeconf.win's AR and RANLIB (B43): zig-ar.exe and zig-ranlib.exe
    for ([_][]const u8{ "zig-ar", "zig-ar.exe", "C:/env/Library/lib/R/bin/toolchain/zig-ar.exe" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .ar);
    for ([_][]const u8{ "zig-ranlib", "zig-ranlib.exe", "C:/env/Library/lib/R/bin/toolchain/zig-ranlib.EXE" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .ranlib);
    // Makeconf.win's LTO names (B43): zig-ar and zig-ranlib, in messages too
    for ([_][]const u8{ "gcc-ar", "gcc-ar.exe", "C:/env/Library/lib/R/bin/toolchain/gcc-ar.EXE" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .ar);
    for ([_][]const u8{ "gcc-ranlib", "gcc-ranlib.exe" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .ranlib);
    try std.testing.expectEqualStrings("zig-ar", Tool.fromName("gcc-ar").?.shimName());
    try std.testing.expectEqualStrings("zig-ranlib", Tool.fromName("gcc-ranlib").?.shimName());
    // ar.exe and ranlib.exe, what CMake finds beside gcc.exe: zig-ar and zig-ranlib too
    for ([_][]const u8{ "ar.exe", "C:/env/Library/lib/R/bin/toolchain/ar.EXE" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .ar);
    for ([_][]const u8{ "ranlib.exe", "C:/env/Library/lib/R/bin/toolchain/ranlib.exe" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == .ranlib);
    // gcc-nm and nm are not (B43-2, B24): conda-forge's binutils/nm.exe
    for ([_][]const u8{ "gcc-nm", "gcc-nm.exe", "nm", "nm.exe" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == null);
    // no other Fortran name: FC is zig-fc, flang and gfortran stay themselves
    for ([_][]const u8{ "flang", "gfortran.exe", "zig-f77" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == null);
    // 8.3 short names name no tool; the long path does (R1, Windows only)
    for ([_][]const u8{ "C:/env/Library/lib/R/bin/TOOLCH~1/G__~1.EXE", "GCC~1.EXE", "ZIG-RA~1.EXE" }) |n| try std.testing.expect(Tool.fromName(toolName(n)) == null);
}

test printArgv {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var env: std.process.Environ.Map = .init(arena.allocator());
    try env.put("ZIG_LIB_DIR", "/cache/r-zig/zig-lib-1/lib/zig");
    // `{ echo first; RZIG_PRINT_ARGV=1 zig-cc -c a.c; } > out`: one open
    // file, its offset past what the shell wrote
    const file = try tmp.dir.createFile(io, "out", .{});
    defer file.close(io);
    var w = file.writerStreaming(io, &.{});
    try w.interface.writeAll("first\n");
    try std.testing.expectEqual(0, try printArgv(io, file, &env, &.{.{ .argv = &.{ "/z/zig", "cc", "-c", "a.c" }, .zig = true }}));
    try std.testing.expectEqual(0, try printArgv(io, file, &env, &.{.{ .argv = &.{"ranlib"}, .zig = false }}));
    const got = try tmp.dir.readFileAlloc(io, "out", arena.allocator(), .limited(4096));
    try std.testing.expectEqualStrings(
        "first\nZIG_LIB_DIR=/cache/r-zig/zig-lib-1/lib/zig\n/z/zig\ncc\n-c\na.c\nZIG_LIB_DIR=/cache/r-zig/zig-lib-1/lib/zig\nranlib\n",
        got,
    );
}

test "printArgv: a split's steps, `&&` between them, ZIG_LIB_DIR before zig's block only (Cc6)" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var env: std.process.Environ.Map = .init(arena.allocator());
    const blocks = [_]Block{
        .{ .argv = &.{ "/tc/flang/bin/flang", "-c", "a.f90", "-o", "/t/rzig-fc-dryrun/0-a.o" }, .zig = false },
        .{ .argv = &.{ "/tc/flang/bin/flang", "-c", "b.f90", "-o", "/t/rzig-fc-dryrun/1-b.o" }, .zig = false },
        .{ .argv = &.{ "/z/zig", "cc", "-o", "p", "/t/rzig-fc-dryrun/0-a.o", "/t/rzig-fc-dryrun/1-b.o" }, .zig = true },
    };
    {
        const file = try tmp.dir.createFile(io, "plain", .{});
        defer file.close(io);
        _ = try printArgv(io, file, &env, &blocks);
    }
    try env.put("ZIG_LIB_DIR", "/m/lib/zig");
    {
        const file = try tmp.dir.createFile(io, "mirror", .{});
        defer file.close(io);
        _ = try printArgv(io, file, &env, &blocks);
    }
    const flang_part = "/tc/flang/bin/flang\n-c\na.f90\n-o\n/t/rzig-fc-dryrun/0-a.o\n&&\n/tc/flang/bin/flang\n-c\nb.f90\n-o\n/t/rzig-fc-dryrun/1-b.o\n&&\n";
    const zig_part = "/z/zig\ncc\n-o\np\n/t/rzig-fc-dryrun/0-a.o\n/t/rzig-fc-dryrun/1-b.o\n";
    try std.testing.expectEqualStrings(flang_part ++ zig_part, try tmp.dir.readFileAlloc(io, "plain", arena.allocator(), .limited(4096)));
    try std.testing.expectEqualStrings(flang_part ++ "ZIG_LIB_DIR=/m/lib/zig\n" ++ zig_part, try tmp.dir.readFileAlloc(io, "mirror", arena.allocator(), .limited(4096)));
}

test "runSteps: the first failing step's code, 128+n for a signal, no later step, tmp removed" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // /bin/sh stand-ins
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const later = f.path("later-ran");
    const touch_later: Block = .{ .argv = &.{ "/bin/sh", "-c", f.fmt(": > '{s}'", .{later}) }, .zig = false };
    const cases = [_]struct { first: Block, code: u8 }{
        .{ .first = .{ .argv = &.{ "/bin/sh", "-c", "exit 0" }, .zig = false }, .code = 0 },
        .{ .first = .{ .argv = &.{ "/bin/sh", "-c", "exit 3" }, .zig = false }, .code = 3 },
        .{ .first = .{ .argv = &.{ "/bin/sh", "-c", "kill -TERM $$" }, .zig = false }, .code = 143 },
        .{ .first = .{ .argv = &.{f.path("no-such-program")}, .zig = false }, .code = 127 },
    };
    for (cases) |case| {
        const tmp = f.path("t/rzig-fc-x");
        // the step sees its directory, and leaves an object in it
        const in_tmp: Block = .{ .argv = &.{ "/bin/sh", "-c", f.fmt("test -d '{s}' && : > '{s}/0-a.o'", .{ tmp, tmp }) }, .zig = false };
        try std.testing.expectEqual(case.code, runSteps(c, &.{ in_tmp, case.first, touch_later }, tmp, null));
        try std.testing.expect(!c.exists(tmp));
        try std.testing.expectEqual(case.code == 0, c.exists(later));
        Io.Dir.cwd().deleteFile(c.io, later) catch {};
    }
    _ = f.takeWarnings();
    // ctx.discard is removed after the steps too
    try f.touch("x.rzig.lib");
    try c.discard.append(c.arena, f.path("x.rzig.lib"));
    try std.testing.expectEqual(0, runSteps(c, &.{touch_later}, f.path("t/rzig-fc-y"), null));
    try std.testing.expect(!c.exists(f.path("x.rzig.lib")));
}

test shellCommand {
    var buf: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{f}", .{shellCommand(&.{ "/z/zig", "cc", "-DX=\"a b\"", "it's", "", "-I/a b", "-Wl,-rpath,/e/lib" })});
    try std.testing.expectEqualStrings("/z/zig cc '-DX=\"a b\"' 'it'\\''s' '' '-I/a b' -Wl,-rpath,/e/lib", s);
}

test {
    _ = @import("cmdline.zig");
    _ = @import("cache.zig");
    _ = @import("linker_args.zig");
    _ = @import("archives.zig");
    _ = @import("dso_fini.zig");
    _ = @import("cfguard.zig");
    _ = @import("strip.zig");
    _ = @import("darwin.zig");
    _ = @import("windows.zig");
    _ = @import("environment.zig");
    _ = @import("flang_rt.zig");
    _ = @import("makefile.zig");
    _ = @import("shellwords.zig");
    _ = response;
    _ = @import("pkgplan.zig");
    _ = pkgbuild;
    _ = @import("tier1.zig");
    _ = def;
    _ = check;
    _ = groups;
    _ = compiler;
    _ = fortran;
    _ = ar;
    _ = find_zig;
    _ = libcxx_mirror;
}

test "rzig's root panic and debug are crash.zig's (K4)" {
    // rzig-test's root is zig's test runner, so tier1.zig's crash test
    // runs testdata/crash.zig's decls, never these
    comptime std.debug.assert(panic == crash.panic and debug == crash.debug);
}
