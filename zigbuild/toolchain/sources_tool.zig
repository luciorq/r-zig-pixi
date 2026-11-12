//! A group directory's SOURCES, written when its files are made (the
//! toolchain build runs this host program as a Run step): a copy's line is
//! known at configure time, a built file's sha256 (pkgconf.exe) only once
//! it is built. zig 0.17's build steps are data, not code, so this program
//! does what a custom step did:
//!   sources_tool <spec.json> <out> [<built file>...]
//! spec.json (build.zig writes it, `Spec`) lists the records and the
//! copies; a copy with `built` set takes the sha256 of that built file
//! (its index among the arguments after <out>). conda.zig's writeSources,
//! the one writer, writes <out>.
const std = @import("std");
const conda = @import("conda.zig");

/// What build.zig serializes: records with only the fields SOURCES
/// writes (no files, paths_data or package-cache path), and the copies by
/// record index.
pub const Spec = struct {
    records: []const conda.Record,
    copies: []const Copy,

    pub const Copy = struct {
        record: u32,
        from: []const u8,
        to: []const u8,
        /// Empty when `built` is set.
        sha256: []const u8 = "",
        changed: ?conda.Changed = null,
        built: ?u32 = null,
    };
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        std.debug.print("usage: sources_tool <spec.json> <out> [<built file>...]\n", .{});
        std.process.exit(2);
    }
    const cwd = std.Io.Dir.cwd();
    const json = try cwd.readFileAlloc(io, args[1], arena, .limited(64 * 1024 * 1024));
    const spec = try std.json.parseFromSliceLeaky(Spec, arena, json, .{});
    const built = args[3..];

    const copies = try arena.alloc(conda.Copy, spec.copies.len);
    for (spec.copies, copies) |c, *out| {
        if (c.record >= spec.records.len) return error.BadRecordIndex;
        var sha = c.sha256;
        if (c.built) |i| {
            if (i >= built.len) return error.BadBuiltIndex;
            const data = try cwd.readFileAlloc(io, built[i], arena, .limited(1024 * 1024 * 1024));
            var d: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(data, &d, .{});
            sha = try arena.dupe(u8, &std.fmt.bytesToHex(d, .lower));
        }
        out.* = .{ .record = &spec.records[c.record], .from = c.from, .to = c.to, .sha256 = sha, .changed = c.changed };
    }
    var w: std.Io.Writer.Allocating = .init(arena);
    try conda.writeSources(arena, &w.writer, copies);
    try cwd.writeFile(io, .{ .sub_path = args[2], .data = w.written() });
}
