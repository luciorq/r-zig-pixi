//! zig-fc (zig-fc.exe on Windows): R's Fortran compiler, Makeconf's FC
//! (feat-no-host-paths F3c). flang compiles, the flang flang_rt.flang
//! finds (the compilers group's, the environment's bin, PATH's), and zig
//! links, every link (feat-standalone-toolchain phase 6, decision E):
//!
//! - A link of objects, shared (`-shared` or `-dynamiclib`) or an
//!   executable, goes through zig cc exactly as zig-cc links
//!   (compiler.zig: the baseline CPU, no -mtune=; the glibc floor, or the
//!   macOS target and SDK; the SONAME; the environment's -L and a conda
//!   env's rpath; OpenMP; Windows' import libraries and `.exe`), with the
//!   Fortran runtime appended, which flang_rt.zig resolves to the static
//!   archive of that flang. R's USE_FC_TO_LINK is such a link: SHLIB_LD =
//!   $(SHLIB_FCLD) = $(FC), and install.R takes $(FLIBS) and $(LIBR) off
//!   it, leaving the runtime to the Fortran driver. The runtime goes last,
//!   where FLIBS sits on an R CMD SHLIB link; lld and zig's Mach-O linker
//!   resolve archives in any order anyway. R's own library is left off
//!   too: Fortran that calls into R from such a package needs `PKG_LIBS =
//!   $(LIBR)` on Windows (PE resolves every symbol at link time), as it
//!   did with upstream's gfortran.
//! - A call that compiles Fortran sources and links (configure's `$FC -o
//!   conftest conftest.f`, `-shared -o p.so a.f b.o`) is split: a flang
//!   compile of each Fortran source into a temporary directory, then
//!   that zig link with each source replaced by its object (`split`). A
//!   C-family source on such a line is no step: it stays on zig's line,
//!   which compiles and links it as zig-cc does (Cc7).
//! - Compiles (.f .f90 .F ...: -c, -S, -E, -M, -fsyntax-only) and probes
//!   (--version, -v alone, -print-*, ...) run flang with the caller's
//!   arguments, on macOS after the floor (floors.zig), so the caller's own
//!   -mmacosx-version-min still wins. flang compiles for its target's
//!   baseline CPU unless told otherwise (target-cpu x86-64 on linux-64 and
//!   win-64, measured 2026-10-06), which zig-cc gets from -mcpu=baseline;
//!   flang refuses that flag ("unsupported option '-mcpu='" on x86_64),
//!   and needs none. A -mtune= stays: flang only tunes for that CPU
//!   (target-cpu still x86-64), which zig cc does not (compiler.zig
//!   dropTune).
//!
//! Why zig links everything: flang's own driver links with ld.lld and the
//! system's C runtime, which a standalone tree has neither of: a sysroot
//! on linux, SDKROOT on macOS, a MinGW CRT snapshot on Windows
//! (FLANG_PIXI_HANDOFF.md §8). In a conda env flang-zig's flang.cfg found
//! them, and its link recorded an absolute rpath into the env
//! (`-Wl,-rpath,<CFGDIR>/../lib`, linux-64 2026-10-03); conda-forge's
//! flang failed with "cannot find -lflang_rt.runtime" (2026-10-02). zig
//! has all of it for every target, and links what zig-cc compiled.
//!
//! Every call that reads Fortran source, the split's compiles included,
//! gets `-fintrinsic-modules-path <dir>` after the caller's arguments,
//! `<dir>` being the modules directory beside that flang
//! (flang_rt.modulesDir): the compilers group's flang has no flang.cfg,
//! and macOS's driver finds no module directory for its default triple
//! without one (linux's and Windows' do; phase 6's Cc13). One rule on
//! every OS, also beside a conda env's cfg, where the flag repeats the
//! cfg's own path. After the caller's arguments: flang searches module
//! paths in order, so a caller's own -fintrinsic-modules-path wins.
//!
//! No flang: nothing runs; zig-fc names the compilers group, flang's
//! (groups.zig, feat-standalone-toolchain B35), and exits 127, as a shell
//! does for a command it cannot find (main.zig). FC names zig-fc whether
//! or not a flang is installed, so a test such as `Sys.which(<R CMD config
//! FC>)` finds a file either way: this message, at the first Fortran
//! compile, is where a missing flang shows, unless the install preflight
//! (`--rzig-check=package`, check.zig) showed it first.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const compiler = @import("compiler.zig");
const flang_rt = @import("flang_rt.zig");
const floors = @import("floors.zig");
const groups = @import("groups.zig");
const Args = cmdline.Args;

/// What zig-fc runs for the caller's arguments. error.NoFlang, after the
/// compilers group's text, when there is no flang.
pub fn command(ctx: *Ctx, caller: Args) !Ctx.Command {
    const flang = (try flang_rt.flang(ctx)) orelse {
        try groups.report(ctx, groups.no_flang, .compilers);
        return error.NoFlang;
    };
    const floor: Args = if (ctx.os == .macos) &.{floors.macos_min_flag} else &.{};
    return switch (kind(caller)) {
        .flang => .{ .program = try mem.concat(ctx.arena, []const u8, &.{ &.{flang}, floor, caller, try modules(ctx, flang, caller) }) },
        .link => .{ .zig = try zigLink(ctx, caller) },
        .split => split(ctx, flang, floor, caller),
    };
}

/// The Fortran runtime as Makeconf's FLIBS spells it (build.zig): flang's,
/// plus libm; on Windows the runtime alone (the math functions are in
/// MinGW's CRT). No -lc++ on any OS: flang-rt-zig 10's archives reference
/// no C++ runtime symbol (feat-standalone-toolchain phase 6, open point K).
pub fn flibs(os: Ctx.Os) Args {
    return switch (os) {
        .windows => &.{flang_rt.flag},
        else => &.{ flang_rt.flag, "-lm" },
    };
}

