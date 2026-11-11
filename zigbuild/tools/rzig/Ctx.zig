//! What the applets ask of the outside world: the environment, the file
//! system, other programs, and which OS's quirks apply. One per run;
//! everything it hands out lives in `arena` until rzig exits or execs.
const Ctx = @This();

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Allocator = mem.Allocator;

pub const Os = enum {
    linux,
    macos,
    windows,
    other,

    pub const host: Os = switch (builtin.os.tag) {
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        else => .other,
    };
};

io: Io,
arena: Allocator,
env: *std.process.Environ.Map,
/// Whose quirks apply: the bash shims' `uname -s` branches. The host's,
/// except in dry-run, where RZIG_OS can choose (see main.zig). Host
/// mechanics (PATH separator, `.exe`, exec or spawn) never follow it.
os: Os,
/// The shim this run stands for, in messages ("zig-cc", ...).
name: []const u8,
/// This binary's own path (symlinks resolved, `/` separators), from which
/// environment.zig finds the environment; null when the OS would not say.
self_exe: ?[]const u8 = null,
/// What asks macOS for the SDK. A test hook may point it elsewhere.
xcrun: []const u8 = "/usr/bin/xcrun",
/// The command that runs zig (find_zig.zig), for main.zig's run. main.zig
/// sets it, null when there is no zig (a command that runs zig then
/// stops, naming the compilers group); unit tests leave it null or point
/// it at a stand-in.
zig: ?[]const []const u8 = null,
/// Unit tests collect `warn`'s messages here instead of stderr.
warnings: ?*std.ArrayList(u8) = null,
/// Unit tests collect `echo`'s lines here instead of stdout (the test
/// runner talks to zig build on its stdout).
echoed: ?*std.ArrayList(u8) = null,
/// Files the command writes that nobody keeps (a Windows link's import
/// library, windows.implib): main.zig's run deletes them when the command
/// is done. Windows only, where rzig waits for the command; on unix it
/// becomes the command (execve), and only a dry run adds to this there.
/// After a command of several steps (`steps`, zig-fc's split), which rzig
/// waits for on every OS, they are deleted too.
discard: std.ArrayList([]const u8) = .empty,
/// RZIG_PRINT_ARGV: nothing will run (main.zig). zig-fc's split then
/// names its temporary directory `rzig-fc-dryrun`, so the printed
/// commands are the same on every run, and nothing creates it.
dry_run: bool = false,

/// `${NAME:-}`: the shims treat unset and empty alike.
pub fn getenv(ctx: *const Ctx, name: []const u8) ?[]const u8 {
    const v = ctx.env.get(name) orelse return null;
    return if (v.len == 0) null else v;
}

fn kind(ctx: *const Ctx, path: []const u8) ?Io.File.Kind {
    if (path.len == 0) return null;
    const st = Io.Dir.cwd().statFile(ctx.io, path, .{}) catch return null;
    return st.kind;
}

/// `[ -f path ]`: a regular file, symlinks followed.
pub fn isFile(ctx: *const Ctx, path: []const u8) bool {
    return ctx.kind(path) == .file;
}

/// `[ -d path ]`
pub fn isDir(ctx: *const Ctx, path: []const u8) bool {
    return ctx.kind(path) == .directory;
}

/// `[ -e path ]`
pub fn exists(ctx: *const Ctx, path: []const u8) bool {
    return ctx.kind(path) != null;
}

pub fn fmt(ctx: *const Ctx, comptime f: []const u8, args: anytype) Allocator.Error![]const u8 {
    return std.fmt.allocPrint(ctx.arena, f, args);
}

/// Messages go to stderr prefixed with the shim's name, as the bash
/// shims' did. Written at once, as `echo` is: std.debug.print writes in
/// 64-byte pieces, and tier1.zig's echo of a parallel job could land
/// between them (RZIG_TRACE lines, which pkg-parity compares).
pub fn warn(ctx: *const Ctx, comptime f: []const u8, args: anytype) void {
    if (ctx.warnings) |w| {
        w.print(ctx.arena, "{s}: " ++ f ++ "\n", .{ctx.name} ++ args) catch {};
        return;
    }
    const text = ctx.fmt("{s}: " ++ f ++ "\n", .{ctx.name} ++ args) catch {
        std.debug.print("{s}: " ++ f ++ "\n", .{ctx.name} ++ args);
        return;
    };
    Io.File.stderr().writeStreamingAll(ctx.io, text) catch {};
}

