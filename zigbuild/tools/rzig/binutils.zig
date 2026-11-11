//! Windows' binutils, as rzig's own names (feat-win-zig-binutils): R's
//! makefiles, R CMD check and CMake run nm, objdump, strip, dlltool,
//! windres and as by the names Makeconf.win gives them, beside rzig in
//! R_HOME/bin/toolchain. Until zig 0.17 they were conda-forge's MinGW
//! binutils (binutils_impl_win-64, x86_64 only: conda-forge has none for
//! win-arm64), copied into the build-tools group's binutils/ with the
//! zstd.dll and vcruntime140.dll they load. Now one toolchain does it all,
//! for x86_64 and aarch64 alike (the machine is rzig's own target):
//!
//!   nm        COFF objects (bigobj ones too), archives of them and import
//!             libraries, read here: the BSD format by default, -P (POSIX: what sotools.R's
//!             read_symbols_from_object_file parses through UserNM, `nm
//!             -Pg`), -g, -u, --defined-only, -p, -n, -r, -A, -a. Its
//!             symbol letters follow GNU nm's for COFF: T code, D data, R
//!             read-only data, B bss, C common, U undefined, w a weak
//!             external (W in a section), A absolute, I an import
//!             library's __imp_ symbol;
//!             lowercase for a local. winshlib.mk's `$(NM) | sed -n
//!             's/^.* [BCDRT] / /p'` reads the default format.
//!   objdump   -h (section headers), -f, -p and -x for PE images and COFF
//!             objects, read here, in the layout GNU objdump prints and
//!             sotools.R's read_symbols_from_dll parses for R CMD check:
//!             each import's "\tDLL Name:" block, then three lines, then
//!             "The Export Tables".
//!   strip     --strip-debug (-g, -S, -d), --strip-unneeded and -s: a COFF
//!             object or each member of an archive loses its debug
//!             sections (.debug$S, .debug$T, .debug_*), the archive is
//!             written again by `zig ar` (its symbol index); a PE image
//!             loses its DWARF sections (.debug_*, the image's last ones)
//!             and a COFF symbol table at its end. zig links with no
//!             symbol table and CodeView in a .pdb by default, so a DLL
//!             rzig linked has nothing to strip: it is left as it is.
//!   dlltool   GNU's options (--input-def/-d, --output-lib/-l,
//!             --dllname/-D, -k, -m) as `zig dlltool` (llvm-dlltool) takes
//!             them, the machine from rzig's target; --as and its assembler
//!             flags dropped (llvm-dlltool writes the import library
//!             itself).
//!   windres   GNU's options (-i/-o, positional input and output, -O, -J,
//!             -F, -I, -D, -U, -l, --preprocessor and its args) as `zig rc`
//!             takes them: /:output-format coff (or res), /:target the
//!             machine, /:auto-includes gnu (zig's MinGW headers, the same
//!             on every machine, never an installed Visual Studio's). zig
//!             rc preprocesses itself and defines RC_INVOKED, so windres'
//!             --preprocessor, which named rzig's gcc.exe, is dropped.
//!   as        `zig cc -c -x assembler`, for a .s file.
//!
//! Each takes `@file` for the words in it (main.zig, response.zig), as
//! GNU's do.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");
const stdio = @import("stdio.zig");

pub const Error = error{ BadFile, OutOfMemory };

// --- the machine ------------------------------------------------------

pub const Machine = enum {
    x86_64,
    aarch64,
    i386,

    pub const own: Machine = switch (builtin.cpu.arch) {
        .aarch64 => .aarch64,
        .x86 => .i386,
        else => .x86_64,
    };

    fn fromCoff(m: u16) ?Machine {
        return switch (m) {
            0x8664 => .x86_64,
            0xaa64 => .aarch64,
            0x14c => .i386,
            else => null,
        };
    }

    /// llvm-dlltool's -m.
    fn dlltool(m: Machine) []const u8 {
        return switch (m) {
            .x86_64 => "i386:x86-64",
            .aarch64 => "arm64",
            .i386 => "i386",
        };
    }

    /// zig rc's /:target.
    fn rc(m: Machine) []const u8 {
        return switch (m) {
            .x86_64 => "x64",
            .aarch64 => "arm64",
            .i386 => "x86",
        };
    }

    /// GNU's bfd target name: pe-<arch> for an object, pei-<arch> for an image.
    fn bfd(m: Machine) []const u8 {
        return switch (m) {
            .x86_64 => "x86-64",
            .aarch64 => "aarch64-little",
            .i386 => "i386",
        };
    }

    fn arch(m: Machine) []const u8 {
        return switch (m) {
            .x86_64 => "i386:x86-64",
            .aarch64 => "aarch64",
            .i386 => "i386",
        };
    }

    fn wide(m: Machine) bool {
        return m != .i386;
    }
};

// --- reading COFF -----------------------------------------------------

fn rd16(d: []const u8, off: usize) Error!u16 {
    if (off + 2 > d.len) return error.BadFile;
    return mem.readInt(u16, d[off..][0..2], .little);
}
fn rd32(d: []const u8, off: usize) Error!u32 {
    if (off + 4 > d.len) return error.BadFile;
    return mem.readInt(u32, d[off..][0..4], .little);
}
fn rd64(d: []const u8, off: usize) Error!u64 {
    if (off + 8 > d.len) return error.BadFile;
    return mem.readInt(u64, d[off..][0..8], .little);
}

pub const Kind = enum { object, image, archive, short_import, other };

const ar_magic = "!<arch>\n";

/// ANON_OBJECT_HEADER_BIGOBJ's class id, as its 16 bytes in the file
/// ({D1BAA1C7-BAEE-4BA9-AF20-FAF66AA4DCB8}): the header LLVM (and MSVC)
/// write for an object of more than 65,279 sections.
const bigobj_class = [16]u8{ 0xc7, 0xa1, 0xba, 0xd1, 0xee, 0xba, 0xa9, 0x4b, 0xaf, 0x20, 0xfa, 0xf6, 0x6a, 0xa4, 0xdc, 0xb8 };
const bigobj_header = 56;

/// An anonymous object header (Sig1 0, Sig2 0xffff) that is a bigobj
/// object: version 2 or later and bigobj's class id. Version 0 is a short
/// import object (an import library's member).
fn isBigobj(d: []const u8) bool {
    if (d.len < bigobj_header) return false;
    if (mem.readInt(u16, d[0..2], .little) != 0 or mem.readInt(u16, d[2..4], .little) != 0xffff) return false;
    return mem.readInt(u16, d[4..6], .little) >= 2 and mem.eql(u8, d[12..28], &bigobj_class);
}

pub fn kindOf(d: []const u8) Kind {
    if (mem.startsWith(u8, d, ar_magic)) return .archive;
    if (d.len >= 0x40 and d[0] == 'M' and d[1] == 'Z') return .image;
    if (d.len >= 20) {
        const m = mem.readInt(u16, d[0..2], .little);
        if (m == 0 and mem.readInt(u16, d[2..4], .little) == 0xffff) {
            // an anonymous header: its version tells which
            if (mem.readInt(u16, d[4..6], .little) == 0) return .short_import;
            if (isBigobj(d)) return .object;
            return .other; // version 1 (LTO, CLR): not read here
        }
        if (Machine.fromCoff(m) != null) return .object;
    }
    return .other;
}

pub const Section = struct {
    name: []const u8,
    vsize: u32,
    va: u32,
    raw_size: u32,
    raw_ptr: u32,
    nrelocs: u16,
    flags: u32,

    const code = 0x20;
    const data = 0x40;
    const bss = 0x80;
    const lnk_info = 0x200;
    const lnk_remove = 0x800;
    const discardable = 0x02000000;
    const mem_write = 0x80000000;

    fn isDebug(s: Section) bool {
        return mem.startsWith(u8, s.name, ".debug");
    }
};

/// A COFF file's header: an object's (a regular or a bigobj one), or the
/// one after an image's PE signature. One reader for nm, objdump, strip
/// and rzig def (def.zig).
pub const Coff = struct {
    data: []const u8,
    /// where the COFF header starts
    hdr: usize,
    machine: Machine,
    sections: []Section,
    symtab: u32,
    nsyms: u32,
    opt_size: u16,
    image: bool,
    /// a bigobj object: 20-byte symbol records with 32-bit section numbers
    bigobj: bool = false,
    /// where the section headers start
    sec_off: usize = 0,

    /// The file offsets of the header's PointerToSymbolTable and
    /// NumberOfSymbols, and NumberOfSections'.
    pub fn symtabField(c: Coff) usize {
        return if (c.bigobj) 48 else c.hdr + 8;
    }
    pub fn nsymsField(c: Coff) usize {
        return if (c.bigobj) 52 else c.hdr + 12;
    }

    /// One symbol record's size: 18 bytes, a bigobj's 20.
    pub fn symSize(c: Coff) usize {
        return if (c.bigobj) 20 else 18;
    }

    pub fn parse(a: mem.Allocator, d: []const u8) Error!Coff {
        if (isBigobj(d)) return parseBigobj(a, d);
        var hdr: usize = 0;
        var image = false;
        if (d.len >= 0x40 and d[0] == 'M' and d[1] == 'Z') {
            const pe: usize = try rd32(d, 0x3c);
            if (pe + 4 > d.len or !mem.eql(u8, d[pe..][0..4], "PE\x00\x00")) return error.BadFile;
            hdr = pe + 4;
            image = true;
        }
        const machine = Machine.fromCoff(try rd16(d, hdr)) orelse return error.BadFile;
        const nsec = try rd16(d, hdr + 2);
        const symtab = try rd32(d, hdr + 8);
        const nsyms = try rd32(d, hdr + 12);
        const opt_size = try rd16(d, hdr + 16);
        const sec_off = hdr + 20 + opt_size;
        return finish(a, d, .{ .data = d, .hdr = hdr, .machine = machine, .sections = &.{}, .symtab = symtab, .nsyms = nsyms, .opt_size = opt_size, .image = image, .sec_off = sec_off }, nsec);
    }

    fn parseBigobj(a: mem.Allocator, d: []const u8) Error!Coff {
        const machine = Machine.fromCoff(try rd16(d, 6)) orelse return error.BadFile;
        const nsec = try rd32(d, 44);
        const symtab = try rd32(d, 48);
        const nsyms = try rd32(d, 52);
        return finish(a, d, .{ .data = d, .hdr = 0, .machine = machine, .sections = &.{}, .symtab = symtab, .nsyms = nsyms, .opt_size = 0, .image = false, .bigobj = true, .sec_off = bigobj_header }, nsec);
    }

    /// The section headers, read once the header's fields are.
    fn finish(a: mem.Allocator, d: []const u8, c0: Coff, nsec: u32) Error!Coff {
        var c = c0;
        const sec_off = c.sec_off;
        const symtab = c.symtab;
        if (sec_off + @as(usize, nsec) * 40 > d.len) return error.BadFile;
        const strtab_at: usize = @as(usize, symtab) + @as(usize, c.nsyms) * c.symSize();
        const sections = try a.alloc(Section, nsec);
        if (symtab != 0 and strtab_at > d.len) return error.BadFile;
        for (sections, 0..) |*s, i| {
            const o = sec_off + i * 40;
            const raw = d[o..][0..8];
            var name: []const u8 = raw[0 .. mem.findScalar(u8, raw, 0) orelse 8];
            // "/<decimal>": the name is in the string table (objects)
            if (name.len > 1 and name[0] == '/' and symtab != 0) {
                if (std.fmt.parseInt(u32, name[1..], 10)) |off| {
                    if (strtab_at + off < d.len) name = mem.sliceTo(d[strtab_at + off ..], 0);
                } else |_| {}
            }
            s.* = .{
                .name = name,
                .vsize = try rd32(d, o + 8),
                .va = try rd32(d, o + 12),
                .raw_size = try rd32(d, o + 16),
                .raw_ptr = try rd32(d, o + 20),
                .nrelocs = try rd16(d, o + 32),
                .flags = try rd32(d, o + 36),
            };
        }
        c.sections = sections;
        return c;
    }

    pub fn strtab(c: Coff) []const u8 {
        if (c.symtab == 0) return "";
        const at: usize = @as(usize, c.symtab) + @as(usize, c.nsyms) * c.symSize();
        if (at + 4 > c.data.len) return "";
        const size = mem.readInt(u32, c.data[at..][0..4], .little);
        if (size < 4 or at + size > c.data.len) return "";
        return c.data[at .. at + size];
    }

    /// The file offset of an image's RVA, or null.
    fn rvaOff(c: Coff, rva: u64) ?usize {
        for (c.sections) |s| {
            const span: u64 = @max(s.vsize, s.raw_size);
            if (rva >= s.va and rva < @as(u64, s.va) + span) {
                const off = @as(usize, s.raw_ptr) + @as(usize, @intCast(rva - s.va));
                return if (off < c.data.len) off else null;
            }
        }
        return null;
    }

    fn sectionOf(c: Coff, rva: u64) ?Section {
        for (c.sections) |s| if (rva >= s.va and rva < @as(u64, s.va) + @max(s.vsize, s.raw_size)) return s;
        return null;
    }

    /// The NUL-terminated string at an image's RVA.
    fn rvaString(c: Coff, rva: u64) []const u8 {
        const off = c.rvaOff(rva) orelse return "";
        return mem.sliceTo(c.data[off..], 0);
    }

    fn pe32plus(c: Coff) bool {
        return c.image and (rd16(c.data, c.hdr + 20) catch 0) == 0x20b;
    }

    fn imageBase(c: Coff) u64 {
        const o = c.hdr + 20;
        return if (c.pe32plus()) (rd64(c.data, o + 24) catch 0) else (rd32(c.data, o + 28) catch 0);
    }

    /// An image's data directory `i` (0 export, 1 import): rva and size.
    fn dir(c: Coff, i: usize) ?struct { rva: u32, size: u32 } {
        const o = c.hdr + 20;
        const n_at: usize = if (c.pe32plus()) 108 else 92;
        const n = rd32(c.data, o + n_at) catch return null;
        if (i >= n) return null;
        const at = o + n_at + 4 + i * 8;
        const rva = rd32(c.data, at) catch return null;
        const size = rd32(c.data, at + 4) catch return null;
        if (rva == 0) return null;
        return .{ .rva = rva, .size = size };
    }
};

