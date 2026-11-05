//! A program that crashes, with rzig's crash handling (crash.zig), for
//! tier1.zig's crash test. build.zig builds it as it builds rzig
//! (ReleaseSafe, stripped) and embeds it in rzig-test.
//!   crash panic      a u16 overflow in a thread: def.zig's in tier 1
//!                    (feat-tier1-engine K3 and K4)
//!   crash segfault   a write to address 0
const std = @import("std");
const crash = @import("crash");

pub const panic = crash.panic;
pub const debug = crash.debug;

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return 2;
    if (std.mem.eql(u8, args[1], "panic")) {
        // section 1640, the first that overflowed
        const t = try std.Thread.spawn(.{}, sectionOffset, .{@as(u16, @intCast(args.len + 1638))});
        t.join();
    } else if (std.mem.eql(u8, args[1], "segfault")) {
        const p: *allowzero volatile u8 = @ptrFromInt(0);
        p.* = 0;
    }
    return 2;
}

/// def.zig's section header offset before K3's fix, in u16.
fn sectionOffset(section: u16) void {
    std.mem.doNotOptimizeAway((section - 1) * @sizeOf(std.coff.SectionHeader));
}
