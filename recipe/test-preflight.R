## r-zig-slim alone (the r-zig wheel alone too, wheel-test.sh): rzig is
## in the base (feat-standalone-toolchain B19, phase 4), and nothing writes
## R_ZIG_TOOLCHAIN_HINT (B35). An R-only package installs; one with
## compiled code stops in the preflight (patch 0009) with rzig's text,
## which names r-zig-compilers, and installs nothing; R CMD SHLIB stops
## with that text too, and of a Makevars rule with both groups' texts
## (feat-shlib-rzig-build); one with a configure
## script gets both groups' texts in that stop; a user's own
## R_ZIG_TOOLCHAIN_HINT follows rzig's text; a zig that is not R's stops
## as a package that cannot be built, with no hint.
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
## the base's boundary, as test-compilers.R's: a run dependency that
## brought make would show here (Sys.which scans PATH in R, patch 0002).
## On Windows m2's make and sh install into Library\usr\bin, which
## narrow() leaves off PATH, so that directory is looked at itself
mk <- c(Sys.which("make"),
        if (windows) Filter(file.exists, file.path(env_bin, "..", "usr", "bin", c("make.exe", "sh.exe"))))
mk <- mk[nzchar(mk)]
if (length(mk)) stop("build tools in an env without r-zig-build-tools: ", paste(mk, collapse = ", "))
tc <- file.path(R.home(), "bin", "toolchain")
stopifnot(file.exists(file.path(tc, if (windows) c("gcc.exe", "rzig.exe") else c("zig-cc", "rzig"))),
          file.exists(file.path(R.home(), "share", "zig", "rpkg", "build_t2.zig")),
          !dir.exists(file.path(tc, "binutils")), !dir.exists(file.path(tc, "usr")))
## no writer of R_ZIG_TOOLCHAIN_HINT came back (B35) (PHASE4 Cc9)
for (f in file.path(R.home("etc"), c("Renviron", "Renviron.site")))
    if (file.exists(f)) stopifnot(!any(startsWith(readLines(f, warn = FALSE), "R_ZIG_TOOLCHAIN_HINT=")))
cat("base: rzig and rpkg, no group's directory, no R_ZIG_TOOLCHAIN_HINT written: OK\n")

lib <- file.path(d, "lib")
dir.create(lib)
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
cat("base: an R-only package installs: OK\n")

## R CMD INSTALL, its output kept (Rcmd.exe on Windows, as
## test-toolchain.R)
inst <- function(pkg) run_to(file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R"),
                             c(if (!windows) "CMD", "INSTALL", "-l", shQuote(lib), shQuote(pkg)))
r <- inst(mkpkg("rzigsrc", src = TRUE)); cat(r$out, sep = "\n")
pip <- if (windows) "  pip:         no wheels for Windows" else "  pip:         pip install r-zig-compilers (zig only: PyPI has no Fortran compiler); r-zig-toolchain installs every group"
stopifnot(r$status != 0L,
          ## no zig is reachable: ZIG_BIN unset, no TC/zig, none in the
          ## env's bin or on this PATH, no python3 with ziglang (PHASE4
          ## Cc8); rzig says `zig-cc:` on Windows too (main.zig: gcc is .cc)
          any(startsWith(r$out, "zig-cc: no zig (")),
          any(startsWith(r$out, "Compiling needs the r-zig compilers for R ")),
          any(startsWith(r$out, "  conda, pixi: pixi add r-zig-compilers (or conda install r-zig-compilers); r-zig-toolchain installs every group")),
          any(startsWith(r$out, pip)),
          any(grepl("which is incomplete (see above)", r$out, fixed = TRUE)),
          ## rzig is there: no hint after its text (PHASE4 Cc9)
          !any(startsWith(r$out, "hint:")),
          !dir.exists(file.path(lib, "rzigsrc")))
cat("base: a compiled package stops in the preflight, naming r-zig-compilers: OK\n")

