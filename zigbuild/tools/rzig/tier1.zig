//! Tier 1 without zig build (cr27 design C): rzig runs the plan itself,
//! the compiles in parallel and then the link, as build_t1.zig's graph did
//! through zig build, with nothing to compile first. zig build's build
//! runner for build_t1.zig (about 45 MB, 3 to 13 s per compile) and its
//! cache directory, key and sweep (feat-shared-build-runner) are gone with
//! it: build_t1.zig's steps had side effects and wrote outside zig build's
//! cache (outputFile), so zig build cached nothing of an install but the
//! runner. zig's global cache is the shared part, as before: std,
//! compiler_rt and zig cc's objects, keyed by the source as named and its
//! contents.
//!
//! The graph, as build_t1.zig had it:
//! - one compile per source, in srcdir, `<tool> <flags> -c <source> -o
//!   <root>/obj/<n>/<object's file name>`, up to `jobs` at a time;
//! - Fortran one after another in OBJECTS order when there is more than
//!   one (flang writes a module's .mod into srcdir, and a later `use`
//!   reads it there; feat-shlib-rzig-build Cc3); C and C++ stay parallel;
//! - after every compile, on Windows the .def from the objects (in
//!   process: def.zig, no `rzig def` child), then the link,
//!   `SHLIB_LINK -o out [def] objects ALL_LIBS`, the objects in
//!   <root>/objects.rsp (response.zig's rspName and rspText);
//! - the library copied to its destination, as zig build's install step
//!   did.
//! Tier 2 runs the same code for its C and C++ sources and its zig
//! object (`rzig t1`, from zigbuild/rpkg/rpkg.zig's addLibrary): one
//! implementation of the compile and link graph for both tiers.
//! A compile that fails stops new ones; those running finish, then 1, as
//! make without -k. The first failure's line names its exit code, or the
//! signal that ended it (`was killed by signal 9`: the OOM killer, not the
//! compiler, as make's `Error 137` tells). Each command line goes to
//! stdout before it runs, as make echoes its recipes into 00install.out
//! (feat-tier1-engine decision 3), and each child inherits stdout and
//! stderr, as make's do: a warning shows where the compile printed it.
//! The echo quotes as a POSIX shell reads it back (shellwords.quote, as
//! `--dry-run` prints), on Windows too.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const pkgplan = @import("pkgplan.zig");
const def = @import("def.zig");
const response = @import("response.zig");
const shellwords = @import("shellwords.zig");

pub const Options = struct {
    /// The build root, absolute: obj/, objects.rsp, the .def, the library.
    root: []const u8,
    /// The library's destination file: <out>/libs<R_ARCH>/<output>, or
    /// <out>/<output> (flat), or what tier 2's zig build names.
    dest: []const u8,
    /// Objects built before (tier 2's zig object), first on the link.
    objects: []const []const u8 = &.{},
    /// -j; 0: the CPU count.
    jobs: usize = 0,
};

/// One child process, its words made before any runs (the arena is not
/// shared across threads).
const Job = struct {
    argv: []const []const u8,
    cwd: []const u8,
    env: *const std.process.Environ.Map,
    /// argv as a shell reads it back (shellwords.quote): what is echoed,
    /// and what a failure names.
    line: []const u8,
};

fn commandLine(a: mem.Allocator, argv: []const []const u8) ![]const u8 {
    var line: std.ArrayList(u8) = .empty;
    for (argv, 0..) |w, i| {
        if (i > 0) try line.append(a, ' ');
        try line.appendSlice(a, try shellwords.quote(a, w));
    }
    return line.items;
}

/// `signal`: the child did not exit, a signal ended it (code 1).
const Result = struct { index: usize, code: u8, err: ?anyerror = null, signal: ?u32 = null };
const Done = union(enum) { done: Result };

fn runJob(io: Io, job: *const Job, index: usize) Result {
    var child = std.process.spawn(io, .{
        .argv = job.argv,
        .cwd = .{ .path = job.cwd },
        .environ_map = job.env,
        .stdin = .ignore,
        // as Ctx's spawns: no console window for each compile when rzig
        // has none (R's GUI). A child then takes no Ctrl-C from rzig's
        // console: rzig stops, and the running compiles finish on their
        // own, their objects in the build root (zig build's Run steps,
        // and make, shared the console). UNVERIFIED on kappa: no
        // interactive console there.
        .create_no_window = true,
    }) catch |err| return .{ .index = index, .code = 127, .err = err };
    const term = child.wait(io) catch |err| return .{ .index = index, .code = 1, .err = err };
    return switch (term) {
        .exited => |c| .{ .index = index, .code = c },
        .signal => |sig| .{ .index = index, .code = 1, .signal = if (builtin.os.tag == .windows) null else @intCast(@backingInt(sig)) },
        else => .{ .index = index, .code = 1 },
    };
}

