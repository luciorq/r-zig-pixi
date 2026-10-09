//! Linux links: -Wl,--strip-debug when nothing asks for debug info
//! (stress round 2, Z10's residual; R2-3). zig builds its own libc++,
//! libc++abi and libunwind with DWARF whatever the caller asks: 4 to 6 MB
//! in every linux C++ package (fstcore, Rcpp, mlpack, duckdb, arrow),
//! which compiler.zig's -g0 cannot reach. Nothing asks for debug info
//! when:
//!   - the command has no -g option (cmdline.debugOption; -g0 counts), and
//!   - none of its input objects has any: no input named *.o is an ELF
//!     relocatable object with a .debug_info section (or .zdebug_info,
//!     the old compressed form). Every -g gives one; other .debug_*
//!     sections alone are no debug info: Boost's headers put a gdb script
//!     in .debug_gdb_scripts in every object that includes
//!     Boost.Unordered, Interprocess or JSON (BH 1.90), and an assembler's
//!     `.cfi_sections .debug_frame` makes a .debug_frame.
//! The second is for debug builds whose link line has no -g. R CMD
//! SHLIB's link line carries LDFLAGS, not CFLAGS: pkgbuild's
//! compile_dll(debug = TRUE), which devtools::load_all() runs, and a
//! ~/.R/Makevars with `CFLAGS = -g -O2` put -g on the compile lines only.
//! Their objects carry DWARF, so the library keeps it, and its .symtab.
//!
//! What zig makes of the flag, with both zigs: zig cc reads
//! -Wl,--strip-debug (and -Wl,-S) as its own strip option, the same as -s.
//! It links a libc++ it built without debug info (a second build in zig's
//! cache) and strips fully: .symtab goes with the .debug_* sections.
//! .dynsym stays, so loading, dlsym, R's routines and exceptions work as
//! before. That is what `R CMD INSTALL --strip` does on linux. It is not
//! binutils' --strip-debug, which keeps .symtab.
//!
//! An object is read only as far as needed: its ELF header, its section
//! headers, and the first bytes of the name of each section that could be
//! DWARF's (PROGBITS, not loaded). Not read:
//!   - archives (.a). A member's debug info reaches the library only when
//!     the link pulls the member in, which only the linker knows. Their
//!     DWARF is often their own build's choice, not the package's
//!     (oneTBB's CMake defaults to RelWithDebInfo), so reading them would
//!     bring zig's libc++ DWARF back into release builds. It would also
//!     take reading every member's headers.
//!   - shared libraries. A link does not copy their debug info.
//!   - objects named otherwise, or listed in a response file (@file).
//! A file that cannot be read, or is no ELF relocatable object (an LLVM
//! bitcode object from -flto too), counts as one without debug info.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const elf = std.elf;
const Ctx = @import("Ctx.zig");
const cmdline = @import("cmdline.zig");
const Args = cmdline.Args;

/// Whether a linux command gets -Wl,--strip-debug: a link (no
/// compile-only flag) with no -g option and no input object with debug
/// info.
pub fn wanted(ctx: *Ctx, args: Args) bool {
    if (cmdline.compileOnly(args) or cmdline.debugOption(args)) return false;
    var it = cmdline.inputs(args);
    while (it.next()) |i| {
        if (mem.endsWith(u8, args[i], ".o") and hasDebugInfo(ctx, args[i])) return false;
    }
    return true;
}

/// Whether `path` is an ELF relocatable object with a .debug_info or
/// .zdebug_info section. false when it cannot be read or is no such
/// object.
pub fn hasDebugInfo(ctx: *Ctx, path: []const u8) bool {
    var file = Io.Dir.cwd().openFile(ctx.io, path, .{}) catch return false;
    defer file.close(ctx.io);
    var buf: [4096]u8 = undefined;
    var r = file.reader(ctx.io, &buf);
    return debugSection(&r) catch false;
}

/// ELF's SHN_XINDEX (std.elf has no name for it).
const shn_xindex = 0xffff;

fn debugSection(r: *Io.File.Reader) !bool {
    const h = try elf.Header.read(&r.interface);
    if (h.type != .REL or h.shoff == 0) return false;
    // 65280 sections or more (a large C++ object): their number is in
    // section 0's sh_size, the name table's index in its sh_link
    var count: u64 = h.shnum;
    var names: u64 = h.shstrndx;
    if (count == 0 or names == shn_xindex) {
        const s0 = try section(r, h, 0);
        if (count == 0) count = s0.sh_size;
        if (names == shn_xindex) names = s0.sh_link;
    }
    if (names >= count) return false;
    const names_offset = (try section(r, h, names)).sh_offset;
    var i: u64 = 1;
    while (i < count) : (i += 1) {
        const s = try section(r, h, i);
        // DWARF's sections are PROGBITS and not loaded
        if (s.sh_type != @intFromEnum(elf.SHT.PROGBITS) or s.sh_flags & elf.SHF_ALLOC != 0) continue;
        var name: [".zdebug_info".len]u8 = undefined;
        const n = try r.file.readPositionalAll(r.io, &name, names_offset +| s.sh_name);
        if (mem.startsWith(u8, name[0..n], ".debug_info") or mem.startsWith(u8, name[0..n], ".zdebug_info")) return true;
    }
    return false;
}

