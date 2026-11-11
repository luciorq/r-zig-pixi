## r-zig-slim + r-zig-compilers (verify-bundle's scenario 2 on conda;
## feat-standalone-toolchain B28, phase 4): no make, and none needed for a
## package that has no configure script and no make rules, which rzig
## build compiles with zig and flang alone (feat-zig-pkg-build, patch
## 0013). One that needs make stops in the preflight (patch 0009), naming
## r-zig-build-tools. R CMD SHLIB of such code needs no make either
## (feat-shlib-rzig-build: patch 0013's one hook, rzig build --shlib):
## pkgbuild's probe, Rcpp's sourceCpp, inline's Fortran and cpp11's
## cpp_source shapes build and load; one with a Makevars rule stops,
## naming r-zig-build-tools.
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
zg <- sub("^.*: zig [^ ]+ at (.*); flang at .*$", "\\1", r$out[1L])
stopifnot(r$status == 0L, startsWith(r$out[1L], "zig-cc: compilers ok: zig 0.17."),
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
## (PHASE4 Cc10 b; no libc++ on any OS since feat-standalone-toolchain
## phase 6, open point K)
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

## R CMD SHLIB, the run-time compiles (feat-shlib-rzig-build): each in a
## fresh directory, through R CMD SHLIB (Rcmd.exe on Windows), with no
## make on PATH, so rzig build builds it; then the library loads.
## shlib(<dir>, <arguments>) runs it there
ext <- .Platform$dynlib.ext
shlib <- function(dir, args) {
    owd <- setwd(dir); on.exit(setwd(owd))
    run_to(file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R"), c(if (!windows) "CMD", "SHLIB", args))
}
shlib_ok <- function(r, what) if (r$status != 0L) { cat(r$out, sep = "\n"); stop(what, ": R CMD SHLIB failed") }
fresh <- function(name) { p <- file.path(d, name); dir.create(p); normalizePath(p, "/") }
## pkgbuild's has_compiler(): foo.c beside a source that does not compile
p <- fresh("shlib-probe")
writeLines("void foo(int *bar) { *bar = 1; }", file.path(p, "foo.c"))
writeLines("this is not C (", file.path(p, "junk.c"))
shlib_ok(shlib(p, "foo.c"), "the probe")
dyn.load(file.path(p, paste0("foo", ext)))
stopifnot(.C("foo", 0L)[[1]] == 1L, !file.exists(file.path(p, "foo.o")))
cat("compilers: R CMD SHLIB foo.c (pkgbuild's probe), no make: OK\n")
## Rcpp's sourceCpp: -o, a header through CLINK_CPPFLAGS
p <- fresh("shlib-cxx"); dir.create(file.path(p, "inc"))
writeLines("#define RZIG_SC 6", file.path(p, "inc", "rzigsc.h"))
writeLines(c("#include <vector>", "#include <R.h>", "#include <Rinternals.h>", "#include <rzigsc.h>",
             'extern "C" SEXP sc(void) { std::vector<int> v(RZIG_SC, 1); int n = 0; for (int x : v) n += x; return ScalarInteger(n); }'),
           file.path(p, "file1.cpp"))
Sys.setenv(CLINK_CPPFLAGS = paste0('-I"', file.path(p, "inc"), '"'))
r <- shlib(p, c("-o", paste0("sourceCpp_1", ext), "file1.cpp"))
Sys.unsetenv("CLINK_CPPFLAGS")
shlib_ok(r, "sourceCpp's shape")
dyn.load(file.path(p, paste0("sourceCpp_1", ext)))
stopifnot(.Call("sc") == 6L)
cat("compilers: R CMD SHLIB -o sourceCpp_1", ext, " (Rcpp's sourceCpp, C++), no make: OK\n", sep = "")
## inline's and knitr's Fortran, with the env's flang
p <- fresh("shlib-fortran")
writeLines(c("      subroutine fw(n, r)", "      integer n, r", "      character(len=12) buf",
             "      write(buf,'(i0)') n", "      read(buf,'(i12)') r", "      end"), file.path(p, "fs.f"))
shlib_ok(shlib(p, c("-o", paste0("fs", ext), "fs.f")), "the Fortran shape")
dyn.load(file.path(p, paste0("fs", ext)))
stopifnot(.Fortran("fw", 42L, r = 0L)$r == 42L)
cat("compilers: R CMD SHLIB of a Fortran file, no make: OK\n")
## a configure script's $FC probe (feat-standalone-toolchain phase 6, open
## point P), with the env's flang and its flang.cfg: Makeconf's FC is
## zig-fc (R CMD config needs make, which this env has not), and zig-fc
## compiles each Fortran source with flang, the intrinsic modules' path
## added, then links through zig (decisions D, E). A fixed-form conftest
## and a program using a derived-type module are each linked and run, in
## a fresh TMPDIR (Windows: TEMP and TMP), which the split's temporary
## directory must leave empty
## (Makeconf.win's line is indented, in USE_LLVM's else branch)
mkconf <- if (windows) file.path(R.home("etc"), "x64", "Makeconf") else file.path(R.home("etc"), "Makeconf")
stopifnot(any(trimws(readLines(mkconf)) == "FC = $(R_HOME)/bin/toolchain/zig-fc"))
fc <- file.path(R.home(), "bin", "toolchain", if (windows) "zig-fc.exe" else "zig-fc")
p <- fresh("fc-probe"); tmp <- fresh("fc-tmp")
writeLines(c("      program conftest", "      print '(a)', 'ok'", "      end"), file.path(p, "conftest.f"))
writeLines(c("module shapes", "  type :: sq", "    integer :: n", "  end type",
             "contains", "  integer function area(s)", "    type(sq), intent(in) :: s",
             "    area = s%n * s%n", "  end function", "end module"), file.path(p, "m.f90"))
writeLines(c("program p", "  use shapes", "  type(sq) :: s", "  s%n = 3",
             "  if (area(s) == 9) print '(a)', 'ok'", "end program"), file.path(p, "u.f90"))
old_tmp <- Sys.getenv(c("TMPDIR", "TEMP", "TMP"), unset = NA)
Sys.setenv(TMPDIR = tmp, TEMP = tmp, TMP = tmp)
owd <- setwd(p)
## the dry run: flang for each source (the env's, with the modules'
## path), then the link through the zig the check found, which on win-64
## is conda-forge's x86_64-w64-mingw32-zig.exe (its zig is a .bat;
## find_zig.zig)
Sys.setenv(RZIG_PRINT_ARGV = "1")
r <- run_to(fc, c("-o", "p", "m.f90", "u.f90"))
Sys.unsetenv("RZIG_PRINT_ARGV")
argv <- r$out[!startsWith(r$out, "ZIG_LIB_DIR=")]
blocks <- split(argv[argv != "&&"], cumsum(argv == "&&")[argv != "&&"])
firsts <- vapply(blocks, `[`, "", 1L)
if (r$status != 0L || length(blocks) != 3L) { cat(r$out, sep = "\n"); stop("zig-fc -o p m.f90 u.f90: not two compiles and a link") }
stopifnot(same_path(shown(dirname(firsts[1:2])), shown(env_bin)),
          vapply(blocks[1:2], function(b) "-fintrinsic-modules-path" %in% b, NA),
          same_path(shown(firsts[3L]), shown(zg)))
## each program named with .exe on Windows, as a configure script does
exe <- if (windows) ".exe" else ""
for (args in list(c("-o", paste0("conftest", exe), "conftest.f"), c("-o", paste0("p", exe), "m.f90", "u.f90"))) {
    r <- run_to(fc, args)
    if (r$status != 0L) { cat(r$out, sep = "\n"); stop("zig-fc ", paste(args, collapse = " "), " failed") }
    prog <- file.path(p, args[2L])
    r <- run_to(prog, character())
    if (r$status != 0L || !identical(r$out, "ok")) { cat(r$out, sep = "\n"); stop(args[2L], " did not print ok") }
}
setwd(owd)
for (v in names(old_tmp)) if (is.na(old_tmp[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old_tmp[v]))
left <- list.files(tmp, pattern = "^rzig-fc-")
if (length(left)) stop("zig-fc left ", paste(left, collapse = ", "), " in TMPDIR")
cat("compilers: a configure-style $FC probe (conftest.f, a derived-type module) through zig-fc, with the env's flang: OK\n")
## cpp11's cpp_source: a Makevars in the working directory, absolute
## sources, --output=
p <- fresh("shlib-cpp11"); dir.create(file.path(p, "inc")); dir.create(file.path(p, "src"))
writeLines("inline int c11v() { return 11; }", file.path(p, "inc", "rzigc11.h"))
writeLines(c("CXX_STD = CXX11", paste0("PKG_CPPFLAGS = -I'", file.path(p, "inc"), "'")), file.path(p, "src", "Makevars"))
writeLines(c("#include <rzigc11.h>", "int c11a() { return c11v(); }"), file.path(p, "src", "a.cpp"))
writeLines(c("#include <R.h>", "#include <Rinternals.h>", "int c11a();",
             'extern "C" SEXP c11(void) { return ScalarInteger(c11a() + 1); }'), file.path(p, "src", "cpp11.cpp"))
shlib_ok(shlib(file.path(p, "src"), c(file.path(p, "src", c("a.cpp", "cpp11.cpp")), paste0("--output=pkg", ext))),
         "cpp11's shape")
dyn.load(file.path(p, "src", paste0("pkg", ext)))
stopifnot(.Call("c11") == 12L)
cat("compilers: R CMD SHLIB of cpp11's shape (absolute sources, --output=, a Makevars), no make: OK\n")
## a Makevars rule needs make: rzig's reason and the build tools' text,
## naming r-zig-build-tools, and nothing built
p <- fresh("shlib-rule")
writeLines("void x(int *n) { *n = 1; }", file.path(p, "x.c"))
writeLines(c("all: $(SHLIB) extra", "extra:", "\t@echo extra"), file.path(p, "Makevars"))
r <- shlib(p, "x.c"); cat(r$out, sep = "\n")
stopifnot(r$status != 0L,
          any(grepl(paste0("x", ext, " needs make: Makevars has a rule or target line"), r$out, fixed = TRUE)),
          any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")),
          any(grepl("pixi add r-zig-build-tools (or conda install r-zig-build-tools)", r$out, fixed = TRUE)),
          ## no make where r-zig-build-tools would put it (open point I a)
          !any(grepl("is installed in R's environment", r$out, fixed = TRUE)),
          !file.exists(file.path(p, c("x.o", paste0("x", ext)))))
cat("compilers: R CMD SHLIB of a Makevars rule stops, naming r-zig-build-tools: OK\n")

## R CMD config evaluates Makeconf through make: patch 0010 stops first
## with rzig's text (Windows: rcmdfn.c runs the check before config.sh's
## sh, PHASE7 open point J a)
r <- run_to(file.path(R.home("bin"), "R"), c("CMD", "config", "CC")); cat(r$out, sep = "\n")
stopifnot(r$status == 127L,
          any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")),
          !any(grepl("is not recognized", r$out, fixed = TRUE)))
cat("compilers: R CMD config names the build tools: OK\n")
