#!/usr/bin/env bash
# Makeconf toolchain-contract test: compile real CRAN packages from source
# against the built R, then exercise them.
#   Rcpp       — C++ compile + runtime evalCpp (compiles C++ through Makeconf)
#   data.table — plain C package
#   minqa      — depends on Rcpp AND compiles Fortran: full mixed-toolchain
#                test (zig C/C++ + flang/gfortran) through R's package build
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
# (No backslash escapes in the R code — see smoke-test.sh.)
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # R_TEST_R_BIN: test a different build's Rscript.exe (e.g. the zig-build
  # prefix's) instead of the in-tree gnuwin32 default.
  R_BIN="${R_TEST_R_BIN:-$SRC_DIR/bin/x64/Rscript.exe}"
  test -x "$R_BIN" || R_BIN="$SRC_DIR/bin/Rscript.exe"
  # package builds read CC=gcc etc from etc/x64/Makeconf — the zig shim
  # names must be on PATH, as during the gnuwin32 build
  export PATH="$BUILD_DIR/win-toolchain:$PATH"
else
  # R_TEST_R_BIN: test a different build's Rscript (e.g. the zig-build
  # prefix's) instead of the autoconf objdir default. See FINALIZATION.md F1.2.
  R_BIN="${R_TEST_R_BIN:-$OBJ_DIR/bin/Rscript}"
fi
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

LIB="$BUILD_DIR/testlib-$VARIANT"
mkdir -p "$LIB"

echo "Contract test (variant: $VARIANT, os: $OS)"
echo "Compiling Rcpp + data.table + minqa + pak + ps from source..."
R_CONTRACT_LIB="$LIB" "$R_BIN" --vanilla -e '
  lib <- Sys.getenv("R_CONTRACT_LIB")
  install.packages(c("Rcpp", "data.table", "minqa", "pak", "ps"),
                   repos = "https://cloud.r-project.org",
                   lib = lib, type = "source", Ncpus = 4)
  .libPaths(lib)
  library(Rcpp); library(data.table); library(minqa); library(pak); library(ps)
  stopifnot(evalCpp("2 + 2") == 4)
  dt <- data.table(g = rep(1:3, 4), x = 1:12)
  stopifnot(identical(dt[, sum(x), by = g][[2]], c(22L, 26L, 30L)))
  # OpenMP proof, machine-independent: data.table prints "OpenMP version"
  # only when compiled with OpenMP. (Do NOT assert getDTthreads() > 1 —
  # its default is 50% of cores, which is 1 on small CI runners.)
  th_info <- capture.output(getDTthreads(verbose = TRUE))
  cat(th_info, sep = "\n")
  stopifnot(any(grepl("OpenMP version", th_info)))
  fit <- bobyqa(c(1, 1), function(x) sum((x - 3)^2))
  stopifnot(max(abs(fit$par - c(3, 3))) < 1e-4)
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
  cat("Rcpp evalCpp (runtime C++ compile via Makeconf): OK\n")
  cat("data.table grouped aggregation: OK\n")
  cat("minqa (Rcpp-dependent + package Fortran) bobyqa: OK\n")
  cat("pak (recursive R.exe invocation + mbedtls quoted -D flags): OK\n")
  cat("ps (process introspection", if (ps::ps_os_type()[["MACOS"]]) "+ apps.m Objective-C ps_apps()" else "", "): OK\n")
'
echo "Contract test passed ($VARIANT/$OS)."
