## r-zig-slim + r-zig-compilers (verify-bundle's scenario 2 on conda;
## feat-standalone-toolchain B28, phase 4): no make, and none needed for a
## package that has no configure script and no make rules, which rzig
## build compiles with zig and flang alone (feat-zig-pkg-build, patch
## 0013). One that needs make stops in the preflight (patch 0009), naming
## r-zig-build-tools.
windows <- .Platform$OS.type == "windows"
d <- tempfile("rzig-"); dir.create(d)
## the caller's settings (pixi run, conda run, wheel-test; rattler-build's
## test env passes them on win-64, and only PATH on unix, SC §3):
## R_ZIG_EXTRA_ENV (pixi.toml) adds an environment; ZIG_BIN a zig;
## R_ZIG_NO_PREFLIGHT skips 0009; R_ZIG_PKG_BUILDER=make sends tier 1 to
## make; RZIG_TRACE changes the logs; a MAKEFLAGS assignment makes rzig
## build decline (0013); ZIG_LOCAL_CACHE_DIR defeats N3's per-install
## cache; R_ZIG_TOOLCHAIN_HINT adds a line
Sys.unsetenv(c("R_ZIG_EXTRA_ENV", "ZIG_BIN", "R_ZIG_TOOLCHAIN_HINT", "R_ZIG_NO_PREFLIGHT",
               "R_ZIG_PKG_BUILDER", "RZIG_TRACE", "MAKEFLAGS", "ZIG_LOCAL_CACHE_DIR"))
## a user Makevars switches the preflight off. Unset, R_MAKEVARS_USER lets
## R (install.R's makevars_user) and rzig (pkgbuild.zig) fall back to
## ~/.R/Makevars*; naming a file that does not exist means "none" to both
Sys.setenv(R_MAKEVARS_USER = file.path(d, "no-Makevars"))
## zig's cache: shared between the recipe tests when conda-package asks
## (R_ZIG_TEST_ZIG_CACHE), else this test's own; rzig's cache in d
Sys.setenv(ZIG_GLOBAL_CACHE_DIR = Sys.getenv("R_ZIG_TEST_ZIG_CACHE", file.path(d, "zig-cache")),
           XDG_CACHE_HOME = file.path(d, "cache"))
## only this env's programs (Windows: also R's bin\x64 and System32);
## env_bin is <prefix>/bin, on Windows <prefix>/Library/bin. With usr_bin
## also the userland R's makefiles run besides make: on Windows m2's
## Library\usr\bin, before the env; on unix the host's /usr/bin and /bin,
## after it (B25), since GNU make runs a recipe line with no shell syntax,
## such as config.mk's `@echo $($(VAR))`, from PATH itself
env_bin <- normalizePath(file.path(R.home(), "..", "..", "bin"))
narrow <- function(usr_bin = FALSE)
    Sys.setenv(PATH = paste(c(if (windows && usr_bin) normalizePath(file.path(env_bin, "..", "usr", "bin")),
                              env_bin,
                              if (windows) c(R.home("bin"), file.path(Sys.getenv("SystemRoot"), "System32"))
                              else if (usr_bin) c("/usr/bin", "/bin")),
                            collapse = .Platform$path.sep))
## how rzig shows a path (check.zig's display(): `/` only on Windows), and
## a comparison that ignores the drive letter's case there
shown <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
same_path <- function(a, b) if (windows) tolower(a) == tolower(b) else a == b
## a command's status and output through a file: a 127 through
## system2(stdout = TRUE) is R's own error (sys-unix.c), not a status;
## through a file R only warns that it is one
run_to <- function(cmd, args) {
    f <- tempfile(tmpdir = d); st <- suppressWarnings(system2(cmd, args, stdout = f, stderr = f))
    list(status = st, out = readLines(f, warn = FALSE))
}

narrow()
## the group's boundary: a run dependency that brought make would show
## here (Sys.which scans PATH in R, patch 0002). On Windows m2's make and
## sh install into Library\usr\bin, which narrow() leaves off PATH, so
## that directory is looked at itself
mk <- c(Sys.which("make"),
        if (windows) Filter(file.exists, file.path(env_bin, "..", "usr", "bin", c("make.exe", "sh.exe"))))
mk <- mk[nzchar(mk)]
if (length(mk)) stop("build tools in an env without r-zig-build-tools: ", paste(mk, collapse = ", "))

