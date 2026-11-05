#!/usr/bin/env bash
# Makeconf toolchain-contract test: compile real CRAN packages from source
# against the built R, then exercise them.
# Which builder each takes (feat-zig-pkg-build, patch 0013, the default
# R_ZIG_PKG_BUILDER=auto): Rcpp, quadprog and, on unix, minqa qualify for
# `rzig build` (tier 1: a Makevars of assignments); data.table and ps
# have configure scripts, and minqa's Makevars.win a $(shell), so they
# take the make path; pak's configure installs its embedded library,
# cli, lpSolve, pkgcache and yaml through rzig build and keyring and zip
# (Makevars rules) through make. Each install's log (RZIG_TRACE=1,
# keep_outputs) must say so: `rzig build: tier 1`, `needs make`, or both
# for pak. Rcpp's evalCpp compiles at run time through R CMD SHLIB,
# which patch 0013's one hook sends to rzig build first; make is on PATH
# here, and the no-make program below proves rzig build alone
# [shlib-tests-4].
#   Rcpp       — C++ compile (rzig build) + runtime evalCpp (R CMD SHLIB:
#                compiles C++ through Makeconf, rzig build first)
#   data.table — plain C package (configure: make)
#   minqa      — depends on Rcpp AND compiles Fortran: full mixed-toolchain
#                test (zig C/C++ + flang) through R's package build (unix:
#                rzig build, the C++ link through SHLIB_CXXLD with FLIBS;
#                Windows: make)
#   pak        — the real-world repro case behind F7.1/F7.6/F7.7 (see
#                TODO.md): its own configure script recursively
#                re-invokes R.exe/Rterm.exe (the access-violation crash
#                fixed by F7.6's Windows ReleaseSafe switch), and its
#                bundled keyring/zip sub-packages compile mbedtls with
#                a -D flag whose value is a quoted string literal (the
#                win-exec-forward.c command-line quoting bug fixed by
#                F7.7). Locks in both fixes against regression.
#   ps         — already pulled in transitively via pak, but listed and
#                exercised explicitly here since it's the actual origin
#                of the F7.8 repro (see TODO.md): its src/arch/macos/
#                apps.m is genuine Objective-C (AppKit-based running-app
#                enumeration), silently compiled as plain C before the
#                OBJC toolchain-shim fix. ps_apps() (macOS only) calls
#                straight into that compiled code; on linux/windows ps
#                has no Objective-C to exercise, so only the plain
#                load + a basic call is asserted there.
#   cpp11, callr, processx, R6 — for the no-make program below: cpp11's
#                headers and callr::rcmd, cpp_source's own SHLIB call.
#                They install here, with the build tools, as ps and pak
#                do (processx has Makevars rules; feat-shlib-rzig-build
#                K). cpp11's Suggests, which cpp_source itself requires,
#                are not installed (Cc1).
# Then the run-time compiles with no make (feat-shlib-rzig-build Cc1,
# Cc6): the base tree, the installed one with no build tools (env.sh's
# R_HOME_DIR; the compile tree's etc/Renviron puts its make first on
# PATH), runs a program with the test library under env -i, zig through
# ZIG_BIN and on PATH only a directory holding sh, cp (R CMD build's,
# for pak's install) and flang: Rcpp's cppFunction (a C++ exception
# caught) and evalCpp, on macOS its OpenMP plugin's dry-run parse (and
# its compile where Makeconf offers OpenMP), cpp11's SHLIB call through
# callr::rcmd, pak's compiler probe in its worker, and pak's install of
# a package with C code. No make on PATH is the evidence that rzig built
# each one.
# (The R programs are written to files, not passed with -e: see below.)
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # R_TEST_R_BIN: test a different build's Rscript.exe (e.g. the zig-build
  # prefix's) instead of the in-tree gnuwin32 default.
  R_BIN="${R_TEST_R_BIN:-$SRC_DIR/bin/x64/Rscript.exe}"
  test -x "$R_BIN" || R_BIN="$SRC_DIR/bin/Rscript.exe"
  # package builds read CC=$(BINPREF)gcc etc from etc/x64/Makeconf, and
  # BINPREF names R_HOME/bin/toolchain/ (rzig's gcc.exe and g++.exe); the
  # gnuwin32 build's win-toolchain dir below is a leftover, empty today
  export PATH="$BUILD_DIR/win-toolchain:$PATH"
