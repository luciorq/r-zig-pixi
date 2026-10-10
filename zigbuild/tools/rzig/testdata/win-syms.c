/* The symbol kinds a package object holds, for def.zig's test: compiled
   for x86_64-windows-gnu with `zig cc -c -O2` (see def.zig). */
#include <string.h>
int exported_data = 1;                 /* D: initialized data */
const int exported_rodata = 2;         /* R: read-only data */
int exported_bss[16];                  /* B: uninitialized data */
static int local_data = 3;             /* d: local, not exported */
extern int imported_var;               /* U: undefined */
int exported_fn(int x) { return x + exported_data + local_data + imported_var; }
static int local_fn(int x) { return x * 2; }
__attribute__((weak)) int weak_fn(int x) { return x; }   /* W: weak, as nm shows it */
int uses_locals(const char *s) { return local_fn((int)strlen(s)) + exported_rodata + exported_bss[0]; }
