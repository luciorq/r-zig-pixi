# r-zig stress suite (stress/README.md). Installs hard-to-build CRAN and
# Bioconductor packages from source with the R that runs this script, one
# at a time, each with a timeout and a log. Then it loads each target, runs
# one smoke call, and writes report.json and report.md (and the job summary
# in CI). A diagnostic, never a gate: package failures do not change the
# exit status (0), unless --strict. A broken harness exits 2.
#
# Base R only. It needs an R with r-zig's toolchain plus an environment of
# system libraries:
#   tree   the dev tree, with the libraries env that R_ZIG_EXTRA_ENV names
#          (pixi run -e stress stress [args]).
#   conda  R installed in the env that also holds the libraries. --conda
#          makes that env with pixi (r-zig-slim, r-zig-toolchain and the
#          selected rows' sysdeps) in the run directory, then runs this
#          script again with that env's R.
#
# Usage: stress.R [options] [target ...]
#   target        a row of packages.tsv (package or package:variant), a group
#                 (g1 to g4), a tag (heavy), or all. Default: all of this OS's rows.
#   --skip=X,Y    leave out these rows, groups or tags (--skip=heavy)
#   --tree        test the R that runs this script (the default)
#   --conda[=CH]  test r-zig-slim + r-zig-toolchain from channel CH: local
#                 (the default: this checkout's dist/conda, made by
#                 `pixi run -e pkg conda-package`), universe (prefix.dev),
#                 or another channel path or URL
#   --out=DIR     run directory (default build/stress/<os>-<arch>-<dist>-<time>)
#   --jobs=N      make -jN and cmake's parallel level (default: cores, max 8)
#   --resume      reuse --out's library: skip what is already installed
#   --keep-path   keep the caller's PATH (default: only the libraries env's
#                 programs and the OS's base directories)
#   --trace       RZIG_TRACE=1: rzig prints its commands into the logs
#   --list        print the install plan and stop
#   --sysdeps     print the selected rows' sysdeps for this OS and stop
#   --strict      exit 1 when a target's result differs from its expect
#   --help        print this
# Environment: STRESS_JOBS (as --jobs), STRESS_TSV (another data file).

argv <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "(=|$)"), argv, value = TRUE)
  if (!length(hit)) return(default)
  v <- sub(paste0("^--", name, "=?"), "", hit[[length(hit)]])
  if (nzchar(v)) v else TRUE
}
flag <- function(name) isTRUE(opt(name))
known <- c("skip", "tree", "conda", "out", "jobs", "resume", "keep-path", "trace", "list", "sysdeps", "strict", "help")
bad <- setdiff(sub("=.*", "", sub("^--", "", grep("^--", argv, value = TRUE))), known)
if (length(bad)) stop("unknown option: --", paste(bad, collapse = " --"), " (see --help)", call. = FALSE)
ca <- commandArgs()                                             # Rscript passes -f FILE (R 4.6) or --file=FILE
script <- c(sub("^--file=", "", grep("^--file=", ca, value = TRUE)), ca[match("-f", ca) + 1])
script <- normalizePath(script[!is.na(script)][1], winslash = "/")
repo <- dirname(dirname(script))
if (flag("help")) {
  x <- readLines(script)
  i <- grep("^# Usage:", x)
  j <- which(!startsWith(x, "#"))
  writeLines(sub("^# ?", "", x[i:(j[j > i][1] - 1)]))
  quit(status = 0)
}
t_start <- Sys.time()
words <- function(x) { x <- unlist(strsplit(x, "[[:space:],]+")); x[nzchar(x) & x != "-"] }
# JSON and Markdown table cells, for the reports
js <- function(x) {
  if (is.data.frame(x)) return(paste0("[", paste(vapply(seq_len(nrow(x)), function(i) js(as.list(x[i, ])), ""), collapse = ",\n"), "]"))
  if (is.list(x)) return(paste0("{", paste(sprintf("\"%s\":%s", names(x), vapply(x, js, "")), collapse = ","), "}"))
  if (length(x) != 1 || is.na(x)) return("null")
  if (is.logical(x)) return(tolower(x))
  if (is.numeric(x)) return(format(x))
  paste0("\"", gsub("[\001-\037]", " ", gsub("\"", "\\\\\"", gsub("\\\\", "\\\\\\\\", x))), "\"")
}
cell <- function(x) gsub("|", "\\|", x, fixed = TRUE)

