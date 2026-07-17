#!/usr/bin/env bash
# Makeconf toolchain-contract test: compile real CRAN packages from source
# against the built R, then exercise them.
#   Rcpp       — C++ compile + runtime evalCpp (compiles C++ through Makeconf)
#   data.table — plain C package
#   minqa      — depends on Rcpp AND compiles Fortran: full mixed-toolchain
#                test (zig C/C++ + flang/gfortran) through R's package build
# (No backslash escapes in the R code — see smoke-test.sh.)
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  R_BIN="$SRC_DIR/bin/x64/Rscript.exe"
  test -x "$R_BIN" || R_BIN="$SRC_DIR/bin/Rscript.exe"
  # package builds read CC=gcc etc from etc/x64/Makeconf — the zig shim
  # names must be on PATH, as during the gnuwin32 build
  export PATH="$BUILD_DIR/win-toolchain:$PATH"
else
  R_BIN="$OBJ_DIR/bin/Rscript"
fi
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

LIB="$BUILD_DIR/testlib-$VARIANT"
mkdir -p "$LIB"

echo "Contract test (variant: $VARIANT, os: $OS)"
echo "Compiling Rcpp + data.table + minqa from source..."
R_CONTRACT_LIB="$LIB" "$R_BIN" --vanilla -e '
  lib <- Sys.getenv("R_CONTRACT_LIB")
  install.packages(c("Rcpp", "data.table", "minqa"),
                   repos = "https://cloud.r-project.org",
                   lib = lib, type = "source", Ncpus = 4)
  .libPaths(lib)
  library(Rcpp); library(data.table); library(minqa)
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
  cat("Rcpp evalCpp (runtime C++ compile via Makeconf): OK\n")
  cat("data.table grouped aggregation: OK\n")
  cat("minqa (Rcpp-dependent + package Fortran) bobyqa: OK\n")
'
echo "Contract test passed ($VARIANT/$OS)."
