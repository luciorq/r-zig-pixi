## r-zig-slim + r-zig-build-tools (feat-standalone-toolchain B28, phase
## 4): rzig's check finds make (Windows: also sh), names
## r-zig-compilers for what is missing, and says when make is installed
## in this env but not on PATH (on Windows R CMD then finds them itself,
## PHASE7 F2 b); R CMD config reads Makeconf through make. On Windows the
## package's own files: pkgconf,
## built from source, as pkgconf and pkg-config, and PKG_CONFIG_PATH's
## default under R CMD (B43); and B39's tools from this env (B11).
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
## make and sh in <prefix>/Library/usr/bin
r <- run_to(cc, "--rzig-check=build-tools"); cat(r$out, sep = "\n")
ok <- r$out[1L]
field <- function(name) sub(paste0("^.*", name, " at ([^;]*).*$"), "\\1", ok)
make_dir <- shown(if (windows) file.path(env_bin, "..", "usr", "bin") else env_bin)
stopifnot(r$status == 0L, startsWith(ok, "zig-cc: build-tools ok: make at "),
          same_path(shown(dirname(field("make"))), make_dir))
if (windows)
    stopifnot(grepl("; sh at ", ok, fixed = TRUE), same_path(shown(dirname(field("sh"))), make_dir))
