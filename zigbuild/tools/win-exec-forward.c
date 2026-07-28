/* Native forwarder: R's own Windows system()/CreateProcess call only ever
 * auto-appends ".exe" when resolving a bare command name (never consults
 * PATHEXT the way cmd.exe does) — so a bash-script "gcc"/"g++" shim, even
 * with an absolute BINPREF path, is invisible to it. This tiny compiled
 * .exe is the real "gcc.exe"/"g++.exe" Makeconf's BINPREF points at; it
 * just forwards argv to the real shim script (toolchain/zig-cc or
 * zig-cxx) via bash, unmodified — all the actual compiler-flag logic
 * stays in that one bash script, not duplicated here.
 *
 * BASH_PATH and SCRIPT_PATH are supplied as -D string literals at compile
 * time (see build.zig's Windows toolchain bundling).
 */
#include <process.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  char **newargv = malloc(sizeof(char *) * ((size_t)argc + 2));
  if (!newargv) return 1;
  newargv[0] = BASH_PATH;
  newargv[1] = SCRIPT_PATH;
  for (int i = 1; i < argc; i++) newargv[i + 1] = argv[i];
  newargv[argc + 1] = NULL;
  intptr_t rc = _spawnv(_P_WAIT, BASH_PATH, (const char *const *)newargv);
  free(newargv);
  return rc < 0 ? 1 : (int)rc;
}