const Kind = enum { flang, link, split };

/// flang's: a call that links nothing (-c, -S, -E, -M, -MM,
/// -fsyntax-only), a probe, or a call with no input. A split: a link with
/// a Fortran source among its inputs. Otherwise a link that is zig's
/// whole, objects or C-family sources alone, as for zig-cc.
fn kind(args: Args) Kind {
    if (cmdline.compileOnly(args) or probe(args)) return .flang;
    for (args) |x| if (mem.eql(u8, x, "-fsyntax-only")) return .flang;
    var it = cmdline.inputs(args);
    var any = false;
    while (it.next()) |i| {
        if (fortranInput(args, i)) return .split;
        any = true;
    }
    return if (any) .link else .flang;
}

/// A question to the driver, not a compile: what flang answers itself.
fn probe(args: Args) bool {
    for (args) |x| {
        for ([_][]const u8{ "--version", "-###", "--help", "-help", "-dumpversion", "-dumpmachine" }) |p| if (mem.eql(u8, x, p)) return true;
        if (mem.startsWith(u8, x, "-print-") or mem.startsWith(u8, x, "--print-")) return true;
    }
    return false;
}

/// args[i] is Fortran source: by the `-x` in force (f95, f95-cpp-input,
/// ...), else by its extension.
fn fortranInput(args: Args, i: usize) bool {
    if (cmdline.xLang(args, i)) |l| return cmdline.isFortranLang(l);
    return cmdline.isFortran(args[i]);
}

/// The modules flag for a flang call that reads Fortran source; nothing
/// for a probe or a call with none.
fn modules(ctx: *Ctx, flang: []const u8, args: Args) !Args {
    if (probe(args)) return &.{};
    var it = cmdline.inputs(args);
    while (it.next()) |i| {
        if (fortranInput(args, i)) return modulesFlag(ctx, flang);
    }
    return &.{};
}

/// `-fintrinsic-modules-path <dir>`, the modules directory beside `flang`
/// (flang_rt.modulesDir); nothing when it has none.
fn modulesFlag(ctx: *Ctx, flang: []const u8) !Args {
    const dir = (try flang_rt.modulesDir(ctx, flang)) orelse return &.{};
    return ctx.arena.dupe([]const u8, &.{ "-fintrinsic-modules-path", dir });
}

/// The zig link of `args`: as zig-cc links, less what zig cc refuses
/// (`link_refused`), with the runtime.
fn zigLink(ctx: *Ctx, args: Args) !Args {
    return compiler.argv(ctx, .c, try mem.concat(ctx.arena, []const u8, &.{ try drop(ctx, args, &link_refused), flibs(ctx.os) }));
}

/// Fortran's options that zig cc refuses on a link, measured (phase 6's
/// PP probe, zig 0.16.0, conda-forge's and upstream's: 5 of 40 flags; the
/// same with both at step 1, linux-64): `-J <dir>`, whose directory zig
/// reads as an input ("unrecognized file extension"; the joined `-J<dir>`
/// passes), and "Unknown Clang option" for the rest. `-Xflang <v>`,
/// `-module-dir`, `-fintrinsic-modules-path`, `-ffree-form`,
/// `-fdefault-real-8`, `-fopenmp` and the other Fortran options pass.
/// `-M*` and `-fno-fortran-main` are older flangs' spellings, which flang
/// 23 refuses too ("unknown argument"), on the compile. A host adds an
/// entry only with its measurement.
const link_refused = [_]Refused{
    .{ .flag = "-J", .value = true },
    .{ .flag = "-Mfixed" },
    .{ .flag = "-Mfree" },
    .{ .flag = "-Mextend" },
    .{ .flag = "-fno-fortran-main" },
};

/// The link-only options flang 23 refuses on a split's compile ("unknown
/// argument", also with -Qunused-arguments, which silences only the
/// options it knows and does not use), measured with flang-zig's flang
/// 23.1.1 (phase 6's CA probe, re-measured on linux-64 at step 1; the
/// driver's option table is the same on every host): macOS's dylib and
/// framework options, the gcc runtime and Windows subsystem options,
/// and the linker's one-letter ones, each with its value where it takes
/// one. The link keeps them all. Two measured lists, one per direction,
/// rather than a list of what passes: a flag on neither that one driver
/// refuses fails that call with its driver's message, never silently.
const compile_refused = [_]Refused{
    .{ .flag = "-dynamiclib" },                           .{ .flag = "-bundle" },
    .{ .flag = "-undefined", .value = true },             .{ .flag = "-framework", .value = true },
    .{ .flag = "-weak_framework", .value = true },        .{ .flag = "-F", .value = true },
    .{ .flag = "-F", .prefix = true },                    .{ .flag = "-install_name", .value = true },
    .{ .flag = "-current_version", .value = true },       .{ .flag = "-compatibility_version", .value = true },
    .{ .flag = "-exported_symbols_list", .value = true }, .{ .flag = "-unexported_symbols_list", .value = true },
    .{ .flag = "-bundle_loader", .value = true },         .{ .flag = "-multiply_defined", .value = true },
    .{ .flag = "-force_load", .value = true },            .{ .flag = "-headerpad_max_install_names" },
    .{ .flag = "-single_module" },                        .{ .flag = "-flat_namespace" },
    .{ .flag = "-dead_strip" },                           .{ .flag = "-arch", .value = true },
    .{ .flag = "-static-libgcc" },                        .{ .flag = "-static-libstdc++" },
    .{ .flag = "-shared-libgcc" },                        .{ .flag = "-static-pie" },
    .{ .flag = "-s" },                                    .{ .flag = "-mwindows" },
    .{ .flag = "-mconsole" },                             .{ .flag = "-municode" },
    .{ .flag = "-mthreads" },                             .{ .flag = "-z", .value = true },
    .{ .flag = "-u", .value = true },                     .{ .flag = "-T", .value = true },
    .{ .flag = "-e", .value = true },
};

