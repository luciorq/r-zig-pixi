# Plan: unify R's Windows front-end with the shell-script design (2026-07-28)

**Status: plan only, no code changes yet.** Written after a real
`install.packages("pak")` failure on Windows (missing `Rcmd.exe`, then
`config.sh` in the wrong place, then a missing `Rcmd_environ` — three
separate real bugs, all documented in `TODO.md`'s F7.1 entry) prompted the
question: why does R's Windows front-end need to be a ~2000-line compiled-C
reimplementation of something Unix does in a few hundred lines of shell?
This document catalogs exactly how both front-ends work today, shows they
are functionally the same dispatcher reimplemented twice, and proposes
replacing the Windows compiled-C front-end with the same shell-script
design Unix already uses (and this build already stages), fronted by the
native-forwarder pattern this project already ships for `gcc.exe`/`g++.exe`.

## 1. How the Unix front-end actually works today (already in this build)

Unix's front-end is not one binary. It's a small stack of POSIX shell
scripts, each one thin, ending in a single real engine binary. This build
already stages all of it, unmodified from upstream, via `installStaticTree`
(`build.zig:2307`):

1. **`bin/R`** — `src/scripts/R.sh.in`, `@VAR@`-substituted then patched
   (`build.zig:2409`, `mkRFront` around 2413-2422: `R_HOME_DIR=` is
   overwritten with `ctx.rhome` as one of four install-time sed-equivalent
   patches). Computes `R_HOME_DIR` once (with a linux `lib64`/`lib`
   fallback), parses the CLI (`-e`, `-f`, `--vanilla`, `--no-environ`,
   `--args`, `--arch`, `-g`/`--gui`, `-d`/`--debugger`, `-h`/`--help`),
   sources `etc${R_ARCH}/ldpaths`, and either:
   - `CMD` as the first arg → `exec sh "${R_HOME}/bin/Rcmd" "${@}"`, or
   - otherwise → `exec "${R_HOME}/bin/exec${R_ARCH}/R" ...` (the one real
     compiled engine binary, `Rmain.c`/`R.bin`).
2. **`bin/Rcmd`** — `src/scripts/Rcmd.in`, staged the same way
   (`rspec.scripts_b`, `build.zig:2362`). Sets `R_OSTYPE="unix"`, sources
   and re-exports `etc${R_ARCH}/Renviron`, then dispatches by subcommand
   name: `Rd2txt`/`Rd2dvi` are special-cased, everything else resolves to
   `${R_HOME}/bin/${1}` if executable, else the bare name off `$PATH`, then
   `exec "${cmd}" ${extra} "${@}"`.
3. **`bin/<SUBCOMMAND>`** (`INSTALL`, `REMOVE`, `SHLIB`, `BATCH`, `build`,
   `check`, `Rprof`, `Rd2pdf`, `Rdconv`, `Rdiff`, `Stangle`, `Sweave`,
   `config`, ...) — `rspec.scripts_s` (`build.zig:198-201`), copied
   **verbatim, byte-identical, no substitution at all**. Each is a tiny,
   independent script. `bin/INSTALL` (35 lines) is representative:
   ```sh
   echo 'tools:::.install_packages()' | R_DEFAULT_PACKAGES= LC_COLLATE=C \
       "${R_HOME}/bin/R" $myArgs --no-echo --args ${args}
   ```
   It just re-invokes `bin/R` (step 1) with a `tools:::.foo()` call piped
   in. `bin/config` (346 lines, byte-identical across both platforms
   already — the one place upstream R itself already unified) is the one
   subcommand with real logic of its own (`R CMD config CC`, `--cppflags`,
   etc.), everything else is a thin wrapper around a `tools:::` call.

**Net shape**: one real engine binary (`bin/exec/R`), three tiers of shell
script on top of it, R_HOME computed exactly **once** (`bin/R`'s own
`R_HOME_DIR=`), inherited by every child process through the environment
from then on. No process ever recomputes R_HOME independently.

## 2. How the Windows front-end actually works today

Windows has no `bin/R`/`bin/Rcmd`/`bin/<SUBCOMMAND>` scripts at all. It
reimplements the same dispatcher as compiled C, spread across five files
that this build already compiles from real gnuwin32 sources
(`winCmdFrontend`, `build.zig:1713`; call sites `build.zig:1086-1087`):

- **`rhome.c`** (211 lines) — `getRHOME()`/`getRHOMElong()`: computes
  R_HOME by calling `GetModuleFileName(NULL, ...)` on **the front-end's
  own `.exe`** and stripping `dirstrip` trailing path components
  (`dirstrip = 2`, `+1` if `R_ARCH` is non-empty). This runs **once per
  front-end process** — R.exe, Rcmd.exe, and (separately, see below)
  Rscript.exe each recompute it independently, from their own module path,
  rather than inheriting a value computed once.
- **`shext.c`** (97 lines) — `getRUser()`/`freeRUser()`: a small helper for
  the per-user temp/home directory fallback, called from `rcmdfn.c`.
- **`R.c`** / **`rcmd.c`** — the two `main()` entry points. `R.c` checks
  for `-h`/`--help`/a literal `"CMD"` token before dispatching (plain `R`
  invocation with no `CMD` just re-execs `Rterm.exe` directly). `rcmd.c` is
  a one-liner, `exit(rcmdfn(1, argc, argv))` — always CMD-mode.
- **`rcmdfn.c`** (546 lines) — the actual dispatcher, shared by both
  binaries. For every subcommand it **inlines, in C, the exact same
  `tools:::.foo()` call** its Unix shell-script sibling makes, e.g.
  (`rcmdfn.c:462-464`, compare `bin/INSTALL` above):
  ```c
  snprintf(cmd, CMD_LEN,
      "\"\"%s/%s/Rterm.exe\" -e tools:::.install_packages() "
      "R_DEFAULT_PACKAGES= LC_COLLATE=C --no-restore --no-echo --args ",
      RHome, BINDIR);
  PROCESS_CMD("nextArg");
  ```
  This pattern repeats **13 times** (INSTALL, REMOVE, build, check, Rprof,
  SHLIB, Rdiff, Rdconv, Rd2txt, Rd2pdf, Sweave, Stangle, plus BATCH's own
  hand-rolled `CreateProcess`+`SetStdHandle` redirection in place of shell
  `>`). Every one of these branches is functionally identical to its
  Unix `bin/<SUBCOMMAND>` counterpart — confirmed by direct comparison in
  this document (§1 vs §2) — just re-expressed as C string templating with
  ~60 lines of hand-rolled Windows command-line quoting
  (`quoted_arg_len`/`quoted_arg_cat`, `rcmdfn.c:95-150`) standing in for
  what a shell gets from its own tokenizer for free. `config` is the one
  fallback case that shells out (`sh "$RHome/bin/config.sh"`,
  `rcmdfn.c:533`) — already proven identical to Unix's `bin/config`
  (`build.zig:1125-1134`'s own comment).
- **`Rcmd_environ`** — the Windows analogue of `bin/Rcmd`'s
  `R_OSTYPE="unix"` + `Renviron`-sourcing (`process_Renviron()` call,
  `rcmdfn.c:265`), a static file, real and already vendored/installed
  (F7.1).

**A third, independent R_HOME/engine-path computation** exists in
`Rscript.c` (`src/unix/Rscript.c`, shared source, `#include "rterm.c"`
under `_WIN32`+`FOR_Rscript`): its own `GetModuleFileName` + backslash-strip
block (`Rscript.c:242-266`), separate from `rhome.c`'s. On non-Windows,
`Rscript.c` instead `execv`s `"$RHOME/bin/R"` as a **subprocess**
(`Rscript.c:279,394`) — i.e. Unix's `Rscript` reuses `bin/R` too, the same
single script every other entry point reuses. Windows' `Rscript.exe`
cannot do that (no `bin/R` script exists to exec) so it calls `AppMain()`
**in-process** instead (`Rscript.c:397`) — a real behavioral divergence,
not just a stylistic one: on Windows there is no analogue of `bin/R` for
any front-end to delegate to, so each one (R.exe/Rcmd.exe via `rhome.c`,
Rscript.exe via its own block) re-derives paths and re-implements dispatch
independently.

**Why this exists historically**: gnuwin32 was written (~2000) when
Windows had no reliably-bundled POSIX shell to build a `bin/R`-style script
against. That constraint doesn't apply to this project — the whole Windows
build already depends on a real bash (m2-bash/MSYS) for `zig-build.sh`
itself, and this project already proved the "native `.exe` stub forwards to
a bash script" pattern works for exactly this reason: `win-exec-forward.c`
(`zigbuild/tools/win-exec-forward.c`) is the real, shipping `gcc.exe`/
`g++.exe` — a ~20-line native stub that `_spawnv(_P_WAIT, BASH_PATH, ...)`s
into `toolchain/zig-cc`/`zig-cxx`, built because R's own Windows `system()`/
`CreateProcess` call only ever auto-appends `.exe` to a bare name and never
consults `PATHEXT` (unlike `cmd.exe`) — so a bash script, even at an
absolute path, is invisible to it. This is the exact mechanism needed to
make `R CMD INSTALL`-style invocations (which R's own package-installation
R code, `packages2.R`, calls via `file.path(R.home("bin"), "R")` /
`"Rcmd.exe"`, hardcoded) resolve to a shell script instead of a compiled
dispatcher.

## 3. What "unify" concretely means here

Not literally one `.exe` file for R.exe/Rcmd.exe/Rscript.exe/Rterm.exe —
Rscript.exe and Rterm.exe are real embeddings of the interpreter
(`AppMain()`) and stay compiled binaries on any platform, same as Unix's
`bin/exec/R`. "Single binary" here means: **one native stub shape**,
reused under every legacy name front-end tooling expects, whose entire job
is forwarding into the *same* shell-script dispatcher Unix already uses —
eliminating the second, C-reimplemented dispatch table (`rcmdfn.c`) and
its own independent R_HOME computation (`rhome.c`) entirely.

### Proposed design

1. **Reuse `bin/R` and `bin/Rcmd` as-is on Windows.** They're already
   staged unmodified by `installStaticTree` for Unix; stage the identical
   two files into the Windows install tree too (`Library/lib/R/bin/R`,
   `Library/lib/R/bin/Rcmd`), with two adjustments, both already precedented
   elsewhere in this codebase:
   - `R.sh.in`'s final dispatch line (`exec "${R_HOME}/bin/exec${R_ARCH}/R"`)
     needs a Windows-shaped substitution pointing at `Rterm.exe` instead —
     this is exactly the kind of one-line `@VAR@`/sed-equivalent patch
     `mkRFront` (`build.zig:2409`) already applies for `R_HOME_DIR=`.
   - `Rcmd.in`'s `R_OSTYPE="unix"` becomes `R_OSTYPE="windows"` — the
     single-line Windows/Unix divergence this whole design is meant to
     shrink *to* (compare today: an entire second 546-line C file for this
     one conceptual difference).
   - `scripts_s` (INSTALL, SHLIB, BATCH, config, ...) need **no changes at
     all** — they already only ever reference `${R_HOME}/bin/R`, which now
     resolves correctly on Windows too. `BATCH`'s output redirection is
     already just shell `>` in `bin/BATCH`; the hand-rolled
     `CreateProcess`+`SetStdHandle` block in `rcmdfn.c`'s BATCH branch
     (`rcmdfn.c:268-401`, ~130 lines) is retired entirely, not ported.
2. **Front every legacy binary name with the native forwarder.** Build
   `R.exe`, `Rcmd.exe` (and evaluate `Rscript.exe`, see §5) from the *same*
   `win-exec-forward.c` source already compiled for `gcc.exe`/`g++.exe`
   (`winCompilerWrapper`, `build.zig:1743`), just pointed at `bin/R`/
   `bin/Rcmd` instead of `toolchain/zig-cc`/`zig-cxx`:
   ```zig
   const win_r = winCompilerWrapper(ctx, "R", bash_abs, bin_r_abs);
   const win_rcmd = winCompilerWrapper(ctx, "Rcmd", bash_abs, bin_rcmd_abs);
   ```
   This directly replaces `winCmdFrontend` (`build.zig:1713`) and its two
   call sites — no more compiling `rhome.c`/`shext.c`/`rcmdfn.c`/`R.c`/
   `rcmd.c` at all.
3. **R_HOME computed once, the same way on every platform.** `bin/R`'s own
   `R_HOME_DIR=` (patched at install time by `mkRFront`, identical
   mechanism already in use) becomes the *only* place R_HOME is determined
   on Windows too — `rhome.c`'s `GetModuleFileName`+`dirstrip` scheme is
   deleted, not ported. `Rscript.c`'s own separate Windows R_HOME block
   (`Rscript.c:230-266`) is unaffected by this change (Rscript.exe is out
   of scope for the forwarder swap, see §5) but is worth flagging as the
   next candidate once this pattern is proven.

### What gets deleted

- `src/gnuwin32/front-ends/rcmdfn.c` (546 lines) — replaced by `bin/R` +
  `bin/Rcmd` + `scripts_s`, already-shipping code, zero new lines.
- `src/gnuwin32/front-ends/R.c`, `rcmd.c` — replaced by two
  `win-exec-forward.c` instantiations (already-shipping code).
- `src/gnuwin32/rhome.c`, `shext.c` — R_HOME/RUser computation folds into
  the shell scripts' own logic (`bin/R`'s `R_HOME_DIR=`, `Rcmd.in`'s
  `HOME`/`TMPDIR` handling already present around its Renviron-sourcing).
- `winCmdFrontend` (`build.zig:1713`, ~23 lines) and its two call sites
  (`build.zig:1086-1087`).
- The `etc/Rcmd_environ` file's `R_OSTYPE=windows` line stays (still needed
  by `bin/Rcmd`'s Renviron-sourcing step, exactly as it's used by
  `Rcmd.in` already), but the file no longer needs vendoring from gnuwin32
  fixed sources if `Rcmd.in`'s own `R_OSTYPE=` line is patched directly
  instead — worth deciding during implementation, not blocking this plan.