/// How a child that did not succeed ended, for its failure's line.
fn ended(ctx: *Ctx, r: Result) ![]const u8 {
    return if (r.signal) |sig| ctx.fmt("was killed by signal {d}", .{sig}) else ctx.fmt("failed ({d})", .{r.code});
}

fn isFortran(lang: []const u8) bool {
    return mem.eql(u8, lang, "f") or mem.eql(u8, lang, "f9x");
}

fn driverFor(plan: *const pkgplan.Plan, lang: []const u8) struct { []const u8, []const []const u8 } {
    const l = std.meta.stringToEnum(pkgplan.Lang, lang) orelse unreachable; // pkgplan wrote it
    return switch (l) {
        .c => .{ plan.cc_tool, plan.cc },
        .cxx => .{ plan.cxx_tool, plan.cxx },
        .f => .{ plan.fc_tool, plan.fc },
        .f9x => .{ plan.fc_tool, plan.f9x },
    };
}

/// The number of jobs: -j, else the CPU count (zig build's default).
pub fn jobCount(given: ?[]const u8) usize {
    if (given) |j| if (std.fmt.parseInt(usize, j, 10) catch null) |n| if (n > 0) return n;
    return std.Thread.getCpuCount() catch 1;
}

/// The plan built into `o.dest`: 0, or 1 after a failed step (its words
/// on stderr, after what it printed itself).
pub fn build(ctx: *Ctx, plan: *const pkgplan.Plan, o: Options) !u8 {
    if (plan.sources.len == 0 and o.objects.len == 0) return 0; // make: `if test "z$(OBJECTS)" != "z"`
    const a = ctx.arena;
    var env = try ctx.env.clone(a);
    for (plan.env) |kv| {
        const eq = mem.indexOfScalar(u8, kv, '=') orelse continue;
        try env.put(kv[0..eq], kv[eq + 1 ..]);
    }
    const n = plan.sources.len;
    const objs = try a.alloc([]const u8, n);
    const jobs = try a.alloc(Job, n);
    var fortran: usize = 0;
    for (plan.sources, 0..) |s, i| {
        if (isFortran(s.lang)) fortran += 1;
        const dir = try ctx.fmt("{s}/obj/{d}", .{ o.root, i });
        Io.Dir.cwd().createDirPath(ctx.io, dir) catch |err| {
            ctx.warn("cannot create {s}: {t}", .{ dir, err });
            return 1;
        };
        objs[i] = try ctx.fmt("{s}/{s}", .{ dir, std.fs.path.basename(s.obj) });
        const tool, const flags = driverFor(plan, s.lang);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.append(a, try ctx.fmt("{s}/{s}", .{ plan.toolchain, tool }));
        try argv.appendSlice(a, flags);
        try argv.appendSlice(a, &.{ "-c", s.path, "-o", objs[i] });
        jobs[i] = .{ .argv = argv.items, .cwd = plan.srcdir, .env = &env, .line = try commandLine(a, argv.items) };
    }
    if (try compileAll(ctx, runJob, jobs, plan.sources, fortran > 1, if (o.jobs == 0) jobCount(null) else o.jobs) != 0) return 1;
    return link(ctx, plan, o, try mem.concat(a, []const u8, &.{ o.objects, objs }), &env);
}

const State = enum { pending, running, done };