# --- where we are ----------------------------------------------------------
os <- switch(Sys.info()[["sysname"]], Linux = "linux", Darwin = "macos", Windows = "windows", "other")
win <- os == "windows"
arch <- R.version$arch
rhome <- normalizePath(R.home(), winslash = "/")
root <- sub("/(Library/)?lib/R$", "", rhome)                 # R's own environment root
dist <- if (dir.exists(file.path(root, "conda-meta"))) "conda" else "tree"
conda <- opt("conda")
if (flag("tree") && !is.null(conda)) stop("--tree and --conda: choose one", call. = FALSE)

# --- the data file and the selection ----------------------------------------
tsv <- normalizePath(Sys.getenv("STRESS_TSV", file.path(dirname(script), "packages.tsv")), winslash = "/")
tab <- read.delim(text = grep("^#", readLines(tsv, warn = FALSE), value = TRUE, invert = TRUE),
                  quote = "", comment.char = "", colClasses = "character", na.strings = character())
tab$name <- sub(":.*", "", tab$package)
tab$variant <- ifelse(grepl(":", tab$package), sub(".*:", "", tab$package), "")
labels <- function(t) lapply(seq_len(nrow(t)), function(i) c(t$package[i], t$group[i], words(t$tags[i])))
named <- function(t, sel) vapply(labels(t), function(l) any(l %in% sel), NA)
targets_arg <- argv[!startsWith(argv, "--")]
skip <- if (is.null(opt("skip"))) character() else words(opt("skip"))
unknown <- setdiff(c(targets_arg, skip), c(unlist(labels(tab)), "all"))
if (length(unknown)) stop("not in ", tsv, ": ", paste(unknown, collapse = " "), call. = FALSE)
rows <- tab[vapply(tab$oses, function(x) any(words(x) %in% c("all", os)), NA), ]
if (length(targets_arg) && !"all" %in% targets_arg) rows <- rows[named(rows, targets_arg), ]
rows <- rows[!named(rows, skip), ]
if (!nrow(rows)) stop("no rows of ", tsv, " left for ", os, ": ", paste(argv, collapse = " "), call. = FALSE)
sysdeps_of <- function(x) { d <- words(x); sub("@.*", "", d[!grepl("@", d) | sub(".*@", "", d) == os]) }
needed <- sort(unique(unlist(lapply(rows$sysdeps, sysdeps_of))))
if (flag("sysdeps")) { writeLines(needed); quit(status = 0) }

# --- what to install, in order ------------------------------------------------
retry <- function(f, tries = 3, wait = c(5, 30)) {
  for (i in seq_len(tries)) {
    r <- tryCatch(f(), error = function(e) e)
    if (!inherits(r, "error")) return(r)
    if (i < tries) Sys.sleep(wait[min(i, length(wait))])
  }
  r
}
options(repos = c(CRAN = "https://cloud.r-project.org"), timeout = 900)
setRepositories(ind = 1:2)                                     # CRAN + BioCsoft for this R (3.23 for R 4.6)
db <- retry(function() suppressWarnings(available.packages()))
base <- rownames(installed.packages(lib.loc = .Library, priority = "base"))
hard <- c("Depends", "Imports", "LinkingTo")
plan <- character()
if (!inherits(db, "error")) {
  have_db <- intersect(unique(rows$name), rownames(db))
  closure <- unique(c(rows$name, unlist(tools::package_dependencies(have_db, db = db, which = hard, recursive = TRUE))))
  direct <- tools::package_dependencies(intersect(closure, rownames(db)), db = db, which = hard)
  seen <- character()
  visit <- function(p) {                                       # dependencies first
    if (p %in% seen || p %in% base) return(invisible())
    seen <<- c(seen, p)
    for (d in direct[[p]]) visit(d)
    plan <<- c(plan, p)
  }
  for (i in seq_len(nrow(rows))) {
    if (nzchar(rows$variant[i])) for (d in direct[[rows$name[i]]]) visit(d) else visit(rows$name[i])
  }
}
items <- rbind(data.frame(package = plan, name = plan, variant = rep("", length(plan)), stringsAsFactors = FALSE),
               rows[nzchar(rows$variant), c("package", "name", "variant")])   # variants last