## 4. Why this is lower-risk than it sounds

- **Not new code.** Every piece being reused (`bin/R`, `bin/Rcmd`,
  `scripts_s`, `win-exec-forward.c`) already ships today, in this exact
  build, proven working (Unix's whole front-end; Windows'
  `gcc.exe`/`g++.exe`). This plan combines two already-verified mechanisms;
  it introduces zero new architecture.
- **The recursive-crash bug (TODO.md F7.1, still open)** — a real
  access-violation when a package's `configure` script recursively
  re-invokes `R.exe` several process levels deep — is exactly the class of
  fragility a compiled-C `system()`/`CreateProcess` dispatcher is prone to
  and a shell `exec` chain is not (no equivalent recursive C call stack;
  each `exec` replaces the process rather than nesting it). This plan may
  fix it as a side effect, but that is not its stated goal and should not
  be assumed without re-testing on kappa.
- **Smaller diff than it looks.** The change is almost entirely deletion:
  ~900 lines of C (`rcmdfn.c` + `rhome.c` + `shext.c` + `R.c` + `rcmd.c`)
  replaced by two `winCompilerWrapper` call sites (a handful of lines) plus
  two small `.in`-template patches to reuse for Windows, matching patches
  `mkRFront` already does for Unix.

## 5. Explicitly out of scope for this pass

