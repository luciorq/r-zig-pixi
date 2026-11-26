//! linux: every C++ compile and link uses gcc's libstdc++, not zig's
//! libc++ (CXX-STDLIB.md decisions 1 and 2; chore-release-11 finding 31;
//! feat-linux-libstdcxx). conda-forge's and the distros' C++ libraries
//! are gcc builds, and packages pass C++ objects to each other at run
//! time (Rcpp's callables), so one standard library for all C++ on linux.
//! macOS and Windows keep zig's libc++.
//!
//! Compile: -nostdinc++ before the caller's arguments; after them (and
//! after the environments' -I, as gcc searches -I before its own C++
//! headers): the shim directory, then libstdc++'s headers
//! (<gcc dir>/include/c++, its <triple> and backward directories) as -I,
//! because zig passes its libc directories as -isystem first, and
//! libstdc++'s #include_next <stdlib.h> must find them after its own
//! (-isystem and -cxx-isystem fail there). -D_GLIBCXX_SYSHDR: libstdc++
//! 15 marks its headers system headers (#pragma GCC system_header) only
//! with it; else -Wall warns in them.
//! Link: -nostdlib++ (zig adds no libc++), then the runtime R loads,
//! libstdc++.so.6 and libgcc_s.so.1, by path (DT_NEEDED is the soname).
//! Without libgcc_s zig links its own libunwind.a, and a C++ exception
//! thrown in libstdc++ code aborts.
//! zig swallows -lstdc++ under -nostdlib++ and maps it to its libc++
//! otherwise, and drops -lgcc_s: so on every linux link, C links too
//! (cargo's cc-rs, cgo, a Makefile that links C++ objects with $(CC)),
//! the caller's -lstdc++ becomes the runtime's two paths, -lgcc_s the
//! libgcc_s path, and -lstdc++fs and -lstdc++exp gcc's archives beside
//! the headers (dropped where there are none: libstdc++ 9 and later has
//! std::filesystem in libstdc++.so). zig ignores -static-libstdc++; it
//! is dropped, with a note under RZIG_TRACE.
//!
//! A C++ command is zig-cxx's, or zig-cc's with -x c++ (or -xc++,
//! c++-header ...). One with no input (--version, -dumpversion, -print-*)
//! gets none of this and never fails. One with an input and no headers
//! stops with the compilers group's text (groups.zig), never a silent
//! fallback to libc++ (decision 2).
//!
//! Where (first found):
//!   headers: lib/gcc/<triple>/<highest version>/include/c++ in R's own
//!     environment (conda: libstdcxx-devel_linux-*), then the compilers
//!     group's <rzig dir>/libstdcxx/ (the standalone tree, the wheel),
//!     then R_ZIG_EXTRA_ENV's;
//!   runtime: lib/libstdc++.so.6 and lib/libgcc_s.so.1 in the first
//!     environment that has both (environment.list: R's own, then
//!     R_ZIG_EXTRA_ENV's). R's own is the one libR.so loads (it needs
//!     both, build.zig's linkCxxRuntime), so a package links against
//!     the runtime it runs with;
//!   shims: <rzig dir>/libstdcxx-shim (sys/single_threaded.h,
//!     bits/c++config.h), installed with rzig, R's base.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const environment = @import("environment.zig");
const flang_rt = @import("flang_rt.zig");
const groups = @import("groups.zig");
const Args = cmdline.Args;

pub const Flags = struct {
    /// before the caller's arguments
    pre: Args = &.{},
    /// after the caller's and the environments' arguments
    post: Args = &.{},
};

/// What a compile says when it finds no headers, before the compilers
/// group's text. verify-bundle.sh and wheel-test.sh grep it.
pub const no_headers = "no libstdc++ headers for C++ on linux (lib/gcc/<triple>/<version>/include/c++ in R's environment, R_HOME/bin/toolchain/libstdcxx, R_ZIG_EXTRA_ENV)";

/// The triple directory name conda-forge's gcc uses.
pub fn triple(ctx: *const Ctx) []const u8 {
    return switch (ctx.arch) {
        .x86_64 => "x86_64-conda-linux-gnu",
        .aarch64 => "aarch64-conda-linux-gnu",
    };
}