items$target <- items$package %in% rows$package
if (flag("list")) {
  if (inherits(db, "error")) stop("cannot read the repositories: ", conditionMessage(db), call. = FALSE)
  items$group <- rows$group[match(items$package, rows$package)]
  items$group[is.na(items$group)] <- "(dependency)"
  print(items[, c("package", "group", "variant")], row.names = FALSE)
  quit(status = 0)
}

# --- the run directory ----------------------------------------------------------
stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
out <- opt("out", file.path("build", "stress", paste(os, arch, if (is.null(conda)) dist else "conda", stamp, sep = "-")))
if (isTRUE(out)) stop("--out needs a directory", call. = FALSE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, winslash = "/")
lib <- file.path(out, "lib")
if (!flag("resume") && length(list.files(lib))) stop(lib, " is not empty: use --resume or another --out", call. = FALSE)

# --- --conda: make the env, then run this script again with its R ---------------
ws <- file.path(out, "conda")
ws_env <- file.path(ws, ".pixi", "envs", "default")
in_ws <- dist == "conda" && dir.exists(ws_env) && tolower(normalizePath(ws_env, winslash = "/")) == tolower(root)
if (!is.null(conda) && !in_ws) {
  channel <- if (isTRUE(conda) || identical(conda, "local")) file.path(repo, "dist", "conda") else
    if (identical(conda, "universe")) "https://prefix.dev/universe" else conda
  if (!grepl("^[a-z]+://", channel)) {
    if (!dir.exists(channel)) stop("no conda channel at ", channel, ": run `pixi run -e pkg conda-package`, or use --conda=universe", call. = FALSE)
    channel <- normalizePath(channel, winslash = "/")
  }
  # conda-forge before universe, as pixi.toml: universe mirrors some
  # conda-forge packages (libdeflate), and pixi's channel priority is strict
  channels <- unique(c(if (channel != "https://prefix.dev/universe") channel, "conda-forge", "https://prefix.dev/universe"))
  subdir <- switch(paste(os, arch), "linux x86_64" = "linux-64", "linux aarch64" = "linux-aarch64",
                   "macos x86_64" = "osx-64", "macos aarch64" = "osx-arm64", "windows x86_64" = "win-64",
                   stop("no conda subdir for ", os, " ", arch, call. = FALSE))
  # the selected rows' sysdeps only, as a user installs what they need: a
  # conflict in one row's libraries then does not block the other rows
  deps <- unique(c("r-zig-slim", "r-zig-toolchain", "pkg-config", needed))
  q <- function(x) paste0("\"", x, "\"", collapse = ", ")
  for (d in c(ws, file.path(out, "logs"))) dir.create(d, showWarnings = FALSE)
  writeLines(c("# written by stress/stress.R --conda", "[workspace]", "name = \"stress-conda\"",
               sprintf("channels = [%s]", q(channels)), sprintf("platforms = [%s]", q(subdir)), "",
               "[dependencies]", sprintf("%s = \"*\"", deps)), file.path(ws, "pixi.toml"))
  pixi <- Sys.getenv("PIXI_EXE", Sys.which("pixi"))
  if (!nzchar(pixi)) stop("--conda needs pixi on PATH", call. = FALSE)
  # the caller's own pixi workspace (pixi run -e stress) must not leak in
  Sys.unsetenv(c("PIXI_PROJECT_MANIFEST", "PIXI_PROJECT_ROOT", "PIXI_PROJECT_NAME", "PIXI_PROJECT_VERSION",
                 "PIXI_ENVIRONMENT_NAME", "PIXI_ENVIRONMENT_PLATFORMS", "PIXI_IN_SHELL", "PIXI_PROMPT", "R_ZIG_EXTRA_ENV"))
  Sys.setenv(STRESS_CHANNEL = channel)
  mf <- shQuote(file.path(ws, "pixi.toml"))
  elog <- file.path(out, "logs", "conda-env.log")
  message("stress: making the conda env in ", ws, " (", paste(channels, collapse = ", "), ")")
  st <- system2(pixi, c("install", "--manifest-path", mf), stdout = elog, stderr = elog)
  if (st != 0) {
    # a result too (the realistic target cannot be installed): report it
    why <- grep("[[:alnum:]]", readLines(elog, warn = FALSE), value = TRUE)
    msg <- sprintf("pixi install failed (%s) for r-zig-slim + r-zig-toolchain + %s from %s",
                   st, paste(needed, collapse = " "), paste(channels, collapse = ", "))
    md <- c(sprintf("## r-zig stress: %s %s, conda", os, arch), "", sprintf("**The conda env could not be made**: %s.", msg),
            "", "Its log (`logs/conda-env.log`) ends:", "", "```", tail(why, 40), "```")
    writeLines(md, file.path(out, "report.md"))
    writeLines(js(list(info = list(os = os, arch = arch, dist = "conda", channel = channel, out = out,
                                   args = paste(argv, collapse = " "), finished = TRUE, error = msg),
                       results = data.frame())), file.path(out, "report.json"))
    if (nzchar(Sys.getenv("GITHUB_STEP_SUMMARY"))) cat(md, file = Sys.getenv("GITHUB_STEP_SUMMARY"), sep = "\n", append = TRUE)
    writeLines(md)
    quit(status = 2)
  }
  rscript <- file.path(ws_env, if (win) "Library/lib/R/bin/x64/Rscript.exe" else "bin/Rscript")
  args <- c(grep("^--out(=|$)", argv, value = TRUE, invert = TRUE), paste0("--out=", out))
  st <- system2(pixi, c("run", "--manifest-path", mf, shQuote(rscript), shQuote(script), shQuote(args)))
  quit(status = st)
}

