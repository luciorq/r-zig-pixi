//! bootgate: lets `zig build` skip R's bootstrap when nothing it reads has
//! changed since the last one finished (build.zig's bootstrap(); backlog
//! M-19, .github/devdocs/wave2-build/PLAN.md).
//!
//!   bootgate check <stamp> <decision-out> <key>... -- <dir>...
//!   bootgate run <decision> -- <command>...
//!   bootgate stamp <stamp> <decision> <key>... -- <dir>...
//!
//! The state is one digest: the keys (build.zig's digest of every bootstrap
//! step's command, stdin, environment and working directory, and the
//! staged library payload's path, which zig's cache names by content) and,
//! for each dir, every entry under it: path, kind, size and mtime (not the
//! mode: the install step resets the launchers' mode on every build, and
//! the bootstrap's chmod, which always runs, sets it again; a directory's
//! path only, as the install step's atomic copies change its mtime).
//!
//! check, after the install step, decides for the whole bootstrap: "skip"
//! when the stamp holds this digest, else "run". The decision's second
//! line is the bootstrap's time, which it writes as each package's
//! `Built:` time: the stamp's on a skip; on a run SOURCE_DATE_EPOCH when
//! set, else now. A run removes the stamp first, so a bootstrap that
//! fails or is interrupted runs again next time.
//!
//! run wraps every bootstrap step: on "run" it runs the command (exec on
//! unix; on Windows a child whose exit code it passes on), on "skip" it
//! reads its stdin to the end (the R steps' code) and exits 0.
//!
//! stamp, after the last step, writes the digest of the tree as the
//! bootstrap left it, with its time.
//!
//! R_ZIG_BOOTGATE_LIST on (1, true or yes; rzig/onoff.zig): what the
//! digest covers goes beside the stamp, as <stamp>.check.list and
//! <stamp>.stamp.list, to see why it ran.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Sha256 = std.crypto.hash.sha2.Sha256;
const onoff = @import("rzig/onoff.zig");

const usage =
    \\usage: bootgate check <stamp> <decision-out> <key>... -- <dir>...
    \\       bootgate run <decision> -- <command>...
    \\       bootgate stamp <stamp> <decision> <key>... -- <dir>...
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const cwd = Io.Dir.cwd();
    if (args.len >= 5 and std.mem.eql(u8, args[1], "run") and std.mem.eql(u8, args[3], "--")) {
        return runStep(arena, io, args[2], args[4..]);
    }
    if (args.len < 5) {
        std.debug.print("{s}", .{usage});
        return 2;
    }
    const mode = args[1];
    const stamp = args[2];
    const decision_path = args[3];
    const sep = for (args[4..], 4..) |a, i| {
        if (std.mem.eql(u8, a, "--")) break i;
    } else {
        std.debug.print("{s}", .{usage});
        return 2;
    };
    var list: std.ArrayList(u8) = .empty;
    const list_var = init.environ_map.get("R_ZIG_BOOTGATE_LIST");
    const want_list = switch (onoff.parse(list_var)) {
        .on => true,
        .off => false,
        .other => blk: {
            std.debug.print("bootgate: " ++ onoff.message ++ "\n", .{ "R_ZIG_BOOTGATE_LIST", list_var.? });
            break :blk false;
        },
    };
    const digest = try treeDigest(arena, io, args[4..sep], args[sep + 1 ..], if (want_list) &list else null);
    if (want_list) {
        if (std.fs.path.dirname(stamp)) |d| try cwd.createDirPath(io, d);
        try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}.{s}.list", .{ stamp, mode }), .data = list.items });
    }

    if (std.mem.eql(u8, mode, "check")) {
        const old = cwd.readFileAlloc(io, stamp, arena, .limited(4096)) catch null;
        if (old) |o| if (std.mem.startsWith(u8, o, &digest) and o.len > digest.len and o[digest.len] == '\n') {
            const built = std.mem.trimEnd(u8, o[digest.len + 1 ..], "\n");
            try cwd.writeFile(io, .{ .sub_path = decision_path, .data = try std.fmt.allocPrint(arena, "skip\n{s}\n", .{built}) });
            std.debug.print("r-zig: bootstrap inputs unchanged since {s}: not running it again\n", .{built});
            return 0;
        };
        cwd.deleteFile(io, stamp) catch |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return e,
        };
        const built = try builtTime(arena, io, init.environ_map);
        try cwd.writeFile(io, .{ .sub_path = decision_path, .data = try std.fmt.allocPrint(arena, "run\n{s}\n", .{built}) });
        return 0;
    }
    if (std.mem.eql(u8, mode, "stamp")) {
        const d = try cwd.readFileAlloc(io, decision_path, arena, .limited(4096));
        const nl = std.mem.indexOfScalar(u8, d, '\n') orelse return error.BadDecision;
        const tmp = try std.fmt.allocPrint(arena, "{s}.tmp", .{stamp});
        if (std.fs.path.dirname(stamp)) |dir| try cwd.createDirPath(io, dir);
        try cwd.writeFile(io, .{ .sub_path = tmp, .data = try std.fmt.allocPrint(arena, "{s}\n{s}", .{ &digest, d[nl + 1 ..] }) });
        try cwd.rename(tmp, cwd, stamp, io);
        return 0;
    }
    std.debug.print("{s}", .{usage});
    return 2;
}

