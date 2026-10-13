## r-zig-toolchain: a package with C and C++ code compiles, installs and
## loads (feat-no-host-paths PLAN.md, phase T). rzig is there under CC's
## name, which the install preflight runs (gcc.exe on Windows,
## feat-standalone-toolchain B26), in R_HOME/bin/toolchain (R.home("bin")
## is bin/x64 on Windows).
windows <- .Platform$OS.type == "windows"
tc <- file.path(R.home(), "bin", "toolchain", if (windows) "gcc.exe" else "zig-cc")
stopifnot(file.exists(tc))
## The shipped tree alone: a dev shell's personal Makevars
## (R_MAKEVARS_USER) and its extra environment for the compilers
## (R_ZIG_EXTRA_ENV, pixi.toml) must not leak into this test.
Sys.unsetenv(c("R_MAKEVARS_USER", "R_ZIG_EXTRA_ENV"))
d <- tempfile("rzig-")
## zig's cache and rzig's in the test's temporary dir, as scripts/env.sh
## puts zig's in build/: the test leaves nothing in the user's caches
## (%LOCALAPPDATA%\zig and \r-zig, ~/.cache/zig and ~/.cache/r-zig).
Sys.setenv(ZIG_GLOBAL_CACHE_DIR = file.path(d, "zig-cache"),
           ZIG_LOCAL_CACHE_DIR = file.path(d, "zig-cache"),
           XDG_CACHE_HOME = file.path(d, "cache"))
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
## R CMD INSTALL builds a package of this shape through `rzig build`
## (feat-zig-pkg-build, patch 0013, the default R_ZIG_PKG_BUILDER=auto),
## asserted from its kept log (RZIG_TRACE=1: `rzig build: tier 1`); the
## make path, which every package that needs make still takes (rzigar
## below, with its Makevars rule), builds the same shapes once more into a
## second library with R_ZIG_PKG_BUILDER=make (make_ref below).
## (install.packages keeps no output for a local path: R CMD INSTALL run
## directly, its log in install-logs/<name>.log)
outs <- file.path(d, "install-logs")
dir.create(outs)
install_log <- function(pkg_dir, name, to) {
    log <- file.path(outs, paste0(name, ".log"))
    r <- file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R")
    st <- system2(r, c(if (!windows) "CMD", "INSTALL", "-l", shQuote(to), shQuote(pkg_dir)),
                  stdout = log, stderr = log)
    if (st != 0L) { cat(readLines(log, warn = FALSE), sep = "\n"); stop("R CMD INSTALL of ", name, " failed") }
    readLines(log, warn = FALSE)
}
Sys.setenv(RZIG_TRACE = "1")
log <- install_log(p, "rzigc", lib)
Sys.unsetenv("RZIG_TRACE")
stopifnot(any(grepl("rzig build: tier 1", log, fixed = TRUE)))
library(rzigc, lib.loc = lib)
stopifnot(one() == 1L, two() == 2L)
cat("toolchain: C and C++ package compiled (rzig build: tier 1) and loaded: OK\n")
lib_make <- file.path(d, "lib-make")
dir.create(lib_make)
make_ref <- function(pkg_dir, name) {
    Sys.setenv(R_ZIG_PKG_BUILDER = "make")
    on.exit(Sys.unsetenv("R_ZIG_PKG_BUILDER"))
    log <- install_log(pkg_dir, name, lib_make)
    stopifnot(!any(grepl("rzig build:", log, fixed = TRUE)))
    name
}
make_ref(p, "rzigc")
stopifnot(getExportedValue(loadNamespace("rzigc", lib.loc = lib_make), "two")() == 2L)
cat("toolchain: the same package through make (R_ZIG_PKG_BUILDER=make): OK\n")

## Makeconf in the conda env (feat-no-host-paths F1.5, F3b): FLIBS as the
## bare runtime rzig resolves, and no flags of the environment: CPPFLAGS
## and LDFLAGS are empty, the compilers add them.
.libPaths(c(lib, .libPaths()))
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
with_env(c(CONDA_PREFIX = decoy), make_ref(pz, "rzigz"))
stopifnot(nzchar(getExportedValue(loadNamespace("rzigz", lib.loc = lib_make), "f")()))
cat("toolchain: the zlib package through make too: OK\n")

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

}

## A package that builds a static library with $(AR) and $(RANLIB) and
## links it into its shared library, as packages with a bundled C library
## do. Both are rzig (zig ar, zig ranlib) on every OS; on Windows since
## feat-standalone-toolchain phase 3 (B43: zig-ar.exe and zig-ranlib.exe,
## where MinGW's ar and ranlib were), and whether zig ar's archives link
## there is B43's risk. The library's source is in a subdirectory, outside
## the package's OBJECTS, so its symbol comes from the archive alone.
for (v in c("AR", "RANLIB")) {
    tool <- cfg(v)
    stopifnot(basename(dirname(tool)) == "toolchain",
              basename(tool) == paste0("zig-", tolower(v), if (windows) ".exe"))
}
pa <- mkpkg("rzigar", list(file = "f.c",
    code = c("#include <Rinternals.h>", "int rzig_foo(void);",
             "SEXP rzig_ar(void) { return ScalarInteger(rzig_foo()); }"),
    R = 'f <- function() .Call("rzig_ar")'),
    c("PKG_LIBS = foo/libfoo.a",
      "$(SHLIB): foo/libfoo.a",
      "foo/libfoo.a: foo/foo.o",
      "\t$(AR) cr $@ foo/foo.o",
      "\t$(RANLIB) $@"))