## rzig's check finds the env's zig and flang. B34's order (the env's bin
## before PATH) is rzig-test's (find_zig.zig, flang_rt.zig): here the two
## are one directory
cc <- file.path(R.home(), "bin", "toolchain", if (windows) "gcc.exe" else "zig-cc")
r <- run_to(cc, "--rzig-check=fortran"); cat(r$out, sep = "\n")
fl <- sub("^.*; flang at ", "", r$out[1L])
stopifnot(r$status == 0L, startsWith(r$out[1L], "zig-cc: compilers ok: zig 0.16."),
          grepl("; flang at ", r$out[1L], fixed = TRUE),
          same_path(shown(dirname(fl)), shown(env_bin)))
cat("compilers: the check finds the env's zig and flang, and the env has no build tools: OK\n")

lib <- file.path(d, "lib")
dir.create(lib)
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
## R CMD INSTALL, its output kept (Rcmd.exe on Windows, as
## test-toolchain.R)
inst <- function(pkg) run_to(file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R"),
                             c(if (!windows) "CMD", "INSTALL", "-l", shQuote(lib), shQuote(pkg)))
## tier 1 through rzig build, traced (RZIG_TRACE=1: `rzig build: tier
## 1`): C, and Fortran with no Makevars, which links FLIBS's runtime
## (PHASE4 Cc10 b; Windows and macOS: with libc++)
tier1 <- function(pkg, name) {
    Sys.setenv(RZIG_TRACE = "1"); on.exit(Sys.unsetenv("RZIG_TRACE"))
    r <- inst(pkg)
    if (r$status != 0L || !any(grepl("rzig build: tier 1", r$out, fixed = TRUE))) {
        cat(r$out, sep = "\n")
        stop(name, ": not installed through rzig build's tier 1")
    }
}
tier1(mkpkg("rzigc", list(file = "one.c",
    code = c("#include <Rinternals.h>", "SEXP rzig_one(void) { return ScalarInteger(1); }"),
    R = 'f <- function() .Call("rzig_one")')), "rzigc")
stopifnot(getExportedValue(loadNamespace("rzigc", lib.loc = lib), "f")() == 1L)
cat("compilers: a C package through rzig build (tier 1), no make: OK\n")
## internal formatted I/O needs the runtime (_FortranAio*): a dropped
## -lflang_rt.runtime fails the package's load
tier1(mkpkg("rzigf", list(file = "s.f",
    code = c("      subroutine fw(n, r)", "      integer n, r",
             "      character(len=12) buf", "      write(buf,'(i0)') n",
             "      read(buf,'(i12)') r", "      end"),
    R = 'f <- function(n) .Fortran("fw", as.integer(n), r = 0L)$r')), "rzigf")
stopifnot(getExportedValue(loadNamespace("rzigf", lib.loc = lib), "f")(42L) == 42L)
cat("compilers: a Fortran package through rzig build (tier 1, FLIBS), no make: OK\n")

## a Makevars rule needs make (test-toolchain.R's rzigar shape): the
## preflight stops, naming r-zig-build-tools, and installs nothing
r <- inst(mkpkg("rzigmk", list(file = "f.c",
    code = c("#include <Rinternals.h>", "int rzig_foo(void);",
             "SEXP rzig_mk(void) { return ScalarInteger(rzig_foo()); }"),
    R = 'f <- function() .Call("rzig_mk")'),
    c("PKG_LIBS = foo/libfoo.a", "$(SHLIB): foo/libfoo.a", "foo/libfoo.a: foo/foo.o",
      "\t$(AR) cr $@ foo/foo.o", "\t$(RANLIB) $@")))
cat(r$out, sep = "\n")
stopifnot(r$status != 0L,
          any(grepl("rzigmk needs make: src/Makevars has a rule or target line", r$out, fixed = TRUE)),
          any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")),
          any(grepl("pixi add r-zig-build-tools (or conda install r-zig-build-tools)", r$out, fixed = TRUE)),
          any(grepl("which is incomplete (see above)", r$out, fixed = TRUE)),
          ## no make where r-zig-build-tools would put it (open point I a)
          !any(grepl("is installed in R's environment", r$out, fixed = TRUE)),
          !dir.exists(file.path(lib, "rzigmk")))
cat("compilers: a package that needs make stops, naming r-zig-build-tools: OK\n")

## R CMD config evaluates Makeconf through make: patch 0010 stops first
## with rzig's text. Windows: rcmdfn.c runs `sh config.sh`, so with no sh
## R CMD config is phase 7's item
if (!windows) {
    r <- run_to(file.path(R.home("bin"), "R"), c("CMD", "config", "CC")); cat(r$out, sep = "\n")
    stopifnot(r$status == 127L,
              any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")))
    cat("compilers: R CMD config names the build tools: OK\n")
}