# --- the libraries env, and the children's environment ----------------------
if (dist == "conda") Sys.unsetenv("R_ZIG_EXTRA_ENV")          # rzig finds R's own env itself
sysroot <- if (dist == "conda") root else Sys.getenv("R_ZIG_EXTRA_ENV")
if (nzchar(sysroot) && dir.exists(sysroot)) sysroot <- normalizePath(sysroot, winslash = "/") else {
  message("warning: no libraries env (R_ZIG_EXTRA_ENV): rows with sysdeps will fail")
  sysroot <- ""
}
envdir <- if (win && nzchar(sysroot)) file.path(sysroot, "Library") else sysroot
meta <- function(pattern) sub("\\.json$", "", list.files(file.path(sysroot, "conda-meta"), pattern))
have <- sub("-[^-]+-[^-]+$", "", meta("\\.json$"))
sysdeps_missing <- if (nzchar(sysroot)) setdiff(needed, have) else needed
if (length(sysdeps_missing)) message("warning: sysdeps not in the env: ", paste(sysdeps_missing, collapse = " "))

for (d in c("lib", "logs", "smoke", "src", "tmp")) dir.create(file.path(out, d), showWarnings = FALSE)
jobs <- Sys.getenv("STRESS_JOBS")                              # empty counts as unset (CI passes an empty input)
jobs <- as.integer(opt("jobs", if (nzchar(jobs)) jobs else min(parallel::detectCores(), 8L, na.rm = TRUE)))
if (is.na(jobs) || jobs < 1) stop("--jobs needs a positive number", call. = FALSE)
git <- Sys.which("git")
commit <- Sys.getenv("GITHUB_SHA")
if (!nzchar(commit) && nzchar(git)) commit <- tryCatch({
  sha <- system2(git, c("-C", shQuote(repo), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)[1]
  dirty <- system2(git, c("-C", shQuote(repo), "status", "--porcelain", "--untracked-files=no"), stdout = TRUE, stderr = FALSE)
  paste0(sha, if (length(dirty)) " (modified)" else "")
}, error = function(e) "", warning = function(w) "")
empty <- file.path(out, "empty"); invisible(file.create(empty))
tmp <- file.path(out, "tmp")
Sys.setenv(
  R_LIBS = lib, R_LIBS_USER = lib, R_LIBS_SITE = lib,           # nothing from other libraries
  R_MAKEVARS_USER = empty, R_ENVIRON_USER = empty, R_PROFILE_USER = empty,
  MAKEFLAGS = paste0("-j", jobs), CMAKE_BUILD_PARALLEL_LEVEL = jobs,
  TMPDIR = tmp, NOT_CRAN = "", R_INSTALL_STAGED = "true")
if (win) Sys.setenv(TMP = tmp, TEMP = tmp)
# zig caches every object it compiles: in the run directory, whatever the
# caller set (as scripts/env.sh does for the build). --resume reuses it.
Sys.setenv(ZIG_GLOBAL_CACHE_DIR = file.path(out, "zig-cache"), ZIG_LOCAL_CACHE_DIR = file.path(out, "zig-cache"))
if (win && nzchar(envdir)) Sys.setenv(R_TOOLS_SOFT = envdir)   # Rtools' place for libraries (sf/terra copy share/gdal, share/proj)
if (flag("trace")) Sys.setenv(RZIG_TRACE = "1")
# PATH: the libraries env's programs (cmake, pkg-config, make, zig, flang)
# first, then the OS's base directories, nothing else (no Homebrew, no
# Rtools or Strawberry gcc). On Linux and macOS this is scripts/env.sh's
# rule; env.sh keeps PATH on Windows, so the Windows list is this script's.
if (!flag("keep-path") && nzchar(sysroot)) Sys.setenv(PATH = paste(if (win) c(
  file.path(rhome, "bin/x64"), sysroot, file.path(sysroot, c("Library/mingw-w64/bin", "Library/usr/bin", "Library/bin", "Scripts", "bin")),
  file.path(Sys.getenv("SystemRoot", "C:/Windows"), c("System32", ""))) else c(file.path(sysroot, "bin"), "/usr/bin", "/bin"),
  collapse = .Platform$path.sep))
zig <- Sys.getenv("ZIG_BIN", Sys.which("zig"))
info <- list(
  date = format(t_start, "%Y-%m-%d %H:%M %Z", tz = "UTC"), r = R.version.string, os = os, arch = arch, dist = dist,
  channel = Sys.getenv("STRESS_CHANNEL"), r_zig = paste(meta("^r-zig-(slim|toolchain)-.*\\.json$"), collapse = " "),
  r_home = rhome, libraries_env = sysroot, commit = commit, jobs = jobs, path = if (flag("keep-path")) "kept" else "narrowed",
  zig = if (nzchar(zig)) tryCatch(system2(zig, "version", stdout = TRUE, stderr = FALSE)[1], error = function(e) "") else "",
  cc = tryCatch(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "--no-user-files", "CC"), stdout = TRUE)[1], error = function(e) ""),
  sysdeps_missing = paste(sysdeps_missing, collapse = " "), tsv = tsv, out = out,
  args = paste(argv, collapse = " "), minutes = 0, finished = FALSE, error = "")