dir.create(file.path(pa, "src", "foo"))
writeLines("int rzig_foo(void) { return 42; }", file.path(pa, "src", "foo", "foo.c"))
install.packages(pa, repos = NULL, type = "source", lib = lib)
stopifnot(rzigar::f() == 42L)
cat("toolchain: AR and RANLIB are rzig; a static library built with them links and loads: OK\n")

if (windows) {
    ## The binutils Makeconf.win names by path (NM, DLLTOOL, RESCOMP,
    ## OBJDUMP, STRIP_*) are conda-forge's MinGW copies in
    ## R_HOME/bin/toolchain/binutils/, which this package owns, with the
    ## records of where they come from: SOURCES names their package and its
    ## sha256, LICENSES/ holds its licences (feat-standalone-toolchain B24,
    ## B41). nm runs, loading zstd.dll from this env's Library/bin.
    nm <- cfg("NM")
    stopifnot(basename(nm) == "nm.exe", basename(dirname(nm)) == "binutils",
              basename(dirname(dirname(nm))) == "toolchain", file.exists(nm))
    bu <- file.path(R.home(), "bin", "toolchain", "binutils")
    stopifnot(file.exists(file.path(bu, paste0(c("nm", "dlltool", "as", "strip", "windres", "objdump"), ".exe"))))
    src <- readLines(file.path(bu, "SOURCES"))
    i <- match("package: binutils_impl_win-64", src)
    stopifnot(!is.na(i))
    blk <- src[i:length(src)]
    blk <- blk[cumsum(blk == "") == 0L]
    stopifnot(any(grepl("^sha256: [0-9a-f]{64}$", blk)),
              length(list.files(file.path(bu, "LICENSES", "binutils_impl_win-64"), recursive = TRUE)) > 0L)
    out <- system2(nm, "--version", stdout = TRUE)
    stopifnot(grepl("GNU nm", out[1L], fixed = TRUE))
    cat("toolchain: NM is", nm, "and binutils/ has its SOURCES (binutils_impl_win-64) and LICENSES: OK\n")
    ## R CMD check's DLL check reads OBJDUMP as sotools.R's
    ## read_symbols_from_dll does: R CMD config's value, kept only when it
    ## plus ".exe" is a file (Makeconf.win names objdump without .exe).
    od <- cfg("OBJDUMP")
    stopifnot(basename(od) == "objdump", basename(dirname(od)) == "binutils",
              file.exists(paste0(od, ".exe")),
              length(tools:::read_symbols_from_dll(file.path(R.home("bin"), "R.dll"))) > 0L)
    used <- get0("DLL_nm", envir = tools:::read_symbols_from_dll_state, inherits = FALSE)
    stopifnot(!is.null(used), normalizePath(paste0(trimws(used), ".exe")) == normalizePath(paste0(od, ".exe")))
    ## CMake looks for ar and ranlib beside the C compiler before PATH
    ## (CMakeFindBinUtils): rzig's ar.exe and ranlib.exe beside gcc.exe.
    stopifnot(file.exists(file.path(dirname(cfg("CC")), c("ar.exe", "ranlib.exe"))))
    cat("toolchain: R CMD check reads R.dll's imports with OBJDUMP,", od, "; ar.exe and ranlib.exe beside CC: OK\n")
}

## Fortran. Internal formatted I/O needs the runtime (_FortranAio*): a
## dropped -lflang_rt.runtime fails the package's load.
fw <- list(file = "s.f",
    code = c("      subroutine fw(n, r)", "      integer n, r",
             "      character(len=12) buf", "      write(buf,'(i0)') n",
             "      read(buf,'(i12)') r", "      end"),
    R = 'f <- function(n) .Fortran("fw", as.integer(n), r = 0L)$r')
if (!windows) {
    ## through FLIBS (-lflang_rt.runtime, resolved by rzig to the static
    ## archive of the env's flang)
    pf <- mkpkg("rzigf", fw)
    install.packages(pf, repos = NULL, type = "source", lib = lib)
    stopifnot(rzigf::f(42L) == 42L)
    make_ref(pf, "rzigf")
    stopifnot(getExportedValue(loadNamespace("rzigf", lib.loc = lib_make), "f")(42L) == 42L)
    cat("toolchain: Fortran package through FLIBS (rzig build, and make): OK\n")
}
## FC is the toolchain's zig-fc (feat-no-host-paths F3c; zig-fc.exe on
## Windows, named without .exe), which runs the env's flang. Under
## USE_FC_TO_LINK, R links with SHLIB_FCLD = $(FC) and leaves $(FLIBS)
## off: zig-fc links the objects through zig, as zig-cc (gcc.exe) links,
## with the static runtime of that flang (flang's own driver: "cannot find
## -lflang_rt.runtime").
fc <- strsplit(cfg("FC"), " +")[[1]][1]
stopifnot(basename(dirname(fc)) == "toolchain", sub("[.]exe$", "", basename(fc)) == "zig-fc")
pfl <- mkpkg("rzigfl", fw, "USE_FC_TO_LINK =")
install.packages(pfl, repos = NULL, type = "source", lib = lib)
stopifnot(rzigfl::f(42L) == 42L)
make_ref(pfl, "rzigfl")
stopifnot(getExportedValue(loadNamespace("rzigfl", lib.loc = lib_make), "f")(42L) == 42L)
if (!windows && Sys.info()[["sysname"]] != "Darwin" && nzchar(Sys.which("readelf"))) {
    for (l in c(lib, lib_make)) {
        dyn <- system2("readelf", c("-d", shQuote(file.path(l, "rzigfl", "libs", "rzigfl.so"))), stdout = TRUE)
        stopifnot(!any(grepl("flang_rt", dyn, fixed = TRUE)))
    }
}
cat("toolchain: FC is", fc, "and a USE_FC_TO_LINK Fortran package links and loads (rzig build, and make): OK\n")
