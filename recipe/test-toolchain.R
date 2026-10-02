## r-zig-toolchain: a package with C and C++ code compiles, installs and
## loads (feat-no-host-paths PLAN.md, phase T).
stopifnot(file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
## The shipped tree alone: a dev shell's personal Makevars
## (R_MAKEVARS_USER) and its extra environment for the compilers
## (R_ZIG_EXTRA_ENV, pixi.toml) must not leak into this test.
Sys.unsetenv(c("R_MAKEVARS_USER", "R_ZIG_EXTRA_ENV"))
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

## Makeconf in the conda env (feat-no-host-paths F1.5, F3b): FLIBS as the
## bare runtime rzig resolves, and no flags of the environment: CPPFLAGS
## and LDFLAGS are empty, the compilers add them.
.libPaths(c(lib, .libPaths()))
windows <- .Platform$OS.type == "windows"
cfg <- function(v) trimws(paste(tools::Rcmd(c("config", "--no-user-files", v), stdout = TRUE), collapse = " "))
stopifnot(grepl("-lflang_rt.runtime", cfg("FLIBS"), fixed = TRUE),
          identical(cfg("CPPFLAGS"), ""), identical(cfg("LDFLAGS"), ""))
cat("toolchain: Makeconf has no environment flags, FLIBS = -lflang_rt.runtime: OK\n")

## What the compilers (rzig) add: the include/ and lib/ of the env R is
## installed in (on Windows <prefix>/Library, headers by -idirafter), and
## on unix an rpath into its lib/, a conda env; nothing from a CONDA_PREFIX
## naming another env. A decoy env with a poisoned zlib.h stands in for
## one, here and in the zlib package's build below.
envdir <- normalizePath(file.path(R.home(), "..", ".."), winslash = "/")
decoy <- file.path(d, "decoy")
for (s in c("conda-meta", "include", "lib", "Library/include", "Library/lib"))
    dir.create(file.path(decoy, s), recursive = TRUE)
for (h in file.path(decoy, c("include", "Library/include"), "zlib.h"))
    writeLines("#error decoy CONDA_PREFIX", h)
with_env <- function(vars, expr) {
    old <- Sys.getenv(names(vars), unset = NA, names = TRUE)
    on.exit(for (v in names(old)) if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old[v])))
    do.call(Sys.setenv, as.list(vars))
    expr
}
## R_HOME/bin/toolchain: R.home("bin") is bin/x64 on Windows.
tc <- file.path(R.home(), "bin", "toolchain", if (windows) "gcc.exe" else "zig-cc")
argv <- with_env(c(RZIG_PRINT_ARGV = "1", CONDA_PREFIX = decoy),
                 system2(tc, c("-shared", "-o", "x.so", "x.o", "-lz"), stdout = TRUE))
cat(argv, sep = "\n")
has <- function(x) if (windows) tolower(x) %in% tolower(argv) else x %in% argv
stopifnot(has(paste0("-L", envdir, "/lib")),
          !any(grepl("decoy", argv, fixed = TRUE)))
if (windows) {
    stopifnot(!any(grepl("rpath", argv, fixed = TRUE)))
    if (dir.exists(file.path(envdir, "include")))
        stopifnot(has("-idirafter"), has(paste0(envdir, "/include")))
} else {
    stopifnot(has(paste0("-Wl,-rpath,", envdir, "/lib")), has(paste0("-I", envdir, "/include")))
}
cat("toolchain: the compilers add this env's -I/-L", if (!windows) "and rpath", "and ignore CONDA_PREFIX: OK\n")

## A package that links an env library with no flags of its own: zlib's
## header and library come from the env the compilers are installed in,
## built with the decoy as CONDA_PREFIX (its zlib.h is an #error).
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
pz <- mkpkg("rzigz", list(file = "z.c",
    code = c("#include <zlib.h>", "#include <Rinternals.h>",
             "SEXP rzig_zv(void) { return mkString(zlibVersion()); }"),
    R = 'f <- function() .Call("rzig_zv")'), "PKG_LIBS = -lz")
with_env(c(CONDA_PREFIX = decoy), install.packages(pz, repos = NULL, type = "source", lib = lib))
stopifnot(nzchar(rzigz::f()))
cat("toolchain: package linking the env's zlib: OK (zlib", rzigz::f(), ")\n")

if (!windows) {
    ## Its rpath: exactly this env's lib dir (RUNPATH, LC_RPATH), so the
    ## env's libz loads in any process, an embedding one too (glibc applies
    ## only the executable's own DT_RPATH to a dlopened library's
    ## dependencies).
    so <- file.path(lib, "rzigz", "libs", "rzigz.so")
    if (Sys.info()[["sysname"]] == "Darwin") {
        ol <- system2("otool", c("-l", shQuote(so)), stdout = TRUE)
        rp <- sub("^ *path (.*) \\(offset [0-9]+\\)$", "\\1", ol[grep("cmd LC_RPATH", ol) + 2L])
    } else if (nzchar(Sys.which("readelf"))) {
        dyn <- system2("readelf", c("-d", shQuote(so)), stdout = TRUE)
        stopifnot(!any(grepl("(RPATH)", dyn, fixed = TRUE)))
        rp <- unlist(strsplit(sub(".*\\[(.*)\\].*", "\\1", grep("(RUNPATH)", dyn, fixed = TRUE, value = TRUE)), ":"))
    } else {
        ## no readelf here: the rpath string, NUL-terminated, in the file
        bytes <- readBin(so, "raw", file.size(so))
        rp <- if (length(grepRaw(c(charToRaw(paste0(envdir, "/lib")), as.raw(0)), bytes, fixed = TRUE)))
            paste0(envdir, "/lib") else character()
        cat("toolchain: no readelf; the rpath checked as a string in the file\n")
    }
    cat("toolchain: rzigz.so rpath:", rp, "\n")
    stopifnot(identical(rp, paste0(envdir, "/lib")))
    cat("toolchain: rzigz.so's rpath is this env's lib: OK\n")

    ## Fortran through FLIBS (-lflang_rt.runtime, resolved by rzig to the
    ## static archive of the env's flang).
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
}