else
  # R_TEST_R_BIN: test a different build's Rscript (e.g. the zig-build
  # prefix's) instead of the autoconf objdir default. See FINALIZATION.md F1.2.
  R_BIN="${R_TEST_R_BIN:-$OBJ_DIR/bin/Rscript}"
fi
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

LIB="$BUILD_DIR/testlib-$VARIANT"
mkdir -p "$LIB"
# rzig build's caches as a user's install has them: tier 1 runs no zig
# build (tier1.zig), each install's objects and library in its build
# root, gone with it; zig cc keeps its objects in env.sh's global cache
# (env.sh's ZIG_LOCAL_CACHE_DIR would be zig cc's cache instead)
# [phase3-P3-6]. rzig's own cache (dso_fini.o, cfguard.o, archive
# copies, the libc++ mirror) stays in the workspace, as env.sh's zig
# caches do, not under $HOME [code-contract-home-cache]: XDG_CACHE_HOME
# names it on every OS (cache.zig's root reads it first). It also moves
# the XDG caches of the programs the installs run (cr27 finding 6).
unset ZIG_LOCAL_CACHE_DIR
if [ "$OS" = windows ]; then
  export XDG_CACHE_HOME="$(cygpath -w "$BUILD_DIR/rzig-cache")"
else
  export XDG_CACHE_HOME="$BUILD_DIR/rzig-cache"
fi