/// The compiles, each by `run_job` (runJob; the tests pass their own), at
/// most `max` at a time; with `serial_fortran`, one Fortran compile at a
/// time, in plan order. 0, or the first failure's code after every
/// running compile has ended.
fn compileAll(ctx: *Ctx, comptime run_job: fn (Io, *const Job, usize) Result, jobs: []const Job, sources: []const pkgplan.Source, serial_fortran: bool, max: usize) !u8 {
    const n = jobs.len;
    const state = try ctx.arena.alloc(State, n);
    @memset(state, .pending);
    const buf = try ctx.arena.alloc(Done, n);
    var sel: Io.Select(Done) = .init(ctx.io, buf);
    // a task ends after it queued its result: the select (its group, on
    // this stack) must outlive every task's end, so wait for them all
    // before returning (Io.Select: cancel before deinit). Without it a
    // worker thread decremented a dead group's count, `num_running > 0`
    // failed in std.Io.Threaded and rzig aborted (7 of 30 quadprog builds,
    // upstream zig, gamma, 2026-10-22). rzig's task is never cancelled; if
    // `sel.await` were, cancelDiscard would cancel the tasks in
    // `child.wait`, and their children would run on unreaped (zig 0.17
    // port).
    defer sel.cancelDiscard();
    var running: usize = 0;
    var fortran_busy = false;
    var failed: u8 = 0;
    while (true) {
        if (failed == 0) {
            for (0..n) |i| {
                if (running >= max) break;
                if (state[i] != .pending) continue;
                const f = serial_fortran and isFortran(sources[i].lang);
                if (f and fortran_busy) continue;
                state[i] = .running;
                running += 1;
                if (f) fortran_busy = true;
                ctx.echo(jobs[i].line);
                sel.concurrent(.done, run_job, .{ ctx.io, &jobs[i], i }) catch sel.async(.done, run_job, .{ ctx.io, &jobs[i], i });
            }
        }
        if (running == 0) break;
        const d = (try sel.await()).done;
        running -= 1;
        state[d.index] = .done;
        if (serial_fortran and isFortran(sources[d.index].lang)) fortran_busy = false;
        if (d.code != 0 and failed == 0) {
            failed = d.code;
            if (d.err) |e| ctx.warn("cannot run {s}: {t}", .{ jobs[d.index].argv[0], e }) else ctx.warn("{s} {s}: {s}", .{ sources[d.index].path, try ended(ctx, d), jobs[d.index].line });
        }
    }
    return failed;
}

/// The .def (Windows), the link into the root, and the library copied to
/// o.dest.
fn link(ctx: *Ctx, plan: *const pkgplan.Plan, o: Options, objs: []const []const u8, env: *const std.process.Environ.Map) !u8 {
    const a = ctx.arena;
    const out = try ctx.fmt("{s}/{s}", .{ o.root, plan.output });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(a, try ctx.fmt("{s}/{s}", .{ plan.toolchain, plan.link_driver }));
    try argv.appendSlice(a, plan.link);
    try argv.appendSlice(a, &.{ "-o", out });
    if (plan.win_def.len > 0) {
        try argv.append(a, plan.win_def); // relative to srcdir, as winshlib.mk names it
    } else if (plan.def) {
        // winshlib.mk's tmp.def, from the objects' symbol tables: def.zig in
        // this process, the objects by their absolute names (no command line)
        const def_file = try ctx.fmt("{s}/{s}.def", .{ o.root, std.fs.path.stem(plan.output) });
        var def_argv: std.ArrayList([]const u8) = .empty;
        try def_argv.appendSlice(a, &.{ "-o", def_file });
        try def_argv.appendSlice(a, objs);
        const code = def.run(ctx, def_argv.items);
        if (code != 0) return 1;
        try argv.append(a, def_file);
    }
    if (try objectsFile(ctx, plan, o.root, objs)) |rsp| {
        try argv.append(a, try ctx.fmt("@{s}", .{rsp}));
    } else try argv.appendSlice(a, objs);
    try argv.appendSlice(a, plan.libs);
    const job: Job = .{ .argv = argv.items, .cwd = plan.srcdir, .env = env, .line = try commandLine(a, argv.items) };
    ctx.echo(job.line);
    const r = runJob(ctx.io, &job, 0);
    if (r.err) |e| {
        ctx.warn("cannot run {s}: {t}", .{ argv.items[0], e });
        return 1;
    }
    if (r.code != 0) {
        ctx.warn("the link {s}: {s}", .{ try ended(ctx, r), job.line });
        return 1;
    }
    if (std.fs.path.dirname(o.dest)) |d| Io.Dir.cwd().createDirPath(ctx.io, d) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ d, err });
        return 1;
    };
    Io.Dir.cwd().copyFile(out, Io.Dir.cwd(), o.dest, ctx.io, .{}) catch |err| {
        ctx.warn("cannot copy {s} to {s}: {t}", .{ out, o.dest, err });
        return 1;
    };
    return 0;
}

/// <root>/objects.rsp with every object, named relative to srcdir, where
/// the link runs (feat-win-link-fixes item 1: Windows' command lines end
/// at 32,767 characters); null (the objects on the command line) when a
/// name holds what the file cannot give back (response.rspText).
fn objectsFile(ctx: *Ctx, plan: *const pkgplan.Plan, root: []const u8, objs: []const []const u8) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (objs) |p| try names.append(ctx.arena, try response.rspName(ctx.arena, ctx.env, plan.srcdir, p));
    const text = (try response.rspText(ctx.arena, names.items)) orelse return null;
    const path = try ctx.fmt("{s}/objects.rsp", .{root});
    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = text }) catch |err| {
        ctx.warn("cannot write {s}: {t}", .{ path, err });
        return error.WriteFailed;
    };
    return path;
}