# --- the report (written after every package, so a killed run keeps one) ------
results <- list()
write_report <- function(final = FALSE) {
  info$minutes <- round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 1)
  info$finished <- final
  res <- if (length(results)) do.call(rbind, lapply(results, as.data.frame, stringsAsFactors = FALSE)) else
    data.frame(package = character(), role = character(), group = character(), status = character(), class = character(),
               expect = character(), minutes = numeric(), size_mb = numeric(), first_error = character())
  res$unexpected <- res$role == "target" & res$expect != "?" &
    ifelse(res$expect == "ok", res$status != "ok", res$status == "ok" | sub("^fail-", "", res$expect) != res$class)
  writeLines(js(list(info = info, results = res)), file.path(out, "report.json"))
  tg <- res[res$role == "target", , drop = FALSE]
  deps <- res[res$role == "dependency", , drop = FALSE]
  count <- function(s) if (length(s)) paste(sprintf("%d %s", table(s), names(table(s))), collapse = ", ") else "none"
  md <- c(sprintf("## r-zig stress: %s %s, %s%s", os, arch, dist, if (final) "" else " (running)"), "",
          sprintf("%s. %s, commit %s. %s min, jobs %d, PATH %s.", info$date, info$r,
                  if (nzchar(commit)) sub("^([0-9a-f]{12})[0-9a-f]+", "\\1", commit) else "unknown",
                  info$minutes, jobs, info$path),
          sprintf("zig %s; CC `%s`; libraries env `%s`%s.", info$zig, info$cc, sysroot,
                  if (dist == "conda") sprintf(" (%s from %s)", info$r_zig, info$channel) else ""),
          if (length(sysdeps_missing)) sprintf("Sysdeps missing from the env: %s.", info$sysdeps_missing),
          if (nzchar(info$error)) c("", sprintf("**The harness stopped: %s**", cell(info$error))), "",
          sprintf("Targets: %s. Unexpected (!): %d. Dependencies: %s.", count(tg$status), sum(tg$unexpected), count(deps$status)))
  if (nrow(tg)) md <- c(md, "", "| package | group | status | class | expect | min | MB | first error |", "|---|---|---|---|---|---|---|---|",
    sprintf("| %s%s | %s | %s | %s | %s | %s | %s | %s |", tg$package, ifelse(tg$unexpected, " (!)", ""), tg$group, tg$status,
            tg$class, tg$expect, tg$minutes, ifelse(is.na(tg$size_mb), "", tg$size_mb), cell(tg$first_error)))
  bad <- deps[deps$status != "ok", , drop = FALSE]
  if (nrow(bad)) md <- c(md, "", "Dependencies that did not install:", "",
    sprintf("- %s: %s, %s: %s", bad$package, bad$status, bad$class, cell(bad$first_error)))
  md <- c(md, "", "Logs: `logs/<package>.log` (install) and `logs/<package>-smoke.log` in the run directory.")
  writeLines(md, file.path(out, "report.md"))
  if (final && nzchar(Sys.getenv("GITHUB_STEP_SUMMARY"))) cat(md, file = Sys.getenv("GITHUB_STEP_SUMMARY"), sep = "\n", append = TRUE)
  invisible(res)
}
harness_error <- function(msg) {
  info$error <<- msg
  write_report(final = TRUE)
  message("stress: ", msg, "\nreport: ", file.path(out, "report.md"))
  quit(status = 2)
}
if (inherits(db, "error")) harness_error(paste("cannot read the repositories:", conditionMessage(db)))