/// <root>/lib/gcc/<triple>/<highest version with include/c++>, or null.
fn gccDir(ctx: *Ctx, root: []const u8) !?[]const u8 {
    const base = try ctx.fmt("{s}/lib/gcc/{s}", .{ root, triple(ctx) });
    var best: ?[]const u8 = null;
    for (try flang_rt.globDirs(ctx, base)) |v| {
        if (!isVersion(v)) continue;
        if (!ctx.isDir(try ctx.fmt("{s}/{s}/include/c++", .{ base, v }))) continue;
        if (best == null or versionLess(best.?, v)) best = v;
    }
    return if (best) |v| try ctx.fmt("{s}/{s}", .{ base, v }) else null;
}

fn isVersion(v: []const u8) bool {
    if (v.len == 0) return false;
    for (v) |c| if (!std.ascii.isDigit(c) and c != '.') return false;
    return true;
}

fn versionLess(a: []const u8, b: []const u8) bool {
    var ia = mem.splitScalar(u8, a, '.');
    var ib = mem.splitScalar(u8, b, '.');
    while (true) {
        const x = ia.next();
        const y = ib.next();
        if (x == null and y == null) return false;
        const nx = std.fmt.parseInt(u32, x orelse "0", 10) catch 0;
        const ny = std.fmt.parseInt(u32, y orelse "0", 10) catch 0;
        if (nx != ny) return nx < ny;
    }
}

/// The gcc directory whose include/c++ C++ compiles use, or null.
pub fn headersDir(ctx: *Ctx) !?[]const u8 {
    if (try environment.own(ctx)) |e| if (try gccDir(ctx, e.dir)) |d| return d;
    if (environment.toolchain(ctx)) |tc| if (try gccDir(ctx, try ctx.fmt("{s}/libstdcxx", .{tc}))) |d| return d;
    // conda's r-zig-compilers in R_ZIG_TOOLCHAIN_ENV (L6) brings
    // libstdcxx-devel there
    if (try environment.toolchainEnv(ctx)) |e| if (try gccDir(ctx, e.dir)) |d| return d;
    if (try environment.extra(ctx)) |e| if (try gccDir(ctx, e.dir)) |d| return d;
    return null;
}

pub const Runtime = struct { stdcxx: []const u8, gcc_s: []const u8 };

pub fn runtime(ctx: *Ctx) !?Runtime {
    for (try environment.list(ctx)) |e| {
        const s = try ctx.fmt("{s}/lib/libstdc++.so.6", .{e.dir});
        const g = try ctx.fmt("{s}/lib/libgcc_s.so.1", .{e.dir});
        if (ctx.isFile(s) and ctx.isFile(g)) return .{ .stdcxx = s, .gcc_s = g };
    }
    return null;
}

/// A C++ command: zig-cxx's, or one with -x c++ (-xc++, -x c++-header).
pub fn isCxx(cxx_driver: bool, args: Args) bool {
    if (cxx_driver) return true;
    for (args, 0..) |x, i| {
        const v = if (mem.eql(u8, x, "-x")) (if (i + 1 < args.len) args[i + 1] else continue) else if (mem.startsWith(u8, x, "-x")) x[2..] else continue;
        if (mem.startsWith(u8, v, "c++")) return true;
    }
    return false;
}

/// An input file, or `-` (standard input, as `-E -x c++ -` reads):
/// --version, -dumpversion, -print-file-name= and the like have none.
pub fn hasInput(args: Args) bool {
    var it = cmdline.inputs(args);
    if (it.next() != null) return true;
    for (args) |x| if (mem.eql(u8, x, "-")) return true;
    return false;
}

/// The caller's own choice of standard headers or libraries: then rzig
/// adds none of that kind (a package that builds its own C++ runtime).
fn ownHeaders(args: Args) bool {
    return cmdline.anyWord(args, "-nostdinc++") or cmdline.anyWord(args, "-nostdinc");
}
fn ownLibs(args: Args) bool {
    return cmdline.anyWord(args, "-nostdlib++") or cmdline.anyWord(args, "-nostdlib") or cmdline.anyWord(args, "-nodefaultlibs");
}