pub const Sym = struct {
    name: []const u8,
    value: u64,
    letter: u8,
    debug: bool = false,
};

const class_external = 2;
const class_static = 3;
const class_label = 6;
const class_weak_external = 105;

/// The letter GNU nm gives a symbol in this section.
fn sectionLetter(s: Section) u8 {
    if (s.flags & Section.code != 0) return 'T';
    if (s.flags & Section.bss != 0) return 'B';
    if (mem.startsWith(u8, s.name, ".idata")) return 'I';
    if (s.flags & Section.data != 0) return if (s.flags & Section.mem_write != 0) 'D' else 'R';
    if (s.isDebug()) return 'N';
    return 'R';
}

/// One symbol-table record, aux records skipped: its name, value, section
/// number (1-based; 0 undefined or common; sec_absolute, sec_debug) and
/// storage class.
pub const SymRec = struct {
    name: []const u8,
    value: u32,
    section: u32,
    class: u8,
};
pub const sec_absolute: u32 = 0xffffffff;
pub const sec_debug: u32 = 0xfffffffe;

/// The symbol table's records (a regular object's 18-byte ones or a
/// bigobj's 20-byte ones), in order.
pub fn records(a: mem.Allocator, c: Coff) Error![]SymRec {
    var out: std.ArrayList(SymRec) = .empty;
    if (c.symtab == 0 or c.nsyms == 0) return out.items;
    const d = c.data;
    const st = c.strtab();
    const size = c.symSize();
    var i: usize = 0;
    while (i < c.nsyms) {
        const at = @as(usize, c.symtab) + i * size;
        if (at + size > d.len) return error.BadFile;
        const rec = d[at..][0..size];
        // a bigobj's record: Name[8] Value[4] SectionNumber[4] Type[2]
        // StorageClass NumberOfAuxSymbols; a regular one's SectionNumber
        // is 2 bytes, with 0xffff and 0xfffe the absolute and debug ones
        const section: u32 = if (c.bigobj) mem.readInt(u32, rec[12..16], .little) else switch (mem.readInt(u16, rec[12..14], .little)) {
            0xffff => sec_absolute,
            0xfffe => sec_debug,
            else => |n| n,
        };
        const class = rec[size - 2];
        // in usize: 1 + 255 aux records overflows u8
        defer i += 1 + @as(usize, rec[size - 1]);
        const name: []const u8 = if (mem.readInt(u32, rec[0..4], .little) != 0)
            rec[0 .. mem.findScalar(u8, rec[0..8], 0) orelse 8]
        else blk: {
            const off = mem.readInt(u32, rec[4..8], .little);
            if (off >= st.len) return error.BadFile;
            break :blk mem.sliceTo(st[off..], 0);
        };
        try out.append(a, .{ .name = name, .value = mem.readInt(u32, rec[8..12], .little), .section = section, .class = class });
    }
    return out.items;
}

/// An object's symbols, in symbol-table order, as GNU nm would list them
/// (debug ones marked, for -a). The letters are BFD's (bfd_decode_symclass
/// over coff_slurp_symbol_table): a WEAK_EXTERNAL (C_NT_WEAK), which PE
/// writes with section 0 and its default in an aux record, is weak and
/// undefined, `w`; one in a section, `W`.
pub fn objectSymbols(a: mem.Allocator, c: Coff, out: *std.ArrayList(Sym)) Error!void {
    for (try records(a, c)) |r| {
        if (r.name.len == 0) continue;
        var letter: u8 = undefined;
        var debug = false;
        switch (r.class) {
            class_external, class_static, class_label, class_weak_external => {
                if (r.section == 0) {
                    if (r.class == class_static or r.class == class_label) continue;
                    letter = if (r.value != 0) 'C' else if (r.class == class_weak_external) 'w' else 'U';
                } else if (r.section == sec_absolute) {
                    letter = 'A';
                } else if (r.section == sec_debug) {
                    letter = 'N';
                    debug = true;
                } else {
                    if (r.section > c.sections.len) return error.BadFile;
                    const s = c.sections[r.section - 1];
                    letter = if (r.class == class_weak_external) 'W' else sectionLetter(s);
                    debug = s.isDebug() or s.flags & Section.lnk_info != 0;
                }
                const global = r.class == class_external or r.class == class_weak_external;
                if (!global and letter != 'U') letter = std.ascii.toLower(letter);
            },
            else => continue, // .file, .bf/.ef, ...
        }
        try out.append(a, .{ .name = r.name, .value = r.value, .letter = letter, .debug = debug });
    }
}

/// A short import object's symbols (an import library member that
/// llvm-dlltool and zig write): __imp_<name>, and <name> for code.
pub fn shortImportSymbols(a: mem.Allocator, d: []const u8, out: *std.ArrayList(Sym)) Error!void {
    if (d.len < 20) return error.BadFile;
    const typ = (try rd16(d, 18)) & 0x3;
    const name = mem.sliceTo(d[20..], 0);
    try out.append(a, .{ .name = try std.fmt.allocPrint(a, "__imp_{s}", .{name}), .value = 0, .letter = 'I' });
    if (typ == 0) try out.append(a, .{ .name = name, .value = 0, .letter = 'T' });
}

/// One member of an ar archive.
pub const Member = struct { name: []const u8, data: []const u8 };

/// The members of an archive, its symbol index and long-name table left
/// out (GNU and BSD long names resolved).
pub fn members(a: mem.Allocator, d: []const u8) Error![]Member {
    if (!mem.startsWith(u8, d, ar_magic)) return error.BadFile;
    var out: std.ArrayList(Member) = .empty;
    var longnames: []const u8 = "";
    var off: usize = ar_magic.len;
    while (off + 60 <= d.len) {
        const h = d[off..][0..60];
        if (!mem.eql(u8, h[58..60], "`\n")) return error.BadFile;
        const size = std.fmt.parseInt(usize, mem.trim(u8, h[48..58], " "), 10) catch return error.BadFile;
        const start = off + 60;
        if (start + size > d.len) return error.BadFile;
        var body = d[start .. start + size];
        off = start + size + (size & 1);
        const raw = mem.trimEnd(u8, h[0..16], " ");
        var name: []const u8 = raw;
        if (mem.eql(u8, raw, "/") or mem.eql(u8, raw, "/SYM64/") or mem.eql(u8, raw, "__.SYMDEF") or mem.eql(u8, raw, "__.SYMDEF SORTED")) continue;
        if (mem.eql(u8, raw, "//")) {
            longnames = body;
            continue;
        }
        if (raw.len > 1 and raw[0] == '/' and std.ascii.isDigit(raw[1])) {
            const lo = std.fmt.parseInt(usize, raw[1..], 10) catch return error.BadFile;
            if (lo >= longnames.len) return error.BadFile;
            const rest = longnames[lo..];
            // GNU's table ends a name with "/\n", llvm-ar's COFF (MS) one,
            // which zig ar writes for Windows, with a NUL
            const end = mem.findAny(u8, rest, "\n\x00") orelse rest.len;
            name = mem.trimEnd(u8, rest[0..end], "/");
        } else if (mem.startsWith(u8, raw, "#1/")) {
            const n = std.fmt.parseInt(usize, raw[3..], 10) catch return error.BadFile;
            if (n > body.len) return error.BadFile;
            name = mem.sliceTo(body[0..n], 0);
            body = body[n..];
        } else if (mem.endsWith(u8, raw, "/")) {
            name = raw[0 .. raw.len - 1];
        }
        try out.append(a, .{ .name = name, .data = body });
    }
    return out.items;
}

// --- nm ---------------------------------------------------------------

const NmOpts = struct {
    posix: bool = false,
    extern_only: bool = false,
    undefined_only: bool = false,
    defined_only: bool = false,
    no_sort: bool = false,
    numeric: bool = false,
    reverse: bool = false,
    file_names: bool = false,
    all: bool = false,
};

fn symLess(o: NmOpts, x: Sym, y: Sym) bool {
    const lt = if (o.numeric)
        (x.value < y.value or (x.value == y.value and mem.lessThan(u8, x.name, y.name)))
    else
        mem.lessThan(u8, x.name, y.name);
    return lt;
}

fn nmList(a: mem.Allocator, o: NmOpts, out: *std.ArrayList(u8), m: Machine, syms: []Sym, prefix: []const u8) !void {
    var keep: std.ArrayList(Sym) = .empty;
    for (syms) |s| {
        if (s.debug and !o.all) continue;
        const undef = s.letter == 'U' or s.letter == 'w';
        if (o.extern_only and !(std.ascii.isUpper(s.letter) or s.letter == 'w')) continue;
        if (o.undefined_only and !undef) continue;
        if (o.defined_only and undef) continue;
        try keep.append(a, s);
    }
    if (!o.no_sort) {
        mem.sort(Sym, keep.items, o, symLess);
        if (o.reverse) mem.reverse(Sym, keep.items);
    }
    const width: usize = if (m.wide()) 16 else 8;
    for (keep.items) |s| {
        const undef = s.letter == 'U' or s.letter == 'w';
        try out.appendSlice(a, prefix);
        if (o.posix) {
            if (undef) {
                try out.print(a, "{s} {c}\n", .{ s.name, s.letter });
            } else {
                try out.print(a, "{s} {c} ", .{ s.name, s.letter });
                try hex(a, out, s.value, width);
                try out.append(a, '\n');
            }
        } else {
            if (undef) try out.appendNTimes(a, ' ', width) else try hex(a, out, s.value, width);
            try out.print(a, " {c} {s}\n", .{ s.letter, s.name });
        }
    }
}