# --- one child process per step -------------------------------------------------
run <- function(args, log, minutes, env = character()) {
  old <- Sys.getenv(names(env), unset = NA, names = TRUE)
  if (length(env)) do.call(Sys.setenv, as.list(env))
  on.exit(for (n in names(old)) if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, as.list(old[n])))
  t0 <- Sys.time()
  # timeout: unix kills the child's process group, Windows its job object;
  # both return 124 (system2's env= is ignored on Windows, hence Sys.setenv)
  st <- suppressWarnings(system2(file.path(R.home("bin"), "R"), args, stdout = log, stderr = log, timeout = round(60 * minutes)))
  list(status = st, minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2))
}
row_env <- function(x) {
  kv <- unlist(strsplit(x, ";")); kv <- trimws(kv[nzchar(kv) & kv != "-"])
  if (!length(kv)) return(character())
  setNames(gsub("{env}", envdir, sub("^[^=]*=", "", kv), fixed = TRUE), sub("=.*", "", kv))
}
# The class is a suggestion from the failing part of the log; a person
# decides (README). First match wins.
patterns <- c(
  network   = "cannot open URL|cannot open the connection to '?https?:|Could not resolve host|Failed to connect|Connection (timed out|refused|reset)|Temporary failure in name resolution|status was '[45][0-9][0-9]|HTTP (error|status) [45][0-9][0-9]|HTTP/[0-9.]+ [45][0-9][0-9]|Timeout of [0-9]+ seconds was reached|curl: \\([0-9]+\\)|download (failed|error)|SSL connect error",
  resource  = "No space left on device|[Cc]annot allocate memory|[Oo]ut of memory|std::bad_alloc|Killed signal terminated|virtual memory exhausted|OutOfMemory",
  abi       = "(undefined (symbol|reference)|[Ss]ymbol not found)[^\n]*(__cxx11|B5cxx11|St3__1|std::__1|__cxa_|__gxx_personality|_Unwind_|\\?[A-Za-z_][A-Za-z0-9_@?$]*@@)",
  toolchain = "rzig: |(zig-cc|zig-cxx|zig-fc|zig-ar|zig-ranlib): (cannot |waiting for |could not |no flang|warning: no |warning: R_ZIG_EXTRA_ENV)|zig: error|error: unable to (spawn|create|open|load|parse|emit)|LLVM ERROR|PLEASE submit a bug report|unknown target CPU|unsupported option|unknown argument|compiler cannot create executables|relocation R_[A-Z0-9_]+ .*against|(undefined (symbol|reference)|[Ss]ymbol not found)[^\n]*(__(u)?(div|mod|mul)ti3|___chkstk_ms|__extend|__trunc|__emutls)",
  sysdep    = "(?m)configure: error|was not found in the pkg-config search path|No package '[^']+' found|fatal error: '?[^ ']+\\.h'?( file)? not found|\\.h: No such file|cannot find -l|unable to find (dynamic |static )?system library|library not found for -l|command not found|: not found$|[Cc][Mm]ake.*not found|Could NOT find")
