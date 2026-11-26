## r-zig-tcltk's test (recipe.yaml): R's tcltk package, the add-on to
## r-zig-slim, loads and runs Tcl from conda-forge's tk 8.6. Headless:
## without DISPLAY (linux) Tk itself is not started and tcltk warns, but
## Tcl runs. Run with Rscript.

stopifnot(capabilities("tcltk"))
d <- system.file(package = "tcltk")
if (!nzchar(d)) stop("no tcltk package")
desc <- packageDescription("tcltk")
stopifnot(identical(desc$Priority, "base"),
          identical(desc$Version, paste(R.version$major, R.version$minor, sep = ".")))
## the real package, not the stub (R/unix/zzzstub.R stops in .onLoad)
suppressWarnings(library(tcltk))
stopifnot(identical(tclvalue(.Tcl("expr {6*7}")), "42"))
pl <- tclvalue(.Tcl("info patchlevel"))
if (!startsWith(pl, "8.6.")) stop("Tcl ", pl, ", not 8.6")
## Tcl's script library and its modules (init.tcl; clock needs msgcat,
## from lib/tcl8): found from the env's tk package, not the build machine
stopifnot(identical(tclvalue(.Tcl("clock format 0 -gmt 1 -format %Y")), "1970"))
## tcltk's own Tcl scripts (exec/), which .onLoad adds to auto_path
stopifnot(file.exists(file.path(d, "exec", "hierarchy.tcl")))
cat("conda tcltk OK: Tcl", pl, "; Tk", if (tcltk:::.TkUp) "up" else "not started (no display)", "\n")