echo "Contract test (variant: $VARIANT, os: $OS)"
echo "Compiling Rcpp + data.table + minqa + quadprog + pak + ps (+ cpp11, callr, processx, R6) from source..."
# The program goes through a file: R's front end omits a `-e` expression
# over 10000 bytes once bin/R has encoded it (spaces as `~+~`), with a
# warning and exit 0, which would make this test vacuous.
cat > "$LIB/contract.R" <<'RCODE'
  lib <- Sys.getenv("R_CONTRACT_LIB")
  pkgs <- c("Rcpp", "data.table", "minqa", "quadprog", "pak", "ps", "cpp11", "callr", "processx", "R6")
  # the builder each took, from its kept install log (keep_outputs)
  outs <- file.path(lib, "install-logs")
  dir.create(outs, showWarnings = FALSE)
  # CRAN mirror hiccups are real (main-branch openblas leg, 2026-09-20:
  # "SSL connect error" downloading Rcpp, then minqa failed on the
  # missing dependency): bounded retries, and fail *here* with a clear
  # message rather than three packages later. install.packages() itself
  # only warns on a failed download.
  options(timeout = 300)
  for (attempt in 1:3) {
    install.packages(pkgs, repos = "https://cloud.r-project.org",
                     lib = lib, type = "source", Ncpus = 4, keep_outputs = outs)
    missing <- setdiff(pkgs, rownames(installed.packages(lib.loc = lib)))
    if (!length(missing)) break
    message("contract: attempt ", attempt, " left ", paste(missing, collapse = ", "),
            " uninstalled", if (attempt < 3) "; retrying in 30 s" else "")
    if (attempt < 3) Sys.sleep(30)
  }
  if (length(missing)) stop("contract: could not install ", paste(missing, collapse = ", "))
  # pak has no src/ of its own: its configure installs its embedded
  # library, where cli, lpSolve, pkgcache and yaml are tier 1 (rzig
  # build) and keyring and zip have Makevars rules (make): mixed
  windows <- .Platform$OS.type == "windows"
  builder_of <- function(p) {
    log <- readLines(file.path(outs, paste0(p, ".out")), warn = FALSE)
    zig <- any(grepl("rzig build: tier 1", log, fixed = TRUE))
    mk <- any(grepl("^rzig build: [^ ]+ needs make: ", log))
    if (zig && mk) "mixed" else if (zig) "rzig build" else if (mk) "make" else "unknown"
  }
  want <- c(Rcpp = "rzig build", data.table = "make", minqa = if (windows) "make" else "rzig build",
            quadprog = "rzig build", pak = "mixed", ps = "make")
  builders <- vapply(pkgs, builder_of, "")
  cat("builders:", paste(pkgs, builders, sep = " = ", collapse = ", "), "\n")
  bad <- names(want)[builders[names(want)] != want]
  if (length(bad)) stop("contract: not the expected builder for ", paste(bad, collapse = ", "),
                        " (", paste(bad, builders[bad], sep = " = ", collapse = ", "),
                        "; wanted ", paste(bad, want[bad], sep = " = ", collapse = ", "), ")")
  .libPaths(lib)
  library(Rcpp); library(data.table); library(minqa); library(quadprog); library(pak); library(ps)
  stopifnot(evalCpp("2 + 2") == 4)
  dt <- data.table(g = rep(1:3, 4), x = 1:12)
  stopifnot(identical(dt[, sum(x), by = g][[2]], c(22L, 26L, 30L)))
  # OpenMP proof, machine-independent: data.table prints "OpenMP version"
  # only when compiled with OpenMP. (Do NOT assert getDTthreads() > 1 —
  # its default is 50% of cores, which is 1 on small CI runners.)
  # minimal is built without OpenMP and its Makeconf offers none, so there
  # the proof runs the other way: the profile property is the empty
  # SHLIB_OPENMP_* flags. data.table follows them on linux, but on macOS
  # its configure probes -Xclang -fopenmp itself and links -lomp, which
  # succeeds wherever a libomp is reachable (conda llvm-openmp in the dev
  # env, whose -L and rpath rzig adds: pixi.toml sets R_ZIG_EXTRA_ENV).
  # That is the package opting in, not R offering OpenMP, so there it is
  # reported only.
  th_info <- capture.output(getDTthreads(verbose = TRUE))
  cat(th_info, sep = "\n")
  if (Sys.getenv("R_CONTRACT_VARIANT") == "minimal") {
    mk <- readLines(file.path(R.home("etc"), "Makeconf"))
    omp <- grep("^SHLIB_OPENMP_(C|CXX|F)FLAGS *=", mk, value = TRUE)
    stopifnot(length(omp) == 3L, all(grepl("= *$", omp)))
    if (Sys.info()[["sysname"]] != "Darwin")
      stopifnot(!any(grepl("OpenMP version", th_info)))
  } else {
    stopifnot(any(grepl("OpenMP version", th_info)))
  }
  fit <- bobyqa(c(1, 1), function(x) sum((x - 3)^2))
  stopifnot(max(abs(fit$par - c(3, 3))) < 1e-4)
  # quadprog: a *pure-Fortran* package (no C/C++ sources at all) — the one
  # shape minqa cannot cover, since its C++ sends the link through
  # SHLIB_CXXLD. rzig build compiles every file with $(FC), the zig-fc of
  # rzig (F3c: the env's flang here, on every platform since Phase 2), and
  # links through SHLIB_LD, the zig-cc of rzig (gcc.exe on Windows), with
  # $(FLIBS) appended — -lflang_rt.runtime, which rzig resolves to the
  # static runtime archive (no libc++ on any OS since feat-standalone-
  # toolchain phase 6, open point K): the words make would have run
  # (pkg-parity asserts they are identical). (R only links via
  # $(FC) itself when a package opts in with USE_FC_TO_LINK in Makevars;
  # verify-bundle.sh and the recipe test build such a package.)
  # minimize (1/2) t(x) D x - t(d) x subject to x >= 0, with D = 2I and
  # d = (2, 6): the solution is x = (1, 3).
  qp <- solve.QP(Dmat = diag(2, 2), dvec = c(2, 6), Amat = diag(2), bvec = c(0, 0))
  stopifnot(max(abs(qp$solution - c(1, 3))) < 1e-8)
  # pak: no network calls here (this test is about the compiled-code
  # toolchain contract, not pak own package-manager functionality) —
  # loading it successfully already proves its compiled sub-packages
  # (keyring, pkgdepends tree-sitter/yaml C code) built and link-loaded
  # correctly; packageVersion() is a real call into the loaded package.
  stopifnot(is.character(as.character(packageVersion("pak"))))
  # ps: a plain call proves the package loaded/link-loaded on every OS;
  # on macOS specifically, ps_apps() calls straight into apps.m -- the
  # genuine Objective-C source behind the F7.8 OBJC-toolchain-shim fix.
  stopifnot(ps::ps_pid(ps::ps_handle()) == Sys.getpid())
  if (ps::ps_os_type()[["MACOS"]]) {
    # nrow not asserted > 0 -- omicron is an SSH-only session with no
    # guaranteed GUI apps running; a successful, non-crashing data frame
    # already proves the compiled apps.m call worked end-to-end.
    apps <- ps::ps_apps()
    stopifnot(is.data.frame(apps))
  }
  # Makeconf names no build path and no environment (feat-no-host-paths
  # F1.5, F3b): FLIBS is the bare runtime rzig resolves, CPPFLAGS and
  # LDFLAGS are empty (the compilers, rzig, add the environment -I, -L and
  # conda rpath), CC is rzig, and FC its zig-fc (F3c; zig-fc.exe on
  # Windows, named without .exe). --no-user-files: the shipped Makeconf
  # alone, whatever personal Makevars this machine has.
  cfg <- function(v) tools::Rcmd(c("config", "--no-user-files", v), stdout = TRUE)
  cc1 <- strsplit(trimws(cfg("CC")), " +")[[1]][1]
  fc1 <- strsplit(trimws(cfg("FC")), " +")[[1]][1]
  stopifnot(grepl("-lflang_rt.runtime", cfg("FLIBS"), fixed = TRUE),
            !grepl("libflang_rt", cfg("FLIBS"), fixed = TRUE),
            identical(trimws(cfg("CPPFLAGS")), ""),
            identical(trimws(cfg("LDFLAGS")), ""),
            basename(dirname(cc1)) == "toolchain",
            sub(".exe$", "", basename(cc1)) %in% c("zig-cc", "gcc"),
            basename(dirname(fc1)) == "toolchain",
            sub(".exe$", "", basename(fc1)) == "zig-fc")
  # Windows: NM names a file that exists (PHASE3 C11). Makeconf names it
  # under R_HOME/bin/toolchain/binutils/, the build-tools group directory
  # (feat-standalone-toolchain B24), which the compile tree has. A missing
  # nm.exe fails no package above: winshlib.mk pipes $(NM) into sed for a
  # DLL linked without a .def file, and the linker then exports everything.
  if (.Platform$OS.type == "windows") {
    nm <- trimws(cfg("NM"))
    stopifnot(file.exists(nm))
    cat("R CMD config NM:", nm, "exists: OK\n")
  }
  cat("Rcpp (rzig build) evalCpp (runtime C++ compile through R CMD SHLIB; R_ZIG_PKG_BUILDER=auto with make on PATH here, the no-make run is below): OK\n")
  cat("data.table (make) grouped aggregation: OK\n")
  cat("minqa (Rcpp-dependent + package Fortran;", builders[["minqa"]], ") bobyqa: OK\n")
  cat("quadprog (pure Fortran: zig-fc compile, FLIBS link through rzig; rzig build) solve.QP: OK\n")
  cat("R CMD config FC:", fc1, "OK\n")
  cat("pak (recursive R.exe invocation + mbedtls quoted -D flags): OK\n")
  cat("ps (process introspection", if (ps::ps_os_type()[["MACOS"]]) "+ apps.m Objective-C ps_apps()" else "", "): OK\n")
  cat("contract program ran to the end\n")
