//! Linker options zig cc (0.16 and 0.17, conda-forge's and upstream's alike) cannot
//! take, which GNU ld, lld and ld64 do (stress round 1, Z2, Z3, Z8). One
//! rule each, for every spelling: inside -Wl, (as one item, or two:
//! `-Wl,-L,dir`), after -Xlinker (`-Xlinker -L -Xlinker dir`), and for
//! -z and --disable-auto-import also on its own (`-z muldefs`).
//!
//! - -L<dir> and --library-path=<dir>: "error: unsupported linker arg:
//!   -L...". RcppParallel's `-Wl,-Ltbb/build/lib_release`, on every OS.
//!   It becomes the driver's own -L<dir>, in the same place: zig searches
//!   it as the linker would.
//! - -l<name>, -l <name>, --library=<name> and --library <name>:
//!   "error: unsupported linker arg: -lstdc++" (`-Wl,-lstdc++`, `-Xlinker
//!   -lm`; zig 0.17.1, conda-forge's and upstream's, every name;
//!   fix-rzig-quick Q24, L21). It becomes the driver's own -l<name>, in
//!   the same place, so the rules after this one see it as any -l:
//!   libstdcxx.zig's libstdc++ on linux, flang_rt.zig's runtime,
//!   windows.zig's import libraries. ld64's own -lto_library and -lazy-*
//!   options are no -l and stay.
//! - --allow-multiple-definition and -z muldefs: "unsupported linker arg"
//!   (StanHeaders' Makevars.win). Dropped: with nothing defined twice the
//!   link is the same, and a real duplicate now fails loudly instead of
//!   linking one of the two.
//! - --disable-auto-import (and -disable-auto-import): "unsupported
//!   linker arg" (in -Wl, and after -Xlinker; on its own zig cc says
//!   "unknown clang option"), zig 0.17.1, conda-forge's and upstream's
//!   (delta, 2026-11-24); a request from libs-zig-pixi's Windows
//!   builds. Dropped: a safety flag only, which makes a link fail where
//!   it would auto-import data from a DLL; without it lld does what its
//!   MinGW default is, auto-import on, as GNU ld's.
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
                .lib => try out.append(a, try ctx.fmt("-l{s}", .{it.value})),
            }
            i += 2 * it.items - 1;
        } else if (mem.eql(u8, x, "-z") and i + 1 < args.len and mem.eql(u8, args[i + 1], "muldefs")) {
            i += 1;
        } else if (disableAutoImport(x)) {
            continue;
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
            .lib => {
                // in order: zig applies -Wl,'s --whole-archive, -Bstatic
                // and --as-needed to the -l after them, so what came
                // before goes first (`-Wl,--whole-archive,-lfoo,...`)
                try flush(ctx, out, &kept);
                try out.append(a, try ctx.fmt("-l{s}", .{it.value}));
                changed = true;
            },
        }
        j += it.items;
    }
    if (!changed) return out.append(a, x);
    try flush(ctx, out, &kept);
}

/// `kept` as one -Wl, argument, when there is any; emptied.
fn flush(ctx: *Ctx, out: *std.ArrayList([]const u8), kept: *std.ArrayList([]const u8)) !void {
    if (kept.items.len == 0) return;
    try out.append(ctx.arena, try ctx.fmt("-Wl,{s}", .{try mem.join(ctx.arena, ",", kept.items)}));
    kept.clearRetainingCapacity();
}

const Item = struct {
    what: enum { keep, drop, lib_dir, lib },
    /// lib_dir's directory, lib's name
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
    if (mem.eql(u8, x, "-z")) {
        const n = next orelse return .{ .what = .keep };
        return if (mem.eql(u8, n, "muldefs")) .{ .what = .drop, .items = 2 } else .{ .what = .keep };
    }
    if (mem.eql(u8, x, "-l") or mem.eql(u8, x, "--library")) {
        const n = next orelse return .{ .what = .keep };
        if (n.len == 0) return .{ .what = .keep };
        return .{ .what = .lib, .value = n, .items = 2 };
    }
    if (cmdline.flagValue(x, "--library=")) |n| return .{ .what = .lib, .value = n };
    if (cmdline.flagValue(x, "-l")) |n| {
        if (!mem.startsWith(u8, n, "to_") and !mem.startsWith(u8, n, "azy")) return .{ .what = .lib, .value = n };
    }
    if (cmdline.flagValue(x, "-L")) |d| return .{ .what = .lib_dir, .value = d };
    if (cmdline.flagValue(x, "--library-path=")) |d| return .{ .what = .lib_dir, .value = d };
    if (mem.eql(u8, x, "--allow-multiple-definition") or
        mem.eql(u8, x, "-allow-multiple-definition") or
        mem.eql(u8, x, "-zmuldefs") or
        disableAutoImport(x)) return .{ .what = .drop };
    return .{ .what = .keep };
}

