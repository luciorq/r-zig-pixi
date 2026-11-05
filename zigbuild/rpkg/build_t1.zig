//! Tier-1 root: one R package's shared library from a plan (plan.zon,
//! written by `rzig build`: zigbuild/tools/rzig/pkgplan.zig). Every
//! compile and the link are Run steps that call rzig (the toolchain's
//! zig-cc / zig-cxx / zig-fc; gcc.exe, g++.exe, zig-fc.exe on Windows) with
//! the words make would have passed; no flag is derived here. Installed
//! to R_HOME/share/zig/rpkg by the repo's build.zig; rzig runs
//!   zig build --build-file <this file> -Dplan=<plan.zon> --prefix <dir> --cache-dir <cache>
//! and finds <dir>/<libs_dir>/<output>; by default <cache> is a directory
//! of rzig's cache, and <this file> its copy there. The steps write their
//! objects and the library into the build root, the plan's directory,
//! never into <cache>: it then holds this file's build runner alone, one
//! per content of this file and zig, which every tier-1 install shares
//! (zigbuild/tools/rzig/pkgbuild.zig's sharedRunner).
const std = @import("std");
const builtin = @import("builtin");
const windows = builtin.os.tag == .windows;

pub const Source = struct { lang: []const u8, path: []const u8, obj: []const u8 };

/// Field names and defaults as pkgplan.zig's `Plan` writes them.
pub const Plan = struct {
    name: []const u8,
    srcdir: []const u8,
    output: []const u8,
    /// "libs", or "libs/x64" on Windows (R_ARCH); "" = the prefix itself
    libs_dir: []const u8 = "libs",
    toolchain: []const u8,
    /// rzig itself, for `rzig def` (Windows); "" when not needed
    rzig: []const u8 = "",
    link_driver: []const u8,
    // the plan always names them (pkgplan.zig, from Makeconf); the defaults
    // are the names installRzig (build.zig) uses on this OS
    cc_tool: []const u8 = if (windows) "gcc.exe" else "zig-cc",
    cxx_tool: []const u8 = if (windows) "g++.exe" else "zig-cxx",
    fc_tool: []const u8 = if (windows) "zig-fc.exe" else "zig-fc",
    sources: []const Source,
    cc: []const []const u8 = &.{},
    cxx: []const []const u8 = &.{},
    fc: []const []const u8 = &.{},
    f9x: []const []const u8 = &.{},
    link: []const []const u8 = &.{},
    libs: []const []const u8 = &.{},
    env: []const []const u8 = &.{}, // NAME=value pairs for the compiler
    target: []const u8 = "", // tier 2: zig target of R, e.g. x86_64-linux-gnu.2.17
    r_include: []const u8 = "", // tier 2: R_HOME/include
    /// Windows: write the .def from the objects (rzig def) and link with it
    def: bool = false,
    /// Windows: the package's own <pkg>-win.def in srcdir, linked instead
    win_def: []const u8 = "",
    /// The build root, the plan's own directory, where the steps write
    /// (outputFile). Not in plan.zon: readPlan sets it.
    root: []const u8 = "",
};

pub fn readPlan(b: *std.Build) *const Plan {
    const plan_path = b.option([]const u8, "plan", "plan.zon") orelse @panic("-Dplan=<file> is required");
    const raw = std.Io.Dir.cwd().readFileAlloc(b.graph.io, plan_path, b.allocator, .limited(16 * 1024 * 1024)) catch @panic("cannot read the plan");
    const z = b.allocator.dupeZ(u8, raw) catch @panic("OOM");
    const plan = b.allocator.create(Plan) catch @panic("OOM");
    @setEvalBranchQuota(20_000); // std.zon.parse's per-field inline switch grows with Plan's fields
    plan.* = std.zon.parse.fromSliceAlloc(Plan, b.allocator, z, null, .{}) catch @panic("cannot parse the plan");
    // absolute: the steps run in srcdir and name their outputs on their
    // command lines. rzig passes it so, with `/` (pkgbuild.zig).
    const root = std.fs.path.dirname(plan_path) orelse ".";
    plan.root = if (std.fs.path.isAbsolute(root)) root else b.pathResolve(&.{ b.graph.cache.cwd, root });
    return plan;
}