first_error <- function(log) {
  x <- tryCatch(readLines(log, warn = FALSE), error = function(e) character())
  x <- iconv(x, "", "UTF-8", sub = "?")
  strong <- grep("(^|[^A-Za-z])(error|Error|ERROR)(:| in | at |\\[)|undefined (symbol|reference)|[Ss]ymbol not found|cannot find -l|library not found for -l|unable to find (dynamic |static )?system library|Killed signal|No space left", x)
  weak <- grep("not found|timed out|[Ff]ailed", x)
  hit <- c(strong, weak)[1]
  from <- if (!is.na(hit)) hit else max(1, length(x) - 40)
  line <- if (!is.na(hit)) x[hit] else tail(c("", x[nzchar(trimws(x))]), 1)
  # classify on the failing part only: a benign line earlier in the log
  # (a download that was retried, a configure probe) must not decide it
  list(line = substr(trimws(line), 1, 240), text = paste(x[from:max(from, length(x))], collapse = "\n"))
}
classify <- function(text) {
  for (k in names(patterns)) if (grepl(patterns[[k]], text, perl = TRUE)) return(k)
  "package"
}
expected <- function(e) {
  e <- words(e)
  if (!length(e)) return("?")
  hit <- grep(paste0("^", os, "="), e, value = TRUE)
  if (length(hit)) sub(".*=", "", hit[1]) else if (!any(grepl("=", e))) e[1] else "?"
}
tarball <- function(p) {
  f <- list.files(file.path(out, "src"), paste0("^", p, "_.*\\.tar\\.gz$"), full.names = TRUE)
  if (length(f)) return(f[1])
  r <- retry(function() download.packages(p, file.path(out, "src"), available = db, type = "source", quiet = TRUE))
  if (inherits(r, "error") || !NROW(r)) return(NA_character_)
  r[1, 2]
}

