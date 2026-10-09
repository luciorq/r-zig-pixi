//! Linker options zig cc (0.16, conda-forge's and upstream's alike) cannot
//! take, which GNU ld, lld and ld64 do (stress round 1, Z2, Z3, Z8). One
//! rule each, for every spelling: inside -Wl, (as one item, or two:
//! `-Wl,-L,dir`), after -Xlinker (`-Xlinker -L -Xlinker dir`), and for
//! -z also on its own (`-z muldefs`).
//!
//! - -L<dir> and --library-path=<dir>: "error: unsupported linker arg:
//!   -L...". RcppParallel's `-Wl,-Ltbb/build/lib_release`, on every OS.
//!   It becomes the driver's own -L<dir>, in the same place: zig searches
//!   it as the linker would.
//! - --dependency-file=<file>: zig panics ("index out of bounds",
//!   conda-forge's) or crashes (upstream's). CMake (4.4 in round 1) adds
//!   `-Xlinker --dependency-file=...` to every ELF link when the linker it
//!   found lists the option in --help, as lld-zig's ld.lld does (on PATH in
//!   the dev env, through flang-zig): RcppParallel's TBB, Rhdf5lib's
//!   libaec, arrow's bundled zlib. Dropped: the file only tells CMake when
//!   to relink, and CMake builds and rebuilds without it. Which linker
//!   CMake finds then no longer matters.
//! - --allow-multiple-definition and -z muldefs: "unsupported linker arg"
//!   (StanHeaders' Makevars.win). Dropped: with nothing defined twice the
//!   link is the same, and a real duplicate now fails loudly instead of
//!   linking one of the two.
//!
//! The bash shims do the same (toolchain/zig-cc, zig-cxx).
const std = @import("std");
const mem = std.mem;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const Args = cmdline.Args;

/// `args` with the rules above applied.
pub fn rewrite(ctx: *Ctx, args: Args) !Args {
    const a = ctx.arena;
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (mem.startsWith(u8, x, "-Wl,")) {
            try wl(ctx, &out, x);
        } else if (mem.eql(u8, x, "-Xlinker") and i + 1 < args.len) {
            // -Xlinker <option> [-Xlinker <its value>]
            const v: ?[]const u8 = if (i + 3 < args.len and mem.eql(u8, args[i + 2], "-Xlinker")) args[i + 3] else null;
            const it = item(args[i + 1], v);
            switch (it.what) {
                .keep => {
                    try out.appendSlice(a, args[i .. i + 2]);
                    i += 1;
                    continue;
                },
                .drop => {},
                .lib_dir => try out.append(a, try ctx.fmt("-L{s}", .{it.value})),
            }
            i += 2 * it.items - 1;
        } else if (mem.eql(u8, x, "-z") and i + 1 < args.len and mem.eql(u8, args[i + 1], "muldefs")) {
            i += 1;
        } else {
            try out.append(a, x);
        }
    }
    return out.items;
}

/// One -Wl, argument: its -L directories out as -L<dir>, its dropped
/// options gone, the rest kept as one -Wl, (the argument as it was when
/// nothing changed).
fn wl(ctx: *Ctx, out: *std.ArrayList([]const u8), x: []const u8) !void {
    const a = ctx.arena;
    var items: std.ArrayList([]const u8) = .empty;
    var split = mem.splitScalar(u8, x["-Wl,".len..], ',');
    while (split.next()) |w| try items.append(a, w);
    var kept: std.ArrayList([]const u8) = .empty;
    var changed = false;
    var j: usize = 0;
    while (j < items.items.len) {
        const next: ?[]const u8 = if (j + 1 < items.items.len) items.items[j + 1] else null;
        const it = item(items.items[j], next);
        switch (it.what) {
            .keep => try kept.append(a, items.items[j]),
            .drop => changed = true,
            .lib_dir => {
                try out.append(a, try ctx.fmt("-L{s}", .{it.value}));
                changed = true;
            },
        }
        j += it.items;
    }
    if (!changed) return out.append(a, x);
    if (kept.items.len > 0) try out.append(a, try ctx.fmt("-Wl,{s}", .{try mem.join(a, ",", kept.items)}));
}

const Item = struct {
    what: enum { keep, drop, lib_dir },
    /// lib_dir's directory
    value: []const u8 = "",
    /// how many linker items it is: 2 when its value is the next one
    items: usize = 1,
};