fn traced(ctx: *const Ctx) bool {
    const v = ctx.getenv("RZIG_TRACE") orelse return false;
    return !mem.eql(u8, v, "0");
}

/// On any linux link: the caller's -lstdc++ (and -l:libstdc++.so*) as
/// the runtime's two paths (libgcc_s once), -lgcc_s as its path,
/// -lstdc++fs and -lstdc++exp as gcc's archives or nothing, and no
/// -static-libstdc++. The two-argument form (`-l stdc++`) counts too: zig
/// would map it to its libc++. With no runtime the names stay (a bare
/// rzig outside any environment: zig then decides, as before).
/// -Wl,-lstdc++ arrives here as -lstdc++: zig refuses an -l inside -Wl,
/// ("unsupported linker arg"), so linker_args.zig makes it the driver's
/// first (fix-rzig-quick Q24; was L21's "not rewritten").
pub fn rewriteLibs(ctx: *Ctx, args: Args, rt: ?Runtime) !Args {
    if (cmdline.compileOnly(args)) return args;
    const a = ctx.arena;
    var out: std.ArrayList([]const u8) = .empty;
    var gcc_s = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        // `-l name` as one word; `orig` is what the caller wrote
        const two = mem.eql(u8, x, "-l") and i + 1 < args.len;
        const lib = if (two) try ctx.fmt("-l{s}", .{args[i + 1]}) else x;
        const orig = if (two) args[i .. i + 2] else args[i .. i + 1];
        if (two) i += 1;
        if (mem.eql(u8, lib, "-lgcc_s") or mem.eql(u8, lib, "-l:libgcc_s.so.1") or mem.eql(u8, lib, "-l:libgcc_s.so")) {
            const r = rt orelse {
                try out.appendSlice(a, orig);
                continue;
            };
            if (!gcc_s) try out.append(a, r.gcc_s);
            gcc_s = true;
        } else if (mem.eql(u8, lib, "-lstdc++") or mem.startsWith(u8, lib, "-l:libstdc++.so")) {
            const r = rt orelse {
                try out.appendSlice(a, orig);
                continue;
            };
            try out.append(a, r.stdcxx);
            if (!gcc_s) try out.append(a, r.gcc_s);
            gcc_s = true;
        } else if (mem.eql(u8, lib, "-lstdc++fs") or mem.eql(u8, lib, "-lstdc++exp")) {
            const archive = if (try headersDir(ctx)) |g| try ctx.fmt("{s}/lib{s}.a", .{ g, lib[2..] }) else null;
            if (archive != null and ctx.isFile(archive.?)) {
                try out.append(a, archive.?);
            } else if (traced(ctx)) {
                ctx.warn("note: {s} dropped: no lib{s}.a beside the libstdc++ headers", .{ lib, lib[2..] });
            }
        } else if (mem.eql(u8, lib, "-static-libstdc++")) {
            // dropped without a word on purpose (feat-linux-libstdcxx
            // PLAN.md): zig ignores it too, and a note on every link
            // would reach configure and CMake checks that read stderr
            if (traced(ctx)) ctx.warn("note: -static-libstdc++ dropped: C++ on linux links libstdc++.so.6, the runtime R loads", .{});
        } else try out.appendSlice(a, orig);
    }
    return out.items;
}

