/* rzig's binutils tests (binutils.zig): an export, an import from the CRT */
#include <stdio.h>
int bu_answer(void) { printf("%d\n", 42); return 42; }
