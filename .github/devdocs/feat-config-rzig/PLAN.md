# feat-config-rzig — `R CMD config` answered by rzig

**Status (2026-11-13).** Item C of the release-11 PR (#48, branch
feat-win-arm64, base 7697c75). Implemented and tested on linux-64; macOS
and Windows not run (see "Left for macOS and Windows"). Not committed:
the user commits. pixi.lock unchanged.

## Why

`R CMD config VAR` was R's src/scripts/config, a sh script that asks make
for `$(VAR)` of etc${R_ARCH}/Makeconf plus the site's and user's Makevars
(on Windows bin/config.sh, started by rcmdfn.c with `sh`). So the query
pkgbuild, pak, rstan (after each `stan_model()` compile) and configure
scripts run first needed the build-tools group, although `rzig build`
compiles tier 0 to 2 packages without make. The earlier patch 0010 only
put rzig's build-tools check in front (exit 127 with the group's text).
Recorded in feat-standalone-toolchain/TODO.md ("Depend less on make ...
Left: `R CMD config` through rzig", pkgbuild's `has_rtools()`).

## The user's decisions

- 2026-11-12: do it now.
- 2026-11-13, point 4 = A: "Makevars constructs that cannot be answered
  without make ($(shell) inside :=, define, !=, and similar) make
  `R CMD config` exit 2 with a message naming the construct, the file and
  the line. Lazy = values that contain $(shell) but are never evaluated
  stay harmless. No fallback to make."

## Design

- Route, the same on every OS: R CMD's own dispatch runs
  `R_HOME/bin/toolchain/rzig config <args>`. Patch
  `0010-config-rzig.patch` (replaces `0010-config-make-check.patch`):
  - unix: `src/scripts/Rcmd.in` gets a `config)` case (cmd = rzig, extra
    = config), beside R's `Rd2txt)` case, which uses `extra` the same way.
  - Windows: `src/gnuwin32/front-ends/rcmdfn.c` builds
    `""<RHome>/bin/toolchain/rzig.exe" config` and closes the outer quote
    itself when no argument follows (PROCESS_CMD closes it only when
    arguments follow; cmd.exe would otherwise strip the wrong quote).
  - bin/config (unix, rspec.zig `scripts_s`) and bin/config.sh (Windows,
    build.zig) are no longer installed. src/scripts/config is untouched
    and serves as the parity test's reference.
  Rejected: a two-line sh bin/config that execs rzig (an extra sh hop,
  unix only, Windows still needing its own route); a copy of rzig named
  bin/config (a second place for the binary).
- rzig: new subcommand `config` (main.zig) → `config.zig`. It follows the
  script step by step: no arguments → usage, exit 1; options in order up
  to the first empty argument; `-h/--help`, `-v/--version` (r89241 and
  R_VERSION from the environment); `--cppflags`/`--ldflags` from Makeconf
  alone, "R was not built as a library" on stderr with exit 0;
  `--no-user-files`, `--no-site-files`, `--all`; a second variable →
  stderr "ERROR: cannot query more than one variable", 1; defunct →
  stderr "'config' variable 'X' is defunct", 2; unknown → stdout
  "ERROR: no information for variable 'X'", 1.
- Files, the script's rule (not install.R's): `etc${R_ARCH}/Makeconf`;
  site: R_MAKEVARS_SITE when set (even empty), else
  `etc${R_ARCH}/Makevars.site`, when it is a file; user: R_MAKEVARS_USER
  when a file, else unix `~/.R/Makevars-$R_PLATFORM`, `~/.R/Makevars`;
  Windows (R_OSTYPE=windows) `Makevars.ucrt`, `.win64`, `.win`, then
  `Makevars`. share/make/config.mk holds only the print rules and is not
  read. R_HOME from the environment, else rzig's own place
  (R_HOME/bin/toolchain/rzig). Windows: R_DOC_DIR, R_INCLUDE_DIR and
  R_SHARE_DIR from R_HOME, MAKE = make, as the script sets them. R_ARCH
  is /x64 on win-64 and win-arm64 (rcmdfn.c; build.zig), so both read
  etc/x64/Makeconf.