cat("build tools: the check finds this env's make", if (windows) "and sh", ": OK\n")

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
## Library/usr/bin), then the text (PHASE4 open point I a, Cg2). On
## Windows only outside R: under R CMD (Rcmd_environ) and in sessions
## (Rprofile.windows) R puts this env's Library/usr/bin on PATH itself,
## after the group's usr/bin, so the same PATH (with this env's
## Library/bin, for R's DLLs) finds m2's make and sh there (PHASE7 F2 b)
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
if (windows) {
    Sys.setenv(PATH = paste(c(empty, env_bin, file.path(Sys.getenv("SystemRoot"), "System32")), collapse = ";"))
    r <- run_to(file.path(R.home("bin"), "Rcmd.exe"), c(shortPathName(cc), "--rzig-check=build-tools"))
    cat(r$out, sep = "\n")
    narrow(usr_bin = TRUE)
    at <- function(name) shown(dirname(sub(paste0("^.*", name, " at ([^;]*).*$"), "\\1", r$out[1L])))
    stopifnot(r$status == 0L, startsWith(r$out[1L], "zig-cc: build-tools ok: make at "),
              same_path(at("make"), make_dir), same_path(at("sh"), make_dir))
    cat("build tools: with the same PATH, under R CMD the check finds this env's make and sh: OK\n")
}

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
    ## no binutils/ any more: the binutils are rzig's names, r-zig-slim's
    ## (feat-win-zig-binutils)
    stopifnot(!dir.exists(file.path(R.home(), "bin", "toolchain", "binutils")))

    ## Makeconf.win names a bare pkg-config (B43): the package's pkgconf,
    ## which the toolchain build compiles from source
    ## (zigbuild/toolchain/pkgconf.zig) into usr/bin as pkgconf.exe and
    ## pkg-config.exe; usr/SOURCES has its block, with each name's sha256,
    ## LICENSES/pkgconf/ its texts, and it runs with System32 alone
    ub <- file.path(R.home(), "bin", "toolchain", "usr")
    src <- readLines(file.path(ub, "SOURCES"))
    i <- match("package: pkgconf", src)
    stopifnot(!is.na(i), length(list.files(file.path(ub, "LICENSES", "pkgconf"))) >= 2L)
    blk <- src[i:length(src)]
    blk <- blk[cumsum(blk == "") == 0L]
    fl <- grep("^file: pkgconf[.]exe -> bin/", blk, value = TRUE)
    want <- sub("^.* ", "", fl)
    names(want) <- sub("^file: pkgconf[.]exe -> (bin/[^ ]+) .*$", "\\1", fl)
    stopifnot(any(grepl("^sha256: [0-9a-f]{64}$", blk)),
              setequal(names(want), c("bin/pkgconf.exe", "bin/pkg-config.exe")),
              unname(tools::sha256sum(file.path(ub, names(want)))) == unname(want))
    Sys.setenv(PATH = file.path(Sys.getenv("SystemRoot"), "System32"))
    for (n in c("pkgconf", "pkg-config")) {
        r <- run_to(file.path(ub, "bin", paste0(n, ".exe")), "--version")
        stopifnot(r$status == 0L, length(r$out) > 0L)
    }
    narrow(usr_bin = TRUE)
    cat("build tools: usr/bin's pkgconf", r$out[1L], "under both names, with its SOURCES and LICENSES: OK\n")

    ## under R CMD (Rcmd_environ): the group's pkg-config first on PATH,
    ## and PKG_CONFIG_PATH, unset, this env's Library/lib/pkgconfig and
    ## Library/share/pkgconfig, where pkg-config finds this env's .pc files
    ## (conda-forge's pkg-config, whose activation set it, is no longer a
    ## dependency)
    pcs <- sub("[.]pc$", "", list.files(file.path(env_bin, "..", "lib", "pkgconfig"), pattern = "[.]pc$"))
    pc <- if ("zlib" %in% pcs) "zlib" else pcs[1L]
    rs <- file.path(d, "pc.R")
    writeLines(c('rh <- Sys.getenv("R_HOME")',
                 'want <- paste0(rh, "/../../lib/pkgconfig;", rh, "/../../share/pkgconfig")',
                 'p <- Sys.getenv("PKG_CONFIG_PATH", NA)',
                 'if (is.na(p) || p != want) stop("PKG_CONFIG_PATH is \'", p, "\', not ", want)',
                 'cat("pkg-config:", Sys.which("pkg-config"), "\\n")',
                 'a <- commandArgs(TRUE)',
                 'if (length(a) && !is.na(a[1L])) quit(status = system2("pkg-config", c("--exists", "--print-errors", a[1L])))'), rs)
    old <- Sys.getenv("PKG_CONFIG_PATH", NA)
    Sys.unsetenv("PKG_CONFIG_PATH")
    r <- run_to(file.path(R.home("bin"), "Rcmd.exe"), c("Rscript.exe", "--vanilla", shQuote(rs), if (!is.na(pc)) pc))
    if (!is.na(old)) Sys.setenv(PKG_CONFIG_PATH = old)
    cat(r$out, sep = "\n")
    w <- sub("^pkg-config: ", "", grep("^pkg-config: ", r$out, value = TRUE))
    stopifnot(r$status == 0L, length(w) == 1L, same_path(shown(dirname(w)), shown(file.path(ub, "bin"))))
    cat("build tools: under R CMD, PKG_CONFIG_PATH is this env's .pc directories",
        if (is.na(pc)) "(this env has no .pc file to look up)" else paste0("and pkg-config finds ", pc),
        ": OK\n")

    ## B39's tools from this env (B11): m2's, in Library/usr/bin. R's
    ## Sys.which looks in System32 before PATH, so a name System32 has too
    ## (find, sort, ...: PHASE7 amendment Am6) is checked by its file, the
    ## rest through Sys.which, the paths compared normalised (8.3 names)
    usr_bin <- shown(file.path(env_bin, "..", "usr", "bin"))
    names <- c("sh", "bash", "make", "sed", "grep", "gawk", "awk", "which", "find", "xargs", "patch",
               "basename", "rm", "cp", "mv", "mkdir", "cat", "tr", "sort", "uname", "chmod", "ln",
               "ls", "expr", "touch", "head", "tail", "wc", "env", "printf", "mktemp", "test")
    shadow <- file.exists(file.path(Sys.getenv("SystemRoot"), "System32", paste0(names, ".exe")))
    for (n in names[shadow])
        if (!file.exists(file.path(usr_bin, paste0(n, ".exe")))) stop(n, ".exe is not in ", usr_bin)
    for (n in names[!shadow]) {
        w <- Sys.which(n)
        if (!nzchar(w) || !same_path(shown(dirname(w)), usr_bin)) stop("Sys.which(\"", n, "\") is '", w, "', not in ", usr_bin)
    }
    cat("build tools: B39's tools are this env's m2 tools (", sum(shadow), "by file, System32 has them:",
        paste(names[shadow], collapse = " "), "): OK\n")
}