fn runStep(arena: std.mem.Allocator, io: Io, decision_path: []const u8, argv: []const []const u8) !u8 {
    const d = try Io.Dir.cwd().readFileAlloc(io, decision_path, arena, .limited(4096));
    if (std.mem.startsWith(u8, d, "skip\n")) {
        // the Run step writes the R code to stdin: take all of it, so
        // that it never writes to a closed pipe
        var buf: [4096]u8 = undefined;
        var r = Io.File.stdin().readerStreaming(io, &buf);
        _ = r.interface.discardRemaining() catch {};
        return 0;
    }
    if (!std.mem.startsWith(u8, d, "run\n")) return error.BadDecision;
    if (builtin.os.tag == .windows) {
        var child = try std.process.spawn(io, .{ .argv = argv });
        return switch (try child.wait(io)) {
            .exited => |code| code,
            else => 1,
        };
    }
    const err = std.process.replace(io, .{ .argv = argv });
    std.debug.print("error: cannot run {s}: {t}\n", .{ argv[0], err });
    return 127;
}

const Entry = struct { path: []const u8, line: []const u8 };

fn lessThan(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn treeDigest(arena: std.mem.Allocator, io: Io, keys: []const []const u8, dirs: []const []const u8, list: ?*std.ArrayList(u8)) ![Sha256.digest_length * 2]u8 {
    var h = Sha256.init(.{});
    h.update("bootgate 1\x00");
    for (keys) |k| {
        h.update(k);
        h.update("\x00");
        if (list) |l| try l.print(arena, "key {s}\n", .{k});
    }
    for (dirs) |d| {
        h.update("dir\x00");
        h.update(d);
        h.update("\x00");
        var dir = Io.Dir.cwd().openDir(io, d, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                h.update("missing\x00");
                continue;
            },
            else => |e| return e,
        };
        defer dir.close(io);
        var entries: std.ArrayList(Entry) = .empty;
        var walker = try dir.walk(arena);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            const st = try e.dir.statFile(io, e.basename, .{ .follow_symlinks = false });
            const path = try arena.dupe(u8, e.path);
            std.mem.replaceScalar(u8, path, '\\', '/');
            // a directory by its name only: the install step's atomic
            // copies change its mtime on every build
            const line = if (st.kind == .directory)
                try std.fmt.allocPrint(arena, "{s}\x00directory\n", .{path})
            else
                try std.fmt.allocPrint(arena, "{s}\x00{t}\x00{d}\x00{d}\n", .{ path, st.kind, st.size, st.mtime.nanoseconds });
            try entries.append(arena, .{ .path = path, .line = line });
        }
        std.mem.sort(Entry, entries.items, {}, lessThan);
        for (entries.items) |e| {
            h.update(e.line);
            if (list) |l| try l.print(arena, "{s}/{s}", .{ d, e.line });
        }
    }
    var out: [Sha256.digest_length]u8 = undefined;
    h.final(&out);
    return std.fmt.bytesToHex(out, .lower);
}

/// `YYYY-MM-DD HH:MM:SS UTC`, as R writes a `Built:` time: SOURCE_DATE_EPOCH
/// (https://reproducible-builds.org/specs/source-date-epoch/) when set,
/// else now.
fn builtTime(arena: std.mem.Allocator, io: Io, env: *const std.process.Environ.Map) ![]const u8 {
    const secs: u64 = if (env.get("SOURCE_DATE_EPOCH")) |sde|
        std.fmt.parseInt(u64, std.mem.trim(u8, sde, " \n\r\t"), 10) catch {
            std.debug.print("error: SOURCE_DATE_EPOCH must be an integer unix time, not '{s}'\n", .{sde});
            return error.SourceDateEpoch;
        }
    else blk: {
        const ts = Io.Clock.real.now(io);
        break :blk @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
    };
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.allocPrint(arena, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
        yd.year,              md.month.numeric(),      md.day_index + 1,
        ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute(),
    });
}