- Evaluation: makefile.zig's evaluator (the one `rzig build` uses) in
  `makeconf` mode, R_HOME and VAR on the command line. Extensions:
  `Origin.default` and `seedDefaults` (GNU make 4.4's built-in variables,
  CC=cc, CXX=g++, FC=f77, OBJC=cc, CPP, AR, RM, MAKE=$(MAKE_COMMAND) ...,
  set before the environment, which beats them; only config seeds them,
  package builds are unchanged); every assignment records `file:line`,
  and an unsupported construct sets `where` (the line being read, or the
  assignment of the recursive variable whose value needed it).
  Also for config only (`seedMakeVariables`, `vars_only`; review fix
  2026-11-13): CURDIR (the working directory, `/` separators), MAKELEVEL
  (the environment's, else 0), SHELL = /bin/sh (make does not take it
  from the environment), `.SHELLFLAGS` = -c, MAKECMDGOALS (`print`, or
  `print-name-and-value` for --all). The variables only make can know
  (MAKEFLAGS, MFLAGS, MAKEFILE_LIST, MAKE_VERSION, MAKE_HOST,
  MAKE_TERMOUT, .VARIABLES, .DEFAULT_GOAL, ...: `make_only`) are seeded
  `automatic`, and reading one fails (exit 2) instead of printing "".
  `vpath` is skipped (it steers rules only); in package builds it is
  still refused.
- Exports (review fix 2026-11-13): makefile.zig records `export NAME`,
  `export NAME = v`, `unexport NAME`, `export` and `unexport` alone, and
  `.EXPORT_ALL_VARIABLES:`. `Evaluator.exported` follows GNU make's
  target_environment: an explicit export or unexport wins; the
  environment's names are exported from the start (so a file's override
  of one is exported with the file's value); command-line variables are
  exported; after `export` alone, every other variable with a sh name
  except make's built-in and automatic ones. In a package's Makevars
  (`makevars` mode) `export NAME` is refused as before (it changes the
  compiler's environment, so that package needs make).
- The echo: config.mk's recipe is `@echo $($(VAR))`, so the value goes
  through sh's word rules. shellwords.zig gets `splitWith(.{ .shell =
  env })`: quotes removed, whitespace collapsed, `$NAME`/`${NAME}` from
  what make exports (`Evaluator.exported` above, with make's values;
  SHELL is the environment's unless exported by name; MAKELEVEL is one
  more than make's; MAKEFLAGS, MFLAGS, MAKE_TERMOUT and MAKE_TERMERR,
  which make always passes, give exit 2), `~` and `~/` as HOME, `#` at a
  word start as a comment. Command substitution, special parameters,
  `;|&<>()`, backquotes and an unquoted glob character (`*?[`, which sh
  matches against the caller's directory, also inside an unquoted
  `$NAME`) give exit 2. `split` stays strict for `rzig build`.
- Variable lists and help text compiled in: the lists in config.zig as
  the script writes them; the usage text verbatim in config_usage.txt
  (@embedFile: it has tabs, which Zig's multiline strings refuse), the
  Windows lines and the tail in config.zig. Kept honest by the parity
  test (--help, --version, --all and every variable, both R_OSTYPE
  branches), which fails when R changes the script.
- What only make can answer (decision 4 A): exit 2, stdout empty, stderr
  `R CMD config: <file>:<line>: <construct>: R CMD config reads these
  files without make, so it cannot answer`. `:=` and conditionals are
  evaluated while the file is read, so a `$(shell)` there fails any
  query; a recursive value fails only when printed. `--all` prints
  nothing on such a failure (the script would print the rest).
- Patch 0010's check is gone: no group is needed for a query.
  `--rzig-check=build-tools` stays (check.zig; verify-bundle uses it).

## Known differences from the script

Silent differences (exit 0 on both sides, different output):

- Under make, dash's `echo` expands backslash escapes and takes a leading
  `-n`; rzig prints the words as they are. No Makeconf value has either.
- `R CMD config` with R_HOME containing spaces: the script broke (its
  `R_HOME=${R_HOME}` is unquoted in an eval); rzig answers.
- Windows (kappa, 2026-11-13): the script runs under MSYS's sh and
  make, which see the environment as MSYS converts it. A path from the
  environment (`$$HOME`, CURDIR) prints in MSYS's spelling there
  (`/tmp/...`); rzig, a native program, prints the native one R gives it
  (`C:\...`; CURDIR `C:/...`, as make writes it). Same directory, other
  spelling; for R's native callers (pkgbuild, rstan) the native one is
  the usable one. `$$SHELL` prints MSYS bash's `/usr/bin/bash` under the
  script and nothing under rzig (no SHELL in R's environment).
  config-parity.sh maps the scratch directory's spellings to one token
  on Windows and leaves the two `$$SHELL` cases out there.
- Windows backslashes (CI, 2026-11-15, run 43718810854): GitHub's
  Windows runners set `JAVA_HOME=C:\hostedtoolcache\...`. R's script
  printed it with its backslashes, rzig without (9 of 309 cases with the
  next item). MSYS's make (GNU Make 4.4.1, built with HAVE_DOS_PATHS)
  runs a recipe line with no unquoted shell metacharacter itself, without
  sh, and keeps a backslash unless a `\`, `'`, whitespace or a
  metacharacter follows it; a line that does go through sh follows sh's
  rule (kappa, 2026-11-15, `echo` of 34 values). rzig reads the echo
  line so on a Windows host (shellwords.zig, `.msys_make`). Package
  compile lines are left as they are: R's always hold a `"`
  (`-I"$(R_INCLUDE_DIR)"`), which sends the line through sh. Also from
  that run: R's MSYS spelled the scratch directory `/c/Users/...` (it has
  no /tmp mount) where the script's MSYS said `/tmp/...`;
  config-parity.sh maps that spelling too. And GitHub's runners have
  `TEMP=C:\Users\RUNNER~1\...` (an 8.3 short name) while make's CURDIR
  comes back in the long form: config-parity.sh takes the scratch
  directory's long form (`cygpath -m -l`; kappa, 2026-11-15, with an 8.3
  TMPDIR).