- **Rterm.exe / Rscript.exe stay compiled binaries**, same as Unix's
  `bin/exec/R`. They are the real interpreter, not a dispatcher — nothing
  to unify there structurally. `Rscript.c`'s own separate Windows R_HOME
  logic is flagged (§3) but not touched here; folding it in is a natural
  follow-up once `bin/R` genuinely exists on Windows and `Rscript.exe`
  could `exec` into it exactly like Unix's `Rscript` does today
  (`Rscript.c:279,394`) instead of embedding `AppMain()` in-process — a
  bigger, separately-riskier change (behavioral: subprocess vs in-process)
  that deserves its own review once this smaller piece is proven.
- **`javareconf`/`mkinstalldirs`/`pager`/`rtags`** (`scripts_b`) are not
  currently installed on Windows at all and stay out of scope — no
  Windows equivalent exists today to unify against, and nothing in F1-F7
  depended on them.
- **`Rgui.exe`** was already ruled out of this build entirely (F6.0,
  CLI-only scope) — not revisited by this plan.

## 6. Verification plan (once implemented)

Same discipline as every other phase in this milestone — real testing on
kappa, not just a local build:

1. `pixi run zig-build` on kappa; confirm `R.exe`/`Rcmd.exe` are now the
   native-forwarder shape (tiny, near-identical file size to `gcc.exe`).