/// An option one driver refuses: the word itself, with the next argument
/// when it takes a value, or every argument it starts (`-F<dir>`).
const Refused = struct { flag: []const u8, value: bool = false, prefix: bool = false };

/// `args` without the options in `list`, each with its value. Another
/// option's value is never read as one of them (`-Xlinker -s` keeps both).
fn drop(ctx: *Ctx, args: Args, list: []const Refused) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    next: while (i < args.len) : (i += 1) {
        const x = args[i];
        for (list) |r| {
            const hit = if (r.prefix) x.len > r.flag.len and mem.startsWith(u8, x, r.flag) else mem.eql(u8, x, r.flag);
            if (!hit) continue;
            if (r.value) i += 1;
            continue :next;
        }
        try out.append(ctx.arena, x);
        if (cmdline.takesValue(x) and i + 1 < args.len) {
            i += 1;
            try out.append(ctx.arena, args[i]);
        }
    }
    return out.items;
}

/// A call with Fortran sources that links (decision E, F): for each
/// Fortran source, in the caller's order (modules are compiled in the
/// order given, as gfortran's driver does), `flang <floor> <the caller's
/// arguments less -o, the inputs, every -x and compile_refused>
/// -Qunused-arguments -c <src> -o <tmp>/<n>-<name>.o <modules flag>`,
/// `-x <lang>` before a source only an -x classified; then the zig link
/// of the caller's arguments with each Fortran source replaced by its
/// object, every -x dropped, and a C-family source that only an -x
/// classified written `-x <lang> <src> -x none`. `n` is the source's
/// place, so `a/x.f` and `b/x.f` get two objects. -Qunused-arguments
/// silences the warnings for the link options flang takes and does not
/// use (-L, -l, -shared, -Wl,...). The caller's -v reaches both, so
/// autoconf's AC_FC_LIBRARY_LDFLAGS reads the line zig links with (ld.lld;
/// macOS: `zig ld`).
fn split(ctx: *Ctx, flang: []const u8, floor: Args, caller: Args) !Ctx.Command {
    var root = tmpRoot(ctx.os, ctx.env, caller);
    if (ctx.os == .windows) root = try mem.replaceOwned(u8, ctx.arena, root, "\\", "/");
    const tmp = if (ctx.dry_run) try ctx.fmt("{s}/rzig-fc-dryrun", .{root}) else blk: {
        var r: [8]u8 = undefined;
        ctx.io.random(&r);
        break :blk try ctx.fmt("{s}/rzig-fc-{s}", .{ root, std.fmt.bytesToHex(r, .lower) });
    };
    // what the compiles share: no -o, no input, no -x
    var shared: std.ArrayList([]const u8) = .empty;
    const is_input = try ctx.arena.alloc(bool, caller.len);
    @memset(is_input, false);
    var it = cmdline.inputs(caller);
    while (it.next()) |i| is_input[i] = true;
    {
        var i: usize = 0;
        while (i < caller.len) : (i += 1) {
            const x = caller[i];
            if (mem.eql(u8, x, "-o") or mem.eql(u8, x, "-x")) {
                i += 1;
            } else if (mem.startsWith(u8, x, "-x") or is_input[i]) {} else {
                try shared.append(ctx.arena, x);
                if (cmdline.takesValue(x) and i + 1 < caller.len) {
                    i += 1;
                    try shared.append(ctx.arena, caller[i]);
                }
            }
        }
    }
    const compile_args = try drop(ctx, shared.items, &compile_refused);
    const mods = try modulesFlag(ctx, flang);

    var steps: std.ArrayList(Ctx.Step) = .empty;
    var link: std.ArrayList([]const u8) = .empty;
    var n: usize = 0;
    var i: usize = 0;
    while (i < caller.len) : (i += 1) {
        const x = caller[i];
        if (mem.eql(u8, x, "-x")) {
            i += 1;
            continue;
        }
        if (mem.startsWith(u8, x, "-x")) continue;
        if (!is_input[i]) {
            try link.append(ctx.arena, x);
            if ((mem.eql(u8, x, "-o") or cmdline.takesValue(x)) and i + 1 < caller.len) {
                i += 1;
                try link.append(ctx.arena, caller[i]);
            }
            continue;
        }
        const lang = cmdline.xLang(caller, i);
        if (!fortranInput(caller, i)) {
            if (lang) |l| try link.appendSlice(ctx.arena, &.{ "-x", l, x, "-x", "none" }) else try link.append(ctx.arena, x);
            continue;
        }
        const obj = try ctx.fmt("{s}/{d}-{s}.o", .{ tmp, n, stem(x) });
        n += 1;
        const x_lang: Args = if (lang) |l| try ctx.arena.dupe([]const u8, &.{ "-x", l }) else &.{};
        try steps.append(ctx.arena, .{ .program = try mem.concat(ctx.arena, []const u8, &.{ &.{flang}, floor, compile_args, &.{ "-Qunused-arguments", "-c" }, x_lang, &.{ x, "-o", obj }, mods }) });
        try link.append(ctx.arena, obj);
    }
    try steps.append(ctx.arena, .{ .zig = try zigLink(ctx, link.items) });
    return .{ .steps = .{ .steps = steps.items, .tmp = tmp } };
}

