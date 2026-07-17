#!/usr/bin/env bash
# Makeconf toolchain-contract test: compile real CRAN packages from source
# against the built R, then exercise them — including Rcpp::evalCpp, which
# compiles C++ at runtime through etc/Makeconf's zig shims exactly like
# user code will. (No backslash escapes in the R code — see smoke-test.sh.)
. "$(dirname "$0")/env.sh"
require_not_windows

R_BIN="$OBJ_DIR/bin/Rscript"
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

LIB="$BUILD_DIR/testlib-$VARIANT"
mkdir -p "$LIB"

echo "Contract test (variant: $VARIANT) — compiling Rcpp + data.table from source"
R_CONTRACT_LIB="$LIB" "$R_BIN" --vanilla -e '
  lib <- Sys.getenv("R_CONTRACT_LIB")
  install.packages(c("Rcpp", "data.table"), repos = "https://cloud.r-project.org",
                   lib = lib, type = "source", Ncpus = 4)
  .libPaths(lib)
  library(Rcpp); library(data.table)
  stopifnot(evalCpp("2 + 2") == 4)
  dt <- data.table(g = rep(1:3, 4), x = 1:12)
  stopifnot(identical(dt[, sum(x), by = g][[2]], c(22L, 26L, 30L)))
  cat("Rcpp evalCpp (runtime C++ compile via Makeconf): OK\n")
  cat("data.table grouped aggregation: OK\n")
'
echo "Contract test passed ($VARIANT)."