/// One file's (or archive member's) symbols; null for a file nm does not
/// read (it names it, as GNU's "file format not recognized").
fn symbolsOf(a: mem.Allocator, d: []const u8, out: *std.ArrayList(Sym)) Error!Machine {
    switch (kindOf(d)) {
        .object => {
            const c = try Coff.parse(a, d);
            try objectSymbols(a, c, out);
            return c.machine;
        },
        .short_import => {
            try shortImportSymbols(a, d, out);
            return Machine.fromCoff(try rd16(d, 6)) orelse Machine.own;
        },
        .image => {
            const c = try Coff.parse(a, d);
            try objectSymbols(a, c, out);
            return c.machine;
        },
        else => return error.BadFile,
    }
}

/// -f/--format's value, as GNU nm takes it (its first letter): true for
/// posix, false for bsd; null for one rzig's nm does not write.
fn nmFormat(v: []const u8) ?bool {
    if (v.len == 0) return null;
    return switch (std.ascii.toLower(v[0])) {
        'p' => true,
        'b' => false,
        else => null,
    };
}

/// `nm [options] file...`: the text on stdout and the exit code (1 when
/// a file could not be read; what was read is printed). The headers are
/// GNU nm's: with more than one file, each file's name ("\n<file>:\n";
/// POSIX "<file>:\n"), an archive's too in BSD format; each archive
/// member's ("\n<member>:\n"; POSIX "<member>:\n", or
/// "<archive>[<member>]:\n" with more than one file); none with -A, which
/// prefixes each line instead ("<archive>:<member>:", POSIX
/// "<archive>[<member>]: ").
pub fn nm(ctx: *Ctx, args: []const []const u8, out: *std.ArrayList(u8)) !u8 {
    const a = ctx.arena;
    var o: NmOpts = .{};
    var files: std.ArrayList([]const u8) = .empty;
    var only_files = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (only_files or x.len < 2 or x[0] != '-') {
            try files.append(a, x);
            continue;
        }
        if (mem.eql(u8, x, "--")) {
            only_files = true;
        } else if (mem.eql(u8, x, "--version") or mem.eql(u8, x, "-V")) {
            try out.appendSlice(a, "GNU-compatible nm (rzig, " ++ build_name ++ ")\n");
            return 0;
        } else if (mem.eql(u8, x, "--portability")) {
            o.posix = true;
        } else if (mem.eql(u8, x, "--format") or mem.startsWith(u8, x, "--format=")) {
            const v = if (x.len > "--format".len) x["--format=".len..] else blk: {
                i += 1;
                if (i >= args.len) {
                    ctx.warn("--format needs a value", .{});
                    return 1;
                }
                break :blk args[i];
            };
            o.posix = nmFormat(v) orelse {
                ctx.warn("unsupported format {s} (rzig's nm: bsd, posix)", .{v});
                return 1;
            };
        } else if (mem.eql(u8, x, "--extern-only")) {
            o.extern_only = true;
        } else if (mem.eql(u8, x, "--undefined-only")) {
            o.undefined_only = true;
        } else if (mem.eql(u8, x, "--defined-only")) {
            o.defined_only = true;
        } else if (mem.eql(u8, x, "--no-sort")) {
            o.no_sort = true;
        } else if (mem.eql(u8, x, "--numeric-sort")) {
            o.numeric = true;
        } else if (mem.eql(u8, x, "--reverse-sort")) {
            o.reverse = true;
        } else if (mem.eql(u8, x, "--print-file-name")) {
            o.file_names = true;
        } else if (mem.eql(u8, x, "--debug-syms")) {
            o.all = true;
        } else if (mem.eql(u8, x, "--plugin")) {
            i += 1; // its file: LTO plugins are GNU's; names are read here
        } else if (mem.eql(u8, x, "--demangle") or mem.eql(u8, x, "--no-demangle") or mem.startsWith(u8, x, "--plugin=")) {
            // names are printed as they are
        } else if (x[1] != '-') {
            var j: usize = 1;
            while (j < x.len) : (j += 1) switch (x[j]) {
                'P' => o.posix = true,
                'B' => o.posix = false,
                'g' => o.extern_only = true,
                'u' => o.undefined_only = true,
                'U' => o.defined_only = true,
                'p' => o.no_sort = true,
                'n', 'v' => o.numeric = true,
                'r' => o.reverse = true,
                'A', 'o' => o.file_names = true,
                'a' => o.all = true,
                'C' => {},
                'f' => {
                    // its value: the rest of this word, or the next one
                    const v = if (j + 1 < x.len) x[j + 1 ..] else blk: {
                        i += 1;
                        if (i >= args.len) {
                            ctx.warn("-f needs a format", .{});
                            return 1;
                        }
                        break :blk args[i];
                    };
                    o.posix = nmFormat(v) orelse {
                        ctx.warn("unsupported format {s} (rzig's nm: bsd, posix)", .{v});
                        return 1;
                    };
                    break;
                },
                else => {
                    ctx.warn("unsupported option -{c} (rzig's nm: -P -B -f -g -u -U -p -n -r -A -a -C)", .{x[j]});
                    return 1;
                },
            };
        } else {
            ctx.warn("unsupported option {s}", .{x});
            return 1;
        }
    }
    if (files.items.len == 0) try files.append(a, "a.out");
    var code: u8 = 0;
    const many = files.items.len > 1;
    for (files.items) |f| {
        const d = Io.Dir.cwd().readFileAlloc(ctx.io, f, a, .limited(1 << 30)) catch |err| {
            ctx.warn("'{s}': {t}", .{ f, err });
            code = 1;
            continue;
        };
        if (kindOf(d) == .archive) {
            const ms = members(a, d) catch {
                ctx.warn("{s}: malformed archive", .{f});
                code = 1;
                continue;
            };
            if (many and !o.file_names and !o.posix) try out.print(a, "\n{s}:\n", .{f});
            for (ms) |m| {
                var syms: std.ArrayList(Sym) = .empty;
                const mach = symbolsOf(a, m.data, &syms) catch {
                    ctx.warn("{s}({s}): file format not recognized", .{ f, m.name });
                    code = 1;
                    continue;
                };
                const prefix = if (!o.file_names) "" else if (o.posix)
                    try std.fmt.allocPrint(a, "{s}[{s}]: ", .{ f, m.name })
                else
                    try std.fmt.allocPrint(a, "{s}:{s}:", .{ f, m.name });
                if (!o.file_names) {
                    if (!o.posix) {
                        try out.print(a, "\n{s}:\n", .{m.name});
                    } else if (many) {
                        try out.print(a, "{s}[{s}]:\n", .{ f, m.name });
                    } else {
                        try out.print(a, "{s}:\n", .{m.name});
                    }
                }
                try nmList(a, o, out, mach, syms.items, prefix);
            }
            continue;
        }
        var syms: std.ArrayList(Sym) = .empty;
        const mach = symbolsOf(a, d, &syms) catch {
            ctx.warn("{s}: file format not recognized", .{f});
            code = 1;
            continue;
        };
        if (syms.items.len == 0 and kindOf(d) == .image) {
            ctx.warn("{s}: no symbols", .{f});
            continue;
        }
        if (many and !o.file_names) {
            if (o.posix) try out.print(a, "{s}:\n", .{f}) else try out.print(a, "\n{s}:\n", .{f});
        }
        const prefix = if (!o.file_names) "" else if (o.posix) try std.fmt.allocPrint(a, "{s}: ", .{f}) else try std.fmt.allocPrint(a, "{s}:", .{f});
        try nmList(a, o, out, mach, syms.items, prefix);
    }
    return code;
}

const build_name = "zig " ++ builtin.zig_version_string;

/// `v` in lowercase hex, zero-padded to `width` digits.
fn hex(a: mem.Allocator, out: *std.ArrayList(u8), v: u64, width: usize) !void {
    var buf: [16]u8 = undefined;
    const digits = std.fmt.bufPrint(&buf, "{x}", .{v}) catch unreachable;
    if (digits.len < width) try out.appendNTimes(a, '0', width - digits.len);
    try out.appendSlice(a, digits);
}

// --- objdump ----------------------------------------------------------

fn sectionFlagsText(a: mem.Allocator, s: Section, image: bool) ![]const u8 {
    var t: std.ArrayList(u8) = .empty;
    const bss = s.flags & Section.bss != 0;
    if (!bss and s.raw_size != 0) try t.appendSlice(a, "CONTENTS, ");
    if (s.flags & Section.lnk_remove == 0 and !s.isDebug() and s.flags & Section.lnk_info == 0) try t.appendSlice(a, "ALLOC, ");
    if (!bss and s.flags & Section.lnk_info == 0 and !s.isDebug()) try t.appendSlice(a, "LOAD, ");
    if (!image and s.nrelocs != 0) try t.appendSlice(a, "RELOC, ");
    if (s.flags & Section.mem_write == 0 and !bss) try t.appendSlice(a, "READONLY, ");
    if (s.flags & Section.code != 0) try t.appendSlice(a, "CODE, ") else if (s.isDebug()) try t.appendSlice(a, "DEBUGGING, ") else if (!bss) try t.appendSlice(a, "DATA, ");
    if (t.items.len >= 2) t.items.len -= 2;
    return t.items;
}

fn objdumpHeaders(a: mem.Allocator, c: Coff, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(a, "\nSections:\n");
    const w: usize = if (c.machine.wide()) 16 else 8;
    try out.print(a, "Idx Name          Size      VMA{s}  LMA{s}  File off  Algn\n", .{ if (w == 16) "             " else "     ", if (w == 16) "             " else "     " });
    const base = if (c.image) c.imageBase() else 0;
    for (c.sections, 0..) |s, i| {
        const size = if (c.image) @max(s.vsize, 0) else s.raw_size;
        const vma = if (c.image) base + s.va else s.va;
        const align_exp: u32 = if (c.image) 2 else blk: {
            const n = (s.flags >> 20) & 0xf;
            break :blk if (n == 0) 0 else n - 1;
        };
        try out.print(a, "{d: >3} {s: <13} {x:0>8}  ", .{ i, s.name, size });
        try hex(a, out, vma, w);
        try out.appendSlice(a, "  ");
        try hex(a, out, vma, w);
        try out.print(a, "  {x:0>8}  2**{d}\n", .{ s.raw_ptr, align_exp });
        try out.print(a, "                  {s}\n", .{try sectionFlagsText(a, s, c.image)});
    }
}