2. `Rcmd.exe config CC` and `R CMD config CC` — the exact command
   `install.packages()` shells out to (root cause of the original bug
   report) — from a real `Rscript.exe` session, not just a bare shell.
3. `install.packages("pak", repos = "https://cloud.r-project.org")` full
   end-to-end — the original failing repro.
4. `R CMD INSTALL`, `R CMD SHLIB`, `R CMD BATCH`, `R CMD build`,
   `R CMD check` against a real package with compiled code — covers every
   `rcmdfn.c` branch being deleted.
5. Re-attempt the recursive-configure crash repro from F7.1 (`pak`'s
   `configure` → nested `R.exe` chain) — record whether it reproduces,
   don't assume it's fixed.
6. `pixi run smoke` / `contract` / `check` — full regression, unrelated
   surface area shouldn't move at all.

## 7. Open questions for the user before implementation starts

- Should `Rcmd_environ`'s `R_OSTYPE=windows` line move into a Windows-
  specific patch of `Rcmd.in` directly (one file, matching `mkRFront`'s own
  patch style), or stay a separately-vendored static file as it is today?
  Either works; the former reduces file count further, the latter is a
  smaller diff from today's already-working F7.1 state.
- Is the `Rscript.c`/Rterm.exe R_HOME unification (§5) wanted as a
  follow-up in the same effort, or should this stay scoped to R.exe/
  Rcmd.exe only for the first pass?