/// A source's base name without its extension.
fn stem(x: []const u8) []const u8 {
    const base = cmdline.baseName(x);
    return if (mem.findScalarLast(u8, base, '.')) |d| (if (d > 0) base[0..d] else base) else base;
}

/// Where the split's temporary directory goes: TMPDIR, else /tmp on unix.
/// On Windows TEMP, then TMP (what a native program reads; never MSYS'
/// TMPDIR, whose /tmp rzig cannot open), else the output's directory, else
/// the working directory (Cc15). split turns Windows' `\\` into `/`.
pub fn tmpRoot(os: Ctx.Os, env: *const std.process.Environ.Map, args: Args) []const u8 {
    const names: []const []const u8 = if (os == .windows) &.{ "TEMP", "TMP" } else &.{"TMPDIR"};
    for (names) |name| {
        if (env.get(name)) |v| if (v.len > 0) return trimSlash(v);
    }
    if (os != .windows) return "/tmp";
    if (cmdline.outputIndex(args)) |o| if (o + 1 < args.len) {
        const out = args[o + 1];
        if (mem.findLastAny(u8, out, "/\\")) |sep| return if (sep == 0) out[0..1] else out[0..sep];
    };
    return ".";
}

fn trimSlash(v: []const u8) []const u8 {
    const t = mem.trimEnd(u8, v, "/\\");
    return if (t.len == 0) v[0..1] else t;
}

// ---------------------------------------------------------------------------

const builtin = @import("builtin");
const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

fn expectProgram(expected: Args, cmd: Ctx.Command) !void {
    switch (cmd) {
        .program => |p| try expectArgs(expected, p),
        else => {
            std.debug.print("expected flang, got: {any}\n", .{cmd});
            return error.TestExpectedProgram;
        },
    }
}

fn expectZig(expected: Args, cmd: Ctx.Command) !void {
    switch (cmd) {
        .zig => |z| try expectArgs(expected, z),
        else => {
            std.debug.print("expected zig, got: {any}\n", .{cmd});
            return error.TestExpectedZig;
        },
    }
}

/// A split's steps: the flang compiles' argv, then zig's link.
fn expectSplit(compiles: []const Args, link: Args, cmd: Ctx.Command) !void {
    const st = switch (cmd) {
        .steps => |st| st,
        else => {
            std.debug.print("expected steps, got: {any}\n", .{cmd});
            return error.TestExpectedSteps;
        },
    };
    try testing.expectEqual(compiles.len + 1, st.steps.len);
    for (compiles, st.steps[0..compiles.len]) |want, got| try expectArgs(want, got.program);
    try expectArgs(link, st.steps[compiles.len].zig);
}

/// An executable flang on PATH (flang.exe on a Windows host), which these
/// cases never run. Its path, as zig-fc finds it.
fn plainFlang(f: *testutil.Fixture) ![]const u8 {
    if (builtin.os.tag == .windows) try f.touch("bin/flang.exe") else try f.touchExe("bin/flang");
    try f.env.put("PATH", f.path("bin"));
    return (try flang_rt.flang(&f.ctx)).?;
}

/// The same in an LLVM tree with its intrinsic modules (flang-rt's
/// layout): the flang, and the flag zig-fc adds for it.
fn modulesFlang(f: *testutil.Fixture) !struct { fc: []const u8, flag: Args } {
    const fc = try f.touchProgram("llvm/bin/flang");
    try f.tmp.dir.createDirPath(testing.io, "llvm/lib/clang/23/finclude/flang/x86_64-conda-linux-gnu");
    try f.env.put("PATH", f.path("llvm/bin"));
    try testing.expectEqualStrings(fc, (try flang_rt.flang(&f.ctx)).?);
    return .{ .fc = fc, .flag = try f.ctx.arena.dupe([]const u8, &.{ "-fintrinsic-modules-path", f.path("llvm/lib/clang/23/finclude/flang/x86_64-conda-linux-gnu") }) };
}

/// zig-cc's link of `args` (compiler.zig): what a link zig-fc sends to
/// zig must equal, on the fixture's OS.
fn zigCc(f: *testutil.Fixture, args: Args) !Args {
    return compiler.argv(&f.ctx, .c, args);
}

fn cat(f: *testutil.Fixture, parts: []const Args) Args {
    return mem.concat(f.ctx.arena, []const u8, parts) catch @panic("OOM");
}

