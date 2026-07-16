#!/usr/bin/env bash
# Quick functional test of the freshly built (not yet installed) R.
# Exercises C paths, Fortran paths (BLAS/LAPACK/fft), and asserts the
# variant's exact compile-time capability profile.
. "$(dirname "$0")/env.sh"
require_not_windows

R_BIN="$OBJ_DIR/bin/R"
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

echo "Smoke-testing variant: $VARIANT"
"$R_BIN" --version | head -3
echo

R_SMOKE_VARIANT="$VARIANT" "$R_BIN" --vanilla --quiet -e '
  # Fortran-backed numerics: LAPACK solve/qr, BLAS matmul, fft
  set.seed(1)
  m <- matrix(rnorm(64), 8, 8)
  stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
  stopifnot(abs(det(qr.R(qr(m)))) > 0)
  stopifnot(max(Mod(fft(fft(1:8), inverse = TRUE) / 8 - 1:8)) < 1e-9)
  # regex (pcre2), iconv, compression paths
  stopifnot(grepl("\\d+", "R 4"), identical(memDecompress(memCompress("x")), charToRaw("x")))
  cat("numerics OK\n")

  caps <- capabilities()
  print(caps)

  # Both variants: headless cairo graphics, no X11/quartz, full i18n plumbing
  stopifnot(caps[["cairo"]], caps[["png"]], caps[["ICU"]], caps[["iconv"]],
            caps[["libcurl"]], caps[["long.double"]],
            !caps[["X11"]], !caps[["aqua"]])

  variant <- Sys.getenv("R_SMOKE_VARIANT")
  if (variant == "slim") {
    stopifnot(!caps[["tcltk"]], !caps[["jpeg"]], !caps[["tiff"]], !caps[["NLS"]])
  } else {
    stopifnot(caps[["tcltk"]], caps[["jpeg"]], caps[["tiff"]], caps[["NLS"]])
  }
  cat("capability profile OK for variant:", variant, "\n")

  cat("\nsessionInfo BLAS/LAPACK:\n")
  si <- sessionInfo(); cat(si$BLAS, "\n", si$LAPACK, "\n")
'
echo "Smoke test passed ($VARIANT)."
