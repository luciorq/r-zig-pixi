//! rzig's CFG stub for Windows links (../cfguard.zig): mingw-w64-crt's
//! cfguard/guard_dispatch.S, which zig's MinGW runtime leaves out. The
//! target of __guard_dispatch_icall_fptr when CFG is off: jump to the
//! address the caller put in rax. That register is no calling
//! convention's argument, so the body is the one instruction, in a naked
//! function. Not auto-exported from a DLL. R's build compiles this file
//! alone into R_HOME/bin/toolchain/cfguard.o (../build.zig's
//! linkObject), x86_64 only, stripped: on aarch64 the check pointer is
//! libmingw32's own, and there is no dispatch pointer.

fn guardDispatchIcallDummy() callconv(.naked) noreturn {
    asm volatile ("jmp *%%rax");
}

comptime {
    @export(&guardDispatchIcallDummy, .{ .name = "__guard_dispatch_icall_dummy" });
    // lld's MinGW auto-export (a DLL with no .def file and no dllexport
    // exports every global symbol) leaves it out
    asm (
        \\.section .drectve,"yni"
        \\.ascii " -exclude-symbols:__guard_dispatch_icall_dummy"
        \\.text
    );
}
