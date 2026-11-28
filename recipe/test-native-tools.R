## r-zig-slim + r-zig-compilers + r-zig-native-tools, Windows (b14-l4
## PLAN.md; user decision U1 b): with R_ZIG_NATIVE_TOOLS=1 and no MSYS2 in
## the env (no r-zig-build-tools), R finds the native set first (patch
## 0018) and R CMD INSTALL builds a package that needs sh and make with it:
## a configure.win, a Makevars.win rule, and a C++ file, so make's command
## line carries install.R's quoted variables (patch 0017). R CMD INSTALL
## --build and utils::zip() then run native/bin's zip (b14-l4 U4).
stopifnot(.Platform$OS.type == "windows")
d <- tempfile("native-"); dir.create(d)
Sys.unsetenv(c("R_ZIG_EXTRA_ENV", "ZIG_BIN", "R_ZIG_TOOLCHAIN_HINT", "R_ZIG_NO_PREFLIGHT", "R_ZIG_TOOLCHAIN_ENV",
               "R_ZIG_PKG_BUILDER", "RZIG_TRACE", "MAKEFLAGS", "ZIG_LOCAL_CACHE_DIR", "CMAKE_GENERATOR",
               "CONFIG_SHELL", "R_CUSTOM_TOOLS_PATH"))
Sys.setenv(R_MAKEVARS_USER = file.path(d, "no-Makevars"),
           ZIG_GLOBAL_CACHE_DIR = Sys.getenv("R_ZIG_TEST_ZIG_CACHE", file.path(d, "zig-cache")),
           XDG_CACHE_HOME = file.path(d, "cache"))
native <- file.path(R.home(), "bin", "toolchain", "native", "bin")
stopifnot(file.exists(file.path(native, c("busybox.exe", "sh.exe", "make.exe", "zip.exe", "pkg-config.exe"))))
## no MSYS2 here: the env has no Library/usr/bin, R_HOME no usr/
env <- dirname(dirname(R.home()))
stopifnot(!dir.exists(file.path(env, "usr", "bin")), !dir.exists(file.path(R.home(), "bin", "toolchain", "usr")))
## only this env's programs, R's and System32 (+ the tools, through R)
Sys.setenv(PATH = paste(c(file.path(env, "bin"), R.home("bin"), file.path(Sys.getenv("SystemRoot"), "System32")),
                        collapse = ";"),
           R_ZIG_NATIVE_TOOLS = "1")
rcmd <- file.path(R.home("bin"), "R.exe")
run <- function(args) {
    f <- tempfile(tmpdir = d); st <- suppressWarnings(system2(rcmd, args, stdout = f, stderr = f))
    list(status = st, out = readLines(f, warn = FALSE))
}

## R CMD INSTALL: configure.win reports its sh, a Makevars.win rule makes
## make build the package (rzig build declines a rule) and report its host
pkg <- file.path(d, "nativetools")
dir.create(file.path(pkg, "src"), recursive = TRUE); dir.create(file.path(pkg, "R"))
writeLines(c("Package: nativetools", "Version: 0.1", "Title: Native Tools Test", "Description: Test package.",
             "License: GPL-2", "Author: r-zig", "Maintainer: r-zig <r-zig@example.org>"), file.path(pkg, "DESCRIPTION"))
writeLines("useDynLib(nativetools)", file.path(pkg, "NAMESPACE"))
writeLines("twice <- function(x) .Call(\"twice\", x)", file.path(pkg, "R", "twice.R"))
writeLines(c("#!/bin/sh", "echo \"configure.win: uname $(uname -s), sh $(command -v sh)\""), file.path(pkg, "configure.win"))
writeLines(c("#include <Rinternals.h>",
             "extern \"C\" SEXP twice(SEXP x) { return Rf_ScalarInteger(2 * Rf_asInteger(x)); }"),
           file.path(pkg, "src", "twice.cpp"))
writeLines(c("all: $(SHLIB) host", "host: ; @echo \"make: MAKE_HOST $(MAKE_HOST)\""), file.path(pkg, "src", "Makevars.win"))
lib <- file.path(d, "lib"); dir.create(lib)
r <- run(c("CMD", "INSTALL", "--no-test-load", paste0("--library=", lib), pkg))
writeLines(r$out)
stopifnot(r$status == 0,
          any(grepl("configure.win: uname Windows_NT", r$out, fixed = TRUE)),
          any(grepl("make: MAKE_HOST Windows32", r$out, fixed = TRUE)))
.libPaths(c(lib, .libPaths()))
stopifnot(nativetools:::twice(21L) == 42L)
cat("native tools: configure.win under busybox sh, make for Windows32, C++ through make: ok\n")

## R CMD INSTALL --build: the binary package as a zip (install.R's
## `zip -r9Xq`), from a fresh library
lib2 <- file.path(d, "lib2"); dir.create(lib2)
owd <- setwd(d)
r <- run(c("CMD", "INSTALL", "--build", "--no-test-load", paste0("--library=", lib2), pkg))
setwd(owd)
writeLines(r$out)
zipped <- file.path(d, "nativetools_0.1.zip")
stopifnot(r$status == 0, file.exists(zipped),
          "nativetools/DESCRIPTION" %in% utils::unzip(zipped, list = TRUE)$Name)
## utils::zip() with R_ZIPCMD unset: "zip" from PATH, here native/bin's
Sys.setenv(PATH = paste0(native, ";", Sys.getenv("PATH")))
Sys.unsetenv("R_ZIPCMD")
z <- file.path(d, "z.zip")
owd <- setwd(d)
st <- utils::zip(z, "nativetools")
setwd(owd)
stopifnot(st == 0, "nativetools/DESCRIPTION" %in% utils::unzip(z, list = TRUE)$Name)
cat("native tools: R CMD INSTALL --build and utils::zip() with native/bin's zip: ok\n")
