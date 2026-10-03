//! zig-ar: `zig ar` as a single-word $AR, with one macOS workaround.
//!
//! conda-forge's osx-64 zig 0.16.0 `zig ar` (llvm-ar) cannot create an
//! archive: `ar rcs new.a x.o` against a missing new.a dies with "unable to
//! open 'new.a': No such file or directory", although that is the case
//! llvm-ar's create path exists for (its ENOENT check misfires; the
//! feedstock links macOS zig against conda's shared libc++, the classic
//! setup for two error_category instances that compare unequal). osx-arm64
//! creates archives fine, and osx-64 appends to an existing one fine (both
//! reproduced on omicron under Rosetta, 2026-09-19). It bit jsonlite's
//! bundled yajl (`$(AR) rcs yajl/libstatyajl.a ...`) on macos-15-intel.
//! So on macOS, when an insert-mode call (r or q) names a missing archive,
//! seed it with the 8-byte empty-archive header, `!<arch>\n`, valid and
//! format-neutral, and pin --format=darwin so llvm-ar doesn't keep the GNU
//! layout of the now pre-existing archive for a Mach-O static library.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Ctx = @import("Ctx.zig");

/// zig's arguments after its own path.
pub fn argv(ctx: *Ctx, caller: []const []const u8) ![]const []const u8 {
    const plain = try mem.concat(ctx.arena, []const u8, &.{ &.{"ar"}, caller });
    if (ctx.os != .macos) return plain;

    // the operation letters, then the archive; long options skipped
    var ops: []const u8 = "";
    var archive: []const u8 = "";
    var have_format = false;
    for (caller) |x| {
        if (mem.startsWith(u8, x, "--format=")) {
            have_format = true;
            continue;
        }
        if (mem.startsWith(u8, x, "--")) continue;
        if (ops.len == 0) {
            ops = x;
            continue;
        }
        archive = x;
        break;
    }
    if (mem.findAny(u8, ops, "rq") == null or archive.len == 0 or ctx.exists(archive)) return plain;

    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = archive, .data = "!<arch>\n" }) catch |err| {
        ctx.warn("cannot create {s}: {t}", .{ archive, err });
    };
    if (have_format) return plain;
    return mem.concat(ctx.arena, []const u8, &.{ &.{ "ar", "--format=darwin" }, caller });
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const testutil = @import("testutil.zig");
const expectArgs = testutil.expectArgs;

test "macOS: a missing archive is seeded and pinned to the darwin format" {
    var f: testutil.Fixture = undefined;
    try f.init(.macos);
    defer f.deinit();
    const ctx = &f.ctx;
    const a = f.path("new.a");
    try expectArgs(&.{ "ar", "--format=darwin", "rcs", a, "x.o" }, try argv(ctx, &.{ "rcs", a, "x.o" }));
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("!<arch>\n", try f.tmp.dir.readFile(testing.io, "new.a", &buf));

    // existing archive, or no insert operation: untouched
    try expectArgs(&.{ "ar", "rcs", a, "x.o" }, try argv(ctx, &.{ "rcs", a, "x.o" }));
    try expectArgs(&.{ "ar", "t", f.path("none.a") }, try argv(ctx, &.{ "t", f.path("none.a") }));
    try testing.expect(!ctx.exists(f.path("none.a")));

    // an explicit format is kept, the seed still written
    const b = f.path("b.a");
    try expectArgs(&.{ "ar", "--format=gnu", "q", b, "x.o" }, try argv(ctx, &.{ "--format=gnu", "q", b, "x.o" }));
    try testing.expect(ctx.isFile(b));

    // the dash form; long options before the operation are skipped, so
    // --plugin's value is taken for the operation, as the shim did
    const d = f.path("d.a");
    try expectArgs(&.{ "ar", "--format=darwin", "-rcs", d, "x.o" }, try argv(ctx, &.{ "-rcs", d, "x.o" }));
    try testing.expect(ctx.isFile(d));
    try expectArgs(&.{ "ar", "--plugin", "x", "rcs", f.path("p.a") }, try argv(ctx, &.{ "--plugin", "x", "rcs", f.path("p.a") }));
    try testing.expect(!ctx.exists(f.path("p.a")));

    // an archive it cannot seed: warned, still pinned
    try expectArgs(&.{ "ar", "--format=darwin", "rcs", f.path("no/dir.a") }, try argv(ctx, &.{ "rcs", f.path("no/dir.a") }));
    try testing.expect(mem.find(u8, f.takeWarnings(), "cannot create") != null);

    // elsewhere: passthrough
    ctx.os = .linux;
    try expectArgs(&.{ "ar", "rcs", f.path("c.a"), "x.o" }, try argv(ctx, &.{ "rcs", f.path("c.a"), "x.o" }));
    try testing.expect(!ctx.exists(f.path("c.a")));
}
