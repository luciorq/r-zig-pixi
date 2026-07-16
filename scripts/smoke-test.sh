#!/usr/bin/env bash
# Quick functional test of the freshly built (not yet installed) R.
# Exercises C paths, Fortran paths (BLAS/LAPACK/fft), and reports capabilities.
. "$(dirname "$0")/env.sh"
require_not_windows

R_BIN="$OBJ_DIR/bin/R"
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

"$R_BIN" --version | head -3
echo

"$R_BIN" --vanilla --quiet -e '
  # Fortran-backed numerics: LAPACK solve/qr, BLAS matmul, fft
  set.seed(1)
  m <- matrix(rnorm(64), 8, 8)
  stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
  stopifnot(abs(det(qr.R(qr(m)))) > 0)
  stopifnot(max(Mod(fft(fft(1:8), inverse = TRUE) / 8 - 1:8)) < 1e-9)
  # regex (pcre2), iconv, compression paths
  stopifnot(grepl("\\d+", "R 4"), identical(memDecompress(memCompress("x")), charToRaw("x")))
  cat("numerics OK\n")
  print(capabilities())
  cat("\nsessionInfo BLAS/LAPACK:\n")
  si <- sessionInfo(); cat(si$BLAS, "\n", si$LAPACK, "\n")
'
echo "Smoke test passed."
