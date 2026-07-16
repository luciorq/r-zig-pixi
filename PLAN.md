# r-zig-pixi — Building R with a Single, Hermetic, Cross-Platform Toolchain

## Goal

Build R from source on Linux, macOS, and Windows with **one build design**,
using **only tools installed from conda-forge through pixi**. A machine with
nothing but `pixi` on it must be able to run:

```sh
pixi run build && pixi run smoke
```

Explicit non-goals: binary compatibility with CRAN/Rtools builds, quartz/aqua
support on macOS, X11 support anywhere (see "feature parity" below).

## Architecture decisions

### 1. Toolchain: zig everywhere, flang/gfortran for Fortran

| Role | linux-64 | win-64 | osx-64 / osx-arm64 | linux-aarch64 |
|------|----------|--------|--------------------|---------------|
| C    | `zig cc` | `zig cc` | `zig cc` | `zig cc` |
| C++  | `zig c++` | `zig c++` | `zig c++` | `zig c++` |
| Fortran | `flang` (LLVM 22) | `flang` (LLVM 22) | `gfortran` (explicit pkg) | `gfortran` (explicit pkg) |
| ar/ranlib | `zig ar` / `zig ranlib` | same | same | same |

- Zig has no Fortran frontend, so Fortran comes from conda-forge. LLVM flang is
  preferred (same LLVM backend and target conventions as `zig cc`); conda-forge
  only ships it for linux-64 and win-64 today, so macOS and linux-aarch64 use an
  explicitly pinned `gfortran` package — *not* the `compilers`/`c-compiler`
  metapackages, which would drag in a full GCC/Clang C toolchain.
- Revisit when conda-forge ships flang for osx-* (tracked in TODO.md).

### 2. Toolchain shims (`toolchain/zig-cc`, `zig-cxx`, `zig-ar`, `zig-ranlib`)

Autoconf and R's `Makeconf` want single-word compiler commands. The shims also
carry one load-bearing flag: **`-fno-sanitize=undefined`** — `zig cc` enables
UBSan in trap mode by default, and R's numeric code contains benign undefined
behavior that would otherwise die with SIGILL at runtime.

Because these shim paths get recorded into `etc/Makeconf`, every R *package*
compiled by this R later inherits the zig toolchain automatically. Makeconf is
the distribution mechanism for the toolchain — no `~/.R/Makevars` hijacking.

### 3. Feature parity = lowest common denominator, chosen deliberately

The same `capabilities()` profile on all three OSes:

- **X11: off everywhere** (`--with-x=no`). Windows and modern macOS have no X11;
  keeping it on Linux would break parity.
- **Graphics: cairo everywhere** (`--with-cairo --with-libpng`). Cairo works
  headless on all platforms. Quartz is dropped on macOS (`--without-aqua`),
  which also removes the Apple-SDK dependency.
- **BLAS/LAPACK: R's internal reference implementation** for v1 — zero external
  ABI risk. An `openblas` pixi feature is a later milestone.
- **Timezones: `--with-internal-tzcode`** + conda-forge `tzdata`, identical
  behavior on all platforms instead of trusting the OS zoneinfo.
- `--enable-R-shlib` (libR.so), `--without-recommended-packages`,
  `--disable-java`.

### 4. Two build variants: slim (default) and full — never more

`capabilities()` is baked at compile time, so capability choices are build
variants, not dependency toggles. To keep the variant matrix sane there are
exactly two, mapped to pixi environments (separate objdirs and prefixes,
`obj-<ver>-slim` / `obj-<ver>-full`):

- **slim (default env)** — the headless profile: cairo+png graphics, ICU,
  pcre2, libcurl, compression stack, internal BLAS, R shlib. No X11/quartz/
  tcltk/readline/NLS/jpeg/tiff. This is where R runs in practice (servers,
  CI, containers, IDE-server backends).
- **full (`pixi run -e full …`)** — slim plus tcltk (conda-forge tk via
  `--with-tcl-config`/`--with-tk-config`), readline+ncurses for the
  interactive console, NLS/gettext translations, jpeg+tiff devices.

