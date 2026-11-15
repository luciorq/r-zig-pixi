#!/usr/bin/env bash
# Quick functional test of the freshly built (not yet installed) R.
# Exercises C paths, Fortran paths (BLAS/LAPACK/fft), and asserts the
# variant's capability profile, on every OS the same way (build.zig's
# variant table holds for Windows too, 2026-11-14): capabilities(), and
# what each capability does, since on Windows capabilities() reads only
# config.h (platform.c), not what grDevices and tcltk were built with:
#   - the bitmap devices draw a file where the variant has the format and
#     fail with R's warning or error where it does not (Windows: the
#     type = "windows" devices, winbitmap.c; unix: R's default type);
#   - tcltk: full loads it and runs Tcl; slim and minimal get the stub's
#     "Tcl/Tk support is not available";
#   - NLS: full translates a base message (German), where the locale lets
#     LANGUAGE work (a C locale does not; on Windows it always must);
#   - BLAS: the internal libRblas or openblas (unix; sessionInfo()'s BLAS
#     field is a library path there).
. "$(dirname "$0")/env.sh"

# R_TEST_R_BIN: test a different build's R (e.g. the zig-build prefix's
# bin/R, Windows: R_HOME/bin/x64/Rscript.exe) instead of the autoconf
# objdir default.
if [ "$OS" = windows ]; then
  R_BIN="${R_TEST_R_BIN:-$SRC_DIR/bin/x64/Rscript.exe}"
  test -x "$R_BIN" || R_BIN="$SRC_DIR/bin/Rscript.exe"
  run_r() { "$R_BIN" --vanilla -e "$1"; }
else
  R_BIN="${R_TEST_R_BIN:-$OBJ_DIR/bin/R}"
  run_r() { "$R_BIN" --vanilla --quiet -e "$1"; }
fi
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

echo "Smoke-testing variant: $VARIANT (BLAS: $BLAS, $OS)"
"$R_BIN" --version | head -3
echo

