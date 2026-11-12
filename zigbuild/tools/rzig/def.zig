//! `rzig def -o <pkg>.def <objects>`: the module-definition file
//! winshlib.mk builds with `nm | sed -n 's/^.* [BCDRT] / /p' $(NM_FILTER)`
//! for a package DLL, from the objects' COFF symbol tables (binutils.zig's
//! reader, below). The make path's exports exactly, without nm and sed; lld's
//! auto-export (`--export-all-symbols`) is not the same set (design
//! record, step 4).
//!
//! nm's [BCDRT]: a global symbol defined in a code, data or bss section, or
//! a common. Not undefined (U), not weak (w: a WEAK_EXTERNAL), not a
//! local (lowercase), not a section or debug symbol. Then NM_FILTER, as
//! CRAN's R has it (src/gnuwin32/MkRules.rules' default, which
//! fixed/Makefile writes into the installed Makeconf, and build.zig into
//! this tree's Makeconf.win): `sed -e '/[.]refptr[.]/d' -e
//! '/[.]weak[.]/d'`, so no name containing `.refptr.` or `.weak.`: the
//! compiler's own globals, the `.refptr.<name>` stubs (EXTERNAL, in their
//! own .rdata COMDAT; nm: R) and a weak function's
//! `.weak.<name>.default.<other>` alias (EXTERNAL in .text; nm: T). Both
//! paths then export what CRAN's DLLs export (records-REC-3, menu 4 of
//! the PR #25 review: until then this tree's Makeconf.win left NM_FILTER
//! empty and rzig def kept them, to match it; cli exported 195 names so on
//! kappa, 2026-10-12, and 185 without them in M5).
//!
//! The objects are read by binutils.zig's COFF reader, the one rzig's nm
//! uses for the make path, so both read a bigobj object (the header LLVM
//! writes for more than 65,279 sections; feat-tier1-engine K3), as GNU nm
//! did.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const response = @import("response.zig");
const binutils = @import("binutils.zig");

pub const Error = error{ BadObject, OutOfMemory };

/// NM_FILTER's two seds: a name with `.refptr.` or `.weak.` anywhere.
fn filtered(name: []const u8) bool {
    return mem.find(u8, name, ".refptr.") != null or mem.find(u8, name, ".weak.") != null;
}

/// The exported names of one COFF object (a regular or a bigobj one), in
/// symbol-table order.
pub fn exports(a: mem.Allocator, data: []const u8, out: *std.ArrayList([]const u8)) Error!void {
    if (binutils.kindOf(data) != .object) return error.BadObject; // an image, an archive, ...
    const c = binutils.Coff.parse(a, data) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.BadObject,
    };
    const recs = binutils.records(a, c) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.BadObject,
    };
    // section flags: IMAGE_SCN_CNT_{CODE,INITIALIZED_DATA,UNINITIALIZED_DATA},
    // and LNK_INFO, LNK_REMOVE, MEM_DISCARDABLE (.drectve, debug)
    const contents: u32 = 0x20 | 0x40 | 0x80;
    const not_linked: u32 = 0x200 | 0x800 | 0x02000000;
    for (recs) |r| {
        if (r.class != 2) continue; // IMAGE_SYM_CLASS_EXTERNAL
        if (r.section == 0) {
            if (r.value == 0) continue; // undefined
            // a common (nm: C)
        } else if (r.section == binutils.sec_absolute or r.section == binutils.sec_debug) {
            continue;
        } else {
            if (r.section > c.sections.len) return error.BadObject;
            const fl = c.sections[r.section - 1].flags;
            if (fl & contents == 0 or fl & not_linked != 0) continue;
        }
        if (r.name.len == 0 or filtered(r.name)) continue;
        var seen = false;
        for (out.items) |x| if (mem.eql(u8, x, r.name)) {
            seen = true;
            break;
        };
        if (!seen) try out.append(a, try a.dupe(u8, r.name));
    }
}

/// The .def text for these objects.
pub fn text(a: mem.Allocator, objects: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "EXPORTS\n");
    for (objects) |o| try out.print(a, "{s}\n", .{o});
    return out.items;
}

