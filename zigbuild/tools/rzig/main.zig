//! rzig: R's compiler toolchain front, one binary for every OS (phase F3
//! of feat-no-host-paths). It replaces the bash shims toolchain/zig-cc,
//! zig-cxx, zig-ar, zig-ranlib and the Windows gcc.exe/g++.exe forwarders
//! (zigbuild/tools/win-exec-forward.c, which ran the shims through bash),
//! and dispatches on its own name, like busybox:
//!
//!   zig-cc, gcc       zig cc   with the shims' argument rewriting
//!   zig-cxx, g++      zig c++  likewise
//!   zig-ar            zig ar   (macOS: seeds a missing archive)
//!   zig-ranlib        zig ranlib
//!   rzig <name> ...   the same, naming the tool explicitly
//!
//! build.zig installs it under those names into R_HOME/bin/toolchain, the
//! directory Makeconf names (Windows: gcc.exe and g++.exe, Makeconf.win's
//! $(BINPREF)gcc and g++). On unix rzig replaces itself with zig (execve);
//! on Windows it runs zig and exits with its exit code.
//!
//! Test hooks (not for builds):
//!   RZIG_PRINT_ARGV=1  print what would run instead of running it: the
//!                      child's ZIG_LIB_DIR as `ZIG_LIB_DIR=<value>` when
//!                      it has one, then the argv, one per line. Side
//!                      effects of preparing the call still happen (the
//!                      libc++ mirror, ar's archive seed, asking flang and
//!                      xcrun).
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
const ar = @import("ar.zig");
const find_zig = @import("find_zig.zig");
const libcxx_mirror = @import("libcxx_mirror.zig");

const Tool = enum {
    cc,
    cxx,
    ar,
    ranlib,

    fn fromName(name: []const u8) ?Tool {
        const map = std.StaticStringMap(Tool).initComptime(.{
            .{ "zig-cc", .cc },   .{ "gcc", .cc },
            .{ "zig-cxx", .cxx }, .{ "g++", .cxx },
            .{ "zig-ar", .ar },   .{ "zig-ranlib", .ranlib },
        });
        return map.get(name);
    }

    /// The shim it stands for, in messages.
    fn shimName(t: Tool) []const u8 {
        return switch (t) {
            .cc => "zig-cc",
            .cxx => "zig-cxx",
            .ar => "zig-ar",
            .ranlib => "zig-ranlib",
        };
    }
};

const usage =
    \\usage: zig-cc|zig-cxx|zig-ar|zig-ranlib|gcc|g++ [args...]
    \\       rzig <one of those names> [args...]
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
    if (tool == null and args.len > 1) {
        tool = Tool.fromName(toolName(args[1]));
        args = args[1..];
    }
    const t = tool orelse {
        std.debug.print("{s}", .{usage});
        return 2;
    };

    const env = init.environ_map;
    const dry_run = if (env.get("RZIG_PRINT_ARGV")) |v| v.len > 0 and !mem.eql(u8, v, "0") else false;
    var ctx: Ctx = .{
        .io = io,
        .arena = arena,
        .env = env,
        .os = Ctx.Os.host,
        .name = t.shimName(),
        .self_exe = selfExe(io, arena, arg0),
    };
    if (dry_run) {
        if (env.get("RZIG_OS")) |v| ctx.os = std.meta.stringToEnum(Ctx.Os, v) orelse {
            std.debug.print("rzig: RZIG_OS must be linux, macos or windows, not '{s}'\n", .{v});
            return 2;
        };
        if (env.get("RZIG_XCRUN")) |v| ctx.xcrun = v;
    }

    const zig = try find_zig.find(&ctx);
    const caller = args[1..];
    var env_changed = false;
    const zig_args = switch (t) {
        .cc, .cxx => cc: {
            if (ctx.os != .windows) env_changed = try libcxx_mirror.apply(&ctx, zig[0]);
            break :cc try compiler.argv(&ctx, if (t == .cc) .c else .cxx, caller);
        },
        .ar => try ar.argv(&ctx, caller),
        .ranlib => try mem.concat(arena, []const u8, &.{ &.{"ranlib"}, caller }),
    };
    const argv = try mem.concat(arena, []const u8, &.{ zig, zig_args });

    if (dry_run) return printArgv(io, env, argv);
    return run(&ctx, argv, if (env_changed) env else null);
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
    return mem.replaceOwned(u8, arena, p, "\\", "/") catch null;
}

fn printArgv(io: Io, env: *const std.process.Environ.Map, argv: []const []const u8) !u8 {
    var buf: [4096]u8 = undefined;
    var w = Io.File.stdout().writer(io, &buf);
    const out = &w.interface;
    if (env.get("ZIG_LIB_DIR")) |v| try out.print("ZIG_LIB_DIR={s}\n", .{v});
    for (argv) |x| try out.print("{s}\n", .{x});
    try out.flush();
    return 0;
}

/// Exit codes as the shell gives for a command it cannot run: 127 not
/// found, 126 found but not runnable.
fn run(ctx: *Ctx, argv: []const []const u8, env: ?*const std.process.Environ.Map) u8 {
    if (builtin.os.tag == .windows) {
        // No exec on Windows: run zig with our standard handles and pass
        // its exit code on, as the forwarder did. The command line is
        // quoted by std (Microsoft's argv rules), so arguments with
        // embedded quotes, -DX='"a.h"', arrive intact (F7.7).
        var child = std.process.spawn(ctx.io, .{ .argv = argv, .environ_map = env }) catch |err| return cannotRun(ctx, argv[0], err);
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
    try std.testing.expect(Tool.fromName(toolName("zig-ar")) == .ar);
    try std.testing.expect(Tool.fromName(toolName("zig-ranlib")) == .ranlib);
}

test {
    _ = @import("cmdline.zig");
    _ = @import("darwin.zig");
    _ = @import("windows.zig");
    _ = @import("environment.zig");
    _ = @import("flang_rt.zig");
    _ = compiler;
    _ = ar;
    _ = find_zig;
    _ = libcxx_mirror;
}