/// The flags of a C++ command on linux. No input: none. No headers (or,
/// on a link, no runtime): error.NoLibstdcxx, after what is missing (the
/// headers: the compilers group's text).
pub fn flags(ctx: *Ctx, args: Args, rt: ?Runtime) !Flags {
    if (!hasInput(args)) return .{};
    const a = ctx.arena;
    var pre: std.ArrayList([]const u8) = .empty;
    var post: std.ArrayList([]const u8) = .empty;
    if (!ownHeaders(args)) {
        const gcc = (try headersDir(ctx)) orelse {
            try groups.report(ctx, no_headers, .compilers);
            return error.NoLibstdcxx;
        };
        try pre.append(a, "-nostdinc++");
        if (environment.toolchain(ctx)) |tc| {
            const shim = try ctx.fmt("{s}/libstdcxx-shim", .{tc});
            if (ctx.isDir(shim)) try post.append(a, try ctx.fmt("-I{s}", .{shim}));
        }
        try post.appendSlice(a, &.{
            try ctx.fmt("-I{s}/include/c++", .{gcc}),
            try ctx.fmt("-I{s}/include/c++/{s}", .{ gcc, triple(ctx) }),
            try ctx.fmt("-I{s}/include/c++/backward", .{gcc}),
            "-D_GLIBCXX_SYSHDR",
        });
    }
    if (!cmdline.compileOnly(args) and !ownLibs(args)) {
        const r = rt orelse {
            ctx.warn("no libstdc++ runtime for a C++ link on linux (lib/libstdc++.so.6 and lib/libgcc_s.so.1 in R's environment or R_ZIG_EXTRA_ENV)", .{});
            return error.NoLibstdcxx;
        };
        try pre.append(a, "-nostdlib++");
        try post.appendSlice(a, &.{ r.stdcxx, r.gcc_s });
    }
    return .{ .pre = pre.items, .post = post.items };
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "headers: R's own environment first, the highest version, then the group, R_ZIG_TOOLCHAIN_ENV, R_ZIG_EXTRA_ENV" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const t = triple(c);
    // none anywhere
    try testing.expectEqual(null, try headersDir(c));
    // R_ZIG_EXTRA_ENV's
    try testutil.libstdcxx(&f, "extra", "15.3.0");
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("extra"));
    try testing.expectEqualStrings(f.fmt("{s}/lib/gcc/{s}/15.3.0", .{ f.path("extra"), t }), (try headersDir(c)).?);
    // R_ZIG_TOOLCHAIN_ENV's (L6), before it
    try testutil.libstdcxx(&f, "tcenv", "15.2.0");
    try f.env.put("R_ZIG_TOOLCHAIN_ENV", f.path("tcenv"));
    try testing.expectEqualStrings(f.fmt("{s}/lib/gcc/{s}/15.2.0", .{ f.path("tcenv"), t }), (try headersDir(c)).?);
    // the compilers group's, in rzig's directory, before both
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cxx");
    try testutil.libstdcxx(&f, "tree/lib/R/bin/toolchain/libstdcxx", "15.3.0");
    try testing.expectEqualStrings(f.fmt("{s}/lib/gcc/{s}/15.3.0", .{ f.path("tree/lib/R/bin/toolchain/libstdcxx"), t }), (try headersDir(c)).?);
    // R's own, before both; the highest version with include/c++, numerically
    try testutil.libstdcxx(&f, "tree", "9.5.0");
    try testutil.libstdcxx(&f, "tree", "15.3.0");
    try f.tmp.dir.createDirPath(testing.io, f.fmt("tree/lib/gcc/{s}/16.2.0", .{t}));
    try f.tmp.dir.createDirPath(testing.io, f.fmt("tree/lib/gcc/{s}/x", .{t}));
    try testing.expectEqualStrings(f.fmt("{s}/lib/gcc/{s}/15.3.0", .{ f.path("tree"), t }), (try headersDir(c)).?);
    try testing.expect(versionLess("9.5.0", "15.3.0"));
    try testing.expect(!versionLess("15.3.0", "15.3"));
    try testing.expect(versionLess("15.3", "15.3.1"));
}

test "a C++ command: zig-cxx, or -x c++; an input, or standard input" {
    try testing.expect(isCxx(true, &.{"-c"}));
    try testing.expect(!isCxx(false, &.{ "-c", "a.c" }));
    try testing.expect(isCxx(false, &.{ "-x", "c++", "-c", "a.c" }));
    try testing.expect(isCxx(false, &.{ "-xc++", "-c", "a.c" }));
    try testing.expect(isCxx(false, &.{ "-x", "c++-header", "a.h" }));
    try testing.expect(!isCxx(false, &.{ "-x", "c", "a.c" }));
    try testing.expect(!isCxx(false, &.{"-x"}));
    try testing.expect(hasInput(&.{ "-c", "a.cpp" }));
    try testing.expect(hasInput(&.{ "-E", "-x", "c++", "-" }));
    try testing.expect(!hasInput(&.{"--version"}));
    try testing.expect(!hasInput(&.{"-dumpversion"}));
    try testing.expect(!hasInput(&.{"-print-file-name=libstdc++.so"}));
    try testing.expect(!hasInput(&.{ "-o", "x" }));
}

