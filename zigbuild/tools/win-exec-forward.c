/* Native forwarder: R's own Windows system()/CreateProcess call only ever
 * auto-appends ".exe" when resolving a bare command name (never consults
 * PATHEXT the way cmd.exe does) — so a bash-script "gcc"/"g++" shim, even
 * with an absolute BINPREF path, is invisible to it. This tiny compiled
 * .exe is the real "gcc.exe"/"g++.exe" Makeconf's BINPREF points at; it
 * just forwards argv to the real shim script (toolchain/zig-cc or
 * zig-cxx) via bash, unmodified — all the actual compiler-flag logic
 * stays in that one bash script, not duplicated here.
 *
 * Both paths below are resolved at RUNTIME, not baked in as compile-time
 * absolute constants: a conda/pixi package is built inside one prefix (a
 * rattler-build sandbox, torn down right after) and installed into a
 * completely different one on the end user's machine, so any absolute
 * path baked in via -D at compile time is guaranteed wrong post-install
 * (found via a real "had status 1" failure from glue/cli's own `cc
 * --version` compiler probe on a real installed package — every
 * invocation of this forwarder was silently failing, not just
 * "--version"; `strings` on the shipped gcc.exe showed the baked paths
 * literally pointed into the rattler-build sandbox's own temp directory).
 *
 * - The target script (SCRIPT_NAME, e.g. "zig-cc" — a bare filename, no
 *   path) lives in the SAME directory as this executable (both R's own
 *   `zig build install`/contract test and the conda package stage the
 *   two together — see build.zig's installWindowsCompilerContract and
 *   scripts/stage.sh) — resolved via GetModuleFileName.
 * - bash.exe (the m2-bash conda-forge package) is looked up via the
 *   *runtime* CONDA_PREFIX environment variable, not the build-time one:
 *   R only ever runs from within an activated pixi/conda env (that's how
 *   it lands on PATH at all — see stage.sh's own Windows staging
 *   comment), and CONDA_PREFIX at the time gcc.exe actually runs is
 *   whichever env the *caller* activated — the dev pixi env while
 *   testing this build locally (where R itself installs into a
 *   project-local dist/ dir, unrelated to CONDA_PREFIX), or the real
 *   end user's own env once packaged. A directory-relative guess from
 *   this executable's own location can't be right for both cases at
 *   once (R.dll and bash.exe share a prefix only in the packaged case),
 *   so this reads the environment instead of computing an offset.
 */
#include <process.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <windows.h>

static char *own_dir(void) {
  DWORD size = 1024;
  char *buf = NULL;
  for (;;) {
    buf = (char *)malloc(size);
    if (!buf) return NULL;
    DWORD res = GetModuleFileNameA(NULL, buf, size);
    if (res > 0 && res < size) break; /* success */
    free(buf);
    if (res != size) return NULL; /* real error, not "buffer too small" */
    size *= 2;
  }
  char *p = strrchr(buf, '\\');
  if (!p) { free(buf); return NULL; }
  *p = '\0';
  return buf;
}

int main(int argc, char **argv) {
  char *dir = own_dir();
  if (!dir) {
    fprintf(stderr, "%s: cannot determine own install location\n", argv[0]);
    return 1;
  }

  char script_path[MAX_PATH * 2];
  snprintf(script_path, sizeof(script_path), "%s\\%s", dir, SCRIPT_NAME);

  const char *conda_prefix = getenv("CONDA_PREFIX");
  if (!conda_prefix || !*conda_prefix) {
    fprintf(stderr, "%s: CONDA_PREFIX is not set — R must be run from "
                     "within its pixi/conda environment\n", argv[0]);
    return 1;
  }
  char bash_path[MAX_PATH * 2];
  snprintf(bash_path, sizeof(bash_path), "%s\\Library\\usr\\bin\\bash.exe",
           conda_prefix);

  char **newargv = malloc(sizeof(char *) * ((size_t)argc + 2));
  if (!newargv) return 1;
  newargv[0] = bash_path;
  newargv[1] = script_path;
  for (int i = 1; i < argc; i++) newargv[i + 1] = argv[i];
  newargv[argc + 1] = NULL;
  intptr_t rc = _spawnv(_P_WAIT, bash_path, (const char *const *)newargv);
  free(newargv);
  return rc < 0 ? 1 : (int)rc;
}