fn driverFor(plan: *const Plan, lang: []const u8) struct { tool: []const u8, flags: []const []const u8 } {
    if (std.mem.eql(u8, lang, "c")) return .{ .tool = plan.cc_tool, .flags = plan.cc };
    if (std.mem.eql(u8, lang, "cxx")) return .{ .tool = plan.cxx_tool, .flags = plan.cxx };
    if (std.mem.eql(u8, lang, "f")) return .{ .tool = plan.fc_tool, .flags = plan.fc };
    if (std.mem.eql(u8, lang, "f9x")) return .{ .tool = plan.fc_tool, .flags = plan.f9x };
    @panic("unknown language in the plan");
}

fn applyEnv(run: *std.Build.Step.Run, plan: *const Plan) void {
    for (plan.env) |kv| {
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        run.setEnvironmentVariable(kv[0..eq], kv[eq + 1 ..]);
    }
}

/// The file `run` writes at `path`, in the build root, named on its
/// command line where addOutputFileArg would name one in zig build's
/// cache, o/<hash of the step's inputs>/, with a manifest in h/: the
/// inputs hash the whole environment, R_SESSION_TMPDIR included, so a
/// cache shared across installs gained an entry per step per install,
/// never reused (feat-zig-pkg-build N3, fact 9). The step always runs, as
/// it did with a cache of its own per install, and writes nothing into
/// the cache. expectExitCode gives it the stdio a step with an output
/// file has: stdin and stdout ignored, stderr piped and shown as the
/// step's diagnostic. Without it a step with no output file inherits
/// stdio and holds zig build's stderr lock while it runs, one compile at
/// a time whatever -j says.
fn outputFile(b: *std.Build, run: *std.Build.Step.Run, path: []const u8) std.Build.LazyPath {
    run.has_side_effects = true;
    run.expectExitCode(0);
    run.addArg(path);
    const file = b.allocator.create(std.Build.GeneratedFile) catch @panic("OOM");
    file.* = .{ .step = &run.step, .path = path };
    return .{ .generated = .{ .file = file } };
}

/// One object per source, in the plan's order. Each compile runs in
/// srcdir and names its source relative to it, `-c one.c`, as make does
/// from src/: zig cc keys its object cache (zig's global cache) on the
/// source path as given, so the absolute path under install.R's new
/// R.INSTALL directory added one entry per source on every tarball
/// install, never reused, where make's entries are [tests-T1]. The file
/// stays an input of the step (addFileInput). The object goes to
/// <root>/obj/<n>/<its file name>, a directory per source as zig build's
/// cache had one per step: OBJECTS may name two files of one name
/// (util.o, sub/util.o) or one outside src/ (../x.o), and rpkg names a
/// tier-2 source's object by its stem. A source outside srcdir (R CMD
/// SHLIB's absolute paths: cpp11, TMB) is named as R named it; make names
/// it so too.
///
/// Fortran compiles one after another, in OBJECTS order, when there is
/// more than one (feat-shlib-rzig-build Cc3): flang writes a module's .mod
/// into the working directory, srcdir, and a later `use` reads it there.
/// R runs make with no -j (install.R), so make compiles OBJECTS in order,
/// where zig build would run them at once. Fixed form (.f) can hold a
/// module too. C and C++ compiles stay parallel.
pub fn compileAll(b: *std.Build, plan: *const Plan) []std.Build.LazyPath {
    var objs = std.ArrayList(std.Build.LazyPath).empty;
    var fortran: usize = 0;
    for (plan.sources) |s| {
        if (isFortran(s.lang)) fortran += 1;
    }
    var prev_fortran: ?*std.Build.Step = null;
    for (plan.sources, 0..) |s, n| {
        const d = driverFor(plan, s.lang);
        const run = b.addSystemCommand(&.{b.pathJoin(&.{ plan.toolchain, d.tool })});
        run.setName(b.fmt("{s} {s}", .{ d.tool, s.path }));
        run.setCwd(.{ .cwd_relative = plan.srcdir });
        applyEnv(run, plan);
        run.addArgs(d.flags);
        run.addArg("-c");
        run.addArg(s.path);
        // pathJoin joins naively: an absolute path is the file itself
        run.addFileInput(.{ .cwd_relative = if (std.fs.path.isAbsolute(s.path)) s.path else b.pathJoin(&.{ plan.srcdir, s.path }) });
        run.addArg("-o");
        const dir = b.fmt("{s}/obj/{d}", .{ plan.root, n });
        std.Io.Dir.cwd().createDirPath(b.graph.io, dir) catch @panic("cannot create the build root's obj/");
        objs.append(b.allocator, outputFile(b, run, b.fmt("{s}/{s}", .{ dir, std.fs.path.basename(s.obj) }))) catch @panic("OOM");
        if (fortran > 1 and isFortran(s.lang)) {
            if (prev_fortran) |prev| run.step.dependOn(prev);
            prev_fortran = &run.step;
        }
    }
    return objs.items;
}