/// What becomes of the linker option `x`, `next` the item after it.
fn item(x: []const u8, next: ?[]const u8) Item {
    if (mem.eql(u8, x, "-L") or mem.eql(u8, x, "--library-path")) {
        const d = next orelse return .{ .what = .keep };
        if (d.len == 0) return .{ .what = .keep };
        return .{ .what = .lib_dir, .value = d, .items = 2 };
    }
    if (mem.eql(u8, x, "--dependency-file")) return .{ .what = .drop, .items = if (next != null) 2 else 1 };
    if (mem.eql(u8, x, "-z")) {
        const n = next orelse return .{ .what = .keep };
        return if (mem.eql(u8, n, "muldefs")) .{ .what = .drop, .items = 2 } else .{ .what = .keep };
    }
    if (cmdline.flagValue(x, "-L")) |d| return .{ .what = .lib_dir, .value = d };
    if (cmdline.flagValue(x, "--library-path=")) |d| return .{ .what = .lib_dir, .value = d };
    if (mem.startsWith(u8, x, "--dependency-file=") or
        mem.eql(u8, x, "--allow-multiple-definition") or
        mem.eql(u8, x, "-allow-multiple-definition") or
        mem.eql(u8, x, "-zmuldefs")) return .{ .what = .drop };
    return .{ .what = .keep };
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "-L out of -Wl, and -Xlinker, in every spelling" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // RcppParallel's PKG_LIBS
    try expectArgs(
        &.{ "-o", "p.so", "a.o", "-Ltbb/build/lib_release", "-ltbb", "-Wl,-rpath,$ORIGIN/../lib" },
        try rewrite(c, &.{ "-o", "p.so", "a.o", "-Wl,-Ltbb/build/lib_release", "-ltbb", "-Wl,-rpath,$ORIGIN/../lib" }),
    );
    // among other linker options, its two-item form, --library-path
    try expectArgs(&.{ "-L/a", "-L/b", "-L/c", "-L/d", "-Wl,-z,now" }, try rewrite(c, &.{"-Wl,-L/a,-z,now,-L,/b,--library-path=/c,--library-path,/d"}));
    try expectArgs(&.{ "-L/a", "-L/b", "-L/c", "-lx" }, try rewrite(c, &.{ "-Xlinker", "-L/a", "-Xlinker", "-L", "-Xlinker", "/b", "-Xlinker", "--library-path=/c", "-lx" }));
    // no value: kept as it was, for zig to say so
    const dangling: Args = &.{ "-Wl,-L", "-Wl,-L,", "-Wl,--library-path=", "-Xlinker", "-L" };
    try expectArgs(dangling, try rewrite(c, dangling));
}

test "--dependency-file dropped, in every spelling" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // CMake's
    try expectArgs(&.{ "-shared", "-o", "l.so" }, try rewrite(c, &.{ "-shared", "-Xlinker", "--dependency-file=CMakeFiles/t.dir/link.d", "-o", "l.so" }));
    try expectArgs(&.{ "-o", "x" }, try rewrite(c, &.{ "-Wl,--dependency-file=x.d", "-o", "x" }));
    try expectArgs(&.{ "-Wl,-z,now", "-o", "x" }, try rewrite(c, &.{ "-Wl,--dependency-file,x.d,-z,now", "-o", "x" }));
    try expectArgs(&.{ "-o", "x" }, try rewrite(c, &.{ "-Xlinker", "--dependency-file", "-Xlinker", "x.d", "-o", "x" }));
    try expectArgs(&.{"a.o"}, try rewrite(c, &.{ "a.o", "-Wl,--dependency-file" }));
    // clang's own -dependency-file (a compile's) is no linker option
    try expectArgs(&.{ "-dependency-file", "a.d", "-c", "a.c" }, try rewrite(c, &.{ "-dependency-file", "a.d", "-c", "a.c" }));
}

test "--allow-multiple-definition and -z muldefs dropped, in every spelling" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    // StanHeaders' Makevars.win
    try expectArgs(&.{ "-shared", "-o", "p.dll", "a.o" }, try rewrite(c, &.{ "-shared", "-Wl,--allow-multiple-definition", "-o", "p.dll", "a.o" }));
    try expectArgs(&.{"-Wl,-z,now"}, try rewrite(c, &.{"-Wl,-allow-multiple-definition,-z,muldefs,-z,now,-zmuldefs"}));
    try expectArgs(&.{"a.o"}, try rewrite(c, &.{ "-Xlinker", "--allow-multiple-definition", "-Xlinker", "-z", "-Xlinker", "muldefs", "-z", "muldefs", "a.o", "-Xlinker", "-zmuldefs" }));
    // other -z keywords stay, in each form
    const others: Args = &.{ "-z", "now", "-Wl,-z,relro", "-Xlinker", "-z", "-Xlinker", "defs", "-Wl,-z", "-z" };
    try expectArgs(others, try rewrite(c, others));
}

test "everything else is left alone" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const same: Args = &.{ "-Wl,--version-script=v.def", "-Xlinker", "-rpath", "-Xlinker", "/x", "-L/c", "-L", "/d", "-Wl,", "-Wl,a,,b,", "-Xlinker" };
    try expectArgs(same, try rewrite(&f.ctx, same));
    // a changed -Wl, keeps its empty items
    try expectArgs(&.{ "-L/a", "-Wl,x,,y" }, try rewrite(&f.ctx, &.{"-Wl,x,,-L/a,y"}));
}
