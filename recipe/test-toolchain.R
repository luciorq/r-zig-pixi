## r-zig-toolchain: a package with C and C++ code compiles, installs and
## loads (feat-no-host-paths PLAN.md, phase T).
stopifnot(file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
## The shipped Makeconf alone: a dev shell's R_MAKEVARS_USER
## (zigbuild/dev.Makevars, pixi.toml) must not leak into this test.
Sys.unsetenv("R_MAKEVARS_USER")
d <- tempfile("rzig-")
lib <- file.path(d, "lib")
p <- file.path(d, "rzigc")
dir.create(lib, recursive = TRUE)
dir.create(file.path(p, "src"), recursive = TRUE)
dir.create(file.path(p, "R"))
writeLines(c("Package: rzigc", "Version: 0.1", "Title: Test",
             "Description: Test package.", "License: MIT",
             "Author: r-zig", "Maintainer: r-zig <r-zig@example.org>"),
           file.path(p, "DESCRIPTION"))
writeLines(c("useDynLib(rzigc)", "export(one, two)"),
           file.path(p, "NAMESPACE"))
writeLines(c('one <- function() .Call("rzig_one")',
             'two <- function() .Call("rzig_two")'),
           file.path(p, "R", "f.R"))
writeLines(c("#include <Rinternals.h>",
             "SEXP rzig_one(void) { return ScalarInteger(1); }"),
           file.path(p, "src", "one.c"))
writeLines(c("#include <Rinternals.h>", "#include <string>",
             'extern "C" SEXP rzig_two(void) { std::string s("ab"); return ScalarInteger((int) s.size()); }'),
           file.path(p, "src", "two.cpp"))
install.packages(p, repos = NULL, type = "source", lib = lib)
library(rzigc, lib.loc = lib)
stopifnot(one() == 1L, two() == 2L)
cat("toolchain: C and C++ package compiled and loaded: OK\n")

## Makeconf in the conda env (feat-no-host-paths F1.5): the environment as
## $(R_HOME)/../.., which make expands to this env, FLIBS as the bare
## runtime the shims resolve, and (unix) an rpath into the env's lib dir,
## the conda package's one difference from the standalone tree.
.libPaths(c(lib, .libPaths()))
cfg <- function(v) tools::Rcmd(c("config", "--no-user-files", v), stdout = TRUE)
envdir <- normalizePath(file.path(R.home(), "..", ".."), winslash = "/")
stopifnot(grepl("-lflang_rt.runtime", cfg("FLIBS"), fixed = TRUE))
if (.Platform$OS.type == "unix") {
    stopifnot(grepl(paste0("-Wl,-rpath,", envdir, "/lib"), cfg("LDFLAGS"), fixed = TRUE))
    mk <- readLines(file.path(R.home("etc"), "Makeconf"))
    stopifnot(any(startsWith(mk, "CPPFLAGS = -I$(R_HOME)/../../include")))
} else {
    stopifnot(!grepl("-rpath", cfg("LDFLAGS"), fixed = TRUE))
}
cat("toolchain: Makeconf names the env relative to R_HOME: OK\n")

## A package that links an env library with no flags of its own: zlib's
## header and library come from Makeconf's $(R_HOME)/../.. (unix; Windows
## Makeconf has no CPPFLAGS, see PLAN.md F1.5).
mkpkg <- function(name, src, makevars = NULL) {
    q <- file.path(d, name)
    dir.create(file.path(q, "src"), recursive = TRUE)
    dir.create(file.path(q, "R"))
    writeLines(c(paste("Package:", name), "Version: 0.1", "Title: Test",
                 "Description: Test package.", "License: MIT", "Author: r-zig",
                 "Maintainer: r-zig <r-zig@example.org>"), file.path(q, "DESCRIPTION"))
    writeLines(c(paste0("useDynLib(", name, ")"), "export(f)"), file.path(q, "NAMESPACE"))
    writeLines(src$R, file.path(q, "R", "f.R"))
    writeLines(src$code, file.path(q, "src", src$file))
    if (!is.null(makevars)) writeLines(makevars, file.path(q, "src", "Makevars"))
    q
}
if (.Platform$OS.type == "unix") {
    pz <- mkpkg("rzigz", list(file = "z.c",
        code = c("#include <zlib.h>", "#include <Rinternals.h>",
                 "SEXP rzig_zv(void) { return mkString(zlibVersion()); }"),
        R = 'f <- function() .Call("rzig_zv")'), "PKG_LIBS = -lz")
    install.packages(pz, repos = NULL, type = "source", lib = lib)
    stopifnot(nzchar(rzigz::f()))
    cat("toolchain: package linking the env's zlib: OK (zlib", rzigz::f(), ")\n")

    ## Fortran through FLIBS (-lflang_rt.runtime, resolved by the shims to
    ## the static archive of the env's flang).
    ## Internal formatted I/O needs the runtime (_FortranAio*): a dropped
    ## -lflang_rt.runtime fails the package's load.
    pf <- mkpkg("rzigf", list(file = "s.f",
        code = c("      subroutine fw(n, r)", "      integer n, r",
                 "      character(len=12) buf", "      write(buf,'(i0)') n",
                 "      read(buf,'(i12)') r", "      end"),
        R = 'f <- function(n) .Fortran("fw", as.integer(n), r = 0L)$r'))
    install.packages(pf, repos = NULL, type = "source", lib = lib)
    stopifnot(rzigf::f(42L) == 42L)
    cat("toolchain: Fortran package through FLIBS: OK\n")

    ## Informational, never fails (PLAN.md F1.5, the conda rpath decision):
    ## a package linking fontconfig (an env library R does not load at
    ## startup), built fresh with Makeconf's LDFLAGS minus the rpath, then
    ## loaded in a fresh R. What it measures: R's own process. exec/R's
    ## rpath into the env covers it there; an embedding process (rpy2,
    ## RInside) has none, and that is not measured here.
    pn <- mkpkg("rzign", list(file = "n.c",
        code = c("#include <fontconfig/fontconfig.h>", "#include <Rinternals.h>",
                 "SEXP rzig_fc(void) { return ScalarInteger(FcGetVersion()); }"),
        R = 'f <- function() .Call("rzig_fc")'), "PKG_LIBS = -lfontconfig")
    lib2 <- file.path(d, "lib2"); dir.create(lib2)
    mv <- file.path(d, "norpath.mk")
    writeLines("LDFLAGS = -L$(R_HOME)/../../lib", mv)
    Sys.setenv(R_MAKEVARS_USER = mv)
    ok <- tryCatch({
        install.packages(pn, repos = NULL, type = "source", lib = lib2)
        out <- system2(file.path(R.home("bin"), "Rscript"),
                       c("--vanilla", "-e", shQuote(sprintf("library(rzign, lib.loc = '%s'); cat(rzign::f())", lib2))),
                       stdout = TRUE, stderr = TRUE)
        is.null(attr(out, "status"))
    }, error = function(e) NA)
    Sys.unsetenv("R_MAKEVARS_USER")
    cat("toolchain (informational): an env library without the env rpath loads in R's own process:",
        ok, "(embedders not measured)\n")
}