Exit 2 where make answers (decision 4 A: a refusal, never a wrong
answer). The full list:

- make functions makefile.zig lacks: `$(shell)`, `$(foreach)`,
  `$(call)`, `$(eval)`, `$(file)`, `$(error)`, `$(warning)`, `$(info)`,
  `$(abspath)`, `$(realpath)`, `$(let)`, `$(intcmp)`, `$(guile)`, in a
  `:=`, a conditional or an include line (read with the file), or in a
  recursive value that is printed (a value never printed is harmless);
- directives: `define`, `!=`, `undefine`, `load`, `private`; a missing
  include or `$(error)` (make fails too, with its own text);
- make's own variables: MAKEFLAGS, MFLAGS, MAKEOVERRIDES, GNUMAKEFLAGS,
  MAKEFILE_LIST, MAKEFILES, MAKE_VERSION, MAKE_HOST, MAKE_RESTARTS,
  MAKE_TERMOUT, MAKE_TERMERR, .DEFAULT_GOAL, .VARIABLES, .FEATURES,
  .INCLUDE_DIRS, .LOADED, .RECIPEPREFIX, .LIBPATTERNS, .EXTRA_PREREQS,
  SUFFIXES (as `$(X)`, `$(value/origin/flavor X)`, `ifdef X`, or `$$X`
  for the four make always exports);
- in the echoed value, what sh does beyond quotes, `$NAME`, `${NAME}`,
  `~` and `#`: `${VAR:-x}` and the other operators, `$$(cmd)` and
  backquotes, special parameters (`$1`, `$@`, `$?` ...), `~user`, `;`,
  `|`, `&`, `<`, `>`, `(`, `)`, and unquoted `*`, `?`, `[`;
- `--all` with one such value: exit 2 and no output, where the script
  printed make's answer (or error) for each variable and went on.

## Files

- zigbuild/patches/R-4.6.2/0010-config-rzig.patch (new; replaces
  0010-config-make-check.patch)
- zigbuild/tools/rzig/config.zig, config_usage.txt (new); main.zig
  (subcommand, usage, test import, comments); makefile.zig (defaults,
  origins default and automatic, make's own variables, exports, vpath
  for config, locations); shellwords.zig (splitWith); check.zig,
  groups.zig (comments)
- zigbuild/rspec.zig (no bin/config), build.zig (no bin/config.sh,
  comments)