fn disableAutoImport(x: []const u8) bool {
    return mem.eql(u8, x, "--disable-auto-import") or mem.eql(u8, x, "-disable-auto-import");
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

test "-l out of -Wl, and -Xlinker, in every spelling (Q24, L21)" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try expectArgs(&.{ "-o", "p.so", "a.o", "-lstdc++", "b.o" }, try rewrite(c, &.{ "-o", "p.so", "a.o", "-Wl,-lstdc++", "b.o" }));
    try expectArgs(&.{ "-lm", "-lz", "-ly", "-lw", "-Wl,-z,now" }, try rewrite(c, &.{"-Wl,-lm,-l,z,--library=y,--library,w,-z,now"}));
    try expectArgs(&.{ "-lm", "-lz", "a.o" }, try rewrite(c, &.{ "-Xlinker", "-lm", "-Xlinker", "-l", "-Xlinker", "z", "a.o" }));
    // the options around it keep their place: zig applies --whole-archive
    // and -Bstatic to the -l after them (measured, zig 0.17.1)
    try expectArgs(&.{ "-Wl,--whole-archive", "-lfoo", "-Wl,--no-whole-archive" }, try rewrite(c, &.{"-Wl,--whole-archive,-lfoo,--no-whole-archive"}));
    try expectArgs(&.{ "-Wl,-Bstatic", "-la", "-lb", "-Wl,-Bdynamic,-rpath,/x" }, try rewrite(c, &.{"-Wl,-Bstatic,-la,-lb,-Bdynamic,-rpath,/x"}));
    // the -Xlinker form too: the archive is linked whole (wave2-rzig/PLAN.md,
    // both zigs 0.17.1)
    try expectArgs(&.{ "-Xlinker", "--whole-archive", "-lfoo", "-Xlinker", "--no-whole-archive" }, try rewrite(c, &.{ "-Xlinker", "--whole-archive", "-Xlinker", "-lfoo", "-Xlinker", "--no-whole-archive" }));
    // ld64's -lto_library and -lazy-l<name>, and no value: kept
    const same: Args = &.{ "-Wl,-lto_library,/x/libLTO.dylib", "-Wl,-lazy-lfoo", "-Wl,-l", "-Wl,-l,", "-Xlinker", "-l" };
    try expectArgs(same, try rewrite(c, same));
}

// zig 0.16 panicked on CMake's `-Xlinker --dependency-file=...` (stress
// round 1, Z3) and rzig dropped it; zig 0.17 links with it and writes the
// file, on every target (feat-zig-017's audit), so it passes through.
test "--dependency-file kept, in every spelling" {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    // CMake's
    const lines = [_]Args{
        &.{ "-shared", "-Xlinker", "--dependency-file=CMakeFiles/t.dir/link.d", "-o", "l.so" },
        &.{ "-Wl,--dependency-file=x.d", "-o", "x" },
        &.{ "-Wl,--dependency-file,x.d,-z,now", "-o", "x" },
        &.{ "-Xlinker", "--dependency-file", "-Xlinker", "x.d", "-o", "x" },
    };
    for (lines) |l| try expectArgs(l, try rewrite(c, l));
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

test "--disable-auto-import dropped, in every spelling" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    try expectArgs(&.{ "-shared", "-o", "p.dll", "a.o" }, try rewrite(c, &.{ "-shared", "-Wl,--disable-auto-import", "-o", "p.dll", "a.o" }));
    try expectArgs(&.{"-Wl,--enable-auto-image-base,-s"}, try rewrite(c, &.{"-Wl,--enable-auto-image-base,-disable-auto-import,-s"}));
    try expectArgs(&.{ "a.o", "-Wl,-s" }, try rewrite(c, &.{ "-Xlinker", "--disable-auto-import", "a.o", "--disable-auto-import", "-disable-auto-import", "-Xlinker", "-disable-auto-import", "-Wl,-s" }));
    // its opposite and the runtime pseudo-relocations are lld's to take
    const others: Args = &.{ "-Wl,--enable-auto-import", "-Xlinker", "--disable-runtime-pseudo-reloc" };
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