RCODE
R_CONTRACT_LIB="$LIB" R_CONTRACT_VARIANT="$VARIANT" RZIG_TRACE=1 "$R_BIN" --vanilla "$LIB/contract.R" | tee "$LIB/contract.out"
grep -q '^contract program ran to the end$' "$LIB/contract.out" || { echo "error: the contract program did not run to its end" >&2; exit 1; }

# Run-time compiles with no make (feat-shlib-rzig-build, patch 0013's one
# hook in .shlib_internal; Cc1, Cc6): the base tree (env.sh's
# R_HOME_DIR), which has no build tools, with the packages installed
# above (R_LIBS), under env -i as pkg-parity's no-make install: zig
# through ZIG_BIN, with env.sh's global cache and rzig's cache above
# (XDG_CACHE_HOME), and on PATH only a directory holding sh, flang and,
# on unix, cp, which R CMD build runs for pak's install (Windows: System32
# and copies of flang and its .cfg files). pak's worker lists the
# system's packages before an install (pkgdepends'
# sysreqs_lookup_system, dpkg-query on Debian and Ubuntu); with that tool
# off PATH its worker spins instead of failing, so the lookup is off
# (PKG_SYSREQS_LOOKUP_SYSTEM=false). It reads system requirements only,
# not what this tests.
NM="$LIB/nomake"
rm -rf "$NM"; mkdir -p "$NM/bin" "$NM/home" "$NM/tmp"
if [ "$OS" = windows ]; then
  base_rscript="$R_HOME_DIR/bin/x64/Rscript.exe"
  fl="$(command -v flang.exe || command -v flang || true)"
  if [ -n "$fl" ]; then
    for f in flang.exe flang-new.exe flang.cfg flang-compile.cfg; do
      [ ! -f "$(dirname "$fl")/$f" ] || cp "$(dirname "$fl")/$f" "$NM/bin/"
    done
  fi
  sysdir="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")"
  # zig's own cache needs a home too (LOCALAPPDATA), as pkg-parity's.
  # Windows always sets PROCESSOR_ARCHITECTURE, and cli's exit-time stop
  # of its tick thread strcmp()s its getenv unchecked (cli's
  # src/thread.c), so pak:::remote() under env -i without it crashes R
  # as it exits (feat-shlib-rzig-build round 1, kappa)
  nm_env=(SYSTEMROOT="$SYSTEMROOT" WINDIR="${WINDIR:-$SYSTEMROOT}"
    PROCESSOR_ARCHITECTURE="${PROCESSOR_ARCHITECTURE:-AMD64}" HOME="$(cygpath -w "$NM/home")"
    USERPROFILE="$(cygpath -w "$NM/home")" LOCALAPPDATA="$(cygpath -w "$NM/home")"
    TMPDIR="$(cygpath -w "$NM/tmp")" TMP="$(cygpath -w "$NM/tmp")" TEMP="$(cygpath -w "$NM/tmp")"
    PATH="$NM/bin:$sysdir/System32" ZIG_BIN="$(cygpath -m "$ZIG")"
    ZIG_GLOBAL_CACHE_DIR="$(cygpath -m "$ZIG_GLOBAL_CACHE_DIR")" XDG_CACHE_HOME="$XDG_CACHE_HOME"
    R_LIBS="$(cygpath -m "$LIB")")
