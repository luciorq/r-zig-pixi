//! `rzig def -o <pkg>.def <objects>`: the module-definition file
//! winshlib.mk builds with `nm | sed -n 's/^.* [BCDRT] / /p'` for a
//! package DLL, from the objects' COFF symbol tables (std.coff's records,
//! read at the object's own offsets: std.coff.Coff reads PE images). The
//! make path's exports exactly, without nm and sed; lld's auto-export
//! (`--export-all-symbols`) is not the same set (design record, step 4).
//!
//! nm's [BCDRT]: a global symbol defined in a code, data or bss section, or
//! a common. Not undefined (U), not weak (w/W), not a local (lowercase),
//! not a section or debug symbol, and not the compiler's own `.refptr.*`
//! and `.weak.*` helpers. Oracle: cli's 185 symbols on kappa (M5,
//! 2026-10-10) are the M1 "make" list (187) without `_CRT_INIT` and
//! `__mingw_module_is_dll`, which that list only had because kappa has no
//! sed: winshlib.mk's tmp.def came out empty and lld auto-exported.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const coff = std.coff;
const Ctx = @import("Ctx.zig");

pub const Error = error{ BadObject, OutOfMemory };

/// The exported names of one COFF object, in symbol-table order.
pub fn exports(a: mem.Allocator, data: []const u8, out: *std.ArrayList([]const u8)) Error!void {
    if (data.len < 20) return error.BadObject;
    const nsections = mem.readInt(u16, data[2..4], .little);
    const symtab_off = mem.readInt(u32, data[8..12], .little);
    const nsyms = mem.readInt(u32, data[12..16], .little);
    const opt_size = mem.readInt(u16, data[16..18], .little);
    if (opt_size != 0) return error.BadObject; // an image, not an object
    const sections_off: usize = 20;
    const section_size = @sizeOf(coff.SectionHeader);
    if (data.len < sections_off + @as(usize, nsections) * section_size) return error.BadObject;
    if (symtab_off == 0 or nsyms == 0) return;
    const symtab_end = @as(usize, symtab_off) + @as(usize, nsyms) * coff.Symbol.sizeOf();
    if (data.len < symtab_end + 4) return error.BadObject;
    const strtab_size = mem.readInt(u32, data[symtab_end..][0..4], .little);
    if (strtab_size < 4 or data.len < symtab_end + strtab_size) return error.BadObject;
    const strtab: coff.Strtab = .{ .buffer = data[symtab_end .. symtab_end + strtab_size] };
    const symtab: coff.Symtab = .{ .buffer = data[symtab_off..symtab_end] };

    var i: usize = 0;
    while (i < nsyms) {
        const sym = symtab.at(i, .symbol).symbol;
        defer i += 1 + sym.number_of_aux_symbols;
        if (sym.storage_class != .EXTERNAL) continue;
        const section = @intFromEnum(sym.section_number);
        if (section == 0) {
            if (sym.value == 0) continue; // undefined
            // a common (nm: C)
        } else if (section == 0xffff or section == 0xfffe) {
            continue; // absolute, debug
        } else {
            if (section > nsections) return error.BadObject;
            const hdr: *align(1) const coff.SectionHeader = @ptrCast(data[sections_off + (section - 1) * section_size ..].ptr);
            const fl = hdr.flags;
            if (!(fl.CNT_CODE or fl.CNT_INITIALIZED_DATA or fl.CNT_UNINITIALIZED_DATA)) continue;
            if (fl.LNK_INFO or fl.LNK_REMOVE or fl.MEM_DISCARDABLE) continue; // .drectve, debug
        }
        const name: []const u8 = sym.getName() orelse blk: {
            const off = sym.getNameOffset() orelse continue;
            if (off >= strtab.buffer.len) return error.BadObject;
            break :blk strtab.get(off);
        };
        if (name.len == 0 or name[0] == '.') continue;
        var seen = false;
        for (out.items) |x| if (mem.eql(u8, x, name)) {
            seen = true;
            break;
        };
        if (!seen) try out.append(a, try a.dupe(u8, name));
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
pub fn run(ctx: *Ctx, args: []const []const u8) u8 {
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
        ctx.warn("usage: rzig def -o <file>.def <object>...", .{});
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

// testdata/win-syms.c compiled with `zig cc -target x86_64-windows-gnu -O2 -c`
const win_syms = @embedFile("testdata/win-syms.o");

test "exports: nm's [BCDRT] set without the compiler's helpers" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var names: std.ArrayList([]const u8) = .empty;
    try exports(arena.allocator(), win_syms, &names);
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
}