/// `rzig t1 --plan <plan.zon> --root <dir> --out <lib> [--object <o>]...
/// [--c <source>]... [--cxx <source>]... [-j N]`: tier 2's C and C++
/// sources (named relative to the plan's srcdir) and its zig object, built
/// and linked as tier 1 builds a package (zigbuild/rpkg/rpkg.zig's
/// addLibrary). The plan is the one `rzig build` wrote for the package;
/// its own sources are replaced by these.
pub fn run(ctx: *Ctx, argv: []const []const u8) !u8 {
    ctx.name = "rzig t1";
    var plan_path: ?[]const u8 = null;
    var root: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var jobs: usize = 0;
    var objects: std.ArrayList([]const u8) = .empty;
    var sources: std.ArrayList(pkgplan.Source) = .empty;
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        if (i + 1 >= argv.len) {
            ctx.warn("{s} needs a value", .{argv[i]});
            return 2;
        }
        const k = argv[i];
        const v = argv[i + 1];
        i += 1;
        if (mem.eql(u8, k, "--plan")) plan_path = v else if (mem.eql(u8, k, "--root")) root = v else if (mem.eql(u8, k, "--out")) out = v else if (mem.eql(u8, k, "--object")) {
            // absolute, `/`: zig build names it relative to its own working
            // directory, which need not be srcdir, where the link runs
            const abs = Io.Dir.cwd().realPathFileAlloc(ctx.io, v, ctx.arena) catch |err| {
                ctx.warn("{s}: {t}", .{ v, err });
                return 1;
            };
            try objects.append(ctx.arena, if (builtin.os.tag == .windows) try mem.replaceOwned(u8, ctx.arena, abs, "\\", "/") else abs);
        } else if (mem.eql(u8, k, "-j")) jobs = jobCount(v) else if (mem.eql(u8, k, "--c") or mem.eql(u8, k, "--cxx")) {
            try sources.append(ctx.arena, .{ .lang = k[2..], .path = v, .obj = try ctx.fmt("{s}.o", .{std.fs.path.stem(v)}) });
        } else {
            ctx.warn("unknown argument '{s}'", .{k});
            return 2;
        }
    }
    if (plan_path == null or root == null or out == null) {
        ctx.warn("usage: rzig t1 --plan <plan.zon> --root <dir> --out <lib> [--object <o>]... [--c|--cxx <source>]... [-j N]", .{});
        return 2;
    }
    const text = Io.Dir.cwd().readFileAllocOptions(ctx.io, plan_path.?, ctx.arena, .limited(16 << 20), .of(u8), 0) catch |err| {
        ctx.warn("cannot read {s}: {t}", .{ plan_path.?, err });
        return 1;
    };
    @setEvalBranchQuota(20_000);
    var diag: std.zon.parse.Diagnostics = undefined;
    var plan = std.zon.parse.fromSlice(pkgplan.Plan, .{ .gpa = ctx.arena, .arena = ctx.arena, .source = text, .diagnostics = &diag }) catch {
        ctx.warn("cannot parse {s}", .{plan_path.?});
        return 1;
    };
    plan.sources = sources.items;
    Io.Dir.cwd().createDirPath(ctx.io, root.?) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ root.?, err });
        return 1;
    };
    return build(ctx, &plan, .{ .root = root.?, .dest = out.?, .jobs = jobs, .objects = objects.items });
}

const testing = std.testing;

test jobCount {
    try testing.expectEqual(4, jobCount("4"));
    try testing.expect(jobCount(null) >= 1);
    try testing.expect(jobCount("0") >= 1);
    try testing.expect(jobCount("x") >= 1);
}

const testutil = @import("testutil.zig");
const crash = @import("crash.zig");

const exe = if (builtin.os.tag == .windows) ".exe" else "";

/// testdata/fake_cc.zig, which build.zig embeds, as the toolchain's cc
/// and ld: a program on every OS.
fn fakeToolchain(f: *testutil.Fixture) !void {
    const perm: std.Io.File.Permissions = if (builtin.os.tag == .windows) .default_file else .fromMode(0o755);
    for ([_][]const u8{ "cc", "ld" }) |t| try f.write(f.fmt("tc/{s}{s}", .{ t, exe }), @embedFile("fake_cc"), perm);
}