test "compiles, -E, -fsyntax-only and probes: flang with the caller's arguments, after the floor on macOS, the modules path last" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try testing.expectEqualStrings("-mmacosx-version-min=13.0", floors.macos_min_flag);
    // calls that read Fortran source: the flag after the caller's arguments
    const reads = [_]Args{
        &.{ "-fpic", "-O2", "-c", "a.f", "-o", "a.o" },
        &.{ "-O2", "-c", "m.f90", "-o", "m.o" },
        &.{ "-I/r/include", "-DX=1", "-c", "p.F", "-o", "p.o" },
        // flang tunes for -mtune's CPU only, unlike zig cc: kept
        &.{ "-mtune=native", "-O2", "-c", "t.f90", "-o", "t.o" },
        &.{ "-E", "p.F90" },
        &.{ "-S", "a.f90" },
        // a check writes nothing to link: one flang call, no split (Cc9)
        &.{ "-fsyntax-only", "a.f90" },
        &.{ "-c", "-x", "f95", "a" },
        // a compile that also names link options stays a compile
        &.{ "-shared", "-c", "a.f" },
    };
    // calls that do not: probes, a C file, no input
    const others = [_]Args{
        &.{"--version"},
        &.{"-v"},
        &.{},
        &.{ "-E", "c.c" },
        &.{"-print-resource-dir"},
        &.{ "-###", "-c", "a.f90" },
        &.{ "-shared", "-c", "a.o" },
    };
    const m = try modulesFlang(&f);
    for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
        c.os = os;
        const floor: Args = if (os == .macos) &.{floors.macos_min_flag} else &.{};
        for (reads) |call| try expectProgram(cat(&f, &.{ &.{m.fc}, floor, call, m.flag }), try command(c, call));
        for (others) |call| try expectProgram(cat(&f, &.{ &.{m.fc}, floor, call }), try command(c, call));
    }
    // a flang with no modules directory beside it: no flag
    c.os = .linux;
    const fc = try plainFlang(&f);
    for (reads ++ others) |call| try expectProgram(cat(&f, &.{ &.{fc}, call }), try command(c, call));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "every link of objects goes through zig, executables too, less what zig cc refuses" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    _ = try plainFlang(&f);
    for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
        c.os = os;
        const fl = flibs(os);
        const links = [_][2]Args{
            // an executable of objects: was flang's own driver's link
            .{ &.{ "-o", "prog", "a.o", "b.o" }, &.{ "-o", "prog", "a.o", "b.o" } },
            .{ &.{ "-shared", "-o", "p.so", "a.o" }, &.{ "-shared", "-o", "p.so", "a.o" } },
            // a word inside another argument is no flag: still a link
            .{ &.{ "-Wl,-shared", "-o", "p.so", "a.o" }, &.{ "-Wl,-shared", "-o", "p.so", "a.o" } },
            // what zig cc refuses goes (-J's directory with it); -J<dir> and
            // other Fortran options stay (phase 6's PP)
            .{ &.{ "-J", "mods", "-Jm2", "-Mfree", "-Mfixed", "-Mextend", "-fno-fortran-main", "-o", "p", "a.o" }, &.{ "-Jm2", "-o", "p", "a.o" } },
            .{ &.{ "-Xlinker", "-J", "-ffree-form", "-o", "p", "a.o" }, &.{ "-Xlinker", "-J", "-ffree-form", "-o", "p", "a.o" } },
            // C sources and no Fortran one: zig's whole, as zig-cc's
            .{ &.{ "-o", "p", "a.o", "glue.c" }, &.{ "-o", "p", "a.o", "glue.c" } },
            // objects in a response file (rzig build's links): an input,
            // no Fortran source, so a link, the @file passed on for zig
            .{ &.{ "-shared", "-o", "p.so", "@objects.rsp", "-lR" }, &.{ "-shared", "-o", "p.so", "@objects.rsp", "-lR" } },
        };
        for (links) |l| try expectZig(try zigCc(&f, cat(&f, &.{ l[1], fl })), try command(c, l[0]));
    }
    // Windows: gcc's .exe on the executable (compiler.zig, windows.exeSuffix)
    c.os = .windows;
    const z = (try command(c, &.{ "-o", "prog", "a.o" })).zig;
    try testing.expect(for (z) |x| {
        if (mem.eql(u8, x, "prog.exe")) break true;
    } else false);
    _ = f.takeWarnings();
}