fn objdumpImports(a: mem.Allocator, c: Coff, out: *std.ArrayList(u8)) !void {
    const imp = c.dir(1) orelse return;
    const sec = c.sectionOf(imp.rva) orelse return;
    const base = c.imageBase();
    try out.print(a, "\nThere is an import table in {s} at 0x{x}\n\n", .{ sec.name, base + imp.rva });
    try out.print(a, "The Import Tables (interpreted {s} section contents)\n", .{sec.name});
    try out.appendSlice(a, " vma:            Hint    Time      Forward  DLL       First\n                 Table   Stamp     Chain    Name      Thunk\n");
    var at: u64 = imp.rva;
    const wide = c.pe32plus();
    while (true) : (at += 20) {
        const off = c.rvaOff(at) orelse break;
        const ilt = try rd32(c.data, off);
        const stamp = try rd32(c.data, off + 4);
        const chain = try rd32(c.data, off + 8);
        const name_rva = try rd32(c.data, off + 12);
        const iat = try rd32(c.data, off + 16);
        try out.print(a, " {x:0>8}\t{x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8}\n", .{ at, ilt, stamp, chain, name_rva, iat });
        if (ilt == 0 and name_rva == 0 and iat == 0) break;
        try out.print(a, "\n\tDLL Name: {s}\n", .{c.rvaString(name_rva)});
        try out.appendSlice(a, "\tvma:     Ordinal  Hint  Member-Name  Bound-To\n");
        var t: u64 = if (ilt != 0) ilt else iat;
        while (true) {
            const toff = c.rvaOff(t) orelse break;
            const entry: u64 = if (wide) try rd64(c.data, toff) else try rd32(c.data, toff);
            if (entry == 0) break;
            const ord_flag: u64 = if (wide) 1 << 63 else 1 << 31;
            if (entry & ord_flag != 0) {
                try out.print(a, "\t{x:0>8}  {d: >5}  <none> <none>\n", .{ entry & 0xffff, entry & 0xffff });
            } else {
                const hn: u32 = @truncate(entry & 0x7fffffff);
                const hoff = c.rvaOff(hn) orelse break;
                const hint = try rd16(c.data, hoff);
                try out.print(a, "\t{x:0>8}  <none>  {x:0>4}  {s}\n", .{ hn, hint, mem.sliceTo(c.data[hoff + 2 ..], 0) });
            }
            t += if (wide) 8 else 4;
        }
        try out.appendSlice(a, "\n");
    }
}

fn objdumpExports(a: mem.Allocator, c: Coff, out: *std.ArrayList(u8)) !void {
    const exp = c.dir(0) orelse return;
    const sec = c.sectionOf(exp.rva) orelse return;
    const off = c.rvaOff(exp.rva) orelse return;
    const d = c.data;
    const base = c.imageBase();
    const flags = try rd32(d, off);
    const stamp = try rd32(d, off + 4);
    const major = try rd16(d, off + 8);
    const minor = try rd16(d, off + 10);
    const name_rva = try rd32(d, off + 12);
    const ord_base = try rd32(d, off + 16);
    const nfun = try rd32(d, off + 20);
    const nnames = try rd32(d, off + 24);
    const eat = try rd32(d, off + 28);
    const npt = try rd32(d, off + 32);
    const ot = try rd32(d, off + 36);
    // three lines before "The Export Tables", as sotools.R's
    // read_symbols_from_dll counts them (l2 - 4 is the imports' last)
    try out.print(a, "\nThere is an export table in {s} at 0x{x}\n\n", .{ sec.name, base + exp.rva });
    try out.print(a, "The Export Tables (interpreted {s} section contents)\n\n", .{sec.name});
    try out.print(a, "Export Flags \t\t\t{x}\nTime/Date stamp \t\t{x}\nMajor/Minor \t\t\t{d}/{d}\nName \t\t\t\t{x:0>8} {s}\nOrdinal Base \t\t\t{d}\n", .{ flags, stamp, major, minor, name_rva, c.rvaString(name_rva), ord_base });
    try out.print(a, "Number in:\n\tExport Address Table \t\t{x:0>8}\n\t[Name Pointer/Ordinal] Table\t{x:0>8}\n", .{ nfun, nnames });
    try out.print(a, "Table Addresses\n\tExport Address Table \t\t{x:0>8}\n\tName Pointer Table \t\t{x:0>8}\n\tOrdinal Table \t\t\t{x:0>8}\n\n", .{ eat, npt, ot });
    try out.print(a, "Export Address Table -- Ordinal Base {d}\n", .{ord_base});
    var i: u32 = 0;
    while (i < nfun) : (i += 1) {
        const eoff = c.rvaOff(@as(u64, eat) + @as(u64, i) * 4) orelse break;
        const rva = try rd32(d, eoff);
        try out.print(a, "\t[{d: >4}] +base[{d: >4}] {x:0>8} Export RVA\n", .{ i, @as(u64, i) + ord_base, rva });
    }
    try out.appendSlice(a, "\n[Ordinal/Name Pointer] Table\n");
    i = 0;
    while (i < nnames) : (i += 1) {
        const noff = c.rvaOff(@as(u64, npt) + @as(u64, i) * 4) orelse break;
        const ooff = c.rvaOff(@as(u64, ot) + @as(u64, i) * 2) orelse break;
        const ord = try rd16(d, ooff);
        try out.print(a, "\t[{d: >4}] {s}\n", .{ ord, c.rvaString(try rd32(d, noff)) });
    }
    try out.appendSlice(a, "\n");
}

fn objdumpFile(a: mem.Allocator, c: Coff, show: ObjdumpShow, out: *std.ArrayList(u8)) !void {
    if (show.file) {
        try out.print(a, "architecture: {s}, flags 0x{x:0>8}:\n", .{ c.machine.arch(), if (c.bigobj) @as(u16, 0) else try rd16(c.data, c.hdr + 18) });
        try out.appendSlice(a, "start address 0x");
        try hex(a, out, 0, if (c.machine.wide()) 16 else 8);
        try out.appendSlice(a, "\n\n");
    }
    if (show.private and c.image) {
        try objdumpImports(a, c, out);
        try objdumpExports(a, c, out);
    }
    if (show.headers) try objdumpHeaders(a, c, out);
    if (show.syms) {
        try out.appendSlice(a, "SYMBOL TABLE:\n");
        var syms: std.ArrayList(Sym) = .empty;
        try objectSymbols(a, c, &syms);
        if (syms.items.len == 0) try out.appendSlice(a, "no symbols\n");
        for (syms.items) |s| try out.print(a, "{x:0>16} {c} {s}\n", .{ s.value, s.letter, s.name });
        try out.appendSlice(a, "\n");
    }
}

const ObjdumpShow = struct { headers: bool = false, private: bool = false, file: bool = false, syms: bool = false };

pub fn objdump(ctx: *Ctx, args: []const []const u8, out: *std.ArrayList(u8)) !u8 {
    const a = ctx.arena;
    var show: ObjdumpShow = .{};
    var files: std.ArrayList([]const u8) = .empty;
    for (args) |x| {
        if (x.len < 2 or x[0] != '-') {
            try files.append(a, x);
        } else if (mem.eql(u8, x, "--version")) {
            try out.appendSlice(a, "GNU-compatible objdump (rzig, " ++ build_name ++ ")\n");
            return 0;
        } else if (mem.eql(u8, x, "--section-headers") or mem.eql(u8, x, "--headers")) {
            show.headers = true;
        } else if (mem.eql(u8, x, "--private-headers")) {
            show.private = true;
        } else if (mem.eql(u8, x, "--file-headers")) {
            show.file = true;
        } else if (mem.eql(u8, x, "--syms")) {
            show.syms = true;
        } else if (mem.eql(u8, x, "--all-headers")) {
            show = .{ .headers = true, .private = true, .file = true, .syms = true };
        } else if (x[1] != '-') {
            for (x[1..]) |c| switch (c) {
                'h' => show.headers = true,
                'p' => show.private = true,
                'f' => show.file = true,
                't' => show.syms = true,
                'x' => show = .{ .headers = true, .private = true, .file = true, .syms = true },
                'w' => {},
                else => {
                    ctx.warn("unsupported option -{c} (rzig's objdump: -h -p -f -t -x)", .{c});
                    return 1;
                },
            };
        } else {
            ctx.warn("unsupported option {s}", .{x});
            return 1;
        }
    }
    if (!(show.headers or show.private or show.file or show.syms)) {
        ctx.warn("at least one of -h -p -f -t -x must be given", .{});
        return 1;
    }
    // no file: GNU's default, a.out (an error, unless there is one)
    if (files.items.len == 0) try files.append(a, "a.out");
    var code: u8 = 0;
    for (files.items) |f| {
        const d = Io.Dir.cwd().readFileAlloc(ctx.io, f, a, .limited(1 << 30)) catch |err| {
            ctx.warn("'{s}': {t}", .{ f, err });
            code = 1;
            continue;
        };
        if (kindOf(d) == .archive) {
            const ms = members(a, d) catch {
                ctx.warn("{s}: malformed archive", .{f});
                code = 1;
                continue;
            };
            try out.print(a, "In archive {s}:\n", .{f});
            for (ms) |m| {
                const c = Coff.parse(a, m.data) catch continue;
                try out.print(a, "\n{s}:     file format pe-{s}\n\n", .{ m.name, c.machine.bfd() });
                try objdumpFile(a, c, show, out);
            }
            continue;
        }
        const c = Coff.parse(a, d) catch {
            ctx.warn("{s}: file format not recognized", .{f});
            code = 1;
            continue;
        };
        try out.print(a, "\n{s}:     file format pe{s}-{s}\n\n", .{ f, if (c.image) "i" else "", c.machine.bfd() });
        try objdumpFile(a, c, show, out);
    }
    return code;
}

// --- strip ------------------------------------------------------------

/// An object without its debug sections: the headers kept (a dropped
/// section's header stays, empty and IMAGE_SCN_LNK_REMOVE, so section
/// numbers and the symbols in it are unchanged), the other sections'
/// contents and relocations written again in order, then the symbol and
/// string tables. null: nothing to strip.
pub fn stripObject(a: mem.Allocator, c: Coff) Error!?[]u8 {
    var any = false;
    for (c.sections) |s| if (s.isDebug() and (s.raw_size != 0 or s.nrelocs != 0)) {
        any = true;
    };
    if (!any) return null;
    const d = c.data;
    const sec_off = c.sec_off;
    const head_end = sec_off + c.sections.len * 40;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, d[0..head_end]);
    for (c.sections, 0..) |s, i| {
        const h = sec_off + i * 40;
        if (s.isDebug()) {
            mem.writeInt(u32, out.items[h + 16 ..][0..4], 0, .little); // SizeOfRawData
            mem.writeInt(u32, out.items[h + 20 ..][0..4], 0, .little); // PointerToRawData
            mem.writeInt(u32, out.items[h + 24 ..][0..4], 0, .little); // PointerToRelocations
            mem.writeInt(u16, out.items[h + 32 ..][0..2], 0, .little); // NumberOfRelocations
            mem.writeInt(u32, out.items[h + 36 ..][0..4], s.flags | Section.lnk_remove, .little);
            continue;
        }
        if (s.raw_size != 0 and s.flags & Section.bss == 0) {
            if (@as(usize, s.raw_ptr) + s.raw_size > d.len) return error.BadFile;
            mem.writeInt(u32, out.items[h + 20 ..][0..4], @intCast(out.items.len), .little);
            try out.appendSlice(a, d[s.raw_ptr..][0..s.raw_size]);
        }
        if (s.nrelocs != 0) {
            const rp = try rd32(d, h + 24);
            const n: usize = if (s.nrelocs == 0xffff and s.flags & 0x01000000 != 0) 0xffff else s.nrelocs;
            // an extended count's first record holds the real one
            const count: usize = if (n == 0xffff) try rd32(d, rp) else n;
            if (@as(usize, rp) + count * 10 > d.len) return error.BadFile;
            mem.writeInt(u32, out.items[h + 24 ..][0..4], @intCast(out.items.len), .little);
            try out.appendSlice(a, d[rp..][0 .. count * 10]);
        }
    }
    if (c.symtab != 0) {
        mem.writeInt(u32, out.items[c.symtabField()..][0..4], @intCast(out.items.len), .little);
        const st = c.strtab();
        const syms_end = @as(usize, c.symtab) + @as(usize, c.nsyms) * c.symSize();
        if (syms_end > d.len) return error.BadFile;
        try out.appendSlice(a, d[c.symtab..syms_end]);
        if (st.len == 0) try out.appendSlice(a, &.{ 4, 0, 0, 0 }) else try out.appendSlice(a, st);
    }
    return out.items;
}