fn testPlan(f: *testutil.Fixture, sources: []const pkgplan.Source) pkgplan.Plan {
    const env = f.ctx.arena.dupe([]const u8, &.{f.fmt("FAKE_CC_DIR={s}", .{f.path("count")})}) catch @panic("OOM");
    return .{
        .name = "p",
        .srcdir = f.path("p/src"),
        .output = "p.so",
        .toolchain = f.path("tc"),
        .link_driver = "ld" ++ exe,
        .cc_tool = "cc" ++ exe,
        .cxx_tool = "cc" ++ exe,
        .fc_tool = "cc" ++ exe,
        .sources = sources,
        .env = env,
    };
}

/// How many compiles ran at once at most (fake_cc's peak/ files; one
/// build per fixture).
fn peak(f: *testutil.Fixture) !usize {
    var dir = try f.tmp.dir.openDir(testing.io, "count/peak", .{ .iterate = true });
    defer dir.close(testing.io);
    var most: usize = 0;
    var it = dir.iterate();
    while (try it.next(testing.io)) |e| {
        var buf: [16]u8 = undefined;
        most = @max(most, try std.fmt.parseInt(usize, try dir.readFile(testing.io, e.name, &buf), 10));
    }
    return most;
}

test "build: Fortran one at a time in plan order, C alongside; then the link, objects.rsp, the library in dest; each command echoed" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try fakeToolchain(&f);
    // a.f90 waits until b.c has started: C runs beside Fortran. Each
    // Fortran compile holds fortran.busy (fake_cc exits 7 when another
    // does) and needs the module the one before it made.
    try f.write("p/src/a.f90", "alone fortran.busy\nwait b.started\nsleep 50\nmake a.mod\n", .default_file);
    try f.write("p/src/b.c", "make b.started\n", .default_file);
    try f.write("p/src/c.f90", "alone fortran.busy\nneed a.mod\nsleep 50\nmake c.mod\n", .default_file);
    try f.touch("p/src/d.c");
    try f.write("p/src/e.f", "alone fortran.busy\nneed c.mod\n", .default_file);
    const sources = [_]pkgplan.Source{
        .{ .lang = "f9x", .path = "a.f90", .obj = "a.o" },
        .{ .lang = "c", .path = "b.c", .obj = "b.o" },
        .{ .lang = "f9x", .path = "c.f90", .obj = "c.o" },
        .{ .lang = "c", .path = "d.c", .obj = "d.o" },
        .{ .lang = "f", .path = "e.f", .obj = "sub/e.o" },
    };
    var plan = testPlan(&f, &sources);
    plan.cc = &.{ "-O2", "-I/r home/include" };
    plan.f9x = &.{"-fPIC"};
    plan.link = &.{"-shared"};
    plan.libs = &.{"-lm"};
    try testing.expectEqual(0, try build(&f.ctx, &plan, .{ .root = f.path("root"), .dest = f.path("out/libs/p.so"), .jobs = 8 }));
    try testing.expectEqualStrings("", f.takeWarnings());
    // the library: what fake_cc's link was given, from objects.rsp, each
    // object relative to srcdir
    var buf: [512]u8 = undefined;
    try testing.expectEqualStrings(
        "../../root/obj/0/a.o\n../../root/obj/1/b.o\n../../root/obj/2/c.o\n../../root/obj/3/d.o\n../../root/obj/4/e.o\n",
        try f.tmp.dir.readFile(testing.io, "out/libs/p.so", &buf),
    );
    // the commands in the order they started: the first pass a, b and d
    // (c and e wait for the Fortran before them), then c, e, the link
    const tc = f.path("tc");
    const root = f.path("root");
    try testing.expectEqualStrings(f.fmt(
        \\{0s}/cc{2s} -fPIC -c a.f90 -o {1s}/obj/0/a.o
        \\{0s}/cc{2s} -O2 '-I/r home/include' -c b.c -o {1s}/obj/1/b.o
        \\{0s}/cc{2s} -O2 '-I/r home/include' -c d.c -o {1s}/obj/3/d.o
        \\{0s}/cc{2s} -fPIC -c c.f90 -o {1s}/obj/2/c.o
        \\{0s}/cc{2s} -c e.f -o {1s}/obj/4/e.o
        \\{0s}/ld{2s} -shared -o {1s}/p.so @{1s}/objects.rsp -lm
        \\
    , .{ tc, root, exe }), f.takeEchoed());
    // the words as b.c's compile got them (fake_cc writes them into the
    // object): `-I/r home/include` one word, on Windows too
    var obj_buf: [512]u8 = undefined;
    try testing.expectEqualStrings(
        f.fmt("-O2\n-I/r home/include\n-c\nb.c\n-o\n{s}/obj/1/b.o\n", .{root}),
        try f.tmp.dir.readFile(testing.io, "root/obj/1/b.o", &obj_buf),
    );
}