fn isFortran(lang: []const u8) bool {
    return std.mem.eql(u8, lang, "f") or std.mem.eql(u8, lang, "f9x");
}

/// The one link: `SHLIB_LINK -o out [def] objects ALL_LIBS`, as shlib.mk
/// and winshlib.mk write it, the objects in a response file (objectsFile).
pub fn link(b: *std.Build, plan: *const Plan, objs: []const std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{b.pathJoin(&.{ plan.toolchain, plan.link_driver })});
    run.setName(b.fmt("link {s}", .{plan.output}));
    run.setCwd(.{ .cwd_relative = plan.srcdir });
    applyEnv(run, plan);
    run.addArgs(plan.link);
    run.addArg("-o");
    const out = outputFile(b, run, b.fmt("{s}/{s}", .{ plan.root, plan.output }));
    const rsp = objectsFile(b, plan, objs);
    if (plan.win_def.len > 0) {
        // relative to srcdir too, as winshlib.mk names it (compileAll)
        run.addArg(plan.win_def);
        run.addFileInput(.{ .cwd_relative = b.pathJoin(&.{ plan.srcdir, plan.win_def }) });
    } else if (plan.def) {
        // winshlib.mk's tmp.def, from the objects' symbol tables
        const def = b.addSystemCommand(&.{ plan.rzig, "def", "-o" });
        def.setName(b.fmt("def {s}", .{plan.output}));
        def.setCwd(.{ .cwd_relative = plan.srcdir });
        const def_file = outputFile(b, def, b.fmt("{s}/{s}.def", .{ plan.root, std.fs.path.stem(plan.output) }));
        addObjects(b, def, objs, rsp);
        run.addFileArg(def_file);
    }
    addObjects(b, run, objs, rsp);
    run.addArgs(plan.libs);
    return out;
}

/// The objects on `run`'s command line: objs[0..first] by name, then
/// `@<root>/objects.rsp` for the rest, each still an input of the step
/// (addFileInput), so zig build runs the compiles first and tracks the
/// objects as before; without a response file, every object by name.
fn addObjects(b: *std.Build, run: *std.Build.Step.Run, objs: []const std.Build.LazyPath, rsp: ?Rsp) void {
    const first = if (rsp) |r| r.first else objs.len;
    for (objs[0..first]) |o| run.addFileArg(o);
    const r = rsp orelse return;
    run.addArg(b.fmt("@{s}", .{r.path}));
    run.addFileInput(.{ .cwd_relative = r.path });
    for (objs[first..]) |o| run.addFileInput(o);
}

/// <root>/objects.rsp, and the first object it names.
const Rsp = struct { path: []const u8, first: usize };