# --- the run -----------------------------------------------------------------------
message(sprintf("stress: %s %s, %s, %d items, jobs %d, run directory %s", os, arch, dist, nrow(items), jobs, out))
failed <- character()
for (i in seq_len(nrow(items))) {
  it <- items[i, ]
  row <- rows[rows$package == it$package, ]
  id <- gsub(":", "-", it$package)
  log <- file.path(out, "logs", paste0(id, ".log"))
  rec <- list(package = it$package, role = if (it$target) "target" else "dependency",
              group = if (nrow(row)) row$group else "", os = os, arch = arch, dist = dist,
              version = if (it$name %in% rownames(db)) unname(db[it$name, "Version"]) else "",
              expect = if (nrow(row)) expected(row$expect) else "ok",
              status = "", class = "", minutes = 0, size_mb = NA, first_error = "", log = paste0("logs/", id, ".log"))
  rec <- tryCatch({
    vlib <- if (nzchar(it$variant)) file.path(out, paste0("lib-", it$variant)) else lib
    dir.create(vlib, showWarnings = FALSE)
    env <- c(R_LIBS = paste(unique(c(vlib, lib)), collapse = .Platform$path.sep), if (nrow(row)) row_env(row$env))
    minutes <- if (nrow(row)) as.numeric(row$timeout_min) else 30
    bad_deps <- if (it$name %in% rownames(db)) intersect(unlist(tools::package_dependencies(it$name, db = db, which = hard, recursive = TRUE)), failed) else character()
    message(sprintf("[%d/%d] %s ...", i, nrow(items), it$package))
    installed <- flag("resume") && file.exists(file.path(vlib, it$name, "DESCRIPTION"))
    src <- NA_character_
    if (installed) {
      rec$class <- "resumed"
    } else if (!it$name %in% rownames(db)) {
      rec$status <- "unavailable"; rec$class <- "network"; rec$first_error <- "not in CRAN or Bioconductor for this R"
    } else if (length(bad_deps)) {
      rec$status <- "skipped"; rec$class <- "dependency"; rec$first_error <- paste("failed dependency:", paste(bad_deps, collapse = " "))
    } else if (is.na(src <- tarball(it$name))) {
      rec$status <- "download-failed"; rec$class <- "network"; rec$first_error <- "download.packages failed 3 times"
    } else {
      for (attempt in 1:3) {                                   # more tries only for a network failure
        r <- run(c("CMD", "INSTALL", shQuote(paste0("--library=", vlib)), shQuote(src)), log, minutes, env)
        fe <- first_error(log)
        if (r$status == 0 || r$status == 124 || attempt == 3 || classify(fe$text) != "network") break
        file.rename(log, sub("\\.log$", paste0("-attempt", attempt, ".log"), log))
        Sys.sleep(c(30, 90)[attempt])
      }
      unlink(Sys.glob(file.path(vlib, "00LOCK-*")), recursive = TRUE)   # left by a killed install
      rec$minutes <- r$minutes
      if (r$status == 124) {
        rec$status <- "timeout"; rec$class <- "timeout"
        rec$first_error <- sprintf("timed out after %s min; last line: %s", minutes, fe$line)
      } else if (r$status != 0) {
        rec$status <- "install-failed"; rec$class <- classify(fe$text)
        rec$first_error <- if (nzchar(fe$line)) fe$line else paste("exit status", r$status)
      } else installed <- TRUE
    }
    if (installed) {
      files <- list.files(file.path(vlib, it$name), recursive = TRUE, full.names = TRUE)
      rec$size_mb <- round(sum(file.info(files)$size) / 2^20, 1)
      # load every package; targets also run their smoke call. In a file:
      # no quoting issues on any OS.
      smoke <- if (nrow(row) && nzchar(row$smoke) && row$smoke != "-") row$smoke else "TRUE"
      sf <- file.path(out, "smoke", paste0(id, ".R"))
      writeLines(c(sprintf("suppressPackageStartupMessages(library(%s))", it$name), sprintf("res <- local(%s)", smoke),
                   "print(res)", "if (isFALSE(res)) stop(\"the smoke call returned FALSE\")"), sf)
      slog <- sub("\\.log$", "-smoke.log", log)
      s <- run(c("--vanilla", "--no-echo", shQuote(paste0("--file=", sf))), slog, 5, env)
      if (s$status == 0) rec$status <- "ok" else {
        fe <- first_error(slog)
        rec$status <- if (s$status == 124) "timeout" else "smoke-failed"
        rec$class <- if (s$status == 124) "timeout" else classify(fe$text)
        rec$first_error <- fe$line
      }
    }
    rec
  }, error = function(e) { rec$status <- "error"; rec$class <- "harness"; rec$first_error <- conditionMessage(e); rec })
  # anything but ok (a failed install, load or smoke call) skips the
  # package's dependents; variants live in their own library: nothing
  # depends on them
  if (rec$status != "ok" && !nzchar(it$variant)) failed <- c(failed, it$name)
  message(sprintf("[%d/%d] %s: %s%s (%s min)", i, nrow(items), it$package, rec$status,
                  if (nzchar(rec$class) && rec$status != "ok") paste0(", ", rec$class) else "", rec$minutes))
  results[[i]] <- rec
  write_report()
  # what a build left in TMPDIR (s2's abseil prefix, a killed build's tree)
  unlink(list.files(tmp, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE)
}

res <- write_report(final = TRUE)
writeLines(readLines(file.path(out, "report.md")))
message("report: ", file.path(out, "report.md"))
quit(status = if (flag("strict") && any(res$unexpected)) 1 else 0)