test "rewriteLibs: -lstdc++ with libgcc_s once, -l stdc++, -lgcc_s, -lstdc++fs, -static-libstdc++" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    const rt: Runtime = .{ .stdcxx = "/e/lib/libstdc++.so.6", .gcc_s = "/e/lib/libgcc_s.so.1" };
    // a C link of C++ objects (the reviewer's abort): libgcc_s comes with it
    try expectArgs(&.{ "-o", "m", "m.o", "t.o", rt.stdcxx, rt.gcc_s }, try rewriteLibs(c, &.{ "-o", "m", "m.o", "t.o", "-lstdc++" }, rt));
    // once, whatever the order and spelling
    try expectArgs(&.{ "-o", "m", "m.o", rt.gcc_s, rt.stdcxx, "-lm" }, try rewriteLibs(c, &.{ "-o", "m", "m.o", "-lgcc_s", "-l:libstdc++.so.6", "-lm", "-l:libgcc_s.so.1" }, rt));
    try expectArgs(&.{ "-o", "m", rt.stdcxx, rt.gcc_s, rt.stdcxx }, try rewriteLibs(c, &.{ "-o", "m", "-lstdc++", "-l:libstdc++.so" }, rt));
    // the two-argument form (zig would map `-l stdc++` to its libc++);
    // other names keep both words
    try expectArgs(&.{ "-o", "m", "m.o", rt.stdcxx, rt.gcc_s, "-l", "m" }, try rewriteLibs(c, &.{ "-o", "m", "m.o", "-l", "stdc++", "-l", "gcc_s", "-l", "m" }, rt));
    try expectArgs(&.{ "-o", "m", "-l" }, try rewriteLibs(c, &.{ "-o", "m", "-l" }, rt));
    try expectArgs(&.{ "-o", "m", "-l", "stdc++" }, try rewriteLibs(c, &.{ "-o", "m", "-l", "stdc++" }, null));
    // Rust's std passes -lgcc_s alone
    try expectArgs(&.{ "-shared", "-o", "x.so", "a.o", rt.gcc_s }, try rewriteLibs(c, &.{ "-shared", "-o", "x.so", "a.o", "-lgcc_s" }, rt));
    // -static-libstdc++ goes (zig ignores it); a note under RZIG_TRACE only
    try expectArgs(&.{ "-o", "m", "m.o" }, try rewriteLibs(c, &.{ "-static-libstdc++", "-o", "m", "m.o" }, rt));
    try testing.expectEqualStrings("", f.takeWarnings());
    try f.env.put("RZIG_TRACE", "1");
    // -lstdc++fs: no headers, so no archive: dropped, with a note
    try expectArgs(&.{ "-o", "m", "m.o" }, try rewriteLibs(c, &.{ "-static-libstdc++", "-o", "m", "m.o", "-lstdc++fs" }, rt));
    const w = f.takeWarnings();
    try testing.expect(mem.find(u8, w, "-static-libstdc++ dropped") != null);
    try testing.expect(mem.find(u8, w, "-lstdc++fs dropped") != null);
    // gcc's archive beside the headers, when there is one
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cc");
    try testutil.libstdcxx(&f, "tree", "15.3.0");
    const g = f.fmt("{s}/lib/gcc/{s}/15.3.0", .{ f.path("tree"), triple(c) });
    try f.touch(f.fmt("tree/lib/gcc/{s}/15.3.0/libstdc++exp.a", .{triple(c)}));
    try expectArgs(&.{ "-o", "m", "m.o", f.fmt("{s}/libstdc++exp.a", .{g}) }, try rewriteLibs(c, &.{ "-o", "m", "m.o", "-lstdc++exp", "-lstdc++fs" }, rt));
    // compiles and a missing runtime: unchanged
    const compile: Args = &.{ "-c", "a.cpp", "-lstdc++" };
    try expectArgs(compile, try rewriteLibs(c, compile, rt));
    try expectArgs(&.{ "-o", "m", "-lstdc++", "-lgcc_s" }, try rewriteLibs(c, &.{ "-o", "m", "-lstdc++", "-lgcc_s" }, null));
}

