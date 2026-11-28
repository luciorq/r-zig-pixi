//! The distribution's libraries on linux, opt-in (backlog M-29; the
//! design is wave2-compat PLAN.md finding 7, F-M13): R_ZIG_SYSTEM_LIBS=1
//! lets a package compile and link against what `apt install
//! libgdal-dev` or `dnf install gdal-devel` put in /usr, as GNU R does
//! with the system's gcc. Unset (the default), rzig searches no host
//! directory, as before: a package compiles against R's environments only
//! (environment.zig), and the same command builds the same package on any
//! machine.
//!
//! zig compiles against its own glibc headers for R's glibc floor
//! (target.zig), never /usr/include. Two things kept distro libraries out
//! (wave2-compat finding 7, Ubuntu 22.04 and 24.04):
//!
//! a) no search path: /usr/include and /usr/lib are not zig's. With the
//!    variable set, every command gets the host's include roots as
//!    -idirafter, after zig's own libc headers and every -I and -isystem,
//!    so a header the distribution adds (curl/curl.h, proj.h, gdal.h's
//!    neighbours) is found and a libc header is still zig's; and a link
//!    gets the host's library directories as its last -L, after the
//!    environments', so -lgdal finds the distribution's libgdal.so and
//!    an -l an environment has still binds the environment's.
//! b) a distribution's .pc files name the include roots themselves
//!    (libcurl.pc: -I/usr/include/x86_64-linux-gnu, which proj.pc pulls
//!    in), and as -I they come before zig's glibc headers: glibc 2.39's
//!    bits/types/time_t.h then met zig's 2.17 headers ("unknown type name
//!    '__time64_t'"). With the variable set, the caller's -I or -isystem
//!    of /usr/include or /usr/include/<multiarch> becomes -idirafter of
//!    the same directory. Without it they stay, as a package asked.
//!
//! c) the distribution's libraries need its glibc: libsqlite3.so on
//!    Ubuntu 24.04 asks for pthread_join@GLIBC_2.34, which zig's glibc
//!    2.17 stubs do not have, and lld stops an executable's link (a
//!    configure test: terra's PROJ check, "undefined reference:
//!    pthread_join@GLIBC_2.34 ... disallowed by --no-allow-shlib-undefined").
//!    A shared library's link allows that already; with the variable set,
//!    an executable's does too (-Wl,--allow-shlib-undefined): the
//!    program runs on the host whose glibc has them, as the libraries
//!    themselves do. R's target and its glibc floor do not change: the
//!    package's own code still asks for no symbol newer than the floor.
//!
//! The libstdc++ ABI needs nothing: C++ compiles with libstdc++'s headers
//! and links its runtime (libstdcxx.zig), the distribution's C++ API
//! included (wave2-compat finding 8: a CPLString from libgdal, a thrown
//! and caught exception). Linux only; elsewhere the variable is ignored,
//! silently: a warning would come on every compile of every object.
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const Args = cmdline.Args;

pub const variable = "R_ZIG_SYSTEM_LIBS";

/// R_ZIG_SYSTEM_LIBS is on (1, true or yes: Ctx.on, onoff.zig) on
/// linux; ignored elsewhere.
pub fn enabled(ctx: *Ctx) bool {
    if (ctx.os != .linux) return false;
    return ctx.on(variable);
}

/// Debian's multiarch directory name for R's architecture; Fedora and
/// RHEL have none (lib64), which `roots` covers.
fn multiarch(ctx: *const Ctx) []const u8 {
    return switch (ctx.arch) {
        .x86_64 => "x86_64-linux-gnu",
        .aarch64 => "aarch64-linux-gnu",
    };
}

/// The host's include roots, the multiarch one first, as gcc searches.
fn includeRoots(ctx: *const Ctx) ![2][]const u8 {
    return .{ try ctx.fmt("/usr/include/{s}", .{multiarch(ctx)}), "/usr/include" };
}

/// An include root of the host: /usr/include or /usr/include/<multiarch>,
/// a trailing `/` allowed.
fn isRoot(ctx: *const Ctx, dir: []const u8) !bool {
    const d = mem.trimEnd(u8, dir, "/");
    for (try includeRoots(ctx)) |r| if (mem.eql(u8, d, r)) return true;
    return false;
}

/// b): the caller's -I<root>, -I <root>, -isystem<root> and -isystem <root>
/// become -idirafter <root>. Other arguments untouched.
pub fn rewrite(ctx: *Ctx, args: Args) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    next: while (i < args.len) : (i += 1) {
        const x = args[i];
        for ([_][]const u8{ "-I", "-isystem" }) |flag| {
            if (mem.eql(u8, x, flag) and i + 1 < args.len and try isRoot(ctx, args[i + 1])) {
                try out.appendSlice(ctx.arena, &.{ "-idirafter", args[i + 1] });
                i += 1;
                continue :next;
            }
            if (mem.startsWith(u8, x, flag) and x.len > flag.len and try isRoot(ctx, x[flag.len..])) {
                try out.appendSlice(ctx.arena, &.{ "-idirafter", x[flag.len..] });
                continue :next;
            }
        }
        try out.append(ctx.arena, x);
    }
    return out.items;
}

