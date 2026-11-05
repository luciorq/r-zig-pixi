//! A compiler and linker stand-in for tier1.zig's tests, in Zig, so they
//! run on every OS (no shell). build.zig builds it for the tests' target
//! and embeds it in rzig-test, which writes it out as a program.
//!
//! A compile (`-c <source> -o <object>`) runs its source's lines in order,
//! then writes the object: its own arguments, one a line, so a test sees
//! the words it was given. Paths are relative to the working directory
//! (the plan's srcdir):
//!   sleep <ms>    sleep
//!   wait <file>   until <file> exists; exit 9 after 20 s
//!   need <file>   exit 8 unless <file> exists (a module a `use` reads)
//!   make <file>   write <file> (a module's .mod)
//!   alone <file>  create <file>, exit 7 if it is there (another compile
//!                 holds it); removed at the end
//!   exit <n>      exit n at once
//!   kill          end by SIGKILL, as the OOM killer ends a compile (not
//!                 on Windows: exit 1)
//! With FAKE_CC_DIR set, the compiles count each other: while one runs,
//! <dir>/running/<n> exists, n being its object's directory's name
//! (tier1.zig's obj/<n>/), and <dir>/peak/<n> holds the most it saw
//! running, itself included, when it started and after its lines.
//!
//! A link (no -c): each object, on the command line (*.o) or in an @file
//! (one `"<name>"` a line), must exist, else exit 6; `-o <lib>` gets their
//! names, one a line, in link order.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    var source: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var objects: std.ArrayList([]const u8) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (mem.eql(u8, x, "-c") and i + 1 < args.len) {
            i += 1;
            source = args[i];
        } else if (mem.eql(u8, x, "-o") and i + 1 < args.len) {
            i += 1;
            out = args[i];
        } else if (mem.startsWith(u8, x, "@")) {
            const text = try Io.Dir.cwd().readFileAlloc(io, x[1..], a, .limited(1 << 20));
            var lines = mem.tokenizeAny(u8, text, "\r\n");
            while (lines.next()) |l| try objects.append(a, mem.trim(u8, l, "\""));
        } else if (mem.endsWith(u8, x, ".o")) try objects.append(a, x);
    }
    const o = out orelse return 2;
    const cwd = Io.Dir.cwd();
    if (source) |s| return compile(io, a, init.environ_map.get("FAKE_CC_DIR"), args[1..], s, o);
    var list: std.ArrayList(u8) = .empty;
    for (objects.items) |obj| {
        if (!exists(io, obj)) return 6;
        try list.print(a, "{s}\n", .{obj});
    }
    try cwd.writeFile(io, .{ .sub_path = o, .data = list.items });
    return 0;
}

fn compile(io: Io, a: mem.Allocator, count_dir: ?[]const u8, argv: []const []const u8, source: []const u8, out: []const u8) !u8 {
    const cwd = Io.Dir.cwd();
    const n = std.fs.path.basename(std.fs.path.dirname(out) orelse ".");
    var running: ?[]const u8 = null;
    var seen: usize = 0;
    if (count_dir) |d| {
        running = try std.fmt.allocPrint(a, "{s}/running/{s}", .{ d, n });
        try cwd.createDirPath(io, try std.fmt.allocPrint(a, "{s}/running", .{d}));
        try cwd.createDirPath(io, try std.fmt.allocPrint(a, "{s}/peak", .{d}));
        try cwd.writeFile(io, .{ .sub_path = running.?, .data = "" });
        seen = try countRunning(io, a, d);
    }
    defer if (running) |r| cwd.deleteFile(io, r) catch {};
    // after the lines too: of compiles that start together, the last to
    // start may count before the others have, but the first to end counts
    // them all
    defer if (count_dir) |d| {
        seen = @max(seen, countRunning(io, a, d) catch 0);
        cwd.writeFile(io, .{ .sub_path = std.fmt.allocPrint(a, "{s}/peak/{s}", .{ d, n }) catch "", .data = std.fmt.allocPrint(a, "{d}", .{seen}) catch "" }) catch {};
    };
    var held: ?[]const u8 = null;
    defer if (held) |h| cwd.deleteFile(io, h) catch {};
    const text = try cwd.readFileAlloc(io, source, a, .limited(1 << 20));
    var lines = mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        var words = mem.tokenizeScalar(u8, line, ' ');
        const op = words.next() orelse continue;
        const arg = words.next() orelse "";
        if (mem.eql(u8, op, "sleep")) {
            try io.sleep(.fromMilliseconds(try std.fmt.parseInt(i64, arg, 10)), .awake);
        } else if (mem.eql(u8, op, "wait")) {
            var waited: usize = 0;
            while (!exists(io, arg)) : (waited += 1) {
                if (waited == 2000) return 9;
                try io.sleep(.fromMilliseconds(10), .awake);
            }
        } else if (mem.eql(u8, op, "need")) {
            if (!exists(io, arg)) return 8;
        } else if (mem.eql(u8, op, "make")) {
            try cwd.writeFile(io, .{ .sub_path = arg, .data = "" });
        } else if (mem.eql(u8, op, "alone")) {
            const f = cwd.createFile(io, arg, .{ .exclusive = true }) catch |err| switch (err) {
                error.PathAlreadyExists => return 7,
                else => |e| return e,
            };
            f.close(io);
            held = arg;
        } else if (mem.eql(u8, op, "exit")) {
            return std.fmt.parseInt(u8, arg, 10);
        } else if (mem.eql(u8, op, "kill")) {
            if (builtin.os.tag != .windows) try std.posix.raise(.KILL);
            return 1;
        }
    }
    var words: std.ArrayList(u8) = .empty;
    for (argv) |w| try words.print(a, "{s}\n", .{w});
    try cwd.writeFile(io, .{ .sub_path = out, .data = words.items });
    return 0;
}

fn countRunning(io: Io, a: mem.Allocator, count_dir: []const u8) !usize {
    var dir = try Io.Dir.cwd().openDir(io, try std.fmt.allocPrint(a, "{s}/running", .{count_dir}), .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    var count: usize = 0;
    while (try it.next(io)) |_| count += 1;
    return count;
}

fn exists(io: Io, path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}