/// The objects' response file, for `rzig def` and the link
/// (feat-win-link-fixes item 1): every object on their command lines made
/// a package with a few hundred objects fail on Windows, whose command
/// lines end at 32,767 characters (libgeos with its unix Makevars, about
/// 390 objects: a 42,743-character `rzig def`, NameTooLong). zig cc reads
/// `@file` with both zigs, rzig def and rzig's other readers too
/// (zigbuild/tools/rzig/response.zig). Written here, at build() time:
/// every tier-1 object, and tier 2's C and C++ ones, has its path now
/// (outputFile). One code path on every OS.
///
/// Each object is named relative to srcdir, where both steps run (`./`
/// first unless it starts with `.`, so never with `-`: rspName), `/`
/// between its parts, one per line in double quotes, as zig reads them
/// (response.zig: std.process.Args.IteratorGeneral). Relative, because
/// the file cannot hold a `'` (zig's reader pairs it with `"`), and a
/// directory every name shares, as C:/Users/O'Brien/..., drops out. A
/// name that would still hold a `'`, `"` or `\` (legal in a POSIX name)
/// means no response file: every object on the command line, as before
/// (only more than 32,767 characters of objects then fail).
///
/// Objects whose path zig build knows only once it has built them (tier
/// 2's zig object, rpkg.zig) stay on the command line, before `@`, as
/// they come first in objs; any other order means no response file.
fn objectsFile(b: *std.Build, plan: *const Plan, objs: []const std.Build.LazyPath) ?Rsp {
    var first: usize = 0;
    while (first < objs.len and knownPath(objs[first]) == null) first += 1;
    if (first == objs.len) return null;
    var names = std.ArrayList([]const u8).empty;
    for (objs[first..]) |o| {
        const p = knownPath(o) orelse return null;
        names.append(b.allocator, rspName(b.allocator, b.graph.cache.cwd, &b.graph.environ_map, plan.srcdir, p) catch @panic("OOM")) catch @panic("OOM");
    }
    const text = (rspText(b.allocator, names.items) catch @panic("OOM")) orelse return null;
    const path = b.fmt("{s}/objects.rsp", .{plan.root});
    std.Io.Dir.cwd().writeFile(b.graph.io, .{ .sub_path = path, .data = text }) catch @panic("cannot write the build root's objects.rsp");
    return .{ .path = path, .first = first };
}

/// The path of an object that outputFile names, else null.
fn knownPath(o: std.Build.LazyPath) ?[]const u8 {
    return switch (o) {
        .generated => |g| if (g.up == 0 and g.sub_path.len == 0) g.file.path else null,
        else => null,
    };
}

/// `obj` relative to `srcdir` (std.fs.path.relative, as std.Build.Step.Run
/// makes a file argument relative to a step's cwd), with `/` on Windows,
/// and `./` before a name that does not start with `.`: as Run's
/// convertPathArg, so a name never starts with `-`, which zig cc would
/// take for an option (a build root under src/-tmp: `Unknown Clang
/// option`). On another Windows drive: the absolute path.
pub fn rspName(gpa: std.mem.Allocator, cwd: []const u8, env: ?*const std.process.Environ.Map, srcdir: []const u8, obj: []const u8) ![]const u8 {
    var rel = try std.fs.path.relative(gpa, cwd, env, srcdir, obj);
    if (!std.fs.path.isAbsolute(rel) and !std.mem.startsWith(u8, rel, ".")) rel = try std.fs.path.join(gpa, &.{ ".", rel });
    if (windows) std.mem.replaceScalar(u8, rel, '\\', '/');
    return rel;
}

/// The response file's text: `"<name>"` and a newline per name; null when
/// a name holds a `'`, `"` or `\`, which the file cannot give back.
pub fn rspText(gpa: std.mem.Allocator, names: []const []const u8) !?[]const u8 {
    var out = std.ArrayList(u8).empty;
    for (names) |n| {
        if (std.mem.findAny(u8, n, "'\"\\") != null) return null;
        try out.print(gpa, "\"{s}\"\n", .{n});
    }
    return out.items;
}

/// "libs" or "libs/x64" under the prefix; "" (rzig build --flat) the
/// prefix itself, where make leaves the library in src/.
pub fn installDir(libs_dir: []const u8) std.Build.InstallDir {
    return if (libs_dir.len == 0) .prefix else .{ .custom = libs_dir };
}

pub fn build(b: *std.Build) void {
    const plan = readPlan(b);
    if (plan.sources.len == 0) return; // make: `if test "z$(OBJECTS)" != "z"`
    const lib = link(b, plan, compileAll(b, plan));
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(lib, installDir(plan.libs_dir), plan.output).step);
}

// ---------------------------------------------------------------------------
// Unit tests: zigbuild/tools/rzig/build.zig's test step runs them with
// rzig's (`zig build --build-file zigbuild/tools/rzig/build.zig test`).

const testing = std.testing;

/// zig cc's reader of response files (zigbuild/tools/rzig/response.zig).
const Words = std.process.Args.IteratorGeneral(.{ .comments = true, .single_quotes = true });

fn expectWords(text: []const u8, want: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var it = try Words.init(arena.allocator(), text);
    for (want) |w| try testing.expectEqualStrings(w, it.next() orelse return error.TestExpectedEqual);
    try testing.expect(it.next() == null);
}