/// `rzig def -o out.def a.o b.o ...`: 0, or 1 with the reason on stderr.
/// An `@file` stands for the objects in it (response.zig): rzig build's
/// links name theirs so, `@<root>/objects.rsp`. tier1.zig calls `run` in
/// its own process, with the objects' paths.
pub fn run(ctx: *Ctx, all: []const []const u8) u8 {
    const args = response.expand(ctx, all) catch return 1;
    var out_path: ?[]const u8 = null;
    var objs: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "-o")) {
            if (i + 1 >= args.len) {
                ctx.warn("def: -o needs a file", .{});
                return 2;
            }
            out_path = args[i + 1];
            i += 1;
        } else objs.append(ctx.arena, args[i]) catch return 1;
    }
    const out = out_path orelse {
        ctx.warn("usage: rzig def -o <file>.def <object>|@<file>...", .{});
        return 2;
    };
    var names: std.ArrayList([]const u8) = .empty;
    for (objs.items) |o| {
        const data = Io.Dir.cwd().readFileAlloc(ctx.io, o, ctx.arena, .limited(256 * 1024 * 1024)) catch |err| {
            ctx.warn("def: cannot read {s}: {t}", .{ o, err });
            return 1;
        };
        exports(ctx.arena, data, &names) catch |err| {
            ctx.warn("def: {s}: {t}", .{ o, err });
            return 1;
        };
    }
    const t = text(ctx.arena, names.items) catch return 1;
    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = out, .data = t }) catch |err| {
        ctx.warn("def: cannot write {s}: {t}", .{ out, err });
        return 1;
    };
    return 0;
}

const testing = std.testing;
const testutil = @import("testutil.zig");
const coff = std.coff;

// testdata/win-syms.c compiled with `zig cc -target x86_64-windows-gnu -O2 -c`
const win_syms = @embedFile("testdata/win-syms.o");

test "exports: nm's [BCDRT] set, then CRAN's NM_FILTER" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var names: std.ArrayList([]const u8) = .empty;
    try exports(arena.allocator(), win_syms, &names);
    // nm: B exported_bss, D exported_data, T exported_fn, R exported_rodata,
    // T uses_locals; not W weak_fn, U strlen, U imported_var, the locals;
    // and not what NM_FILTER drops, R .refptr.imported_var and
    // T .weak.weak_fn.default.exported_fn (records-REC-3, menu 4)
    const expected = [_][]const u8{ "exported_bss", "exported_data", "exported_fn", "exported_rodata", "uses_locals" };
    try testing.expectEqual(expected.len, names.items.len);
    for (expected) |e| {
        var found = false;
        for (names.items) |n| if (mem.eql(u8, n, e)) {
            found = true;
        };
        if (!found) {
            std.debug.print("missing {s}\n", .{e});
            return error.TestExpectedEqual;
        }
    }
    // the same object twice adds nothing (COMDAT duplicates across objects)
    try exports(arena.allocator(), win_syms, &names);
    try testing.expectEqual(expected.len, names.items.len);
    try testing.expectEqualStrings("EXPORTS\na\nb\n", try text(arena.allocator(), &.{ "a", "b" }));
    try testing.expectError(error.BadObject, exports(arena.allocator(), "not an object", &names));
    // the seds match anywhere in the name, not only at its start
    for ([_][]const u8{ ".refptr.x", "a.refptr.b", ".weak.f.default.g", "x.weak.y" }) |n| try testing.expect(filtered(n));
    for ([_][]const u8{ "refptr", "x.weak", "weak.x", "a_refptr_b", "R_init_pkg" }) |n| try testing.expect(!filtered(n));
}

test "exports: symbols in section 1640 and up to 65,279, the most a COFF object has (K3)" {
    // mlpack's dbscan.o has 2,791 sections, and a symbol in section 1640,
    // whose header is at 20 + 1639 * 40 = 65,580: def.zig computed that in
    // u16 and panicked (kappa, 2026-10-30). An object of n code sections,
    // no data, and one EXTERNAL symbol in each of three of them.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = 65_279;
    const syms = [_]struct { name: []const u8, section: u16 }{ .{ .name = "first", .section = 1 }, .{ .name = "s1640", .section = 1640 }, .{ .name = "last", .section = n } };
    const symtab_off = 20 + n * @sizeOf(coff.SectionHeader);
    const data = try a.alloc(u8, symtab_off + syms.len * coff.Symbol.sizeOf() + 4);
    @memset(data, 0);
    mem.writeInt(u16, data[0..2], 0x8664, .little); // x86_64
    mem.writeInt(u16, data[2..4], n, .little);
    mem.writeInt(u32, data[8..12], symtab_off, .little);
    mem.writeInt(u32, data[12..16], syms.len, .little);
    for (0..n) |s| mem.writeInt(u32, data[20 + s * @sizeOf(coff.SectionHeader) + 36 ..][0..4], 0x60000020, .little); // CNT_CODE, MEM_EXECUTE, MEM_READ
    for (syms, 0..) |s, i| {
        const r = data[symtab_off + i * coff.Symbol.sizeOf() ..][0..18];
        @memcpy(r[0..s.name.len], s.name);
        mem.writeInt(u16, r[12..14], s.section, .little);
        r[16] = @backingInt(coff.StorageClass.EXTERNAL);
    }
    mem.writeInt(u32, data[data.len - 4 ..][0..4], 4, .little); // an empty string table
    var names: std.ArrayList([]const u8) = .empty;
    try exports(a, data, &names);
    try testing.expectEqual(syms.len, names.items.len);
    for (syms, names.items) |s, name| try testing.expectEqualStrings(s.name, name);
}