test "build: a failed compile, 1, no link and no library; a link that cannot run, 1; nothing to compile, 0" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try fakeToolchain(&f);
    try f.write("p/src/bad.c", "exit 1\n", .default_file);
    try f.touch("p/src/ok.c");
    const sources = [_]pkgplan.Source{ .{ .lang = "c", .path = "bad.c", .obj = "bad.o" }, .{ .lang = "c", .path = "ok.c", .obj = "ok.o" } };
    const plan = testPlan(&f, &sources);
    try testing.expectEqual(1, try build(&f.ctx, &plan, .{ .root = f.path("root"), .dest = f.path("out/p.so"), .jobs = 1 }));
    // the failure in one line, after the compile's own output
    const line = f.fmt("{s}/cc{s} -c bad.c -o {s}/obj/0/bad.o", .{ f.path("tc"), exe, f.path("root") });
    try testing.expectEqualStrings(f.fmt("rzig-test: bad.c failed (1): {s}\n", .{line}), f.takeWarnings());
    // -j1 and the failure first: ok.c never started
    try testing.expectEqualStrings(f.fmt("{s}\n", .{line}), f.takeEchoed());
    try testing.expect(!f.ctx.exists(f.path("root/obj/1/ok.o")));
    try testing.expect(!f.ctx.exists(f.path("out/p.so")));
    // no link driver: 1, nothing installed
    var no_ld = testPlan(&f, sources[1..]);
    no_ld.link_driver = "missing" ++ exe;
    try testing.expectEqual(1, try build(&f.ctx, &no_ld, .{ .root = f.path("root1"), .dest = f.path("out1/p.so") }));
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), f.fmt("rzig-test: cannot run {s}/missing{s}: ", .{ f.path("tc"), exe })));
    try testing.expect(!f.ctx.exists(f.path("out1/p.so")));
    _ = f.takeEchoed();
    const none = testPlan(&f, &.{});
    try testing.expectEqual(0, try build(&f.ctx, &none, .{ .root = f.path("root2"), .dest = f.path("out2/p.so") }));
    try testing.expect(!f.ctx.exists(f.path("root2")));
    try testing.expectEqualStrings("", f.takeEchoed());
    // a compile a signal ends (the OOM killer's KILL): named so, not as
    // the compiler's exit code. No signals on Windows.
    if (builtin.os.tag != .windows) {
        try f.write("p/src/oom.c", "kill\n", .default_file);
        const killed = testPlan(&f, &.{.{ .lang = "c", .path = "oom.c", .obj = "oom.o" }});
        try testing.expectEqual(1, try build(&f.ctx, &killed, .{ .root = f.path("root3"), .dest = f.path("out3/p.so") }));
        try testing.expectEqualStrings(f.fmt("rzig-test: oom.c was killed by signal 9: {s}/cc -c oom.c -o {s}/obj/0/oom.o\n", .{ f.path("tc"), f.path("root3") }), f.takeWarnings());
        try testing.expect(!f.ctx.exists(f.path("out3/p.so")));
        _ = f.takeEchoed();
    }
}

test "build: at most -j compiles at once, and -j of them" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try fakeToolchain(&f);
    // the first three wait for each other: they end only when three run
    // at once (else fake_cc exits 9 after 20 s); the others sleep, so
    // more than three at once would show in the peak
    var sources: [12]pkgplan.Source = undefined;
    for (&sources, 0..) |*s, i| {
        s.* = .{ .lang = "c", .path = f.fmt("s{d}.c", .{i}), .obj = f.fmt("s{d}.o", .{i}) };
        try f.write(f.fmt("p/src/{s}", .{s.path}), if (i < 3) f.fmt("make go{d}\nwait go0\nwait go1\nwait go2\n", .{i}) else "sleep 50\n", .default_file);
    }
    const plan = testPlan(&f, &sources);
    try testing.expectEqual(0, try build(&f.ctx, &plan, .{ .root = f.path("root"), .dest = f.path("out/p.so"), .jobs = 3 }));
    try testing.expectEqualStrings("", f.takeWarnings());
    try testing.expectEqual(3, try peak(&f));
}