R_SMOKE_VARIANT="$VARIANT" R_SMOKE_BLAS="$BLAS" run_r '
  # Fortran-backed numerics: LAPACK solve/qr, BLAS matmul, fft
  set.seed(1)
  m <- matrix(rnorm(64), 8, 8)
  stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
  stopifnot(abs(det(qr.R(qr(m)))) > 0)
  stopifnot(max(Mod(fft(fft(1:8), inverse = TRUE) / 8 - 1:8)) < 1e-9)
  # regex (pcre2), iconv, compression paths
  # NB: no backslash escapes here — R'\''s sh wrapper passes -e through echo,
  # and macOS /bin/sh has xpg_echo, which eats one backslash level.
  stopifnot(grepl("[0-9]+", "R 4", perl = TRUE),
            identical(memDecompress(memCompress("x")), charToRaw("x")))
  cat("numerics OK\n")

  # OpenMP parallel regions in R itself (slim and full; minimal runs the
  # serial code): colSums() (array.c, a region with 10 firstprivate
  # values, entered even with 1 thread) and dist() (stats distance.c, a
  # region only with more than 1 thread). Win-arm64 libomp builds have
  # broken regions with more than six shared values (feat-win-arm64).
  old <- .Internal(setMaxNumMathThreads(4L))
  for (nt in c(1L, 4L)) {
    invisible(.Internal(setNumMathThreads(nt)))
    x <- matrix(as.double(1:600), 20)
    stopifnot(identical(colSums(x), vapply(1:30, function(j) sum(x[, j]), 0)),
              identical(colMeans(x), colSums(x) / 20))
    d <- as.vector(dist(cbind(0:39 * 3, 0:39 * 4)))
    stopifnot(isTRUE(all.equal(d, unlist(lapply(1:39, function(j) 5 * seq_len(40 - j))))))
  }
  invisible(.Internal(setNumMathThreads(1L))); invisible(.Internal(setMaxNumMathThreads(old)))
  cat("OpenMP regions (colSums, dist) OK\n")

  windows <- .Platform$OS.type == "windows"
  caps <- capabilities()
  print(caps)

  # Every variant: iconv + libcurl (configure requires it); unix: no X11
  # or quartz. long.double is intentionally not asserted: on arm64 macOS
  # long double IS double (hardware fact; CRAN arm64 builds report FALSE).
  stopifnot(caps[["iconv"]], caps[["libcurl"]])
  if (!windows) stopifnot(!caps[["X11"]], !caps[["aqua"]])
  cat("long.double:", caps[["long.double"]], "(informational)\n")

  # The variant table (build.zig variantFeatures), the same on every OS.
  variant <- Sys.getenv("R_SMOKE_VARIANT")
  full <- variant == "full"
  minimal <- variant == "minimal"
  want <- c(cairo = !minimal, png = !minimal, ICU = !minimal,
            tcltk = full, jpeg = full, tiff = full, NLS = full)
  have <- caps[names(want)]
  if (!identical(unname(have), unname(want))) {
    print(rbind(want = want, capabilities = have))
    stop("capabilities() do not match the variant ", variant)
  }

  # pdf() is grDevices own C code, no cairo involved: every variant.
  f <- tempfile(fileext = ".pdf")
  pdf(f); plot(1:10); invisible(dev.off())
  stopifnot(file.size(f) > 1000)
  if (!minimal) {
    # headless cairo graphics (Windows: winCairo.dll, loaded on first use)
    f <- tempfile(fileext = ".svg"); svg(f); plot(1:10); invisible(dev.off())
    g <- tempfile(fileext = ".png"); png(g, type = "cairo"); plot(1:10); invisible(dev.off())
    stopifnot(file.size(f) > 1000, file.size(g) > 1000)
    cat("cairo devices OK\n")
  }

  # The bitmap devices: a file where the variant has the format, the
  # warning or error from the device where it does not.
  draw <- function(dev, ext) {
    f <- tempfile(fileext = ext)
    msgs <- character()
    res <- tryCatch(withCallingHandlers({
      if (windows) dev(f, type = "windows") else dev(f)
      plot(1:10); invisible(dev.off()); "drawn"
    }, warning = function(w) {
      msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning")
    }), error = function(e) paste("error:", conditionMessage(e)))
    graphics.off()
    list(made = file.exists(f) && file.size(f) > 100, msgs = c(res, msgs))
  }
  for (fmt in c("png", "jpeg", "tiff")) {
    r <- draw(get(fmt), paste0(".", fmt))
    cat(sprintf("  %s(): %s [%s]\n", fmt, if (r$made) "file written" else "no file",
                paste(r$msgs, collapse = "; ")))
    if (r$made != want[[fmt]])
      stop(fmt, "() ", if (r$made) "wrote a file" else "wrote no file",
           ", but variant ", variant, if (want[[fmt]]) " has " else " has no ", fmt)
    # "drawn" alone: the device opened and closed without a word
    # (an error replaces "drawn"; a warning follows it)
    if (!r$made && identical(r$msgs, "drawn"))
      stop(fmt, "() wrote no file and gave no warning or error")
  }
  cat("bitmap devices OK\n")

  # tcltk: the real package (full) or the stub (slim, minimal)
  if (full) {
    suppressWarnings(library(tcltk))
    stopifnot(identical(tclvalue(.Tcl("expr {6*7}")), "42"))
    cat("tcltk OK: Tcl", tclvalue(.Tcl("info patchlevel")), "\n")
  } else {
    m <- tryCatch({ library(tcltk); "loaded" }, error = function(e) conditionMessage(e))
    if (!grepl("Tcl/Tk support is not available", m)) stop("library(tcltk): ", m)
    cat("tcltk stub OK:", m, "\n")
  }

  # NLS: a translated base message (full)
  if (full) {
    ok <- isTRUE(attr(suppressWarnings(Sys.setLanguage("de")), "ok"))
    msg <- tryCatch(log(-1), warning = function(w) conditionMessage(w))
    Sys.setLanguage("en")
    if (grepl("wurden erzeugt", msg)) {
      cat("NLS OK:", msg, "\n")
    } else if (windows) {
      stop("NLS: no German translation of a base message (", msg, ")")
    } else {
      cat("NLS: translation not checked: the locale", Sys.getlocale("LC_MESSAGES"),
          "ignores LANGUAGE (setLanguage ok:", ok, "); got:", msg, "\n")
    }
  }
  cat("capability profile OK for variant:", variant, "\n")

  cat("\nsessionInfo BLAS/LAPACK:\n")
  si <- sessionInfo(); cat(si$BLAS, "\n", si$LAPACK, "\n")
  if (!windows) {
    if (Sys.getenv("R_SMOKE_BLAS") == "openblas") {
      stopifnot(grepl("openblas", si$BLAS, ignore.case = TRUE))
    } else {
      stopifnot(grepl("libRblas", si$BLAS))
    }
  }
'
echo "Smoke test passed ($OS/$VARIANT)."
