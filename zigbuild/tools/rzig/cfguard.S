/* rzig's CFG stub for Windows links (zigbuild/tools/rzig/cfguard.zig):
   mingw-w64-crt's cfguard/guard_dispatch.S, which zig's MinGW runtime
   leaves out. The target of __guard_dispatch_icall_fptr when CFG is off:
   jump to the address the caller put in %rax. Not auto-exported from a
   DLL. R's build assembles it into R_HOME/bin/toolchain/cfguard.o
   (zigbuild/tools/rzig/build.zig), x86_64 only. */
    .text
    .globl __guard_dispatch_icall_dummy
__guard_dispatch_icall_dummy:
    jmp *%rax
    .section .drectve,"yni"
    .ascii " -exclude-symbols:__guard_dispatch_icall_dummy"