test "build: many tiny compiles at the CPU count, round after round; a failure in the middle, 1 and no library" {
    // the scheduler under load: every other round, one compile fails in
    // the middle
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try fakeToolchain(&f);
    const n = 64;
    var sources: [n]pkgplan.Source = undefined;
    for (&sources, 0..) |*s, i| {
        s.* = .{ .lang = "c", .path = f.fmt("s{d}.c", .{i}), .obj = f.fmt("s{d}.o", .{i}) };
        try f.write(f.fmt("p/src/{s}", .{s.path}), if (i == 40) "exit 3\n" else "", .default_file);
    }
    for (0..12) |round| {
        const fails = round % 2 == 1;
        const plan = testPlan(&f, if (fails) &sources else sources[0..40]);
        const dest = f.fmt("out{d}/p.so", .{round});
        try testing.expectEqual(@as(u8, if (fails) 1 else 0), try build(&f.ctx, &plan, .{ .root = f.path(f.fmt("root{d}", .{round})), .dest = f.path(dest) }));
        try testing.expectEqual(!fails, f.ctx.isFile(f.path(dest)));
        try testing.expectEqualStrings(if (fails) "rzig-test: s40.c failed (3): " else "", f.takeWarnings()[0..if (fails) 29 else 0]);
        _ = f.takeEchoed();
    }
}

test "build: on Windows the .def from the objects, in this process, on the link; a package's own <pkg>-win.def instead" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try fakeToolchain(&f);
    // tier 2's zig object alone, a COFF object (def.zig's fixture)
    try f.write("z/p.o", @embedFile("testdata/win-syms.o"), .default_file);
    // the build roots, as rzig build and `rzig t1` make them
    for ([_][]const u8{ "p/src", "root", "root1" }) |d| try f.tmp.dir.createDirPath(testing.io, d);
    var plan = testPlan(&f, &.{});
    plan.output = "p.dll";
    plan.def = true;
    const objects: []const []const u8 = &.{f.path("z/p.o")};
    try testing.expectEqual(0, try build(&f.ctx, &plan, .{ .root = f.path("root"), .dest = f.path("out/p.dll"), .objects = objects }));
    try testing.expectEqualStrings("", f.takeWarnings());
    // the object's exports (def.zig), no command line of its own
    const d = try f.tmp.dir.readFileAlloc(testing.io, "root/p.def", f.ctx.arena, .limited(4096));
    try testing.expect(mem.startsWith(u8, d, "EXPORTS\n") and mem.indexOf(u8, d, "\nexported_fn\n") != null);
    const tc = f.path("tc");
    try testing.expectEqualStrings(f.fmt("{0s}/ld{2s} -o {1s}/p.dll {1s}/p.def @{1s}/objects.rsp\n", .{ tc, f.path("root"), exe }), f.takeEchoed());
    try testing.expect(f.ctx.isFile(f.path("out/p.dll")));
    // the package's own, named as winshlib.mk names it (relative to
    // srcdir); no .def written
    try f.touch("p/src/p-win.def");
    plan.win_def = "p-win.def";
    try testing.expectEqual(0, try build(&f.ctx, &plan, .{ .root = f.path("root1"), .dest = f.path("out1/p.dll"), .objects = objects }));
    try testing.expectEqualStrings(f.fmt("{0s}/ld{2s} -o {1s}/p.dll p-win.def @{1s}/objects.rsp\n", .{ tc, f.path("root1"), exe }), f.takeEchoed());
    try testing.expect(!f.ctx.exists(f.path("root1/p.def")));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "a crash in rzig's process, where the .def is made: a failure R reads as one, never 3, needs make (K4)" {
    // testdata/crash.zig, with rzig's crash handling (crash.zig). R's
    // .rzig_build reads an exit as its status and a signal as its raw
    // wait status (patch 0013: SIGABRT reads as 6, or 134 with a core
    // dump), and runs make on 3 alone.
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const perm: std.Io.File.Permissions = if (builtin.os.tag == .windows) .default_file else .fromMode(0o755);
    try f.write("crash" ++ exe, @embedFile("crash_program"), perm);
    for ([_][2][]const u8{ .{ "panic", "panic: integer overflow" }, .{ "segfault", " at address 0x0" } }) |case| {
        const r = try std.process.run(f.ctx.arena, testing.io, .{ .argv = &.{ f.path("crash" ++ exe), case[0] } });
        if (builtin.os.tag == .windows) {
            try testing.expectEqual(std.process.Child.Term{ .exited = crash.exit_crash }, r.term);
        } else try testing.expectEqual(std.process.Child.Term{ .signal = .ABRT }, r.term);
        try testing.expect(mem.indexOf(u8, r.stderr, case[1]) != null);
    }
    try testing.expect(crash.exit_crash != @import("pkgbuild.zig").exit_needs_make);
}