- scripts/config-parity.sh (new), scripts/zig-contract.sh (runs it),
  pixi.toml (contract's comment)
- Tests that expected exit 127 without build tools, changed on purpose to
  expect an answer: scripts/hermetic-check.sh (base alone, no make, no
  sh on PATH: exit 0 and R's CC), recipe/test-preflight.R (was Windows
  only: 127; now every OS: exit 0, CC, and --all), recipe/test-compilers.R
  (127 → exit 0, CC and FC). Comment-only: recipe/test-build-tools.R,
  scripts/verify-bundle.sh, scripts/verify-helpers.sh.
- README.md, scripts/make-wheel.py (build tools no longer for R CMD
  config), recipe/recipe.yaml (build 11's note),
  feat-standalone-toolchain/TODO.md.

## Tests (linux-64, 2026-11-13, conda-forge zig 0.17.0 unless noted)

Logs in the agent's scratch directory (rel11/scratchb-config).

| command | exit |
|---|---|
| `pixi run --frozen build -- -j6` (three times, the last with the final code) | 0 |
| `pixi run --frozen bash scripts/config-parity.sh` (dist tree): 288 cases equal to R's script with make, plus 4 exit-2 cases | 0 |
| `pixi run --frozen rzig-test` (198 unit tests, parity-test.sh) | 0 |
| `ZIG_BIN=<PyPI ziglang 0.17.1> pixi run --frozen rzig-test` | 0 |
| `zig build --build-file zigbuild/tools/rzig/build.zig -Dtarget=` x86_64-windows-gnu, aarch64-windows-gnu, aarch64-macos, x86_64-macos, aarch64-linux-gnu (compile only) | 0 each |
| patched rcmdfn.c, `zig cc -target x86_64-windows-gnu -fsyntax-only` | no diagnostics |
| `pixi run --frozen smoke` | 0 |
| `pixi run --frozen verify-tree` | 0 |
| `pixi run --frozen hermetic` | 1, then 0: its strace allowlist now names R_HOME/bin/toolchain/rzig |
| `pixi run --frozen toolchain -- -j6`, `compile-tree` | 0 |
| `pixi run --frozen contract` (config-parity.sh on the compile tree first: 288 cases) | 0 |
| `env -i PATH=<tree>/bin strace -e execve <tree>/bin/R CMD config CC` | 0; programs: /bin/sh (bin/R's Rcmd), bin/R, rzig; no make |

Review fix pass (2026-11-13; an independent review found `export`
ignored, CURDIR/MAKELEVEL unset, and an incomplete list of differences;
logs in rel11/scratchb-config/fix/):

| command | exit |
|---|---|
| `pixi run --frozen rzig-test` (200 unit tests, new: exports, make's variables, globs) | 0 |
| `ZIG_BIN=<PyPI ziglang 0.17.1> pixi run --frozen rzig-test` | 0 |
| `pixi run --frozen build -- -j6` | 0 |
| `pixi run --frozen bash scripts/config-parity.sh` (dist tree): 306 cases (+ export, unexport, `export` alone, .EXPORT_ALL_VARIABLES, vpath, CURDIR, MAKELEVEL from the environment, SHELL, MAKECMDGOALS; exit 2 for MAKEFLAGS, `$$MAKEFLAGS`, MAKEFILE_LIST, a glob) | 0 |
| reviewer's differentials re-run (export, `export` alone, unexport, CURDIR/MAKELEVEL, SHELL, vpath): equal to make; `*`, MAKEFLAGS, foreach, `${HOME:-x}`, a glob in `$FOO`: exit 2 | as designed |
| `env -i <tree>/lib/R/bin/toolchain/rzig config CC` (no environment, no PATH) and `env -i PATH=<tree>/bin R CMD config CC` | 0, 0 (fix/nomake2.log) |
| `pixi run --frozen smoke`, `verify-tree`, `hermetic` | 0, 0, 0 |
| `pixi run --frozen toolchain -- -j6`, `compile-tree`, `contract` (306 parity cases on the compile tree) | 0, 0, 0 |
| rzig cross-compile for x86_64/aarch64-windows-gnu, x86_64/aarch64-macos, aarch64-linux-gnu | 0 each |

Not run here: conda-package and its recipe tests (test-preflight.R,
test-compilers.R, test-build-tools.R), verify-bundle, wheel-test.

## Left for macOS and Windows

On omicron (osx-arm64; osx-64 under Rosetta) and kappa (win-64;
win-arm64 in CI): build, smoke, verify-tree, rzig-test, toolchain,
compile-tree, contract (runs config-parity.sh first; on Windows through
R.exe's CMD and the build-tools group's sh and make), hermetic (Windows:
PATH = bin\x64 + System32, so no make and no sh). On kappa also:
`pkgbuild::has_rtools(debug = TRUE)` with base + compilers only (TODO.md
item), `R CMD config` with no arguments from cmd.exe (rcmdfn.c's closing
quote), and an R_HOME path with a space. CI: conda-package (recipe tests
above) on every leg.

(2026-11-24, b13-hosts H3 and CI12, build 12 from universe on kappa:
done. has_rtools(debug = TRUE) is TRUE with r-zig-slim and
r-zig-compilers alone, from "R CMD config CC" once Rtools45 is hidden;
R CMD config answers from cmd.exe, also in an env under a path with a
space. Details in b13-hosts/PLAN.md.)
