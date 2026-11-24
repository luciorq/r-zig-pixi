set.seed(1)
m <- matrix(rnorm(64), 8, 8)
stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
stopifnot(abs(det(qr.R(qr(m)))) > 0)
stopifnot(max(Mod(fft(fft(1:8), inverse = TRUE) / 8 - 1:8)) < 1e-9)
stopifnot(
  grepl("[0-9]+", "R 4", perl = TRUE),
  identical(memDecompress(memCompress("x")), charToRaw("x"))
)
## OpenMP parallel regions in R itself (r-zig-slim has OpenMP, as on
## unix): colSums() (array.c, a region with 10 firstprivate values,
## entered even with 1 thread) and dist() (stats distance.c, a region
## only with more than 1 thread). Win-arm64 libomp builds have broken
## regions with more than six shared values (feat-win-arm64).
old <- .Internal(setMaxNumMathThreads(4L))
for (nt in c(1L, 4L)) {
  invisible(.Internal(setNumMathThreads(nt)))
  x <- matrix(as.double(1:600), 20)
  stopifnot(
    identical(colSums(x), vapply(1:30, function(j) sum(x[, j]), 0)),
    identical(colMeans(x), colSums(x) / 20)
  )
  d <- as.vector(dist(cbind(0:39 * 3, 0:39 * 4)))
  stopifnot(isTRUE(all.equal(d, unlist(lapply(1:39, function(j) 5 * seq_len(40 - j))))))
}
invisible(.Internal(setNumMathThreads(1L)))
invisible(.Internal(setMaxNumMathThreads(old)))
## r-zig-slim's profile, as on unix (the recipe's unix one-liner): the
## variant table is the same on every OS since 2026-11-14. On Windows
## capabilities() reads config.h only (platform.c), so the devices and
## tcltk are also checked by what they do.
## tcltk (build 13): win-64's libR has HAVE_TCLTK and the tcltk package
## is the add-on r-zig-tcltk's; win-arm64 (no tk 8.6 on conda-forge)
## keeps the stub and capabilities("tcltk") FALSE.
arm64 <- R.version$arch == "aarch64"
caps <- capabilities()
stopifnot(
  caps[["cairo"]], caps[["png"]], caps[["ICU"]], caps[["iconv"]],
  caps[["libcurl"]],
  caps[["tcltk"]] == !arm64, !caps[["jpeg"]], !caps[["tiff"]], !caps[["NLS"]]
)
## the cairo devices draw: winCairo.dll loads on first use, and
## capabilities("cairo") is TRUE even when it cannot load
f <- tempfile(fileext = ".svg"); svg(f); plot(1:10); invisible(dev.off())
stopifnot(file.size(f) > 1000)
## the Windows bitmap devices (winbitmap.c): png draws a file; jpeg and
## tiff fail cleanly (the r-zig stubs, zigbuild/patches 0015) with R's
## warning or error and no file
draw <- function(dev, ext) {
  f <- tempfile(fileext = ext)
  msgs <- character()
  res <- tryCatch(withCallingHandlers({
    dev(f, type = "windows"); plot(1:10); invisible(dev.off()); "drawn"
  }, warning = function(w) {
    msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning")
  }), error = function(e) paste("error:", conditionMessage(e)))
  graphics.off()
  list(made = file.exists(f) && file.size(f) > 100, msgs = c(res, msgs))
}
r <- draw(png, ".png")
if (!r$made) stop("png(type = 'windows') wrote no file: ", paste(r$msgs, collapse = "; "))
for (fmt in c("jpeg", "tiff")) {
  r <- draw(get(fmt), paste0(".", fmt))
  if (r$made) stop(fmt, "() wrote a file, but r-zig-slim has no ", fmt)
  # "drawn" alone: the device opened and closed without a word (an error
  # replaces "drawn"; a warning follows it), as in scripts/smoke-test.sh
  if (identical(r$msgs, "drawn")) stop(fmt, "() wrote no file and gave no warning or error")
  cat(fmt, "() fails cleanly: ", paste(r$msgs, collapse = "; "), "\n", sep = "")
}
cat("conda R OK\n")
## tcltk: on win-64 the package is r-zig-tcltk's, so r-zig-slim has
## none; on win-arm64 library(tcltk) is the stub (R/unix/zzzstub.R, as on
## unix), which stops with its own message
if (arm64) {
  m <- tryCatch({ library(tcltk); "loaded" }, error = function(e) conditionMessage(e))
  if (!grepl("Tcl/Tk support is not available", m)) stop("library(tcltk): ", m)
  cat("conda tcltk stub OK:", m, "\n")
} else {
  if (nzchar(system.file(package = "tcltk"))) stop("r-zig-slim has a tcltk package; it is r-zig-tcltk's")
  cat("conda tcltk: none in the base (r-zig-tcltk's)\n")
}
