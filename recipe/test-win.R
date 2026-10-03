set.seed(1)
m <- matrix(rnorm(64), 8, 8)
stopifnot(max(abs(solve(m) %*% m - diag(8))) < 1e-9)
stopifnot(abs(det(qr.R(qr(m)))) > 0)
stopifnot(max(Mod(fft(fft(1:8), inverse = TRUE) / 8 - 1:8)) < 1e-9)
stopifnot(
  grepl("[0-9]+", "R 4", perl = TRUE),
  identical(memDecompress(memCompress("x")), charToRaw("x"))
)
caps <- capabilities()
stopifnot(caps[["png"]], caps[["iconv"]], caps[["libcurl"]], caps[["cairo"]])
## the cairo devices draw: winCairo.dll loads on first use, and
## capabilities("cairo") is TRUE even when it cannot load
f <- tempfile(fileext = ".svg"); svg(f); plot(1:10); invisible(dev.off())
stopifnot(file.size(f) > 1000)
cat("conda R OK\n")
## tcltk: a conda env has no R_HOME/Tcl, so etc/Renviron.site's MY_TCLTK
## points tcltk's .onLoad at the tk package's DLLs in Library/bin, and Tcl
## finds its scripts and modules (msgcat, which `clock` needs) beside them
## in Library/lib (build.zig installEnvRuntime).
library(tcltk)
stopifnot(tclvalue(.Tcl("clock format 0 -gmt 1 -format %Y")) == "1970")
cat("conda tcltk OK: Tcl/Tk", tclvalue(tcl("info", "patchlevel")), "\n")