else
  base_rscript="$R_HOME_DIR/bin/Rscript"
  ln -s "$(command -v sh)" "$NM/bin/sh"; ln -s "$(command -v cp)" "$NM/bin/cp"
  fl="$(command -v flang || command -v flang-new || true)"
  [ -z "$fl" ] || ln -s "$fl" "$NM/bin/flang"
  nm_env=(HOME="$NM/home" TMPDIR="$NM/tmp" PATH="$NM/bin" ZIG_BIN="$ZIG"
    ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR" XDG_CACHE_HOME="$XDG_CACHE_HOME" R_LIBS="$LIB")
fi
test -x "$base_rscript" || { echo "error: no base tree at $R_HOME_DIR: run 'pixi run build'" >&2; exit 1; }
test ! -e "$R_HOME_DIR/bin/toolchain/usr" || { echo "error: $R_HOME_DIR/bin/toolchain has usr/: not the base alone" >&2; exit 1; }
test -n "$ZIG" || { echo "error: no zig for the no-make program (ZIG_BIN, or zig on PATH)" >&2; exit 1; }
cat > "$NM/nomake.R" <<'RCODE'
  windows <- .Platform$OS.type == "windows"
  so <- .Platform$dynlib.ext
  if (nzchar(Sys.which("make"))) stop("make is on PATH: ", Sys.which("make"))
  library(Rcpp)
  f <- cppFunction('int f(int x) { if (x < 0) throw std::range_error("neg"); return x; }')
  stopifnot(f(2L) == 2L, inherits(try(f(-1L), silent = TRUE), "try-error"), evalCpp("2 + 2") == 4)
  cat("no make: Rcpp cppFunction (a C++ exception caught) and evalCpp (R CMD SHLIB, rzig build): OK\n")
  # macOS: Rcpp's OpenMP plugin reads the compiler from R CMD SHLIB
  # --dry-run's line after "make would use", now rzig's first compile
  # line; with nothing there it stops with a subscript error (Cc6). The
  # compile only where Makeconf offers OpenMP (not minimal).
  if (Sys.info()[["sysname"]] == "Darwin") {
    p <- Rcpp:::.openmpPluginDarwin()
    stopifnot(identical(p$env$PKG_CXXFLAGS, "-fopenmp"))
    mk <- readLines(file.path(R.home("etc"), "Makeconf"))
    if (any(grepl("^SHLIB_OPENMP_CXXFLAGS *= *-", mk))) {
      g <- cppFunction("int g() { return 1; }", plugins = "openmp")
      stopifnot(g() == 1L)
    }
    cat("no make: Rcpp's macOS OpenMP plugin parses R CMD SHLIB --dry-run: OK\n")
  }
  # cpp11's cpp_source call without its code generator (cpp11
  # R/source.R): a Makevars in the working directory, an absolute
  # source, --output=, through callr::rcmd
  d <- normalizePath(tempfile("cpp11-"), "/", mustWork = FALSE)
  dir.create(file.path(d, "src"), recursive = TRUE)
  writeLines(c("CXX_STD = CXX11",
               paste0("PKG_CPPFLAGS = -I'", normalizePath(system.file("include", package = "cpp11"), "/"), "'")),
             file.path(d, "src", "Makevars"))
  writeLines(c('#include "cpp11/as.hpp"', '#include "cpp11/declarations.hpp"',
               'extern "C" SEXP rzig_twice(SEXP x) {', '  BEGIN_CPP11',
               '  return cpp11::as_sexp(2 * cpp11::as_cpp<int>(x));', '  END_CPP11', '}'),
             file.path(d, "src", "code.cpp"))
  r <- callr::rcmd("SHLIB", c(file.path(d, "src", "code.cpp"), paste0("--output=pkg", so)), wd = file.path(d, "src"))
  if (r$status != 0L) { cat(r$stdout, r$stderr, sep = "\n"); stop("cpp11's SHLIB call failed with no make") }
  dyn.load(file.path(d, "src", paste0("pkg", so)))
  stopifnot(.Call("rzig_twice", 21L, PACKAGE = "pkg") == 42L)
  cat("no make: cpp11's SHLIB call through callr::rcmd: OK\n")
  # pak's own probe, pkgbuild's has_compiler() in pak's worker: R CMD
  # SHLIB foo.c (feat-shlib-rzig-build section 4)
  stopifnot(isTRUE(pak:::remote(function() pkgbuild::check_build_tools())))
  cat("no make: pak's compiler probe (pkgbuild::check_build_tools in its worker): OK\n")
  if (windows)
    print(pak:::remote(function() pkgbuild::has_rtools(debug = TRUE)))  # open point H: printed only
  # pak's install of a package with C code: R CMD build, then R CMD
  # INSTALL through rzig build (patch 0013)
  p <- file.path(d, "rzigpak")
  dir.create(file.path(p, "src"), recursive = TRUE); dir.create(file.path(p, "R"))
  writeLines(c("Package: rzigpak", "Version: 0.1", "Title: Test", "Description: Test package.", "License: MIT",
               "Author: r-zig", "Maintainer: r-zig <r-zig@example.org>"), file.path(p, "DESCRIPTION"))
  writeLines(c("useDynLib(rzigpak)", "export(f)"), file.path(p, "NAMESPACE"))
  writeLines('f <- function() .Call("rzig_one")', file.path(p, "R", "f.R"))
  writeLines(c("#include <Rinternals.h>", "SEXP rzig_one(void) { return ScalarInteger(1L); }"),
             file.path(p, "src", "one.c"))
  tl <- file.path(d, "lib"); dir.create(tl)
  pak::local_install(p, lib = tl, dependencies = FALSE, ask = FALSE)
  stopifnot(getExportedValue(loadNamespace("rzigpak", lib.loc = tl), "f")() == 1L)
  cat("no make: pak's install of a package with C code: OK\n")
  cat("no-make program ran to the end\n")
RCODE
(cd "$NM" && env -i "${nm_env[@]}" PKG_SYSREQS_LOOKUP_SYSTEM=false "$base_rscript" --vanilla nomake.R) 2>&1 | tee "$NM/nomake.out"
grep -q '^no-make program ran to the end' "$NM/nomake.out" ||
  { echo "error: the no-make program (Rcpp, cpp11's SHLIB call, pak's probe and install on the base tree, no make on PATH) did not run to its end" >&2; exit 1; }
# The environments rzig compiled those against (feat-no-host-paths F3b):
# the tree's own (R_HOME/../..), then the pixi env, which pixi.toml names
# in R_ZIG_EXTRA_ENV. A link line as rzig would run it: both -L after the
# caller's arguments, the -o included (fix-stress-round1 S10), an rpath
# only into the pixi env (a conda env; the tree is not), the headers after
# the caller's arguments in the same order. Windows: the
# environments are <root>/Library, headers by -idirafter, no rpath.
if [ -n "${R_ZIG_EXTRA_ENV:-}" ]; then
  rhome="$("$R_BIN" --vanilla -e 'cat(normalizePath(R.home(), winslash = "/"))')"
  own="$(cd "$rhome/../.." && pwd -P)"
  env_root="$R_ZIG_EXTRA_ENV"
  [ "$OS" = windows ] && env_root="$(cygpath -u "$env_root")"
  extra="$(cd "$env_root" && pwd -P)"
  tc="$rhome/bin/toolchain/zig-cc"
  if [ "$OS" = windows ]; then
    own="$(cygpath -m "$own")"; extra="$(cygpath -m "$extra")/Library"; tc="$rhome/bin/toolchain/gcc.exe"
  fi
  argv="$(cd "$LIB" && RZIG_PRINT_ARGV=1 "$tc" -shared -o rzig-contract.so a.o -lz)"
  # Never fails (set -e, pipefail): a missing flag is an empty position,
  # which the checks below report with the argv.
  at() { printf '%s\n' "$argv" | grep -nixF -- "$1" | head -1 | cut -d: -f1 || true; }
  o="$(at -o)" lo="$(at "-L$own/lib")" le="$(at "-L$extra/lib")"
  bad=""
  { [ -n "$o" ] && [ -n "$lo" ] && [ -n "$le" ] && [ "$o" -lt "$lo" ] && [ "$lo" -lt "$le" ]; } || bad="$bad order-of-L"
  if [ "$OS" = windows ]; then
    printf '%s\n' "$argv" | grep -q -- '-rpath' && bad="$bad rpath"
    ie="$(at "$extra/include")"
    { [ -n "$ie" ] && [ "$ie" -gt "$o" ] && [ "$(printf '%s\n' "$argv" | sed -n "$((ie - 1))p")" = -idirafter ]; } || bad="$bad idirafter"
  else
    re="$(at "-Wl,-rpath,$extra/lib")" ie="$(at "-I$extra/include")"
    { [ -n "$re" ] && [ "$re" = $((le + 1)) ]; } || bad="$bad extra-rpath"
    [ -z "$(at "-Wl,-rpath,$own/lib")" ] || bad="$bad own-rpath"
    { [ -n "$ie" ] && [ "$ie" -gt "$o" ]; } || bad="$bad extra-include"
    if [ -d "$own/include" ]; then
      io="$(at "-I$own/include")"
      { [ -n "$io" ] && [ "$io" -lt "$ie" ]; } || bad="$bad own-include"
    fi
  fi
  if [ -n "$bad" ]; then
    printf '%s\n' "$argv" >&2
    echo "error: rzig's environment flags (own $own, extra $extra):$bad" >&2
    exit 1
  fi
  echo "rzig environments: $own, then $extra (R_ZIG_EXTRA_ENV): -L and headers after the caller's arguments, rpath into conda envs only: OK"
fi
# Static libc++ everywhere (decided 2026-09-30): no compiled package may
# depend on a shared C++ runtime. zig links its own libc++ statically, but
# conda-forge's zig switches to a shared one whenever a libc++ sits beside
# it (always in a macOS conda env; on linux with any `libcxx` package);
# rzig (R_HOME/bin/toolchain's zig-cc and zig-cxx) defeats that with a
# ZIG_LIB_DIR mirror.
if [ "$OS" = linux ] || [ "$OS" = macos ]; then
  shared_cxx=""
  for so in "$LIB"/*/libs/*.so; do
    if [ "$OS" = linux ]; then
      hit="$(patchelf --print-needed "$so" 2>/dev/null | grep -E '^lib(c\+\+|stdc\+\+)\.so' || true)"
    else
      hit="$(otool -L "$so" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E '(^|/)lib(c\+\+|stdc\+\+)[.0-9]*\.dylib$' || true)"
    fi
    [ -z "$hit" ] || shared_cxx="$shared_cxx ${so#$LIB/}->$hit"
  done
  if [ -n "$shared_cxx" ]; then
    echo "error: compiled packages depend on a shared C++ runtime:$shared_cxx" >&2
    exit 1
  fi
  echo "C++ runtime: static in every compiled package"
fi
# macOS: every compiled package at or below the deployment target rzig
# passes (MACOS_MIN), and the SDK's lib dir last on its link lines:
# data.table's zlib.h comes from the env, so its libz must too, not the
# SDK's older stub in /usr/lib.
if [ "$OS" = macos ]; then
  bad=""
  for so in "$LIB"/*/libs/*.so; do
    m="$(macho_minos "$so")"
    if [ -z "$m" ] || version_gt "$m" "$MACOS_MIN"; then bad="$bad ${so#$LIB/}=${m:-none}"; fi
  done
  if [ -n "$bad" ]; then
    echo "error: compiled packages above the macOS $MACOS_MIN floor:$bad" >&2
    exit 1
  fi
  if otool -L "$LIB/data.table/libs/data_table.so" | grep -q '/usr/lib/libz\.'; then
    echo "error: data.table linked the SDK's libz stub (the SDK -L is not last on rzig's link line)" >&2
    exit 1
  fi
  echo "macOS floor: every compiled package at minos <= $MACOS_MIN"
fi
echo "Contract test passed ($VARIANT/$OS)."
