# The stress suite

An on-demand test of r-zig's toolchain on hard-to-build CRAN and Bioconductor
packages. It installs each package from source, loads it, runs one small
call, and reports per package, OS and distribution whether that worked.

It is a diagnostic. It never runs on a push or a pull request, and a failing
package does not fail the run.

## The files

| file | what it is |
|---|---|
| `packages.tsv` | the data: one row per target, with its group, OSes, system libraries, env vars, timeout, expected result, smoke call and a note. The header explains each column. |
| `stress.R` | the one entry script. Base R only. `--help` prints its options. |
| `pixi.toml`, `[feature.stress]` | the `stress` environment: the system libraries the rows need (GDAL, GEOS, PROJ, cmake, ...), plus the default feature's zig and flang. |
| `.github/workflows/stress.yaml` | the manual CI workflow. |

The groups follow the brief:

| group | what it tests | rows |
|---|---|---|
| g3 | C libraries from the env (rzig's `-I`/`-L` rule) | curl, openssl, xml2, gert, units, systemfonts, textshaping, ragg, magick, hdf5r, ncdf4, gsl, Rmpfr, RPostgres |
| g4 | own build systems and bundled code | nloptr, s2, igraph, stringi, stringi:bundled, qs2, fst, geos, Rhdf5lib |
| g2 | C++ across a library boundary (the C++ ABI risk) | lwgeom, sf, terra, gdalraster, RcppParallel, RcppParallel:system-tbb, protolite, arrow, arrow:source, V8 |
| g1 | heavy C++ | Rcpp, RcppArmadillo, lme4, StanHeaders, rstan, duckdb, mlpack |

The runner installs the rows in file order (cheap groups first), each after
its dependencies, and the `name:variant` rows last. The tag `heavy` marks
the longest builds (duckdb, mlpack, arrow:source), so `--skip=heavy` leaves
them out. A `name:variant` row installs the same package again with other
env vars, into a library of its own (for example `stringi:bundled` builds
stringi's own ICU).

## Run it locally

The tree (the dev tree that `pixi run build` makes, with the stress env's
libraries):

```sh
pixi run build
pixi run -e stress stress g3                  # a group
pixi run -e stress stress gsl units           # some packages
pixi run -e stress stress --skip=heavy        # all rows but the longest
pixi run -e stress stress --list g1           # the install plan only
```

The conda distribution (r-zig-slim and r-zig-toolchain, plus the selected
rows' system libraries, in a fresh pixi env):

```sh
pixi run -e pkg conda-package                 # this checkout's packages, in dist/conda
pixi run -e stress stress --conda g3          # from dist/conda
pixi run -e stress stress --conda=universe g3 # the packages published on prefix.dev
```

`--conda` makes the env in `<run dir>/conda` with pixi, then runs `stress.R`
again with that env's R. The dev tree's R only starts it: any R works for
that step.

Useful options (`--help` lists them all):

- `--out=DIR`: the run directory. The default is
  `build/stress/<os>-<arch>-<dist>-<time>`. Put it on a big disk: a full run
  may need about 10 GB (the library, zig's cache of every object, the build
  temp files, and with `--conda` the env, about 1 GB more). Delete the run
  directory once you have read the report.
- `--jobs=N`: `make -jN` and cmake's parallel level. The default is the
  number of cores, at most 8. rstan needs about 2 to 3 GB per job.
- `--resume`: with an existing `--out`, keep what is already installed.
- `--trace`: rzig prints the environments it chose and its zig command
  into the logs (`RZIG_TRACE=1`), as lines that start with `zig-cc:` and the
  like.
- `--keep-path`: keep your PATH. By default the runner narrows it.
- `--strict`: exit 1 when a result differs from its `expect`.

## Run it in CI

Actions, "stress", "Run workflow", or with `gh`:

```sh
gh workflow run stress.yaml -f oses='["ubuntu-latest","macos-latest"]' -f packages='g3 g4'
gh workflow run stress.yaml -f packages=g2 -f distribution=both -f channel=universe
gh workflow run stress.yaml -f packages=all -f skip=heavy -f jobs=2
```

The inputs are the runners (a JSON list), the targets, rows to skip, the
distribution (tree, conda or both), the conda channel (local: this run's
`conda-package`; universe), the job count and the zig (conda-forge's, or
upstream's from `pixi run fetch-zig`). Each OS and distribution is one job.
Jobs never stop each other (`fail-fast: false`) and may take up to 6 hours.

Every job builds the dev tree. The conda job with the local channel also
builds the conda packages. The report goes to the job summary. The
artifact `stress-<os>-<dist>` holds `report.md`, `report.json`, the logs, the
smoke files and the conda env's `pixi.toml` and `pixi.lock`.

## What a run does

For each package, dependencies first:

1. Download the source from CRAN or Bioconductor's release for this R
   (base R's `setRepositories(ind = 1:2)`, no BiocManager), with 3 tries.
2. Install it with `R CMD INSTALL` in a child process, with the row's env
   vars and timeout. A network failure gets two more tries.
3. Load it and run the row's smoke call in a fresh R. Dependencies are only
   loaded.

A package whose dependency failed is skipped. A dependency counts as failed
when its install, its load or, for a target, its smoke call failed (in round
1 on Windows, stringi's smoke call skipped textshaping and ragg). The report
is rewritten after every package, so a killed run still has one.

What the runner sets for the children, so that the run tests r-zig and
nothing else on the machine:

- A fresh library in the run directory (`lib/`), and no other library:
  `R_LIBS`, `R_LIBS_USER` and `R_LIBS_SITE` all point to it. Each package is
  installed once per run, and later packages use it.
- An empty file for `R_MAKEVARS_USER`, `R_ENVIRON_USER` and `R_PROFILE_USER`.
- `TMPDIR` and zig's cache in the run directory. The temp files are deleted
  after each package. rzig's own cache stays where it is: with conda-forge's
  zig on macOS it makes a libc++ mirror (a directory of symlinks) in
  `$XDG_CACHE_HOME/r-zig`, by default `~/.cache/r-zig`.
- A narrow PATH. On Linux and macOS: `<env>/bin:/usr/bin:/bin`, the rule
  `scripts/env.sh` uses for the build. On Windows, where env.sh keeps PATH,
  the runner's own list: R's `bin/x64`, the env's directories, and System32.
  So Homebrew, Rtools or a MinGW gcc cannot step in, and the env's
  pkg-config comes first. A tool the env lacks can still come from
  `/usr/bin` or `/bin`. R's `bin/toolchain` is not on PATH: packages reach
  rzig through Makeconf.
- Windows only: `R_TOOLS_SOFT` is the env's `Library`, where packages built
  for Rtools look for libraries (sf and terra copy GDAL's and PROJ's data
  from there).

The distribution comes from where R lives. An R inside a conda env (its root
has `conda-meta`) is "conda", and that env holds the libraries. Otherwise it
is "tree", and the libraries env is `R_ZIG_EXTRA_ENV`. The stress env sets it
(the `pipeline` feature), so rzig adds that env's `-I`, `-L` and rpath.

The timeout uses `system2(timeout=)`: on Linux and macOS R kills the child's
process group, on Windows its job object. Only the Linux path has been seen
working (the harness test); no row has timed out on macOS or Windows yet.

## Read the report

`report.md` starts with the run: date, R, commit, minutes, jobs, zig, the
`CC` from Makeconf and the libraries env. The commit is `GITHUB_SHA` when it
is set, else the checkout's `git rev-parse HEAD`, plus "(modified)" when
tracked files have changes; a copy without `.git` says "unknown". Then one
line per target:

| column | meaning |
|---|---|
| package | the row; `(!)` marks a result that differs from `expect` |
| status | `ok`, `install-failed`, `smoke-failed`, `timeout`, `skipped` (a dependency failed), `download-failed`, `unavailable` (not on CRAN or Bioconductor), `error` (the harness) |
| class | the runner's guess at the cause, from the failing part of the log |
| expect | the row's expectation for this OS |
| min, MB | install minutes and installed size |
| first error | the first error line of the log |

Dependencies that did not install follow the table. Each package has
`logs/<package>.log` (the install) and `logs/<package>-smoke.log`.
`report.json` has the same data, plus the run's details.

The classes, and who acts on them:

| class | what it looks like | next step |
|---|---|---|
| network | `cannot open URL`, HTTP 4xx/5xx, `curl: (n)`; also a package missing from the repositories | rerun |
| resource | out of memory, no space left | fewer jobs, a bigger runner |
| abi | an undefined symbol with `St3__1`, `__cxx11` or an MSVC name: libc++ code against a libstdc++ (or MSVC) library | a design decision for the user |
| toolchain | rzig's own messages (`zig-cc: cannot run ...`), `LLVM ERROR`, an unknown option, a missing compiler-rt helper | fix in rzig, after the user agrees |
| sysdep | `configure: error`, a missing header, `-l` or pkg-config module, `command not found` | add it to the stress feature (or the extras for tools) |
| package | anything else: C23 keywords, gcc-only code, Rtools assumptions | record it |
| timeout | the row's timeout passed | read the log: a hang, slowness, or memory |

Three more values appear: `dependency` on a `skipped` row, `harness` on an
`error` row, and `resumed` on a package that `--resume` kept.

The class is a guess. The final class is a person's call, written down with
the log. There is no class for an upstream packaging bug (a conda-forge
library with a broken `.pc` file or a Homebrew path): the runner calls it
`sysdep` or `package`.

## Results

- Round 1, 2026-10-08, the tree on linux-64, osx-arm64 and win-64:
  [results/2026-10-08.md](results/2026-10-08.md).

## Notes and known issues

- The `expect` column is a guess until a run confirms it. Update it with
  each round of results. Round 1's values are not in `packages.tsv` yet
  (see its results file).
- The stress env is not in solve group "r": there its libraries changed the
  R envs' lock entries. So it can differ from the default env by a patch or
  build (libxml2, llvm-openmp, glib, python on 2026-10-08). Compare them
  after each re-lock: `pixi list -e default` and `pixi list -e stress`.
- 2026-10-08: the published r-zig-slim build 4 cannot share an env with
  conda-forge's libgdal-core. r-zig-slim needs `libdeflate >=1.26` (the
  version its build solved), and every libgdal-core needs `<1.26`. A conda run
  with sf, terra, lwgeom or gdalraster stops at `pixi install` and its report
  says so. The tree is not affected: the lock holds libdeflate 1.25.
- The conda env holds only the selected rows' libraries. A run's env can
  therefore change a package's build path: on macOS, s2 takes abseil from
  the env when libprotobuf is there. The tree's stress env holds them all.
