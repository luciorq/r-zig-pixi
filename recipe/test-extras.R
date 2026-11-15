## r-zig-slim + r-zig-extras (feat-extras-group): conda-forge's cmake, the
## extras group on this channel, runs from this env as a package's
## configure script or makefile runs it (plain `cmake`, PATH), and rzig's
## check finds it there (--rzig-check=extras); off PATH, the check says it
## is installed in this env, then the group's text.
windows <- .Platform$OS.type == "windows"
d <- tempfile("rzig-"); dir.create(d)
Sys.unsetenv(c("R_ZIG_EXTRA_ENV", "ZIG_BIN", "R_ZIG_TOOLCHAIN_HINT", "R_ZIG_NO_PREFLIGHT"))
## only this env's programs; env_bin is <prefix>/bin, on Windows
## <prefix>/Library/bin, where conda-forge's cmake.exe is
env_bin <- normalizePath(file.path(R.home(), "..", "..", "bin"))
narrow <- function()
    Sys.setenv(PATH = paste(c(env_bin, if (windows) c(R.home("bin"), file.path(Sys.getenv("SystemRoot"), "System32"))),
                            collapse = .Platform$path.sep))
## how rzig shows a path (check.zig's display(): `/` only on Windows)
shown <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
same_path <- function(a, b) if (windows) tolower(a) == tolower(b) else a == b
## a command's status and output through a file (a 127 through
## system2(stdout = TRUE) is R's own error)
run_to <- function(cmd, args) {
    f <- tempfile(tmpdir = d); st <- suppressWarnings(system2(cmd, args, stdout = f, stderr = f))
    list(status = st, out = readLines(f, warn = FALSE))
}
cc <- file.path(R.home(), "bin", "toolchain", if (windows) "gcc.exe" else "zig-cc")

narrow()
## cmake, as a configure script finds it: on PATH, this env's
w <- Sys.which("cmake")
stopifnot(nzchar(w), same_path(shown(dirname(w)), shown(env_bin)))
r <- run_to("cmake", "--version"); cat(r$out, sep = "\n")
stopifnot(r$status == 0L, startsWith(r$out[1L], "cmake version "))
cat("extras:", r$out[1L], "at", w, ": OK\n")

## rzig's check finds the same cmake
r <- run_to(cc, "--rzig-check=extras"); cat(r$out, sep = "\n")
stopifnot(r$status == 0L, startsWith(r$out[1L], "zig-cc: extras ok: cmake at "),
          same_path(shown(dirname(sub("^.*cmake at ", "", r$out[1L]))), shown(env_bin)))
cat("extras: the check finds this env's cmake: OK\n")

## off PATH: installed in this env, named as such, then the group's text
empty <- file.path(d, "empty"); dir.create(empty)
Sys.setenv(PATH = paste(c(empty, if (windows) file.path(Sys.getenv("SystemRoot"), "System32")), collapse = .Platform$path.sep))
r <- run_to(cc, "--rzig-check=extras"); cat(r$out, sep = "\n")
narrow()
not_on_path <- " is installed in R's environment, which is not on PATH: activate it (pixi shell, conda activate) or start R with pixi run"
line <- grep("no cmake on PATH", r$out, value = TRUE, fixed = TRUE)
stopifnot(r$status == 127L, length(line) == 1L, endsWith(line, not_on_path),
          any(grepl("pixi add r-zig-extras", r$out, fixed = TRUE)))
cat("extras: cmake off PATH is named as installed in this env: OK\n")