test "run: rzig t1, tier 2's zig object and its C and C++ sources, built and linked as tier 1" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try fakeToolchain(&f);
    try f.touch("p/src/util.c");
    try f.touch("p/src/k.cpp");
    try f.touch("zig-cache/o/1/p.o");
    // the plan rzig build wrote; its sources are replaced
    var plan = testPlan(&f, &.{.{ .lang = "c", .path = "gone.c", .obj = "gone.o" }});
    plan.cc = &.{"-DC"};
    plan.cxx = &.{"-DCXX"};
    var zon: Io.Writer.Allocating = .init(f.ctx.arena);
    try pkgplan.writeZon(&plan, &zon.writer);
    try f.write("t2/plan.zon", zon.written(), .default_file);
    const root = f.path("t2/t1");
    try testing.expectEqual(0, try run(&f.ctx, &.{ "--plan", f.path("t2/plan.zon"), "--root", root, "--object", f.path("zig-cache/o/1/p.o"), "--c", "util.c", "--cxx", "k.cpp", "--out", f.path("zout/p.so"), "-j", "2" }));
    try testing.expectEqualStrings("", f.takeWarnings());
    var buf: [512]u8 = undefined;
    try testing.expectEqualStrings("../../zig-cache/o/1/p.o\n../../t2/t1/obj/0/util.o\n../../t2/t1/obj/1/k.o\n", try f.tmp.dir.readFile(testing.io, "zout/p.so", &buf));
    const tc = f.path("tc");
    try testing.expectEqualStrings(f.fmt(
        \\{0s}/cc{2s} -DC -c util.c -o {1s}/obj/0/util.o
        \\{0s}/cc{2s} -DCXX -c k.cpp -o {1s}/obj/1/k.o
        \\{0s}/ld{2s} -o {1s}/p.so @{1s}/objects.rsp
        \\
    , .{ tc, root, exe }), f.takeEchoed());
    // what it needs
    try testing.expectEqual(2, try run(&f.ctx, &.{ "--plan", f.path("t2/plan.zon"), "--root", root }));
    try testing.expect(mem.startsWith(u8, f.takeWarnings(), "rzig t1: usage: rzig t1 "));
    try testing.expectEqual(2, try run(&f.ctx, &.{ "--plan", f.path("t2/plan.zon"), "--root" }));
    try testing.expectEqualStrings("rzig t1: --root needs a value\n", f.takeWarnings());
}

/// The lifetime test's tasks: no process, the quickest tasks there are.
fn doneAtOnce(_: Io, _: *const Job, index: usize) Result {
    return .{ .index = index, .code = 0 };
}

fn failedAtOnce(_: Io, _: *const Job, index: usize) Result {
    return .{ .index = index, .code = 127, .err = error.FileNotFound };
}

test "compileAll: round after round of tasks that end at once (Io.Select's lifetime)" {
    // A task ends after it queued its result, so compileAll's Io.Select,
    // on its stack, must outlive every task (`defer sel.cancelDiscard()`).
    // Without it, a worker decremented the next round's group, and
    // std.Io.Threaded aborted rzig ("reached unreachable code"): with
    // this test, in 20 of 20 runs at its default 30,000 rounds, and in
    // 14 of 20 at 10,000 (gamma, both zigs, the whole test binary,
    // 2026-10-23). The rounds cost about 6 s there.
    // The tasks run no process, the same on every OS. This test's first
    // form spawned a missing program, and zig 0.16's processSpawnPosix
    // returns the exec error without reaping the child: a zombie for
    // each such spawn, 3,600 at 1,000 rounds. On omicron, at
    // RZIG_TEST_STRESS=5000 or under `ulimit -u 3000`, fork then hit the
    // per-user process limit and later tests failed (2026-10-23).
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const rounds = if (testing.environ.getAlloc(f.ctx.arena, "RZIG_TEST_STRESS")) |v| try std.fmt.parseInt(usize, v, 10) else |_| 30_000;
    const n = 4;
    var sources: [n]pkgplan.Source = undefined;
    var jobs: [n]Job = undefined;
    const env = try f.ctx.env.clone(f.ctx.arena);
    for (&sources, &jobs) |*s, *j| {
        s.* = .{ .lang = "c", .path = "s.c", .obj = "s.o" };
        j.* = .{ .argv = &.{"cc"}, .cwd = f.path("."), .env = &env, .line = "" };
    }
    for (0..rounds) |r| {
        const ok = r % 10 == 0;
        const code = if (ok) try compileAll(&f.ctx, doneAtOnce, &jobs, &sources, false, n) else try compileAll(&f.ctx, failedAtOnce, &jobs, &sources, false, n);
        try testing.expectEqual(@as(u8, if (ok) 0 else 127), code);
        f.warnings.clearRetainingCapacity();
        f.echoed.clearRetainingCapacity();
    }
}
