/* rzig's __clear_cache for Windows on ARM links (zigbuild/tools/rzig/
   clear_cache.zig): compiler-rt's clear_cache.c, its _WIN32 branch, which
   zig's compiler_rt leaves as a TODO. Weak, so a link that defines the
   symbol itself keeps its own; not auto-exported from a DLL. R's build
   compiles it into R_HOME/bin/toolchain/clear_cache.o
   (zigbuild/tools/rzig/build.zig), aarch64 only. */
#include <windows.h>

__attribute__((weak)) void __clear_cache(void *start, void *end) {
  FlushInstructionCache(GetCurrentProcess(), start, (SIZE_T)((char *)end - (char *)start));
}

__asm__(".section .drectve,\"yni\"\n"
        ".ascii \" -exclude-symbols:__clear_cache\"\n"
        ".text");