/// An image without its debug sections (.debug_*: DWARF, which zig cc
/// -gdwarf-4 and MinGW's ld put in a DLL; zig's default debug information
/// is CodeView in a .pdb) and without a COFF symbol table at its end, as
/// GNU strip writes it. Both are at the end of the file and of the image
/// (MinGW's ld and lld place the debug sections last, discardable), so
/// the kept sections and their file and virtual layout stay as they are:
/// the file is cut where the last kept section's data ends, the dropped
/// headers zeroed, NumberOfSections and SizeOfImage lowered. null:
/// nothing to strip. error.BadFile: an image laid out otherwise (a debug
/// section among kept ones, a data directory in one, a kept section named
/// through the string table), which this does not rewrite.
pub fn stripImage(a: mem.Allocator, c: Coff) Error!?[]u8 {
    var first_debug: ?usize = null;
    for (c.sections, 0..) |s, i| {
        if (s.isDebug()) {
            if (first_debug == null) first_debug = i;
        } else if (first_debug != null) return error.BadFile; // a kept section after a debug one
    }
    if (first_debug == null and c.symtab == 0) return null;
    const keep = c.sections[0 .. first_debug orelse c.sections.len];
    const d = c.data;
    var file_end: usize = 0;
    var image_end: u64 = 0;
    for (keep) |s| {
        file_end = @max(file_end, @as(usize, s.raw_ptr) + s.raw_size);
        image_end = @max(image_end, @as(u64, s.va) + @max(s.vsize, s.raw_size));
    }
    const dropped = c.sections[keep.len..];
    for (dropped) |s| {
        if (s.raw_size != 0 and s.raw_ptr < file_end) return error.BadFile;
        if (s.va < image_end) return error.BadFile;
    }
    if (c.symtab != 0 and c.symtab < file_end) return error.BadFile;
    for (keep, 0..) |_, i| {
        const raw = d[c.sec_off + i * 40 ..][0..8];
        if (raw[0] == '/') return error.BadFile; // its name is in the string table
    }
    const opt = c.hdr + 20;
    const n_at: usize = if (c.pe32plus()) 108 else 92;
    const ndirs = try rd32(d, opt + n_at);
    var k: usize = 0;
    while (k < @min(ndirs, 16)) : (k += 1) {
        const rva = try rd32(d, opt + n_at + 4 + k * 8);
        if (rva == 0) continue;
        if (k == 4) return error.BadFile; // a signature: cutting the file would break it
        for (dropped) |s| if (rva >= s.va and rva < @as(u64, s.va) + @max(s.vsize, s.raw_size)) return error.BadFile;
    }
    const head_end = c.sec_off + c.sections.len * 40;
    const cut = @max(file_end, head_end);
    if (cut > d.len) return error.BadFile;
    const out = try a.dupe(u8, d[0..cut]);
    mem.writeInt(u32, out[c.hdr + 8 ..][0..4], 0, .little); // PointerToSymbolTable
    mem.writeInt(u32, out[c.hdr + 12 ..][0..4], 0, .little); // NumberOfSymbols
    if (dropped.len > 0) {
        mem.writeInt(u16, out[c.hdr + 2 ..][0..2], @intCast(keep.len), .little);
        @memset(out[c.sec_off + keep.len * 40 .. head_end], 0);
        const sect_align = try rd32(d, opt + 32);
        if (sect_align == 0) return error.BadFile;
        const size = std.mem.alignForward(u64, image_end, sect_align);
        if (size > std.math.maxInt(u32)) return error.BadFile;
        mem.writeInt(u32, out[opt + 56 ..][0..4], @intCast(size), .little); // SizeOfImage
        mem.writeInt(u32, out[opt + 64 ..][0..4], 0, .little); // CheckSum: no longer this file's
    }
    return out;
}

pub fn strip(ctx: *Ctx, args: []const []const u8) !u8 {
    const a = ctx.arena;
    var files: std.ArrayList([]const u8) = .empty;
    var output: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (x.len < 2 or x[0] != '-') {
            try files.append(a, x);
        } else if (mem.eql(u8, x, "-o")) {
            i += 1;
            if (i >= args.len) {
                ctx.warn("-o needs a file", .{});
                return 1;
            }
            output = args[i];
        } else if (mem.startsWith(u8, x, "--output-file=")) {
            output = x["--output-file=".len..];
        } else if (mem.eql(u8, x, "--version")) {
            stdio.writeAll(ctx.io, .stdout(), "GNU-compatible strip (rzig, " ++ build_name ++ ")\n") catch {};
            return 0;
        } else if (!(mem.eql(u8, x, "--strip-debug") or mem.eql(u8, x, "--strip-unneeded") or mem.eql(u8, x, "--strip-all") or
            mem.eql(u8, x, "-g") or mem.eql(u8, x, "-S") or mem.eql(u8, x, "-d") or mem.eql(u8, x, "-s") or mem.eql(u8, x, "-x") or
            mem.eql(u8, x, "-X") or mem.eql(u8, x, "-p") or mem.eql(u8, x, "--preserve-dates") or mem.eql(u8, x, "--discard-all") or mem.eql(u8, x, "--discard-locals")))
        {
            ctx.warn("unsupported option {s} (rzig's strip: --strip-debug, --strip-unneeded, --strip-all, -o)", .{x});
            return 1;
        }
    }
    if (files.items.len == 0 or (output != null and files.items.len != 1)) {
        ctx.warn("usage: strip [--strip-debug|--strip-unneeded|--strip-all] [-o out] file...", .{});
        return 1;
    }
    var code: u8 = 0;
    for (files.items) |f| {
        const d = Io.Dir.cwd().readFileAlloc(ctx.io, f, a, .limited(1 << 30)) catch |err| {
            ctx.warn("'{s}': {t}", .{ f, err });
            code = 1;
            continue;
        };
        const dest = output orelse f;
        const new: ?[]const u8 = switch (kindOf(d)) {
            .object => blk: {
                const c = Coff.parse(a, d) catch {
                    ctx.warn("{s}: file format not recognized", .{f});
                    code = 1;
                    continue;
                };
                break :blk stripObject(a, c) catch {
                    ctx.warn("{s}: cannot strip", .{f});
                    code = 1;
                    continue;
                };
            },
            .image => stripImage(a, Coff.parse(a, d) catch {
                ctx.warn("{s}: file format not recognized", .{f});
                code = 1;
                continue;
            }) catch {
                ctx.warn("{s}: cannot strip: its debug sections or symbol table are not at the end of the image (a layout rzig's strip does not rewrite)", .{f});
                code = 1;
                continue;
            },
            .archive => stripArchive(ctx, f, d, dest) catch |err| {
                ctx.warn("{s}: cannot strip: {t}", .{ f, err });
                code = 1;
                continue;
            },
            .short_import => null,
            .other => {
                ctx.warn("{s}: file format not recognized", .{f});
                code = 1;
                continue;
            },
        };
        const bytes = new orelse if (output != null and kindOf(d) != .archive) d else continue;
        Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = dest, .data = bytes }) catch |err| {
            ctx.warn("cannot write {s}: {t}", .{ dest, err });
            code = 1;
        };
    }
    return code;
}

/// An archive's members stripped, written into a directory beside `dest`
/// and archived again in their order by `zig ar crs` (a new symbol index),
/// then renamed over `dest`. null when no member had anything to strip
/// (and dest is the archive itself).
fn stripArchive(ctx: *Ctx, src: []const u8, d: []const u8, dest: []const u8) !?[]const u8 {
    const a = ctx.arena;
    const ms = try members(a, d);
    var changed = false;
    var datas = try a.alloc([]const u8, ms.len);
    for (ms, 0..) |m, i| {
        datas[i] = m.data;
        if (kindOf(m.data) != .object) continue;
        const c = try Coff.parse(a, m.data);
        if (try stripObject(a, c)) |s| {
            datas[i] = s;
            changed = true;
        }
    }
    if (!changed) {
        if (!mem.eql(u8, src, dest)) return d;
        return null;
    }
    const zig = ctx.zig orelse return error.NoZig;
    const tmp = try std.fmt.allocPrint(a, "{s}.rzig-strip", .{dest});
    Io.Dir.cwd().deleteTree(ctx.io, tmp) catch {};
    try Io.Dir.cwd().createDirPath(ctx.io, tmp);
    defer Io.Dir.cwd().deleteTree(ctx.io, tmp) catch {};
    const out_ar = try std.fmt.allocPrint(a, "{s}/out.a", .{tmp});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, zig);
    try argv.appendSlice(a, &.{ "ar", "crs", out_ar });
    for (ms, datas, 0..) |m, x, i| {
        // one directory per member: two members may share a name
        const sub = try std.fmt.allocPrint(a, "{s}/{d}", .{ tmp, i });
        try Io.Dir.cwd().createDirPath(ctx.io, sub);
        const p = try std.fmt.allocPrint(a, "{s}/{s}", .{ sub, std.fs.path.basename(m.name) });
        try Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = p, .data = x });
        try argv.append(a, p);
    }
    if (!ctx.succeeds(argv.items)) return error.ZigArFailed;
    return try Io.Dir.cwd().readFileAlloc(ctx.io, out_ar, a, .limited(1 << 30));
}

// --- dlltool, windres, as: zig commands -------------------------------

/// The value of `-x v`, `-xv`, `--long v` or `--long=v` at args[i.*].
fn optValue(args: []const []const u8, i: *usize, short: ?[]const u8, long: ?[]const u8) ?[]const u8 {
    const x = args[i.*];
    if (long) |l| {
        if (mem.eql(u8, x, l)) {
            if (i.* + 1 >= args.len) return null;
            i.* += 1;
            return args[i.*];
        }
        if (mem.startsWith(u8, x, l) and x.len > l.len and x[l.len] == '=') return x[l.len + 1 ..];
    }
    if (short) |s| {
        if (mem.eql(u8, x, s)) {
            if (i.* + 1 >= args.len) return null;
            i.* += 1;
            return args[i.*];
        }
        if (mem.startsWith(u8, x, s) and x.len > s.len and x[1] != '-') return x[s.len..];
    }
    return null;
}

fn isOpt(x: []const u8, short: ?[]const u8, long: ?[]const u8) bool {
    if (long) |l| if (mem.eql(u8, x, l) or (mem.startsWith(u8, x, l) and x.len > l.len and x[l.len] == '=')) return true;
    if (short) |s| if (mem.startsWith(u8, x, s) and (x.len == s.len or x[1] != '-')) return true;
    return false;
}

pub const Usage = error{Usage};

