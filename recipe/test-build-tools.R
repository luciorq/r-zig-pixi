## r-zig-slim + r-zig-build-tools (feat-standalone-toolchain B28, phase
## 4): rzig's check finds make (Windows: also sh and the binutils), names
## r-zig-compilers for what is missing, and says when make is installed
## in this env but not on PATH; R CMD config reads Makeconf through make.
## On Windows the package's own files: the MinGW binutils, with the
## records of where they come from (B24, B41), which load the env's
## zstd.dll (E2).
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

narrow(usr_bin = TRUE)
cc <- file.path(R.home(), "bin", "toolchain", if (windows) "gcc.exe" else "zig-cc")
tc <- shown(file.path(R.home(), "bin", "toolchain"))
## the build tools, from this env: unix make in <prefix>/bin; Windows m2's
## make and sh in <prefix>/Library/usr/bin, and the binutils beside rzig
r <- run_to(cc, "--rzig-check=build-tools"); cat(r$out, sep = "\n")
ok <- r$out[1L]
field <- function(name) sub(paste0("^.*", name, " at ([^;]*).*$"), "\\1", ok)
make_dir <- shown(if (windows) file.path(env_bin, "..", "usr", "bin") else env_bin)
stopifnot(r$status == 0L, startsWith(ok, "zig-cc: build-tools ok: make at "),
          same_path(shown(dirname(field("make"))), make_dir))
if (windows)
    stopifnot(grepl("; sh at ", ok, fixed = TRUE), same_path(shown(dirname(field("sh"))), make_dir),
              same_path(field("binutils"), paste0(tc, "/binutils")))
cat("build tools: the check finds this env's make", if (windows) "and sh, and the binutils", ": OK\n")

## no compilers: the check names r-zig-compilers (127, through a file),
## with this env's programs alone, so no host zig is reached
narrow()
r <- run_to(cc, "--rzig-check"); cat(r$out, sep = "\n")
narrow(usr_bin = TRUE)
stopifnot(r$status == 127L, any(grepl("pixi add r-zig-compilers", r$out, fixed = TRUE)))
cat("build tools: no zig, the check names r-zig-compilers: OK\n")

## installed in this env but not on PATH (an env used without activation:
## an IDE pointed at its R; win-64's R.bat adds nothing to PATH): the
## check says so, naming this env's make (Windows: m2's, in
## Library/usr/bin), then the text (PHASE4 open point I a, Cg2)
empty <- file.path(d, "empty"); dir.create(empty)
Sys.setenv(PATH = paste(c(empty, if (windows) file.path(Sys.getenv("SystemRoot"), "System32")), collapse = .Platform$path.sep))
r <- run_to(cc, "--rzig-check=build-tools"); cat(r$out, sep = "\n")
narrow(usr_bin = TRUE)
not_on_path <- " is installed in R's environment, which is not on PATH: activate it (pixi shell, conda activate) or start R with pixi run"
line <- r$out[startsWith(r$out, "zig-cc: no make on PATH")]
stopifnot(r$status == 127L, length(line) == 1L, endsWith(line, not_on_path),
          same_path(sub("^.*; ", "", substr(line, 1L, nchar(line) - nchar(not_on_path))),
                    paste0(make_dir, if (windows) "/make.exe" else "/make")),
          any(startsWith(r$out, "Building packages needs the r-zig build tools for R ")))
cat("build tools: make off PATH is named as installed in this env: OK\n")

## R CMD config passes patch 0010's check, and make reads Makeconf: CC is
## rzig's name, with -std=gnu23 after it on unix and $(M_ARCH) on Windows
## (PHASE4 Cc1)
r <- run_to(file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R"), c(if (!windows) "CMD", "config", "CC"))
cat(r$out, sep = "\n")
cfg_cc <- strsplit(trimws(paste(r$out, collapse = " ")), " +")[[1]][1]
stopifnot(r$status == 0L, basename(dirname(cfg_cc)) == "toolchain",
          basename(cfg_cc) == if (windows) "gcc.exe" else "zig-cc")
cat("build tools: R CMD config CC is", cfg_cc, ": OK\n")

if (windows) {
    ## SOURCES names the binutils' package and its sha256; LICENSES/ holds
    ## its licences (B24, B41). The six tools' files are package_contents'
    bu <- file.path(R.home(), "bin", "toolchain", "binutils")
    src <- readLines(file.path(bu, "SOURCES"))
    i <- match("package: binutils_impl_win-64", src)
    stopifnot(!is.na(i))
    blk <- src[i:length(src)]
    blk <- blk[cumsum(blk == "") == 0L]
    stopifnot(any(grepl("^sha256: [0-9a-f]{64}$", blk)),
              length(list.files(file.path(bu, "LICENSES", "binutils_impl_win-64"), recursive = TRUE)) > 0L)
    ## nm runs with this env's Library/bin and System32 alone: zstd.dll,
    ## which the binutils import, comes from this env (E2)
    Sys.setenv(PATH = paste(env_bin, file.path(Sys.getenv("SystemRoot"), "System32"), sep = ";"))
    r <- run_to(file.path(bu, "nm.exe"), "--version")
    narrow(usr_bin = TRUE)
    stopifnot(r$status == 0L, grepl("GNU nm", r$out[1L], fixed = TRUE))
    ## Makeconf.win names a bare pkg-config (B43)
    r <- run_to("pkg-config", "--version")
    stopifnot(r$status == 0L, length(r$out) > 0L)
    cat("build tools: binutils/ has its SOURCES and LICENSES, nm runs with this env's zstd.dll, pkg-config", r$out[1L], ": OK\n")
}
