//! rzig's __clear_cache for Windows on ARM links (../clear_cache.zig):
//! compiler-rt's clear_cache.c, its _WIN32 branch, which zig's
//! compiler_rt leaves as a TODO. Weak, so a link that defines the symbol
//! itself keeps its own; not auto-exported from a DLL. R's build compiles
//! this file alone into R_HOME/bin/toolchain/clear_cache.o
//! (../build.zig's linkObject), aarch64 Windows only, stripped: a C
//! compile for Windows carries CodeView's object-name record, which names
//! the build machine's path even at -g0.
const std = @import("std");

extern "kernel32" fn FlushInstructionCache(process: ?*anyopaque, base: ?*const anyopaque, size: usize) callconv(.winapi) i32;

/// GetCurrentProcess()'s pseudo-handle.
const current_process: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

fn clearCache(start: [*]u8, end: [*]u8) callconv(.c) void {
    _ = FlushInstructionCache(current_process, start, @intFromPtr(end) - @intFromPtr(start));
}

comptime {
    @export(&clearCache, .{ .name = "__clear_cache", .linkage = .weak });
    // lld's MinGW auto-export (a DLL with no .def file and no dllexport
    // exports every global symbol) leaves it out, as cfguard.zig's symbol
    asm (
        \\.section .drectve,"yni"
        \\.ascii " -exclude-symbols:__clear_cache"
        \\.text
    );
}