## R CMD SHLIB (feat-shlib-rzig-build Cg5, Cg13): R asks rzig build first
## (patch 0013's one hook), which stops with the compilers' text, the
## text pkgbuild's check_build_tools(debug = TRUE) shows for its probe,
## and builds nothing; with a Makevars rule as well, both groups' texts,
## the compilers' first, then rzig's reason and the build tools'
ext <- .Platform$dynlib.ext
shlib <- function(dir, args) {
    owd <- setwd(dir); on.exit(setwd(owd))
    run_to(file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R"), c(if (!windows) "CMD", "SHLIB", args))
}
p <- file.path(d, "shlib-probe"); dir.create(p)
writeLines("void foo(int *bar) { *bar = 1; }", file.path(p, "foo.c"))
r <- shlib(p, "foo.c"); cat(r$out, sep = "\n")
stopifnot(r$status != 0L,
          any(startsWith(r$out, "rzig build: no zig (")),
          any(startsWith(r$out, "Compiling needs the r-zig compilers for R ")),
          any(startsWith(r$out, "  conda, pixi: pixi add r-zig-compilers (or conda install r-zig-compilers); r-zig-toolchain installs every group")),
          any(startsWith(r$out, pip)),
          !file.exists(file.path(p, c("foo.o", paste0("foo", ext)))))
cat("base: R CMD SHLIB foo.c stops with the compilers' text, nothing built: OK\n")
p <- file.path(d, "shlib-rule"); dir.create(p)
writeLines("void x(int *n) { *n = 1; }", file.path(p, "x.c"))
writeLines(c("all: $(SHLIB) extra", "extra:", "\t@echo extra"), file.path(p, "Makevars"))
r <- shlib(p, "x.c"); cat(r$out, sep = "\n")
comp <- which(startsWith(r$out, "Compiling needs the r-zig compilers for R "))
why <- which(grepl(paste0("x", ext, " needs make: Makevars has a rule or target line"), r$out, fixed = TRUE))
bt <- which(startsWith(r$out, "Building packages needs the r-zig build tools for R "))
stopifnot(r$status != 0L, length(comp) == 1L, length(why) == 1L, length(bt) == 1L, comp < why, why < bt,
          any(startsWith(r$out, "  conda, pixi: pixi add r-zig-build-tools (or conda install r-zig-build-tools); r-zig-toolchain installs every group")),
          !file.exists(file.path(p, c("x.o", paste0("x", ext)))))
cat("base: R CMD SHLIB of a Makevars rule stops with both groups' texts, the compilers' first: OK\n")

## a configure script R runs needs both groups: both texts in one stop,
## the compilers' first, and the script does not run (PHASE4 open point
## H a, Cg1). R-only; R runs configure.win on Windows
mkpkg_conf <- function(name) {
    p <- mkpkg(name)
    conf <- file.path(p, if (windows) "configure.win" else "configure")
    writeLines(c("#!/bin/sh", paste0("touch '", shown(file.path(d, paste0(name, "-ran"))), "'")), conf)
    Sys.chmod(conf, "755")
    p
}
r <- inst(mkpkg_conf("rzigconf")); cat(r$out, sep = "\n")
comp <- which(startsWith(r$out, "Compiling needs the r-zig compilers for R "))
bt <- which(startsWith(r$out, "Building packages needs the r-zig build tools for R "))
stopifnot(r$status != 0L, length(comp) == 1L, length(bt) == 1L, comp < bt,
          any(startsWith(r$out, "zig-cc: rzigconf needs make: a configure script R runs; ")),
          any(startsWith(r$out, "  conda, pixi: pixi add r-zig-build-tools (or conda install r-zig-build-tools); r-zig-toolchain installs every group")),
          any(grepl("which is incomplete (see above)", r$out, fixed = TRUE)),
          ## no make where r-zig-build-tools would put it (open point I a)
          !any(grepl("is installed in R's environment", r$out, fixed = TRUE)),
          !file.exists(file.path(d, "rzigconf-ran")),
          !dir.exists(file.path(lib, "rzigconf")))
cat("base: a configure script stops in the preflight with both groups' texts, and does not run: OK\n")

## Windows: R CMD config with no build tools in this env names them, as
## on unix (test-compilers.R), and exits with rzig's 127: rcmdfn.c runs
## rzig's check before config.sh's sh, so cmd.exe has no sh to miss
## (patch 0010; PHASE7 open point J a)
if (windows) {
    r <- run_to(file.path(R.home("bin"), "R"), c("CMD", "config", "CC")); cat(r$out, sep = "\n")
    stopifnot(r$status == 127L,
              any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")),
              !any(grepl("is not recognized", r$out, fixed = TRUE)))
    cat("base: R CMD config names the build tools, exit 127: OK\n")
}

## a user's own R_ZIG_TOOLCHAIN_HINT: shown after rzig's text on a 127
## (PHASE3 C8; PHASE4 open point B b, Cg4)
Sys.setenv(R_ZIG_TOOLCHAIN_HINT = "r-zig-test-hint")
r <- inst(file.path(d, "rzigsrc")); cat(r$out, sep = "\n")
Sys.unsetenv("R_ZIG_TOOLCHAIN_HINT")
hint <- which(r$out == "hint: r-zig-test-hint")
stopifnot(r$status != 0L, length(hint) == 1L,
          hint > which(startsWith(r$out, "Compiling needs the r-zig compilers for R "))[1L],
          hint < which(grepl("which is incomplete (see above)", r$out, fixed = TRUE))[1L],
          !dir.exists(file.path(lib, "rzigsrc")))
cat("base: a user's R_ZIG_TOOLCHAIN_HINT follows rzig's text: OK\n")

## a zig that is not R's (a user's zig 0.17 in ZIG_BIN or on PATH): rzig's
## check exits 1, not 127, so 0009 says the package cannot be built, not
## that the toolchain is incomplete, and shows no hint, which is for a 127
## only (PHASE4 open points J a and B b). Unix: the stand-in zig is a
## shell script
if (!windows) {
    fz <- file.path(d, "fakezig", "zig")
    dir.create(dirname(fz))
    writeLines(c("#!/bin/sh", "echo 0.99.0"), fz)
    Sys.chmod(fz, "755")
    Sys.setenv(ZIG_BIN = fz, R_ZIG_TOOLCHAIN_HINT = "r-zig-test-hint")
    r <- inst(file.path(d, "rzigsrc")); cat(r$out, sep = "\n")
    Sys.unsetenv(c("ZIG_BIN", "R_ZIG_TOOLCHAIN_HINT"))
    stopifnot(r$status != 0L,
              any(startsWith(r$out, "zig-cc: ") & grepl("is zig 0.99.0, not R's zig", r$out, fixed = TRUE)),
              any(grepl("this package cannot be built (see above)", r$out, fixed = TRUE)),
              !any(grepl("which is incomplete (see above)", r$out, fixed = TRUE)),
              !any(startsWith(r$out, "hint:")),
              !dir.exists(file.path(lib, "rzigsrc")))
    cat("base: a zig that is not R's stops as a package that cannot be built, with no hint: OK\n")
}