test "sources and a link: a flang compile per Fortran source, then zig's link" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    c.dry_run = true;
    try f.env.put("TMPDIR", f.path("t"));
    const m = try modulesFlang(&f);
    const fc = m.fc;
    const d = f.path("t/rzig-fc-dryrun");
    const o0 = f.fmt("{s}/0-conftest.o", .{d});
    const fl = flibs(.linux);
    const q: Args = &.{ "-Qunused-arguments", "-c" };
    // configure's AC_LANG(Fortran) link probe
    try expectSplit(
        &.{cat(&f, &.{ &.{ fc, "-O2" }, q, &.{ "conftest.f", "-o", o0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-o", "conftest", "-O2", o0 }, fl })),
        try command(c, &.{ "-o", "conftest", "-O2", "conftest.f" }),
    );
    // -v reaches both: autoconf's AC_FC_LIBRARY_LDFLAGS reads zig's line
    try expectSplit(
        &.{cat(&f, &.{ &.{ fc, "-v" }, q, &.{ "conftest.f", "-o", o0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-v", "-o", "conftest", o0 }, fl })),
        try command(c, &.{ "-v", "-o", "conftest", "conftest.f" }),
    );
    const a0 = f.fmt("{s}/0-a.o", .{d});
    // a source and an object
    try expectSplit(
        &.{cat(&f, &.{ &.{ fc, "-shared" }, q, &.{ "a.f", "-o", a0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-shared", "-o", "p.so", a0, "b.o" }, fl })),
        try command(c, &.{ "-shared", "-o", "p.so", "a.f", "b.o" }),
    );
    // a C source is no step: zig compiles and links it (Cc7)
    try expectSplit(
        &.{cat(&f, &.{ &.{ fc, "-shared" }, q, &.{ "a.f", "-o", a0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-shared", "-o", "p.so", a0, "glue.c" }, fl })),
        try command(c, &.{ "-shared", "-o", "p.so", "a.f", "glue.c" }),
    );
    // Fortran by -x, both of flang's names; no -x reaches the link
    for ([_][]const u8{ "f95", "f95-cpp-input" }) |lang| {
        try expectSplit(
            &.{cat(&f, &.{ &.{ fc, "-shared" }, q, &.{ "-x", lang, "a", "-o", a0 }, m.flag })},
            try zigCc(&f, cat(&f, &.{ &.{ "-shared", "-o", "p.so", a0 }, fl })),
            try command(c, &.{ "-shared", "-x", lang, "-o", "p.so", "a" }),
        );
        try expectSplit(
            &.{cat(&f, &.{ &.{fc}, q, &.{ "-x", lang, "a", "-o", a0 }, m.flag })},
            try zigCc(&f, cat(&f, &.{ &.{ a0, "-o", "p" }, fl })),
            try command(c, &.{ f.fmt("-x{s}", .{lang}), "a", "-o", "p" }),
        );
    }
    // a C source only an -x classified keeps it, on zig's line alone
    try expectSplit(
        &.{cat(&f, &.{ &.{fc}, q, &.{ "-x", "f95", "a", "-o", a0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-x", "c", "g", "-x", "none", a0, "-o", "p", "x.o" }, fl })),
        try command(c, &.{ "-x", "c", "g", "-x", "f95", "a", "-o", "p", "-x", "none", "x.o" }),
    );
    // two sources with one base name: two objects, in the caller's order
    try expectSplit(
        &.{
            cat(&f, &.{ &.{fc}, q, &.{ "a/x.f", "-o", f.fmt("{s}/0-x.o", .{d}) }, m.flag }),
            cat(&f, &.{ &.{fc}, q, &.{ "b/x.f", "-o", f.fmt("{s}/1-x.o", .{d}) }, m.flag }),
        },
        try zigCc(&f, cat(&f, &.{ &.{ "-o", "p", f.fmt("{s}/0-x.o", .{d}), f.fmt("{s}/1-x.o", .{d}) }, fl })),
        try command(c, &.{ "-o", "p", "a/x.f", "b/x.f" }),
    );
    // a module directory: on both compiles, off the link (zig reads its
    // value as an input); a module used across the two files
    try expectSplit(
        &.{
            cat(&f, &.{ &.{ fc, "-J", "mods" }, q, &.{ "m.f90", "-o", f.fmt("{s}/0-m.o", .{d}) }, m.flag }),
            cat(&f, &.{ &.{ fc, "-J", "mods" }, q, &.{ "u.f90", "-o", f.fmt("{s}/1-u.o", .{d}) }, m.flag }),
        },
        try zigCc(&f, cat(&f, &.{ &.{ "-o", "p", f.fmt("{s}/0-m.o", .{d}), f.fmt("{s}/1-u.o", .{d}) }, fl })),
        try command(c, &.{ "-J", "mods", "-o", "p", "m.f90", "u.f90" }),
    );
    // what zig cc refuses stays on the compile (flang 23 refuses -Mfree
    // there itself, loudly); a value of -Xlinker is no option
    try expectSplit(
        &.{cat(&f, &.{ &.{ fc, "-Mfree", "-Xlinker", "-s" }, q, &.{ "a.f", "-o", a0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-Xlinker", "-s", "-o", "p", a0 }, fl })),
        try command(c, &.{ "-Mfree", "-Xlinker", "-s", "-o", "p", "a.f" }),
    );
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "a split on macOS and Windows: the floor on each compile; link-only options off the compile, on the link (Cc1, Cc2)" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const c = &f.ctx;
    c.dry_run = true;
    try f.env.put("TMPDIR", f.path("t"));
    try f.env.put("TEMP", "C:\\Users\\u\\Temp\\");
    const m = try modulesFlang(&f);
    const q: Args = &.{ "-Qunused-arguments", "-c" };
    const a0 = f.path("t/rzig-fc-dryrun/0-a.o");
    // macOS SHLIB's link line, as R CMD SHLIB writes it with sources
    try expectSplit(
        &.{cat(&f, &.{ &.{ m.fc, floors.macos_min_flag, "-Wl,-headerpad_max_install_names", "-O2" }, q, &.{ "a.f90", "-o", a0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ &.{ "-dynamiclib", "-Wl,-headerpad_max_install_names", "-undefined", "dynamic_lookup", "-framework", "Accelerate", "-F/x", "-O2", "-o", "x.so", a0 }, flibs(.macos) })),
        try command(c, &.{ "-dynamiclib", "-Wl,-headerpad_max_install_names", "-undefined", "dynamic_lookup", "-framework", "Accelerate", "-F/x", "-O2", "-o", "x.so", "a.f90" }),
    );
    // every measured option, with its value
    const refused: Args = &.{ "-bundle", "-weak_framework", "W", "-F", "/f", "-install_name", "n", "-current_version", "1", "-compatibility_version", "1", "-exported_symbols_list", "e", "-unexported_symbols_list", "u", "-bundle_loader", "b", "-multiply_defined", "suppress", "-force_load", "l.a", "-headerpad_max_install_names", "-single_module", "-flat_namespace", "-dead_strip", "-arch", "arm64", "-z", "now", "-u", "s", "-T", "t.ld", "-e", "main" };
    try expectSplit(
        &.{cat(&f, &.{ &.{ m.fc, floors.macos_min_flag }, q, &.{ "a.f90", "-o", a0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ refused, &.{ "-o", "x", a0 }, flibs(.macos) })),
        try command(c, cat(&f, &.{ refused, &.{ "-o", "x", "a.f90" } })),
    );
    // Windows' SHLIB line: TEMP's directory, `/` only
    c.os = .windows;
    const w0 = "C:/Users/u/Temp/rzig-fc-dryrun/0-a.o";
    const win: Args = &.{ "-shared", "-s", "-static-libgcc", "-static-libstdc++", "-shared-libgcc", "-static-pie", "-mwindows", "-mconsole", "-municode", "-mthreads" };
    try expectSplit(
        &.{cat(&f, &.{ &.{ m.fc, "-shared" }, q, &.{ "a.f90", "-o", w0 }, m.flag })},
        try zigCc(&f, cat(&f, &.{ win, &.{ "-o", "x.dll", w0 }, flibs(.windows) })),
        try command(c, cat(&f, &.{ win, &.{ "-o", "x.dll", "a.f90" } })),
    );
    _ = f.takeWarnings();
}

test "the split's directory: TMPDIR or /tmp; Windows: TEMP, TMP, the output's directory (Cc15); random unless a dry run" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    var env: std.process.Environ.Map = .init(f.ctx.arena);
    const args: Args = &.{ "-o", "C:\\out\\dir\\x.exe", "a.f" };
    try testing.expectEqualStrings("/tmp", tmpRoot(.linux, &env, args));
    try testing.expectEqualStrings(".", tmpRoot(.windows, &env, &.{ "-o", "x", "a.f" }));
    try testing.expectEqualStrings(".", tmpRoot(.windows, &env, &.{"a.f"}));
    try testing.expectEqualStrings("C:\\out\\dir", tmpRoot(.windows, &env, args));
    try testing.expectEqualStrings("/", tmpRoot(.windows, &env, &.{ "-o", "/x", "a.f" }));
    // MSYS' TMPDIR is never a native program's
    try env.put("TMPDIR", "/tmp/");
    try testing.expectEqualStrings("/tmp", tmpRoot(.linux, &env, args));
    try testing.expectEqualStrings("C:\\out\\dir", tmpRoot(.windows, &env, args));
    try env.put("TMP", "C:\\b");
    try testing.expectEqualStrings("C:\\b", tmpRoot(.windows, &env, args));
    try env.put("TEMP", "C:\\a\\");
    try testing.expectEqualStrings("C:\\a", tmpRoot(.windows, &env, args));
    // empty is unset, as everywhere in rzig
    try env.put("TEMP", "");
    try testing.expectEqualStrings("C:\\b", tmpRoot(.windows, &env, args));

    // a real run: rzig-fc-<16 hex>, a new one each time, not made yet
    const c = &f.ctx;
    try f.env.put("TMPDIR", f.path("t"));
    _ = try plainFlang(&f);
    var seen: [2][]const u8 = undefined;
    for (&seen) |*s| {
        const st = (try command(c, &.{ "-o", "p", "a.f" })).steps;
        const prefix = f.path("t/rzig-fc-");
        try testing.expect(mem.startsWith(u8, st.tmp, prefix) and st.tmp.len == prefix.len + 16);
        try testing.expect(!c.exists(st.tmp));
        s.* = st.tmp;
    }
    try testing.expect(!mem.eql(u8, seen[0], seen[1]));
    _ = f.takeWarnings();
}

/// A flang on PATH that answers -print-resource-dir with an LLVM tree
/// holding the static runtime for `triple`. The archive's path.
fn runtimeFlang(f: *testutil.Fixture, triple: []const u8) ![]const u8 {
    const rd = f.path("llvm/lib/clang/23");
    const a = f.fmt("{s}/lib/{s}/libflang_rt.runtime.a", .{ rd, triple });
    try f.touch(f.fmt("llvm/lib/clang/23/lib/{s}/libflang_rt.runtime.a", .{triple}));
    try f.write("bin/flang", f.fmt("#!/bin/sh\n[ \"$1\" = -print-resource-dir ] && printf '%s\\n' '{s}'\n", .{rd}), .fromMode(0o755));
    try f.env.put("PATH", f.path("bin"));
    return a;
}

const linux_target = @tagName(builtin.cpu.arch) ++ "-linux-gnu." ++ floors.majorMinor(floors.glibc);

test "linux: a shared link of objects goes through zig cc, as zig-cc's, with the static runtime and -lm" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for flang
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const a = try runtimeFlang(&f, "x86_64-unknown-linux-gnu");
    // installed in a conda env: its -L and rpath, as zig-cc adds them
    try f.tmp.dir.createDirPath(testing.io, "env/lib/R/bin/toolchain");
    try f.tmp.dir.createDirPath(testing.io, "env/conda-meta");
    c.self_exe = f.path("env/lib/R/bin/toolchain/zig-fc");
    const l = f.fmt("-L{s}", .{f.path("env/lib")});
    const rp = f.fmt("-Wl,-rpath,{s}", .{f.path("env/lib")});
    const pre: Args = &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-target", linux_target };
    // R CMD SHLIB under USE_FC_TO_LINK: $(SHLIB_FCLD) $(SHLIB_FCLDFLAGS)
    // $(LIBR0) $(LDFLAGS) -o pkg.so <objects> $(PKG_LIBS) $(SHLIB_LIBADD)
    try expectZig(
        pre ++ &[_][]const u8{ "-Wl,--strip-debug", "-shared", "-L/r/lib", "-o", "pkg.so", "a.o", "b.o", "-L/opt/lib", "-lfoo", a, "-lm", l, rp },
        try command(c, &.{ "-shared", "-L/r/lib", "-o", "pkg.so", "a.o", "b.o", "-L/opt/lib", "-lfoo" }),
    );
    // a package that also asks for $(FLIBS): the runtime once; a SONAME for lib*.so
    try expectZig(
        pre ++ &[_][]const u8{ "-Wl,-soname,libfx.so", "-Wl,--strip-debug", "-shared", "-o", "libfx.so", "a.o", a, "-lm", "-lm", l, rp },
        try command(c, &.{ "-shared", "-o", "libfx.so", "a.o", "-lflang_rt.runtime", "-lm" }),
    );
    // a -mtune= on the link (zig cc's: dropped, compiler.zig dropTune)
    try expectZig(
        pre ++ &[_][]const u8{ "-Wl,--strip-debug", "-shared", "-O2", "-o", "pkg.so", "a.o", a, "-lm", l, rp },
        try command(c, &.{ "-shared", "-O2", "-mtune=native", "-o", "pkg.so", "a.o" }),
    );
    // OpenMP, as zig-cc: -lomp when an environment has omp.h
    try f.touch("env/include/omp.h");
    try expectZig(
        pre ++ &[_][]const u8{ "-Wl,--strip-debug", "-shared", "-fopenmp", "-o", "p.so", "a.o", a, "-lm", l, rp, f.fmt("-I{s}", .{f.path("env/include")}), "-lomp" },
        try command(c, &.{ "-shared", "-fopenmp", "-o", "p.so", "a.o" }),
    );
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "macOS: the shared link has the target, the SDK and the runtime; -dynamiclib counts" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-ins for flang and xcrun
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const c = &f.ctx;
    const a = try runtimeFlang(&f, "darwin");
    try f.write("xcrun", "#!/bin/sh\necho /SDK\n", .fromMode(0o755));
    c.xcrun = f.path("xcrun");
    const t: Args = &.{ "-target", (if (builtin.cpu.arch == .aarch64) "aarch64" else "x86_64") ++ "-native.13.0", "-F/SDK/System/Library/Frameworks" };
    // macOS SHLIB_FCLDFLAGS; the caller's -lm is kept and the runtime's
    // second one dropped (darwin.dedupLibs), the SDK's -L last
    try expectZig(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-Wl,-headerpad_max_install_names", "-undefined", "dynamic_lookup", "-L/r/lib", "-o", "p.so", "a.o", "-lflangish", "-lm", a, "-L/SDK/usr/lib" },
        try command(c, &.{ "-dynamiclib", "-Wl,-headerpad_max_install_names", "-undefined", "dynamic_lookup", "-L/r/lib", "-o", "p.so", "a.o", "-lflangish", "-lm" }),
    );
    try expectZig(
        &[_][]const u8{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0" } ++ t ++ &[_][]const u8{ "-dynamiclib", "-o", "p.so", "a.o", a, "-lm", "-L/SDK/usr/lib" },
        try command(c, &.{ "-dynamiclib", "-o", "p.so", "a.o" }),
    );
}

test "Windows: the shared link resolves -l to import libraries, adds the runtime alone, no .exe" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // shell-script stand-in for flang
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    const a = try runtimeFlang(&f, "x86_64-w64-windows-gnu");
    try f.touch("d/libz.dll.a");
    const l = f.fmt("-L{s}", .{f.path("d")});
    // winshlib.mk: $(SHLIB_LD) $(SHLIB_LDFLAGS) $(LDFLAGS) $(DLLFLAGS) -o pkg.dll tmp.def <objects> $(ALL_LIBS),
    // then a DLL's default system library (windows.defaultLibs)
    try expectZig(
        &.{ "cc", "-fno-sanitize=undefined", "-mcpu=baseline", "-Wno-error=date-time", "-g0", "-Xlinker", "--out-implib=pkg.dll.rzig.lib", "-shared", "-O2", "-s", "-static-libgcc", "-o", "pkg.dll", "tmp.def", "a.o", l, f.path("d/libz.dll.a"), a, "-lws2_32" },
        try command(c, &.{ "-shared", "-O2", "-s", "-static-libgcc", "-o", "pkg.dll", "tmp.def", "a.o", l, "-lz" }),
    );
}

test "no flang: nothing runs, the compilers group's text; R_ZIG_TOOLCHAIN_HINT not read" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.env.put("PATH", f.path("nothing"));
    // the same text a compile with no zig and the check mode print (groups.zig)
    const msg = f.fmt("rzig-test: no flang (R_HOME/bin/toolchain/flang/bin, the environment's bin, PATH)\n{s}", .{try groups.text(c.arena, .compilers, groups.this)});
    try testing.expect(mem.find(u8, msg, "\nCompiling needs the r-zig compilers for R ") != null);
    for ([_]Args{ &.{ "-c", "a.f" }, &.{"--version"}, &.{ "-shared", "-o", "p.so", "a.o" } }) |call| {
        try testing.expectError(error.NoFlang, command(c, call));
        try testing.expectEqualStrings(msg, f.takeWarnings());
    }
    // R_ZIG_TOOLCHAIN_HINT, a user's value since phase 4, changes nothing
    // (the two values are what the channels wrote before it)
    for ([_][]const u8{
        "pip install r-zig-toolchain (same Python environment as r-zig)",
        "add the r-zig-toolchain package to this environment",
    }) |hint| {
        try f.env.put("R_ZIG_TOOLCHAIN_HINT", hint);
        for ([_]Ctx.Os{ .linux, .macos, .windows }) |os| {
            c.os = os;
            try testing.expectError(error.NoFlang, command(c, &.{ "-c", "a.f" }));
            try testing.expectEqualStrings(msg, f.takeWarnings());
        }
    }
    c.os = .macos;
    // a file named flang that is not executable is no flang
    if (builtin.os.tag != .windows) {
        try f.touch("bin/flang");
        try f.env.put("PATH", f.path("bin"));
        try testing.expectError(error.NoFlang, command(c, &.{ "-c", "a.f" }));
    }
}

test "the compilers group's flang wins over PATH's; zig-fc runs it" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-fc");
    _ = try plainFlang(&f);
    const tc = try f.touchProgram("tree/lib/R/bin/toolchain/flang/bin/flang");
    try expectProgram(&.{ tc, "-c", "a.f90" }, try command(c, &.{ "-c", "a.f90" }));
    // its modules, from its own place (flang_rt.modulesDir)
    const mods = "tree/lib/R/bin/toolchain/flang/lib/clang/23/finclude/flang/x86_64-conda-linux-gnu";
    try f.tmp.dir.createDirPath(testing.io, mods);
    try expectProgram(&.{ tc, "-c", "a.f90", "-fintrinsic-modules-path", f.path(mods) }, try command(c, &.{ "-c", "a.f90" }));
}