test "rspText: every name back from zig's reader, LF or CRLF; none for a ', \" or \\" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // relative names as objectsFile writes them: a space, UTF-8, a `#` at
    // a part's start and at the name's, an `@`, CRLF made of the LF text
    const names = [_][]const u8{ "../../tmp/RtmpX/R.INSTALL1/.rzig/obj/0/a.o", "../rz wf ção/obj/1/b c.o", "../#x/obj/2/d.o", "#e.o", "../@f/obj/3/g.o", "C:/Users/a b/obj/4/h.o" };
    const text = (try rspText(a, &names)).?;
    try testing.expectEqualStrings("\"../../tmp/RtmpX/R.INSTALL1/.rzig/obj/0/a.o\"\n", text[0 .. std.mem.indexOfScalar(u8, text, '\n').? + 1]);
    try expectWords(text, &names);
    const crlf = try std.mem.replaceOwned(u8, a, text, "\n", "\r\n");
    try expectWords(crlf, &names);
    try expectWords((try rspText(a, &.{})).?, &.{});
    // what the file cannot hold: no file, the objects on the command line
    for ([_][]const u8{ "../O'Brien/obj/0/a.o", "a\"b.o", "dir\\a.o" }) |bad| {
        try testing.expect(try rspText(a, &.{ "ok.o", bad }) == null);
    }
}

test "rspName: relative to srcdir, wherever the root is; never a leading -" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (windows) {
        // `/` between the parts; a `'` the two share drops out; another drive: absolute
        try testing.expectEqualStrings("../.rzig/obj/0/a.o", try rspName(a, "C:\\w", null, "C:\\Users\\O'Brien\\pkg\\src", "C:/Users/O'Brien/pkg/.rzig/obj/0/a.o"));
        try testing.expectEqualStrings("../../Temp/RtmpX/.rzig.0123/obj/0/f.o", try rspName(a, "C:\\w", null, "C:\\Users\\me\\proj\\src", "C:/Users/me/Temp/RtmpX/.rzig.0123/obj/0/f.o"));
        try testing.expectEqualStrings("D:/t/.rzig/obj/0/a.o", try rspName(a, "C:\\w", null, "C:\\pkg\\src", "D:/t/.rzig/obj/0/a.o"));
        try testing.expectEqualStrings("./-tmp/.rzig/obj/0/a.o", try rspName(a, "C:\\w", null, "C:\\pkg\\src", "C:/pkg/src/-tmp/.rzig/obj/0/a.o"));
    } else {
        try testing.expectEqualStrings("../.rzig/obj/0/a.o", try rspName(a, "/w", null, "/home/O'Brien/pkg/src", "/home/O'Brien/pkg/.rzig/obj/0/a.o"));
        try testing.expectEqualStrings("../../tmp/RtmpX/.rzig.0123/obj/0/f.o", try rspName(a, "/w", null, "/home/me/src", "/home/tmp/RtmpX/.rzig.0123/obj/0/f.o"));
        // a relative srcdir, from the build runner's cwd
        try testing.expectEqualStrings("../.rzig/obj/0/a.o", try rspName(a, "/home/me", null, "pkg/src", "/home/me/pkg/.rzig/obj/0/a.o"));
        // a `'` the two do not share: kept, so no response file (rspText)
        try testing.expectEqualStrings("../O'Brien/t/obj/0/a.o", try rspName(a, "/w", null, "/home/me", "/home/O'Brien/t/obj/0/a.o"));
        // a root below srcdir: `./` first, so `-tmp` is not an option; a `.` name as it is
        try testing.expectEqualStrings("./-tmp/RtmpX/.rzig.0123/obj/0/f.o", try rspName(a, "/w", null, "/home/me/src", "/home/me/src/-tmp/RtmpX/.rzig.0123/obj/0/f.o"));
        try testing.expectEqualStrings("./obj/0/a.o", try rspName(a, "/w", null, "/home/me/src", "/home/me/src/obj/0/a.o"));
        try testing.expectEqualStrings(".rzig/obj/0/a.o", try rspName(a, "/w", null, "/home/me/src", "/home/me/src/.rzig/obj/0/a.o"));
    }
}