test "exports: a symbol with 255 aux records, the most its u8 count holds (K3)" {
    // def.zig added 1 + number_of_aux_symbols in u8, which overflowed at
    // 255 (review of K3, 2026-10-31). One code section, one EXTERNAL
    // symbol in it, then its 255 aux records.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const naux = 255;
    const symtab_off = 20 + @sizeOf(coff.SectionHeader);
    const data = try a.alloc(u8, symtab_off + (1 + naux) * coff.Symbol.sizeOf() + 4);
    @memset(data, 0);
    mem.writeInt(u16, data[0..2], 0x8664, .little); // x86_64
    mem.writeInt(u16, data[2..4], 1, .little);
    mem.writeInt(u32, data[8..12], symtab_off, .little);
    mem.writeInt(u32, data[12..16], 1 + naux, .little);
    mem.writeInt(u32, data[20 + 36 ..][0..4], 0x60000020, .little); // CNT_CODE, MEM_EXECUTE, MEM_READ
    const r = data[symtab_off..][0..18];
    @memcpy(r[0..2], "fn");
    mem.writeInt(u16, r[12..14], 1, .little);
    r[16] = @backingInt(coff.StorageClass.EXTERNAL);
    r[17] = naux;
    mem.writeInt(u32, data[data.len - 4 ..][0..4], 4, .little); // an empty string table
    var names: std.ArrayList([]const u8) = .empty;
    try exports(a, data, &names);
    try testing.expectEqual(1, names.items.len);
    try testing.expectEqualStrings("fn", names.items[0]);
}

test "exports: a bigobj object, symbols in sections past 65,535 (binutils.bigobjFixture)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const data = try binutils.bigobjFixture(a, 0x8664);
    var names: std.ArrayList([]const u8) = .empty;
    try exports(a, data, &names);
    // not the undefined `undef`, the weak `weak_fn`, nor `local_fn`; the
    // last one's name from the string table
    const want = [_][]const u8{ "first", "past_u16", "last", "long_name_in_the_string_table" };
    try testing.expectEqual(want.len, names.items.len);
    for (want, names.items) |w, n| try testing.expectEqualStrings(w, n);
    // a short import object (version 0) is no object
    var imp: [24]u8 = @splat(0);
    mem.writeInt(u16, imp[2..4], 0xffff, .little);
    try testing.expectError(error.BadObject, exports(a, &imp, &names));
}

test "run: the objects from a response file (rzig build's objects.rsp), as on the command line" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const c = &f.ctx;
    try f.write("sp ace/ção.o", win_syms, .default_file);
    try f.write("b.o", win_syms, .default_file);
    try f.write("objects.rsp", f.fmt("\"{s}\"\r\n\"{s}\"\r\n", .{ f.path("sp ace/ção.o"), f.path("b.o") }), .default_file);
    try testing.expectEqual(0, run(c, &.{ "-o", f.path("argv.def"), f.path("sp ace/ção.o"), f.path("b.o") }));
    try testing.expectEqual(0, run(c, &.{ "-o", f.path("rsp.def"), f.fmt("@{s}", .{f.path("objects.rsp")}) }));
    const want = try f.tmp.dir.readFileAlloc(testing.io, "argv.def", c.arena, .limited(4096));
    try testing.expect(std.mem.startsWith(u8, want, "EXPORTS\n") and std.mem.indexOf(u8, want, "\nexported_fn\n") != null);
    try testing.expectEqualStrings(want, try f.tmp.dir.readFileAlloc(testing.io, "rsp.def", c.arena, .limited(4096)));
    // a missing response file: kept as a name, which cannot be read
    try testing.expectEqual(1, run(c, &.{ "-o", f.path("x.def"), f.fmt("@{s}", .{f.path("nowhere.rsp")}) }));
    try testing.expect(std.mem.indexOf(u8, f.takeWarnings(), "def: cannot read @") != null);
}
