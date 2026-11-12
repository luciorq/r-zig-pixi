//! rzig's own writes to its stdout and stderr: what nm and objdump list,
//! the command lines it echoes, its messages and `--version` lines.
//!
//! On Windows, not through std's File.writeStreamingAll. zig 0.17's
//! blocking write (std/Io/Threaded.zig, fileWriteStreamingWindows) takes
//! NtWriteFile's STATUS_PENDING for unreachable ("wrong File nonblocking
//! flag"), and MSYS2's pipes are overlapped handles: a write larger than
//! the pipe's buffer returns PENDING, and rzig panicked. winshlib.mk's
//! `$(NM) $(OBJECTS) | sed ... >> tmp.def` did so for a C++ package (Rcpp's
//! objects list over 64 KiB): the .def came out empty, lld exported
//! every symbol, and the make path's DLL differed from rzig build's
//! (pkg-parity on kappa, 2026-11-10). A small listing fit in the buffer,
//! so cli, digest and quadprog passed.
//!
//! This does what kernel32's WriteFile does without an OVERLAPPED: on
//! PENDING, wait on the handle, then read the status block. Elsewhere it is
//! std's writeStreamingAll.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

pub const Error = error{WriteFailed};

/// All of `bytes` to `file` (stdout or stderr).
pub fn writeAll(io: Io, file: Io.File, bytes: []const u8) Error!void {
    if (builtin.os.tag != .windows) return file.writeStreamingAll(io, bytes) catch error.WriteFailed;
    const w = std.os.windows;
    var rest = bytes;
    while (rest.len > 0) {
        var iosb: w.IO_STATUS_BLOCK = undefined;
        const len: w.ULONG = @intCast(@min(rest.len, 1 << 30));
        var status = w.ntdll.NtWriteFile(file.handle, null, null, null, &iosb, rest.ptr, len, null, null);
        if (status == .PENDING) {
            _ = w.ntdll.NtWaitForSingleObject(file.handle, .FALSE, null);
            status = iosb.u.Status;
        }
        if (status != .SUCCESS or iosb.Information == 0) return error.WriteFailed;
        rest = rest[@min(iosb.Information, rest.len)..];
    }
}

/// A buffered Io.Writer on `file` whose drain is writeAll.
pub const Writer = struct {
    io: Io,
    file: Io.File,
    interface: Io.Writer,

    pub fn init(io: Io, file: Io.File, buffer: []u8) Writer {
        return .{ .io = io, .file = file, .interface = .{ .vtable = &.{ .drain = drain }, .buffer = buffer } };
    }

    fn drain(iw: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *Writer = @alignCast(@fieldParentPtr("interface", iw));
        try writeAll(self.io, self.file, iw.buffered());
        iw.end = 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |d| {
            try writeAll(self.io, self.file, d);
            n += d.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| try writeAll(self.io, self.file, last);
        return n + last.len * splat;
    }
};

test "Writer: buffer, then each slice, the last one splat times" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile(io, "out", .{});
    var buf: [4]u8 = undefined;
    var w: Writer = .init(io, f, &buf);
    try w.interface.writeAll("ab");
    try w.interface.writeAll("cdefgh"); // over the buffer: drain
    var parts = [_][]const u8{ "1", "xy" };
    try w.interface.writeSplatAll(&parts, 3);
    try w.interface.flush();
    f.close(io);
    var rbuf: [64]u8 = undefined;
    const got = try tmp.dir.readFile(io, "out", &rbuf);
    try std.testing.expectEqualStrings("abcdefgh1xyxyxy", got);
}