What slim deliberately keeps: ICU, iconv, long double, libcurl, pcre2 —
anything whose removal would silently *change results or break package
installation* rather than just shrink the build. Slim must be smaller,
never differently-numbered.

Note: there is no configure-level way to trim R's legacy C API surface —
that's compiled unconditionally and every CRAN package assumes it. API
trimming is a milestone-5 (`build.zig`) ambition, not a configure flag.

### 5. Portable userland

- Build scripts are bash, but bash itself comes from conda-forge (`bash` on
  Unix, `m2-bash` on Windows). Orchestration entry points are pixi tasks, which
  are already cross-platform.
- Coreutils are the Rust uutils (`uutils-coreutils`) on linux-64/osx/win-64;
  GNU `coreutils` on linux-aarch64 where uutils isn't packaged. sed/grep/gawk/
  tar/gzip/curl all from conda-forge.
- The zig compile cache lives in `build/zig-cache/` inside the workspace, not
  in `$HOME` — nothing leaks onto or from the host.

### 6. Source provenance

R source comes from CRAN as a release tarball, pinned by version in
`pixi.toml` (`R_VERSION`) and by sha256 in `scripts/checksums/` (pinned on
first fetch, then enforced).

## Layout

```
pixi.toml              # platforms, toolchain deps, features, tasks
toolchain/zig-*        # compiler shims recorded into R's Makeconf
scripts/env.sh         # shared paths/helpers, sourced by all scripts
scripts/*.sh           # fetch / configure / build / smoke / check / install / clean
scripts/checksums/     # pinned source tarball hashes
build/                 # (gitignored) source tree, out-of-tree objdir, zig cache
dist/                  # (gitignored) install prefix
```

Build is out-of-tree (`build/obj-<ver>` vs `build/R-<ver>`), so the source tree
stays pristine and a reconfigure is just deleting the objdir.

## Milestones

1. **[current] Linux (linux-64)**: full configure + make + smoke test with
   zig cc + flang. Proves the toolchain design end-to-end.
2. **macOS (osx-64/osx-arm64)**: same scripts, gfortran instead of flang; needs
   validation on real hardware — expect linker-flag deltas (ld64 vs lld
   semantics via `zig cc`) and possibly `-Wl,-rpath` syntax differences.
3. **Windows (win-64)**: the hard one. R 4.x cannot be built via autoconf on
   Windows; the supported path is the `src/gnuwin32` Makefile tree, which
   assumes MinGW. Plan: drive gnuwin32 with `zig cc -target x86_64-windows-gnu`
   as the MinGW-compatible compiler + conda-forge `flang`, `m2-*` msys2 tools
   for the shell, `make` from conda-forge. Scripts currently fail fast on
   Windows with a pointer here.
4. **R regression suite** (`pixi run check`) green on all working platforms.
5. **openblas pixi feature**, recommended packages, and a relocatable install
   story (Makeconf currently records absolute workspace paths).
6. **Long term**: replace autoconf/gnuwin32 with a single `build.zig`, turning
   configure flags into `zig build` options — the true "one build system" end
   state. The dependency/flag inventory produced by milestones 1–3 is the spec.

## Known risks / open questions

- zig 0.16 is young; `zig cc` flag-compat regressions are possible. The version
  is pinned in pixi.toml; bumps should be deliberate.
- flang's Fortran runtime (`libflang_rt`) must be linkable by `zig cc` (lld) at
  final link; R's configure derives FLIBS from `flang -v` output.
- gfortran-on-macOS mixes a GNU Fortran runtime with an LLVM C toolchain;
  works (CRAN does clang + gfortran) but keep an eye on `-lgfortran` paths.
- uutils-coreutils is a young reimplementation; if R's Makefiles hit a missing
  GNU flag, the fallback is conda-forge GNU `coreutils` (still not the host's).
- No X11 means `capabilities("X11")` is FALSE forever by design; interactive
  graphics go through cairo devices (png/svg/pdf) and whatever tk provides.