/// a): last on every command: the host's include roots as -idirafter,
/// and on a link its library directories, Debian's multiarch ones, then
/// Fedora's lib64, then lib (those that exist); c): and
/// --allow-shlib-undefined.
pub fn last(ctx: *Ctx, link: bool) !Args {
    var out: std.ArrayList([]const u8) = .empty;
    for (try includeRoots(ctx)) |r| if (ctx.isDir(r)) try out.appendSlice(ctx.arena, &.{ "-idirafter", r });
    if (link) {
        const m = multiarch(ctx);
        for ([_][]const u8{
            try ctx.fmt("/usr/lib/{s}", .{m}),
            try ctx.fmt("/lib/{s}", .{m}),
            "/usr/lib64",
            "/usr/lib",
        }) |d| if (ctx.isDir(d)) try out.append(ctx.arena, try ctx.fmt("-L{s}", .{d}));
        try out.append(ctx.arena, "-Wl,--allow-shlib-undefined");
    }
    return out.items;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "enabled: linux, 1, true or yes (onoff.zig); ignored elsewhere, without a warning" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    try testing.expect(!enabled(&f.ctx));
    for ([_][]const u8{ "", "0", "false", "NO" }) |v| {
        try f.env.put(variable, v);
        try testing.expect(!enabled(&f.ctx));
    }
    for ([_][]const u8{ "1", "true", "Yes" }) |v| {
        try f.env.put(variable, v);
        try testing.expect(enabled(&f.ctx));
    }
    try testing.expectEqualStrings("", f.takeWarnings());
    f.ctx.os = .macos;
    try testing.expect(!enabled(&f.ctx));
    try testing.expectEqualStrings("", f.takeWarnings());
}

test "Ctx.on: the on/off rule; any other value is off with one warning naming the variable" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const name = "RZIG_TEST_SWITCH";
    try testing.expect(!f.ctx.on(name));
    for ([_][]const u8{ "1", "true", "TRUE", "yes", "YES" }) |v| {
        try f.env.put(name, v);
        try testing.expect(f.ctx.on(name));
    }
    for ([_][]const u8{ "", "0", "false", "False", "no" }) |v| {
        try f.env.put(name, v);
        try testing.expect(!f.ctx.on(name));
    }
    try testing.expectEqualStrings("", f.takeWarnings());
    try f.env.put(name, "maybe");
    try testing.expect(!f.ctx.on(name));
    try testing.expect(!f.ctx.on(name));
    try testing.expectEqualStrings("rzig-test: RZIG_TEST_SWITCH='maybe' is neither on (1, true, yes) nor off (0, false, no, empty): taken as off\n", f.takeWarnings());
    // R_ZIG_SYSTEM_LIBS through the same rule, on linux
    try f.env.put(variable, "on");
    try testing.expect(!enabled(&f.ctx));
    try testing.expectEqualStrings("rzig-test: R_ZIG_SYSTEM_LIBS='on' is neither on (1, true, yes) nor off (0, false, no, empty): taken as off\n", f.takeWarnings());
}

test "rewrite: the host's include roots become -idirafter, every spelling; other -I kept" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    f.ctx.arch = .x86_64;
    try expectArgs(
        &.{ "-idirafter", "/usr/include/x86_64-linux-gnu", "-I/usr/include/gdal", "-idirafter", "/usr/include", "-idirafter", "/usr/include/", "-idirafter", "/usr/include/x86_64-linux-gnu", "-I/usr/local/include", "-I/usr/include/aarch64-linux-gnu", "-c", "a.c" },
        try rewrite(&f.ctx, &.{ "-I/usr/include/x86_64-linux-gnu", "-I/usr/include/gdal", "-I", "/usr/include", "-isystem/usr/include/", "-isystem", "/usr/include/x86_64-linux-gnu", "-I/usr/local/include", "-I/usr/include/aarch64-linux-gnu", "-c", "a.c" }),
    );
    // a trailing -I with no directory: kept as it is
    try expectArgs(&.{ "a.c", "-I" }, try rewrite(&f.ctx, &.{ "a.c", "-I" }));
    f.ctx.arch = .aarch64;
    try expectArgs(&.{ "-idirafter", "/usr/include/aarch64-linux-gnu" }, try rewrite(&f.ctx, &.{"-I/usr/include/aarch64-linux-gnu"}));
}

test "last: include roots on every command (those that exist), -L and --allow-shlib-undefined on links only" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    // the host's directories: what exists here decides, so only the shape
    const compile = try last(&f.ctx, false);
    try testing.expect(compile.len % 2 == 0);
    var i: usize = 0;
    while (i < compile.len) : (i += 2) {
        try testing.expectEqualStrings("-idirafter", compile[i]);
        try testing.expect(mem.startsWith(u8, compile[i + 1], "/usr/include"));
    }
    const link = try last(&f.ctx, true);
    try testing.expectEqualStrings("-Wl,--allow-shlib-undefined", link[link.len - 1]);
    try expectArgs(compile, link[0..compile.len]);
    for (link[compile.len .. link.len - 1]) |x| try testing.expect(mem.startsWith(u8, x, "-L/"));
}

test "argv: R_ZIG_SYSTEM_LIBS on linux rewrites the caller's roots and appends the host's last" {
    const compiler = @import("compiler.zig");
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const off = try compiler.argv(&f.ctx, .c, &.{ "-I/usr/include/gdal", "-I/usr/include", "-c", "a.c" });
    for (off) |x| try testing.expect(!mem.eql(u8, x, "-idirafter"));
    try f.env.put(variable, "1");
    const on = try compiler.argv(&f.ctx, .c, &.{ "-I/usr/include/gdal", "-I/usr/include", "-c", "a.c" });
    const tail = try last(&f.ctx, false);
    try expectArgs(&.{ "-I/usr/include/gdal", "-idirafter", "/usr/include", "-c", "a.c" }, on[on.len - tail.len - 5 .. on.len - tail.len]);
    try expectArgs(tail, on[on.len - tail.len ..]);
}