/// A command line on stdout before the command runs, as make echoes its
/// recipes (tier1.zig): written at once, so it comes before what the
/// command prints.
pub fn echo(ctx: *const Ctx, line: []const u8) void {
    if (ctx.echoed) |e| {
        e.print(ctx.arena, "{s}\n", .{line}) catch {};
        return;
    }
    const text = ctx.fmt("{s}\n", .{line}) catch return;
    Io.File.stdout().writeStreamingAll(ctx.io, text) catch {};
}

/// What an applet runs: zig, with these arguments after its own path
/// (main.zig finds zig, and for the compilers prepares the libc++ mirror),
/// or another program, a whole command (zig-fc's flang), or several of
/// those in order.
pub const Command = union(enum) {
    zig: []const []const u8,
    program: []const []const u8,
    /// A call that compiles sources and links (zig-fc's split,
    /// fortran.zig): each step in order until one fails, that step's exit
    /// code, then `tmp` (the steps' objects) removed, whatever happened.
    steps: struct { steps: []const Step, tmp: []const u8 },
};

/// One step of `Command.steps`: zig's arguments or a whole command, as
/// in Command.
pub const Step = union(enum) {
    zig: []const []const u8,
    program: []const []const u8,
};

pub const Output = struct {
    /// It ran and exited 0.
    ok: bool,
    /// What it printed, with the trailing newlines removed as `$(...)`
    /// does; "" when it could not run.
    stdout: []const u8,
    /// Why it did not run to an exit of its own, for check.zig's "did not
    /// run": the error that kept it from starting (InvalidExe for a file
    /// that is no program), or the signal that ended it. null when it
    /// exited, whatever its code.
    not_run: ?[]const u8 = null,
};

/// `argv > /dev/null`: run a program, its stdin and stdout discarded, its
/// stderr passed on (what it says when it fails is the user's to see).
/// Whether it ran and exited 0. argv[0] as for `capture`.
pub fn succeeds(ctx: *const Ctx, argv: []const []const u8) bool {
    var child = std.process.spawn(ctx.io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
        .create_no_window = true,
    }) catch return false;
    const term = child.wait(ctx.io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// `$(argv 2>/dev/null)`: run a program, its stdin and stderr discarded,
/// and keep its standard output. argv[0] should be a path (see
/// find_zig.onPath): a bare name would be looked up in rzig's own PATH, not
/// in `ctx.env`'s.
pub fn capture(ctx: *const Ctx, argv: []const []const u8) Output {
    var child = std.process.spawn(ctx.io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
        .create_no_window = true,
    }) catch |err| return .{ .ok = false, .stdout = "", .not_run = @errorName(err) };
    defer child.kill(ctx.io);
    var buf: [4096]u8 = undefined;
    var r = child.stdout.?.readerStreaming(ctx.io, &buf);
    const out = mem.trimEnd(u8, r.interface.allocRemaining(ctx.arena, .limited(1 << 20)) catch "", "\n");
    const term = child.wait(ctx.io) catch |err| return .{ .ok = false, .stdout = out, .not_run = @errorName(err) };
    return switch (term) {
        .exited => |code| .{ .ok = code == 0, .stdout = out },
        .signal => |sig| .{ .ok = false, .stdout = out, .not_run = ctx.fmt("killed by signal {d}", .{@backingInt(sig)}) catch "killed by a signal" },
        .stopped => |sig| .{ .ok = false, .stdout = out, .not_run = ctx.fmt("stopped by signal {d}", .{@backingInt(sig)}) catch "stopped by a signal" },
        .unknown => |status| .{ .ok = false, .stdout = out, .not_run = ctx.fmt("ended with status {d}", .{status}) catch "ended with an unknown status" },
    };
}