/// Section header `i`, in ELF64's form.
fn section(r: *Io.File.Reader, h: elf.Header, i: u64) !elf.Elf64_Shdr {
    const size: u64 = if (h.is_64) @sizeOf(elf.Elf64_Shdr) else @sizeOf(elf.Elf32_Shdr);
    try r.seekTo(h.shoff +| i *| size);
    return elf.takeSectionHeader(&r.interface, h.is_64, h.endian);
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");

// `int f(void) { return 1; }` (f.c), compiled by conda-forge's zig 0.16.0:
//   zig cc -target x86_64-linux-gnu -O2 -g -fdebug-compilation-dir=. -c f.c -o f-g.o
//   zig cc -target x86_64-linux-gnu -O2 -g0 -c f.c -o f-g0.o
// f-g.o has .debug_abbrev, .debug_info, .debug_str and .debug_line;
// f-g0.o has no .debug_* section. f-gdb.o is f-g0.o plus a gdb script in
// .debug_gdb_scripts, as Boost's headers put one (f-gdb.c: f.c and a
// `.pushsection ".debug_gdb_scripts", "MS",%progbits,1` asm block, -g0).
const f_g = @embedFile("testdata/f-g.o");
const f_g0 = @embedFile("testdata/f-g0.o");
const f_gdb = @embedFile("testdata/f-gdb.o");

/// `bytes` as an object with ELF's extended section numbering, as one with
/// 65280 sections or more has: e_shnum 0 and e_shstrndx SHN_XINDEX, the
/// real values in section 0's sh_size and sh_link.
fn extended(a: mem.Allocator, bytes: []const u8) ![]u8 {
    const b = try a.dupe(u8, bytes);
    const shoff: usize = @intCast(mem.readInt(u64, b[40..48], .little));
    mem.writeInt(u64, b[shoff + 32 ..][0..8], mem.readInt(u16, b[60..62], .little), .little);
    mem.writeInt(u32, b[shoff + 40 ..][0..4], mem.readInt(u16, b[62..64], .little), .little);
    mem.writeInt(u16, b[60..62], 0, .little);
    mem.writeInt(u16, b[62..64], shn_xindex, .little);
    return b;
}

test hasDebugInfo {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.write("f-g.o", f_g, .default_file);
    try f.write("f-g0.o", f_g0, .default_file);
    try testing.expect(hasDebugInfo(c, f.path("f-g.o")));
    try testing.expect(!hasDebugInfo(c, f.path("f-g0.o")));
    // a .debug_* section that is no debug info: Boost's gdb script
    try f.write("f-gdb.o", f_gdb, .default_file);
    try testing.expect(!hasDebugInfo(c, f.path("f-gdb.o")));
    // extended section numbering
    try f.write("x-g.o", try extended(c.arena, f_g), .default_file);
    try f.write("x-g0.o", try extended(c.arena, f_g0), .default_file);
    try testing.expect(hasDebugInfo(c, f.path("x-g.o")));
    try testing.expect(!hasDebugInfo(c, f.path("x-g0.o")));
    // not a relocatable object: f-g.o's bytes as a shared library's (ET_DYN)
    const dyn = try c.arena.dupe(u8, f_g);
    mem.writeInt(u16, dyn[16..18], @intFromEnum(elf.ET.DYN), .little);
    try f.write("dyn.o", dyn, .default_file);
    try testing.expect(!hasDebugInfo(c, f.path("dyn.o")));
    // cut short, empty, an archive, text, a directory, no file: none
    try f.write("short.o", f_g[0..1024], .default_file);
    try f.write("header.o", f_g[0..64], .default_file);
    try f.touch("empty.o");
    try f.write("ar.o", "!<arch>\n" ++ f_g, .default_file);
    try f.write("text.o", "INPUT(f-g.o)\n", .default_file);
    try f.tmp.dir.createDirPath(testing.io, "dir.o");
    for ([_][]const u8{ "short.o", "header.o", "empty.o", "ar.o", "text.o", "dir.o", "nowhere.o" }) |p| {
        try testing.expect(!hasDebugInfo(c, f.path(p)));
    }
    try testing.expectEqualStrings("", f.takeWarnings());
}

test wanted {
    var f: testutil.Fixture = undefined;
    try f.init(.linux);
    defer f.deinit();
    const c = &f.ctx;
    try f.write("f-g.o", f_g, .default_file);
    try f.write("f-g0.o", f_g0, .default_file);
    const g = f.path("f-g.o");
    const g0 = f.path("f-g0.o");
    // objects without debug info, sources, names that are no file
    try testing.expect(wanted(c, &.{ "-shared", "-o", "p.so", g0, "a.o", "-lR" }));
    // a release object that includes Boost.Unordered (its gdb script)
    try f.write("f-gdb.o", f_gdb, .default_file);
    try testing.expect(wanted(c, &.{ "-shared", "-o", "p.so", g0, f.path("f-gdb.o"), "-lR" }));
    try testing.expect(wanted(c, &.{ "-o", "conftest", "-O2", "conftest.c" }));
    // one object with debug info is enough: a library or an executable
    // (pkgbuild's compile_dll(debug = TRUE): -g on the compile lines only)
    try testing.expect(!wanted(c, &.{ "-shared", "-L/r/lib", "-o", "p.so", g0, g, "-L/r/lib", "-lR" }));
    try testing.expect(!wanted(c, &.{ "-o", "prog", g }));
    // a -g option: the caller's choice, -g0 included; compiles: never
    for ([_][]const u8{ "-g", "-g0", "-gline-tables-only" }) |opt| try testing.expect(!wanted(c, &.{ "-shared", opt, "-o", "p.so", g0 }));
    try testing.expect(!wanted(c, &.{ "-c", "a.c", "-o", "a.o" }));
    // archives, shared libraries, other names: not read
    for ([_][]const u8{ "libx.a", "libx.so", "libx.so.1", "x.obj", "x.lo" }) |name| {
        try f.write(name, f_g, .default_file);
        try testing.expect(wanted(c, &.{ "-shared", "-o", "p.so", g0, f.path(name) }));
    }
    // the output: not an input (a partial link's, say)
    try testing.expect(wanted(c, &.{ "-r", "-o", g, g0 }));
}