/// `zig dlltool` (llvm-dlltool) for GNU dlltool's arguments.
pub fn dlltoolArgv(ctx: *Ctx, args: []const []const u8) ![]const []const u8 {
    const a = ctx.arena;
    var out: std.ArrayList([]const u8) = .empty;
    try out.append(a, "dlltool");
    var machine: []const u8 = Machine.own.dlltool();
    var have_lib = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (isOpt(x, "-d", "--input-def") or isOpt(x, null, "--def")) {
            // --def: GNU dlltool's other name for it (its long_options)
            const long = if (isOpt(x, null, "--def")) "--def" else "--input-def";
            try out.appendSlice(a, &.{ "-d", optValue(args, &i, "-d", long) orelse return usage(ctx, "--input-def needs a file") });
        } else if (isOpt(x, "-l", "--output-lib")) {
            try out.appendSlice(a, &.{ "-l", optValue(args, &i, "-l", "--output-lib") orelse return usage(ctx, "--output-lib needs a file") });
            have_lib = true;
        } else if (isOpt(x, "-D", "--dllname")) {
            try out.appendSlice(a, &.{ "-D", optValue(args, &i, "-D", "--dllname") orelse return usage(ctx, "--dllname needs a name") });
        } else if (isOpt(x, "-m", "--machine")) {
            const m = optValue(args, &i, "-m", "--machine") orelse return usage(ctx, "--machine needs a value");
            machine = if (mem.eql(u8, m, "i386:x86-64") or mem.eql(u8, m, "x86_64") or mem.eql(u8, m, "x64")) "i386:x86-64" else if (mem.eql(u8, m, "arm64") or mem.eql(u8, m, "aarch64")) "arm64" else m;
        } else if (mem.eql(u8, x, "-k") or mem.eql(u8, x, "--kill-at")) {
            try out.append(a, "-k");
        } else if (isOpt(x, "-S", "--as") or isOpt(x, "-f", "--as-flags") or isOpt(x, "-t", "--temp-prefix")) {
            // the assembler and its flags: llvm-dlltool writes the
            // library itself
            const takes_value = mem.eql(u8, x, "-S") or mem.eql(u8, x, "--as") or mem.eql(u8, x, "-f") or mem.eql(u8, x, "--as-flags") or mem.eql(u8, x, "-t") or mem.eql(u8, x, "--temp-prefix");
            if (takes_value) i += 1;
        } else if (mem.eql(u8, x, "--no-leading-underscore") or mem.eql(u8, x, "-U") or mem.eql(u8, x, "--add-underscore") or
            mem.eql(u8, x, "-A") or mem.eql(u8, x, "--add-stdcall-alias") or mem.eql(u8, x, "-v") or mem.eql(u8, x, "--verbose") or
            mem.eql(u8, x, "--no-delete") or mem.eql(u8, x, "-n"))
        {
            // leading underscores are i386's, which rzig does not target
        } else if (mem.eql(u8, x, "--version")) {
            stdio.writeAll(ctx.io, .stdout(), "GNU-compatible dlltool (rzig, zig dlltool, " ++ build_name ++ ")\n") catch {};
            return error.Usage;
        } else {
            return usage(ctx, try ctx.fmt("unsupported argument {s} (rzig's dlltool: --input-def, --output-lib, --dllname, -k, -m; --as and its flags are ignored)", .{x}));
        }
    }
    if (!have_lib) return usage(ctx, "no --output-lib: rzig's dlltool writes import libraries only");
    try out.appendSlice(a, &.{ "-m", machine });
    return out.items;
}

fn usage(ctx: *Ctx, msg: []const u8) Usage {
    ctx.warn("{s}", .{msg});
    return error.Usage;
}

/// `zig rc` for GNU windres' arguments.
pub fn windresArgv(ctx: *Ctx, args: []const []const u8) ![]const []const u8 {
    const a = ctx.arena;
    var opts: std.ArrayList([]const u8) = .empty;
    var input: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var out_format: ?[]const u8 = null;
    var in_format: ?[]const u8 = null;
    var target: []const u8 = Machine.own.rc();
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (x.len < 2 or x[0] != '-') {
            if (input == null) input = x else if (output == null) output = x else return usage(ctx, try ctx.fmt("one input and one output, not also {s}", .{x}));
        } else if (isOpt(x, "-i", "--input")) {
            input = optValue(args, &i, "-i", "--input") orelse return usage(ctx, "--input needs a file");
        } else if (isOpt(x, "-o", "--output")) {
            output = optValue(args, &i, "-o", "--output") orelse return usage(ctx, "--output needs a file");
        } else if (isOpt(x, "-O", "--output-format")) {
            out_format = optValue(args, &i, "-O", "--output-format") orelse return usage(ctx, "--output-format needs a value");
        } else if (isOpt(x, "-J", "--input-format")) {
            in_format = optValue(args, &i, "-J", "--input-format") orelse return usage(ctx, "--input-format needs a value");
        } else if (isOpt(x, "-F", "--target")) {
            const t = optValue(args, &i, "-F", "--target") orelse return usage(ctx, "--target needs a value");
            if (mem.find(u8, t, "x86-64") != null or mem.find(u8, t, "x86_64") != null) target = "x64" else if (mem.find(u8, t, "aarch64") != null or mem.find(u8, t, "arm64") != null) target = "arm64" else if (mem.find(u8, t, "i386") != null) target = "x86";
        } else if (isOpt(x, "-I", "--include-dir")) {
            try opts.appendSlice(a, &.{ "/i", optValue(args, &i, "-I", "--include-dir") orelse return usage(ctx, "--include-dir needs a directory") });
        } else if (isOpt(x, "-D", "--define")) {
            try opts.appendSlice(a, &.{ "/d", optValue(args, &i, "-D", "--define") orelse return usage(ctx, "--define needs a symbol") });
        } else if (isOpt(x, "-U", "--undefine")) {
            try opts.appendSlice(a, &.{ "/u", optValue(args, &i, "-U", "--undefine") orelse return usage(ctx, "--undefine needs a symbol") });
        } else if (isOpt(x, "-l", "--language")) {
            const l = optValue(args, &i, "-l", "--language") orelse return usage(ctx, "--language needs a value");
            try opts.appendSlice(a, &.{ "/l", if (mem.startsWith(u8, l, "0x")) l[2..] else l });
        } else if (isOpt(x, "-c", "--codepage")) {
            const cp = optValue(args, &i, "-c", "--codepage") orelse return usage(ctx, "--codepage needs a value");
            try opts.appendSlice(a, &.{ "/c", cp });
        } else if (mem.eql(u8, x, "--preprocessor") or mem.eql(u8, x, "--preprocessor-arg")) {
            // zig rc preprocesses itself, with RC_INVOKED defined
            i += 1;
        } else if (mem.startsWith(u8, x, "--preprocessor=") or mem.startsWith(u8, x, "--preprocessor-arg=") or
            mem.eql(u8, x, "--use-temp-file") or mem.eql(u8, x, "--no-use-temp-file") or mem.eql(u8, x, "-v") or mem.eql(u8, x, "--verbose"))
        {} else if (mem.eql(u8, x, "--version")) {
            stdio.writeAll(ctx.io, .stdout(), "GNU-compatible windres (rzig, zig rc, " ++ build_name ++ ")\n") catch {};
            return error.Usage;
        } else {
            return usage(ctx, try ctx.fmt("unsupported argument {s} (rzig's windres: -i, -o, -O, -J, -F, -I, -D, -U, -l, -c)", .{x}));
        }
    }
    const in = input orelse return usage(ctx, "no input file (rzig's windres reads a .rc file, not stdin)");
    const out = output orelse return usage(ctx, "no output file (rzig's windres writes a file, not stdout)");
    const fmt_name = out_format orelse if (std.ascii.endsWithIgnoreCase(out, ".res")) "res" else "coff";
    const zig_format = if (std.ascii.eqlIgnoreCase(fmt_name, "coff")) "coff" else if (std.ascii.eqlIgnoreCase(fmt_name, "res")) "res" else return usage(ctx, try ctx.fmt("output format {s}: rzig's windres writes coff or res", .{fmt_name}));
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "rc", "/:output-format", zig_format, "/:target", target, "/:auto-includes", "gnu" });
    if (in_format) |f| {
        if (std.ascii.eqlIgnoreCase(f, "res")) try argv.appendSlice(a, &.{ "/:input-format", "res" }) else if (!std.ascii.eqlIgnoreCase(f, "rc")) return usage(ctx, try ctx.fmt("input format {s}: rzig's windres reads rc or res", .{f}));
    }
    try argv.appendSlice(a, opts.items);
    try argv.appendSlice(a, &.{ "/fo", out, "--", in });
    return argv.items;
}

/// `zig cc -c -x assembler` for GNU as' arguments.
pub fn asArgv(ctx: *Ctx, args: []const []const u8) ![]const []const u8 {
    const a = ctx.arena;
    var out_file: []const u8 = "a.out";
    var inputs: std.ArrayList([]const u8) = .empty;
    var incs: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (x.len < 2 or x[0] != '-') {
            try inputs.append(a, x);
        } else if (isOpt(x, "-o", null)) {
            out_file = optValue(args, &i, "-o", null) orelse return usage(ctx, "-o needs a file");
        } else if (isOpt(x, "-I", null)) {
            try incs.appendSlice(a, &.{ "-I", optValue(args, &i, "-I", null) orelse return usage(ctx, "-I needs a directory") });
        } else if (mem.eql(u8, x, "--64") or mem.eql(u8, x, "--32") or mem.eql(u8, x, "-W") or mem.eql(u8, x, "--no-warn") or mem.eql(u8, x, "-g") or mem.eql(u8, x, "--gdwarf-2")) {} else if (mem.eql(u8, x, "--version")) {
            stdio.writeAll(ctx.io, .stdout(), "GNU-compatible as (rzig, zig cc, " ++ build_name ++ ")\n") catch {};
            return error.Usage;
        } else {
            return usage(ctx, try ctx.fmt("unsupported option {s} (rzig's as: -o, -I)", .{x}));
        }
    }
    if (inputs.items.len != 1) return usage(ctx, "rzig's as assembles one .s file");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "cc", "-c", "-x", "assembler" });
    try argv.appendSlice(a, incs.items);
    try argv.appendSlice(a, &.{ inputs.items[0], "-o", out_file });
    return argv.items;
}

/// A bigobj object for tests (def.zig's too): 70,000 empty code sections,
/// then EXTERNAL symbols `first` (section 1), `past_u16` (66,000; a section
/// number a regular object's u16 cannot hold), `last` (70,000), a static
/// `local_fn`, an undefined `undef`, a weak external `weak_fn`
/// (section 0, an aux record), and `long_name_in_the_string_table` (section
/// 2): 20-byte records, a string table.
pub fn bigobjFixture(a: mem.Allocator, machine: u16) ![]u8 {
    const n: u32 = 70_000;
    const Rec = struct { name: []const u8, section: u32, class: u8, naux: u8 = 0 };
    const recs = [_]Rec{
        .{ .name = "first", .section = 1, .class = class_external },
        .{ .name = "past_u16", .section = 66_000, .class = class_external },
        .{ .name = "last", .section = n, .class = class_external },
        .{ .name = "local_fn", .section = 3, .class = class_static },
        .{ .name = "undef", .section = 0, .class = class_external },
        .{ .name = "weak_fn", .section = 0, .class = class_weak_external, .naux = 1 },
        .{ .name = "long_name_in_the_string_table", .section = 2, .class = class_external },
    };
    var nrec: u32 = 0;
    for (recs) |r| nrec += 1 + r.naux;
    const long = "long_name_in_the_string_table";
    const symtab: u32 = bigobj_header + n * 40;
    const strtab_size: u32 = 4 + long.len + 1;
    const d = try a.alloc(u8, symtab + nrec * 20 + strtab_size);
    @memset(d, 0);
    mem.writeInt(u16, d[2..4], 0xffff, .little);
    mem.writeInt(u16, d[4..6], 2, .little); // version
    mem.writeInt(u16, d[6..8], machine, .little);
    @memcpy(d[12..28], &bigobj_class);
    mem.writeInt(u32, d[44..48], n, .little);
    mem.writeInt(u32, d[48..52], symtab, .little);
    mem.writeInt(u32, d[52..56], nrec, .little);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const h = d[bigobj_header + i * 40 ..][0..40];
        @memcpy(h[0..5], ".text");
        mem.writeInt(u32, h[36..40], 0x60000020, .little); // CNT_CODE, MEM_EXECUTE, MEM_READ
    }
    var at: usize = symtab;
    for (recs) |r| {
        const rec = d[at..][0..20];
        if (r.name.len <= 8) @memcpy(rec[0..r.name.len], r.name) else mem.writeInt(u32, rec[4..8], 4, .little);
        mem.writeInt(u32, rec[12..16], r.section, .little);
        rec[18] = r.class;
        rec[19] = r.naux;
        at += 20 * (1 + @as(usize, r.naux));
    }
    mem.writeInt(u32, d[at..][0..4], strtab_size, .little);
    @memcpy(d[at + 4 ..][0..long.len], long);
    return d;
}

