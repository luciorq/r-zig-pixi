## r-zig-toolchain: a package with C and C++ code compiles, installs and
## loads (feat-no-host-paths PLAN.md, phase T).
stopifnot(file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")))
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
