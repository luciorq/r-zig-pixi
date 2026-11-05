//! How rzig ends after a crash (feat-tier1-engine K4). main.zig declares
//! `panic` and `debug` below as its root's, so they cover every thread.
//!
//! zig ends a panic, and a fault its handler reports (an access violation,
//! a stack overflow), with std.process.abort(). On Windows that is
//! RtlExitUserProcess(3), and 3 is rzig build's "needs make"
//! (pkgbuild.exit_needs_make): R's .rzig_build (patch 0013) then runs the
//! make path, and the crash is hidden behind a second build. Tier 1 runs
//! def.zig in rzig's own process, so def.zig's u16 overflow did exactly
//! that for mlpack (kappa, 2026-10-30). On Windows rzig now prints what
//! zig prints (`thread <id> panic: <msg>` and the stack trace, or the
//! fault and its address) and exits with exit_crash, which R fails on.
//! Elsewhere zig's own: SIGABRT, which R reads as 6, or 134 with a core
//! dump (patch 0013: a child a signal ends reads as its raw wait status),
//! a failure too.
const std = @import("std");
const builtin = @import("builtin");

/// rzig's exit status after a crash on Windows: EX_SOFTWARE (sysexits.h).
/// Not 0, 1, 2, 3 or 127, the statuses rzig gives otherwise.
pub const exit_crash: u8 = 70;

const windows = builtin.os.tag == .windows;

/// The root's `panic`.
pub const panic = std.debug.FullPanic(if (windows) panicExit else std.debug.defaultPanic);

/// The root's `debug`: std.debug calls its handleSegfault for a fault.
pub const debug = if (windows) struct {
    pub const handleSegfault = faultExit;
} else struct {};

/// A crash while one is being reported exits at once.
threadlocal var crashing = false;

fn panicExit(msg: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);
    if (!crashing) {
        crashing = true;
        std.Options.debug_io.vtable.crashHandler(std.Options.debug_io.userdata);
        std.debug.print("thread {d} panic: {s}\n", .{ std.Thread.getCurrentId(), msg });
        std.debug.dumpCurrentStackTrace(.{ .first_address = first_trace_addr orelse @returnAddress(), .allow_unsafe_unwind = true });
    }
    std.process.exit(exit_crash);
}

fn faultExit(addr: ?usize, name: []const u8, context: ?std.debug.CpuContextPtr) noreturn {
    if (!crashing) {
        crashing = true;
        std.Options.debug_io.vtable.crashHandler(std.Options.debug_io.userdata);
        if (addr) |a| std.debug.print("{s} at address 0x{x}\n", .{ name, a }) else std.debug.print("{s} (no address available)\n", .{name});
        if (context) |c| std.debug.dumpCurrentStackTrace(.{ .context = c, .allow_unsafe_unwind = true });
    }
    std.process.exit(exit_crash);
}
