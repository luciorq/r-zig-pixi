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
 *
 * Command-line construction: _spawnv's own argv-to-command-line
 * conversion (MinGW/MSVCRT's built-in quoting) does NOT correctly
 * preserve an embedded double-quote character inside an argument — found
 * via a real, reproduced bug: a CRAN package's own Makevars.win passes
 * -DMBEDTLS_CONFIG_FILE='"zip_mbedtls_config.h"' (correctly shell-quoted,
 * confirmed intact in bash's own argv via `set -x`, and confirmed intact
 * when bash spawns `zig cc` *directly*), but the compiler ends up seeing
 * `#define MBEDTLS_CONFIG_FILE zip_mbedtls_config.h` — quotes silently
 * gone — only when the call is routed through this forwarder's own
 * `_spawnv` re-invocation of bash. Root-caused by isolating each hop:
 * bash -> native exe (this forwarder, or zig directly) preserves the
 * embedded quote; this forwarder -> bash via `_spawnv` does not. Fixed by
 * not trusting `_spawnv`'s own quoting at all: build the child command
 * line ourselves with the exact Microsoft-documented argv-quoting
 * algorithm (the same one `rcmdfn.c`'s own `quoted_arg_cat`/
 * `quoted_arg_len` already implement elsewhere in this codebase for the
 * identical reason — CreateProcess takes one command-line string, not an
 * argv array, so *something* has to encode array boundaries into it
 * correctly), then call `CreateProcess` directly.
 */
#include <stdio.h>
#include <stdlib.h>
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

/* Microsoft's documented argv-quoting algorithm (CommandLineToArgvW's own
 * inverse): double backslashes immediately before a literal quote or at
 * the very end of the argument, escape the quote itself as \", surround
 * the whole argument in "..." unconditionally (simpler than deciding
 * per-argument whether quoting is needed, and always correct). */
static size_t quoted_arg_len(const char *arg) {
  size_t len = 0, nbackslashes = 0;
  for (size_t i = 0; arg[i]; i++) {
    if (arg[i] == '\\') {
      nbackslashes++;
    } else if (arg[i] == '"') {
      len += 2 * nbackslashes + 2;
      nbackslashes = 0;
    } else {
      len += nbackslashes + 1;
      nbackslashes = 0;
    }
  }
  len += 2 * nbackslashes;
  len += 2; /* surrounding quotes */
  return len;
}

static void quoted_arg_cat(char *dest, const char *arg) {
  size_t j = strlen(dest), nbackslashes = 0;
  dest[j++] = '"';
  for (size_t i = 0; arg[i]; i++) {
    if (arg[i] == '\\') {
      nbackslashes++;
    } else if (arg[i] == '"') {
      for (; nbackslashes; nbackslashes--) { dest[j++] = '\\'; dest[j++] = '\\'; }
      dest[j++] = '\\';
      dest[j++] = '"';
    } else {
      for (; nbackslashes; nbackslashes--) dest[j++] = '\\';
      dest[j++] = arg[i];
    }
  }
  for (; nbackslashes; nbackslashes--) { dest[j++] = '\\'; dest[j++] = '\\'; }
  dest[j++] = '"';
  dest[j] = '\0';
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

  size_t total = quoted_arg_len(bash_path) + 1 + quoted_arg_len(script_path);
  for (int i = 1; i < argc; i++) total += 1 + quoted_arg_len(argv[i]);
  char *cmdline = (char *)malloc(total + 1);
  if (!cmdline) return 1;
  cmdline[0] = '\0';
  quoted_arg_cat(cmdline, bash_path);
  strcat(cmdline, " ");
  quoted_arg_cat(cmdline, script_path);
  for (int i = 1; i < argc; i++) {
    strcat(cmdline, " ");
    quoted_arg_cat(cmdline, argv[i]);
  }

  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  ZeroMemory(&pi, sizeof(pi));
  if (!CreateProcessA(bash_path, cmdline, NULL, NULL, TRUE, 0, NULL, NULL,
                       &si, &pi)) {
    fprintf(stderr, "%s: CreateProcess failed for %s\n", argv[0], bash_path);
    free(cmdline);
    return 1;
  }
  free(cmdline);
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  return (int)code;
}