test "flags: headers and runtime, the caller's opt-outs, no input, a missing group" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain/libstdcxx-shim");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cxx");
    // no headers: nothing for a version query; the compilers' text for a compile
    try expectArgs(&.{}, (try flags(c, &.{"--version"}, null)).post);
    try expectArgs(&.{}, (try flags(c, &.{"-dumpversion"}, null)).pre);
    try testing.expectError(error.NoLibstdcxx, flags(c, &.{ "-c", "a.cpp" }, null));
    const w = f.takeWarnings();
    try testing.expect(mem.startsWith(u8, w, "rzig-test: " ++ no_headers ++ "\nCompiling needs the r-zig compilers"));
    try testutil.libstdcxx(&f, "tree", "15.3.0");
    const g = f.fmt("{s}/lib/gcc/{s}/15.3.0", .{ f.path("tree"), triple(c) });
    const shim = f.fmt("-I{s}/libstdcxx-shim", .{f.path("tree/lib/R/bin/toolchain")});
    const inc: Args = &.{ shim, f.fmt("-I{s}/include/c++", .{g}), f.fmt("-I{s}/include/c++/{s}", .{ g, triple(c) }), f.fmt("-I{s}/include/c++/backward", .{g}), "-D_GLIBCXX_SYSHDR" };
    const compile = try flags(c, &.{ "-c", "a.cpp" }, null);
    try expectArgs(&.{"-nostdinc++"}, compile.pre);
    try expectArgs(inc, compile.post);
    // standard input counts as an input
    try expectArgs(inc, (try flags(c, &.{ "-E", "-x", "c++", "-" }, null)).post);
    // a link: the runtime too, or a stop without one
    try testing.expectError(error.NoLibstdcxx, flags(c, &.{ "-shared", "-o", "x.so", "a.o" }, null));
    try testing.expect(mem.find(u8, f.takeWarnings(), "no libstdc++ runtime") != null);
    const rt: Runtime = .{ .stdcxx = "/e/lib/libstdc++.so.6", .gcc_s = "/e/lib/libgcc_s.so.1" };
    const link = try flags(c, &.{ "-shared", "-o", "x.so", "a.o" }, rt);
    try expectArgs(&.{ "-nostdinc++", "-nostdlib++" }, link.pre);
    try expectArgs(try mem.concat(c.arena, []const u8, &.{ inc, &.{ rt.stdcxx, rt.gcc_s } }), link.post);
    // the caller's own: -nostdinc++ / -nostdinc, -nostdlib++ / -nostdlib / -nodefaultlibs
    const own = try flags(c, &.{ "-nostdinc", "-nodefaultlibs", "-o", "x", "a.cpp" }, rt);
    try expectArgs(&.{}, own.pre);
    try expectArgs(&.{}, own.post);
    const own_libs = try flags(c, &.{ "-nostdlib++", "-o", "x", "a.cpp" }, null);
    try expectArgs(&.{"-nostdinc++"}, own_libs.pre);
    try expectArgs(inc, own_libs.post);
}

test "runtime: the first environment with both files" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.tmp.dir.createDirPath(testing.io, "tree/lib/R/bin/toolchain");
    c.self_exe = f.path("tree/lib/R/bin/toolchain/zig-cxx");
    try testing.expectEqual(null, try runtime(c));
    try f.touch("extra/lib/libstdc++.so.6");
    try f.touch("extra/lib/libgcc_s.so.1");
    try f.env.put("R_ZIG_EXTRA_ENV", f.path("extra"));
    // R's own has libstdc++ alone: not it
    try f.touch("tree/lib/libstdc++.so.6");
    try testing.expectEqualStrings(f.fmt("{s}/lib/libstdc++.so.6", .{f.path("extra")}), (try runtime(c)).?.stdcxx);
    try f.touch("tree/lib/libgcc_s.so.1");
    const r = (try runtime(c)).?;
    try testing.expectEqualStrings(f.fmt("{s}/lib/libstdc++.so.6", .{f.path("tree")}), r.stdcxx);
    try testing.expectEqualStrings(f.fmt("{s}/lib/libgcc_s.so.1", .{f.path("tree")}), r.gcc_s);
}