// --- tests ------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

// testdata/win-syms.c compiled with `zig cc -target x86_64-windows-gnu -O2 -c`
const win_syms = @embedFile("testdata/win-syms.o");
// testdata/bu.c: `zig cc -target <t> -g0 -O2 -c` (bu-x64.o, bu-arm64.o)
// and -shared (bu-x64.dll, bu-arm64.dll; imports printf from the CRT);
// bu-x64-g.o with -g (its .debug$S and .debug$T)
const bu_x64_o = @embedFile("testdata/bu-x64.o");
// testdata/bu-dwarf.c: `zig cc -target <t> -gdwarf-4 -O1 -shared -nostdlib
// -Wl,--entry=DllMainCRTStartup` (bu-x64-dwarf.dll, bu-arm64-dwarf.dll):
// lld places the .debug_* sections last, mapped
const bu_x64_dwarf_dll = @embedFile("testdata/bu-x64-dwarf.dll");
const bu_arm64_dwarf_dll = @embedFile("testdata/bu-arm64-dwarf.dll");
const bu_arm64_o = @embedFile("testdata/bu-arm64.o");
const bu_x64_g_o = @embedFile("testdata/bu-x64-g.o");
const bu_x64_dll = @embedFile("testdata/bu-x64.dll");
const bu_arm64_dll = @embedFile("testdata/bu-arm64.dll");
// `zig dlltool -m i386:x86-64 -D bu.dll -d bu.def -l libbu.dll.a`
const bu_implib = @embedFile("testdata/libbu.dll.a");
// `zig rc /:output-format coff /:target x64 bu.rc bu-res.o`
const bu_res_o = @embedFile("testdata/bu-res.o");

fn nmText(f: *testutil.Fixture, args: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try testing.expectEqual(0, try nm(&f.ctx, args, &out));
    return out.items;
}

test "nm: GNU's letters for a COFF object, sorted, BSD and POSIX formats" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.write("w.o", win_syms, .default_file);
    const bsd = try nmText(&f, &.{f.path("w.o")});
    // def.zig's set: [BCDRT] and external
    for ([_][]const u8{ " B exported_bss\n", " D exported_data\n", " T exported_fn\n", " R exported_rodata\n", " T uses_locals\n", " w weak_fn\n", " U strlen\n", " U imported_var\n" }) |l| {
        if (mem.find(u8, bsd, l) == null) {
            std.debug.print("missing {s} in\n{s}", .{ l, bsd });
            return error.TestExpectedEqual;
        }
    }
    // weak_fn is a WEAK_EXTERNAL with section 0 (its default in an aux
    // record): weak and undefined, `w`, as BFD decodes it
    // a defined one's value in 16 hex digits, an undefined one's blank
    const blank16 = "                ";
    try testing.expect(mem.find(u8, bsd, "\n" ++ blank16 ++ " U strlen\n") != null or mem.startsWith(u8, bsd, blank16 ++ " U"));
    // winshlib.mk's sed sees the same names as rzig def does
    var sed: std.ArrayList([]const u8) = .empty;
    var lines = mem.splitScalar(u8, bsd, '\n');
    while (lines.next()) |l| {
        if (l.len < 19) continue;
        if (mem.findScalar(u8, "BCDRT", l[17]) != null and l[18] == ' ') {
            const n = l[19..];
            if (mem.find(u8, n, ".refptr.") == null and mem.find(u8, n, ".weak.") == null) try sed.append(f.ctx.arena, n);
        }
    }
    var defs: std.ArrayList([]const u8) = .empty;
    try @import("def.zig").exports(f.ctx.arena, win_syms, &defs);
    try testing.expectEqual(defs.items.len, sed.items.len);
    // -Pg: sotools.R's columns, externals only
    const posix = try nmText(&f, &.{ "-Pg", f.path("w.o") });
    try testing.expect(mem.find(u8, posix, "exported_fn T 0000000000000000\n") != null or mem.find(u8, posix, "exported_fn T ") != null);
    try testing.expect(mem.find(u8, posix, "strlen U\n") != null);
    var pl = mem.splitScalar(u8, posix, '\n');
    while (pl.next()) |l| {
        if (l.len == 0) continue;
        var w = mem.tokenizeScalar(u8, l, ' ');
        _ = w.next();
        const letter = w.next().?;
        try testing.expect(std.ascii.isUpper(letter[0]) or letter[0] == 'w');
    }
    // -u: undefined only; -p: table order
    const u = try nmText(&f, &.{ "-u", f.path("w.o") });
    var ul = mem.splitScalar(u8, u, '\n');
    while (ul.next()) |l| if (l.len > 0) try testing.expect(mem.find(u8, l, " U ") != null or mem.find(u8, l, " w ") != null);
    try testing.expect(mem.find(u8, u, " w weak_fn\n") != null);
}

test "nm: aarch64 objects, archives with member headers, import libraries' __imp_ symbols" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.write("a.o", bu_arm64_o, .default_file);
    try testing.expect(mem.find(u8, try nmText(&f, &.{f.path("a.o")}), " T bu_answer\n") != null);
    try f.write("libbu.dll.a", bu_implib, .default_file);
    const imp = try nmText(&f, &.{f.path("libbu.dll.a")});
    try testing.expect(mem.find(u8, imp, " I __imp_bu_answer\n") != null);
    try testing.expect(mem.find(u8, imp, " T bu_answer\n") != null);
    try testing.expect(mem.find(u8, imp, "\nbu.dll:\n") != null);
}

test "objdump -p: the import and export tables as sotools.R reads them, x86_64 and aarch64" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    for ([_][]const u8{ bu_x64_dll, bu_arm64_dll }, [_][]const u8{ "pei-x86-64", "pei-aarch64-little" }) |dll, fmt_name| {
        try f.write("bu.dll", dll, .default_file);
        var out: std.ArrayList(u8) = .empty;
        try testing.expectEqual(0, try objdump(&f.ctx, &.{ "-x", f.path("bu.dll") }, &out));
        const s = out.items;
        try testing.expect(mem.find(u8, s, fmt_name) != null);
        // read_symbols_from_dll: lines from the first DLL Name + 2 to "The
        // Export Tables" - 4, their last word where "\t<hex>" starts it
        var lines: std.ArrayList([]const u8) = .empty;
        var it = mem.splitScalar(u8, s, '\n');
        while (it.next()) |l| try lines.append(f.ctx.arena, l);
        var l1: ?usize = null;
        var l2: ?usize = null;
        for (lines.items, 0..) |l, i| {
            if (l1 == null and mem.startsWith(u8, l, "\tDLL Name:")) l1 = i;
            if (mem.startsWith(u8, l, "The Export Tables")) l2 = i;
        }
        try testing.expect(l1 != null and l2 != null and l1.? < l2.?);
        var names: std.ArrayList([]const u8) = .empty;
        for (lines.items[l1.? + 2 .. l2.? - 3]) |l| {
            if (l.len < 2 or l[0] != '\t' or !std.ascii.isHex(l[1])) continue;
            const sp = mem.findScalarLast(u8, l, ' ') orelse continue;
            try names.append(f.ctx.arena, l[sp + 1 ..]);
        }
        var printf = false;
        for (names.items) |n| if (mem.eql(u8, n, "printf") or mem.eql(u8, n, "__stdio_common_vfprintf") or mem.eql(u8, n, "__acrt_iob_func")) {
            printf = true;
        };
        if (!printf) {
            std.debug.print("{s}\n", .{s});
            return error.TestExpectedEqual;
        }
        // the export itself
        try testing.expect(mem.find(u8, s, "] bu_answer\n") != null);
        try testing.expect(mem.find(u8, s, "\tDLL Name: ") != null);
    }
}

test "objdump -h: a windres (zig rc) object's .rsrc section; an object's sections" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.write("r.o", bu_res_o, .default_file);
    var out: std.ArrayList(u8) = .empty;
    try testing.expectEqual(0, try objdump(&f.ctx, &.{ "-h", f.path("r.o") }, &out));
    try testing.expect(mem.find(u8, out.items, ".rsrc") != null);
    try testing.expect(mem.find(u8, out.items, "pe-x86-64") != null);
}

test "strip: an object's debug sections go, its code and symbols stay; a zig DLL is left as it is" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const a = f.ctx.arena;
    const c = try Coff.parse(a, bu_x64_g_o);
    const s = (try stripObject(a, c)).?;
    try testing.expect(s.len < bu_x64_g_o.len);
    const c2 = try Coff.parse(a, s);
    try testing.expectEqual(c.sections.len, c2.sections.len);
    for (c2.sections) |sec| if (sec.isDebug()) try testing.expectEqual(0, sec.raw_size);
    // same symbols, and the code's bytes
    var s1: std.ArrayList(Sym) = .empty;
    var s2: std.ArrayList(Sym) = .empty;
    try objectSymbols(a, c, &s1);
    try objectSymbols(a, c2, &s2);
    try testing.expectEqual(s1.items.len, s2.items.len);
    for (s1.items, s2.items) |x, y| try testing.expectEqualStrings(x.name, y.name);
    for (c.sections, c2.sections) |x, y| if (!x.isDebug() and x.raw_size != 0 and x.flags & Section.bss == 0)
        try testing.expectEqualSlices(u8, bu_x64_g_o[x.raw_ptr..][0..x.raw_size], s[y.raw_ptr..][0..y.raw_size]);
    // stripping again changes nothing
    try testing.expect(try stripObject(a, c2) == null);
    // zig's DLLs: no symbol table, no debug sections
    try testing.expect(try stripImage(a, try Coff.parse(a, bu_x64_dll)) == null);
    try testing.expect(try stripImage(a, try Coff.parse(a, bu_arm64_dll)) == null);
    // through the command: in place, then nm still reads it
    try f.write("g.o", bu_x64_g_o, .default_file);
    try testing.expectEqual(0, try strip(&f.ctx, &.{ "--strip-debug", f.path("g.o") }));
    try testing.expect(mem.find(u8, try nmText(&f, &.{f.path("g.o")}), " T bu_answer\n") != null);
    const after = try f.tmp.dir.readFileAlloc(testing.io, "g.o", a, .limited(1 << 20));
    try testing.expectEqual(s.len, after.len);
}

