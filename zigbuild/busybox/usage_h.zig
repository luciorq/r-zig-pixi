//! include/usage_compressed.h from busybox's applets/usage output, as
//! applets/usage_compressed writes it with `od -v -b` and sed, less the
//! bzip2 part: FEATURE_COMPRESS_USAGE is off (config/<arch>.config), so
//! appletlib.c reads UNPACKED_USAGE and never PACKED_USAGE.
//!
//!   usage_h <usage's output> <usage_compressed.h>
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) return error.Usage;
    const text = try std.Io.Dir.cwd().readFileAlloc(io, args[1], arena, .limited(64 << 20));
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "#define UNPACKED_USAGE \"\" \\\n");
    var i: usize = 0;
    while (i < text.len) : (i += 16) {
        try out.append(arena, '"');
        for (text[i..@min(i + 16, text.len)]) |c| try out.print(arena, "\\{o:0>3}", .{c});
        try out.appendSlice(arena, "\" \\\n");
    }
    try out.print(arena, "\n#define UNPACKED_USAGE_LENGTH {d}\n\n#define PACKED_USAGE \\\n\n", .{text.len});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = out.items });
}
