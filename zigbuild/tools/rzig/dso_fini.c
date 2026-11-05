/* rzig's finalization object for linux shared libraries
   (zigbuild/tools/rzig/dso_fini.zig): crtbeginS.o's part that a zig link
   of a linux shared library lacks. __dso_handle holds its own address
   (lld's stand-in is the image base), and a .fini_array entry runs and
   forgets the handlers this library registered with __cxa_atexit or
   atexit when it is unloaded. R's build compiles it into
   R_HOME/bin/toolchain/dso_fini.o (zigbuild/tools/rzig/build.zig). */
void *__dso_handle __attribute__((visibility("hidden"), weak)) = &__dso_handle;
extern void __cxa_finalize(void *) __attribute__((weak));
static void r_zig_fini(void) { if (__cxa_finalize) __cxa_finalize(__dso_handle); }
__attribute__((section(".fini_array"), used)) static void (*r_zig_fini_p)(void) = r_zig_fini;
