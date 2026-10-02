## r-zig-slim alone (no r-zig-toolchain): an R-only package installs from
## source, and one with compiled code stops with the preflight message
## that names the toolchain package (feat-no-host-paths PLAN.md, phase T).
stopifnot(!file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
## A user Makevars switches the preflight off: a dev shell's
## R_MAKEVARS_USER must not leak in, nor its R_ZIG_EXTRA_ENV (pixi.toml),
## the compilers' extra environment.
Sys.unsetenv(c("R_MAKEVARS_USER", "R_ZIG_EXTRA_ENV"))
d <- tempfile("rzig-")
lib <- file.path(d, "lib")
dir.create(lib, recursive = TRUE)
mkpkg <- function(name, src = FALSE) {
    p <- file.path(d, name)
    dir.create(file.path(p, "R"), recursive = TRUE)
    writeLines(c(paste("Package:", name), "Version: 0.1", "Title: Test",
                 "Description: Test package.", "License: MIT",
                 "Author: r-zig", "Maintainer: r-zig <r-zig@example.org>"),
               file.path(p, "DESCRIPTION"))
    writeLines("export(hi)", file.path(p, "NAMESPACE"))
    writeLines('hi <- function() "hi"', file.path(p, "R", "hi.R"))
    if (src) {
        dir.create(file.path(p, "src"))
        writeLines("int rzig_one(void) { return 1; }", file.path(p, "src", "one.c"))
    }
    p
}
install.packages(mkpkg("rzigronly"), repos = NULL, type = "source", lib = lib)
stopifnot(requireNamespace("rzigronly", lib.loc = lib))
out <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
                                c("CMD", "INSTALL", "-l", shQuote(lib),
                                  shQuote(mkpkg("rzigsrc", src = TRUE))),
                                stdout = TRUE, stderr = TRUE))
cat(out, sep = "\n")
stopifnot(!is.null(attr(out, "status")),
          any(grepl("r-zig toolchain is not installed", out, fixed = TRUE)),
          !dir.exists(file.path(lib, "rzigsrc")))
cat("base package without the toolchain: OK\n")