test "dlltool: GNU's options as zig dlltool's, the machine rzig's own" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const m = Machine.own.dlltool();
    try expectArgs(&.{ "dlltool", "-k", "-D", "R.dll", "-d", "R.def", "-l", "libR.dll.a", "-m", m }, try dlltoolArgv(&f.ctx, &.{ "--as", "C:/tc/as.exe", "-k", "--dllname", "R.dll", "--input-def", "R.def", "--output-lib", "libR.dll.a" }));
    try expectArgs(&.{ "dlltool", "-D", "x.dll", "-d", "x.def", "-l", "libx.dll.a", "-m", "arm64" }, try dlltoolArgv(&f.ctx, &.{ "--dllname=x.dll", "--input-def=x.def", "--output-lib=libx.dll.a", "-m", "aarch64" }));
    try expectArgs(&.{ "dlltool", "-d", "y.def", "-l", "liby.dll.a", "-m", m }, try dlltoolArgv(&f.ctx, &.{ "--def", "y.def", "-l", "liby.dll.a" }));
    try testing.expectError(error.Usage, dlltoolArgv(&f.ctx, &.{ "--input-def", "x.def", "--output-exp", "x.exp" }));
    try testing.expectError(error.Usage, dlltoolArgv(&f.ctx, &.{ "--input-def", "x.def" }));
    _ = f.takeWarnings();
}

test "windres: GNU's options as zig rc's, the gcc preprocessor dropped" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const t = Machine.own.rc();
    // Makeconf.win's %.o: %.rc rule and R's RCFLAGS of before
    try expectArgs(&.{ "rc", "/:output-format", "coff", "/:target", t, "/:auto-includes", "gnu", "/fo", "r.o", "--", "r.rc" }, try windresArgv(&f.ctx, &.{ "--preprocessor=C:/tc/gcc.exe", "--preprocessor-arg=-E", "--preprocessor-arg=-xc", "--preprocessor-arg=-DRC_INVOKED", "-i", "r.rc", "-o", "r.o" }));
    // CMake's: -O coff, defines, includes, then the source and the object
    try expectArgs(&.{ "rc", "/:output-format", "coff", "/:target", t, "/:auto-includes", "gnu", "/d", "TBB=1", "/i", "C:/x y/include", "/fo", "obj/r.rc.obj", "--", "src/r.rc" }, try windresArgv(&f.ctx, &.{ "-O", "coff", "-DTBB=1", "-I", "C:/x y/include", "src/r.rc", "obj/r.rc.obj" }));
    // a .res output; a target; a language in hex
    try expectArgs(&.{ "rc", "/:output-format", "res", "/:target", "arm64", "/:auto-includes", "gnu", "/l", "409", "/fo", "r.res", "--", "r.rc" }, try windresArgv(&f.ctx, &.{ "-F", "pe-aarch64-little", "-l", "0x409", "--input=r.rc", "--output=r.res" }));
    try testing.expectError(error.Usage, windresArgv(&f.ctx, &.{"r.rc"}));
    try testing.expectError(error.Usage, windresArgv(&f.ctx, &.{ "-O", "rc", "r.rc", "r.txt" }));
    _ = f.takeWarnings();
}

test "as: zig cc -c -x assembler" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try expectArgs(&.{ "cc", "-c", "-x", "assembler", "-I", "inc", "a.s", "-o", "a.o" }, try asArgv(&f.ctx, &.{ "--64", "-Iinc", "-o", "a.o", "a.s" }));
    try testing.expectError(error.Usage, asArgv(&f.ctx, &.{ "a.s", "b.s" }));
    _ = f.takeWarnings();
}

test "bigobj: nm reads it as GNU nm does (symbols past section 65,535), objdump -h, strip a debug section" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const a = f.ctx.arena;
    const big = try bigobjFixture(a, 0x8664);
    try testing.expectEqual(Kind.object, kindOf(big));
    try f.write("big.o", big, .default_file);
    const t = try nmText(&f, &.{ "-P", f.path("big.o") });
    for ([_][]const u8{ "first T 0000000000000000\n", "past_u16 T 0000000000000000\n", "last T 0000000000000000\n", "local_fn t 0000000000000000\n", "undef U\n", "weak_fn w\n", "long_name_in_the_string_table T 0000000000000000\n" }) |l| {
        if (mem.find(u8, t, l) == null) {
            std.debug.print("missing {s} in\n{s}", .{ l, t });
            return error.TestExpectedEqual;
        }
    }
    try testing.expect(mem.find(u8, t, "__imp_") == null);
    // aarch64's too
    const big_arm = try bigobjFixture(a, 0xaa64);
    const c_arm = try Coff.parse(a, big_arm);
    try testing.expectEqual(Machine.aarch64, c_arm.machine);
    // strip: a debug section's contents go, the symbols stay where they were
    const dbg = try a.dupe(u8, big);
    const h = dbg[bigobj_header + 5 * 40 ..][0..40];
    @memset(h[0..8], 0);
    @memcpy(h[0..8], ".debug_x");
    // its contents: the string table's first 4 bytes stand in
    const c0 = try Coff.parse(a, dbg);
    mem.writeInt(u32, h[16..20], 4, .little);
    mem.writeInt(u32, h[20..24], @intCast(@as(usize, c0.symtab) + @as(usize, c0.nsyms) * 20), .little);
    const stripped = (try stripObject(a, try Coff.parse(a, dbg))).?;
    const c1 = try Coff.parse(a, stripped);
    try testing.expect(c1.bigobj);
    try testing.expectEqual(@as(u32, 0), c1.sections[5].raw_size);
    try testing.expect(c1.sections[5].flags & Section.lnk_remove != 0);
    var syms: std.ArrayList(Sym) = .empty;
    try objectSymbols(a, c1, &syms);
    try testing.expectEqual(@as(usize, 7), syms.items.len);
    // a short import object (version 0) stays one
    var imp: [24]u8 = @splat(0);
    mem.writeInt(u16, imp[2..4], 0xffff, .little);
    try testing.expectEqual(Kind.short_import, kindOf(&imp));
    mem.writeInt(u16, imp[4..6], 1, .little);
    try testing.expectEqual(Kind.other, kindOf(&imp));
}

test "archive: llvm-ar's COFF long-name table ends a name with a NUL" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: std.ArrayList(u8) = .empty;
    try d.appendSlice(a, ar_magic);
    const names = "longname_member_with_long_name-g.o\x00other_long_member_name.o\x00";
    try d.print(a, "{s: <16}{s: <12}{s: <6}{s: <6}{s: <8}{d: <10}`\n", .{ "//", "0", "0", "0", "0", names.len });
    try d.appendSlice(a, names);
    if (names.len & 1 == 1) try d.append(a, '\n');
    try d.print(a, "{s: <16}{s: <12}{s: <6}{s: <6}{s: <8}{d: <10}`\n", .{ "/0", "0", "0", "0", "644", 2 });
    try d.appendSlice(a, "ab");
    try d.print(a, "{s: <16}{s: <12}{s: <6}{s: <6}{s: <8}{d: <10}`\n", .{ "/35", "0", "0", "0", "644", 2 });
    try d.appendSlice(a, "cd");
    const ms = try members(a, d.items);
    try testing.expectEqual(@as(usize, 2), ms.len);
    try testing.expectEqualStrings("longname_member_with_long_name-g.o", ms[0].name);
    try testing.expectEqualStrings("other_long_member_name.o", ms[1].name);
}

test "nm: -f/--format with a separate value, --plugin's value, GNU's headers for one and many files" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    try f.write("w.o", win_syms, .default_file);
    try f.write("libbu.a", bu_implib, .default_file);
    const p = try nmText(&f, &.{ "-P", f.path("w.o") });
    for ([_][]const []const u8{
        &.{ "-f", "posix", f.path("w.o") },
        &.{ "--format", "posix", f.path("w.o") },
        &.{ "--format=posix", f.path("w.o") },
        &.{ "-fposix", f.path("w.o") },
        &.{ "-gf", "p", "--plugin", "/x/liblto_plugin.so", f.path("w.o") },
    }, 0..) |args, k| {
        const t = try nmText(&f, args);
        if (k < 4) try testing.expectEqualStrings(p, t) else try testing.expect(mem.find(u8, t, "liblto") == null and t.len > 0);
    }
    // one file: no header; two: each file's
    try testing.expect(!mem.startsWith(u8, try nmText(&f, &.{f.path("w.o")}), "\n"));
    const two = try nmText(&f, &.{ f.path("w.o"), f.path("w.o") });
    try testing.expect(mem.startsWith(u8, two, f.fmt("\n{s}:\n", .{f.path("w.o")})));
    // an archive alone: its members' headers, not its own
    const one_ar = try nmText(&f, &.{f.path("libbu.a")});
    try testing.expect(mem.find(u8, one_ar, f.fmt("{s}:", .{f.path("libbu.a")})) == null);
    try testing.expect(mem.startsWith(u8, one_ar, "\n"));
    // POSIX with two files: <archive>[<member>]:
    const two_p = try nmText(&f, &.{ "-P", f.path("libbu.a"), f.path("w.o") });
    try testing.expect(mem.find(u8, two_p, f.fmt("{s}[", .{f.path("libbu.a")})) != null);
    // -A: the prefix GNU writes, <archive>:<member>: (BSD)
    const pre = try nmText(&f, &.{ "-A", f.path("libbu.a") });
    try testing.expect(mem.startsWith(u8, pre, f.fmt("{s}:", .{f.path("libbu.a")})));
    _ = f.takeWarnings();
}

test "strip: an image's DWARF sections go (the last ones), its exports and layout stay" {
    var f: testutil.Fixture = undefined;
    try f.init(.windows);
    defer f.deinit();
    const a = f.ctx.arena;
    for ([_][]const u8{ bu_x64_dwarf_dll, bu_arm64_dwarf_dll }) |dll| {
        const c = try Coff.parse(a, dll);
        var ndebug: usize = 0;
        for (c.sections) |sec| {
            if (sec.isDebug()) ndebug += 1;
        }
        try testing.expect(ndebug > 0);
        const s = (try stripImage(a, c)).?;
        try testing.expect(s.len < dll.len);
        const c2 = try Coff.parse(a, s);
        try testing.expectEqual(c.sections.len - ndebug, c2.sections.len);
        for (c2.sections) |sec| try testing.expect(!sec.isDebug());
        // the kept sections' headers and bytes as they were
        for (c2.sections, c.sections[0..c2.sections.len]) |y, x| {
            try testing.expectEqual(x.va, y.va);
            try testing.expectEqual(x.raw_ptr, y.raw_ptr);
            try testing.expectEqualSlices(u8, dll[x.raw_ptr..][0..x.raw_size], s[y.raw_ptr..][0..y.raw_size]);
        }
        // SizeOfImage: the last kept section's end, SectionAlignment-aligned
        const opt = c2.hdr + 20;
        const last = c2.sections[c2.sections.len - 1];
        const sect_align = try rd32(s, opt + 32);
        try testing.expectEqual(@as(u32, @intCast(mem.alignForward(u64, @as(u64, last.va) + @max(last.vsize, last.raw_size), sect_align))), try rd32(s, opt + 56));
        // the exports objdump -p shows (sotools.R)
        var out: std.ArrayList(u8) = .empty;
        try objdumpFile(a, c2, .{ .private = true }, &out);
        try testing.expect(mem.find(u8, out.items, "] dbgf\n") != null);
        // stripping again: nothing to do
        try testing.expect(try stripImage(a, c2) == null);
        // a kept section after a debug one: not rewritten
        if (ndebug >= 2) {
            const bad = try a.dupe(u8, dll);
            // the last section, a debug one, renamed: a kept section after
            // the other debug ones
            const h = c.sec_off + (c.sections.len - 1) * 40;
            @memcpy(bad[h..][0..8], ".rdata\x00\x00");
            try testing.expectError(error.BadFile, stripImage(a, try Coff.parse(a, bad)));
        }
    }
}
