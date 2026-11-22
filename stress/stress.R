# r-zig stress suite (stress/README.md). Installs hard-to-build CRAN and
# Bioconductor packages from source with the R that runs this script, one
# at a time, each with a timeout and a log. Then it loads each target, runs
# one smoke call, unloads the namespace, checks that R exits cleanly, and
# writes report.json and report.md (and the job summary in CI). A
# diagnostic, never a gate: package failures do not change the exit status
# (0), unless --strict. A broken harness exits 2.
#
# Base R only. It needs an R with r-zig's toolchain plus an environment of
# system libraries:
#   tree   the dev tree, with the libraries env that R_ZIG_EXTRA_ENV names
#          (pixi run -e stress stress [args]).
#   conda  R installed in the env that also holds the libraries. --conda
#          makes that env with pixi (r-zig-slim, r-zig-toolchain and the
#          sysdeps of the rows the run installs) in the run directory, then
#          runs this script again with that env's R.
#
# Usage: stress.R [options] [target ...]
#   target        a row of packages.tsv (package or package:variant), a group
#                 (g0 to g4), a tag (heavy), or all. Default: all of this OS's rows.
#   --skip=X,Y    leave out these rows, groups or tags (--skip=heavy)
#   --tree        test the R that runs this script (the default)
#   --conda[=CH]  test r-zig-slim + r-zig-toolchain from channel CH: local
#                 (the default: this checkout's dist/conda, made by
#                 `pixi run -e pkg conda-package`), universe (prefix.dev),
#                 or another channel path or URL
#   --libs-channel=CH  with --conda: one more channel, right after r-zig's
#                 (before universe and conda-forge), for libs-zig-pixi's
#                 zig-* packages (zig-gdal, zig-abseil, ...) before they are
#                 published (M5): a channel directory (the libs-zig-pixi CI
#                 artifact channel-<subdir>-<leg>) or URL. Without it the
#                 rows' zig-* sysdeps are left out of the conda env unless
#                 the libraries env has them (stress/README.md, zig-libs).
#                 Ignored, with a note, for the tree
#   --out=DIR     run directory (default build/stress/<os>-<arch>-<dist>-<time>)
#   --jobs=N      make -jN and cmake's parallel level (default: cores, max 8)
#   --resume      reuse --out's library: skip what is already installed
#   --keep-path   keep the caller's PATH (default: only the libraries env's
#                 programs and the OS's base directories) and, on macOS,
#                 skip the runner's CMake toolchain file that leaves
#                 Homebrew out (a tree with its own etc/r-zig.cmake gets none)
#   --msys-from-tree  Windows, the tree: leave the libraries env's
#                 Library/usr/bin and Library/mingw-w64/bin off PATH, so that
#                 sh, make and the tools R's makefiles run come from the
#                 tree's build-tools group alone (R_HOME/bin/toolchain/usr/bin,
#                 which R puts first); ignored, with a note, elsewhere and
#                 for a conda env, whose tools are in its Library/usr/bin
#   --no-rtools-libs  Windows on ARM: do not use CRAN's Rtools45 aarch64
#                 toolchain-libs tree. By default a run there downloads it
#                 (pinned URL and sha256) into <repo>/build/rtools45
#                 (STRESS_RTOOLS_DIR overrides), extracts it, and uses it as
#                 the fallback for the libraries conda-forge lacks for
#                 win-arm64 (rzig's R_ZIG_FALLBACK_SOFT, closed .pc files
#                 first on PKG_CONFIG_PATH, R_TOOLS_SOFT; stress/README.md).
#                 If that fails, the rows run without it and report.md's
#                 Fallback line says why. Elsewhere nothing to turn off
#   --trace       RZIG_TRACE=1: rzig prints its commands into the logs, and
#                 `rzig build` (patch 0013) its tier; R_ZIG_PKG_BUILDER=make
#                 in the environment makes every install take the make path
#   --list        print the install plan and stop
#   --sysdeps     print the sysdeps of the rows the run installs on this OS
#                 (the selected ones and their dependencies' rows) and stop
#   --strict      exit 1 when a target's result differs from its expect
#   --help        print this
# Environment: STRESS_JOBS (as --jobs), STRESS_TSV (another data file),
# STRESS_RTOOLS_DIR (where the Rtools45 tree goes), STRESS_LIBS_CHANNEL (as
# --libs-channel), R_ZIG_PKG_BUILDER (auto or make; the report records it).

argv <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "(=|$)"), argv, value = TRUE)
  if (!length(hit)) return(default)
  v <- sub(paste0("^--", name, "=?"), "", hit[[length(hit)]])
  if (nzchar(v)) v else TRUE
}
flag <- function(name) isTRUE(opt(name))
known <- c("skip", "tree", "conda", "libs-channel", "out", "jobs", "resume", "keep-path", "msys-from-tree", "no-rtools-libs", "trace", "list",
           "sysdeps", "strict", "help")
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
# libs-zig-pixi's zig-* packages before M5: their channel (--libs-channel)
libs_channel <- opt("libs-channel", if (nzchar(Sys.getenv("STRESS_LIBS_CHANNEL"))) Sys.getenv("STRESS_LIBS_CHANNEL"))
if (isTRUE(libs_channel)) stop("--libs-channel needs a channel directory or URL", call. = FALSE)
if (!is.null(libs_channel) && is.null(conda) && dist == "tree") {
  message("stress: --libs-channel is for --conda (the tree's libraries env is the stress env); ignored")
  libs_channel <- NULL
}
# zig's triple, the directory below a Windows env's Library/zig-libs that
# the zig-* packages install into (rzig's environment.zig)
zig_triple <- paste0(arch, "-windows-gnu")
# conda's name for this R's platform: the --conda env's, and the one the
# libraries env must have
subdir <- switch(paste(os, arch), "linux x86_64" = "linux-64", "linux aarch64" = "linux-aarch64",
                 "macos x86_64" = "osx-64", "macos aarch64" = "osx-arm64", "windows x86_64" = "win-64",
                 "windows aarch64" = "win-arm64", NA_character_)
# the names of a conda env's packages, and its platform (the first
# package that is not noarch says it)
env_pkgs <- function(prefix) sub("-[^-]+-[^-]+\\.json$", "", list.files(file.path(prefix, "conda-meta"), "\\.json$"))
env_subdir <- function(prefix) {
  for (f in list.files(file.path(prefix, "conda-meta"), "\\.json$", full.names = TRUE)) {
    x <- paste(readLines(f, warn = FALSE), collapse = "\n")
    m <- regmatches(x, regexpr("\"subdir\": *\"[^\"]*\"", x))
    s <- sub(".*\"([^\"]*)\"$", "\\1", m)
    if (length(s) && s != "noarch") return(s)
  }
  NA_character_
}

# --- the data file and the selection ----------------------------------------
tsv <- normalizePath(Sys.getenv("STRESS_TSV", file.path(dirname(script), "packages.tsv")), winslash = "/")
tab <- read.delim(text = grep("^#", readLines(tsv, warn = FALSE), value = TRUE, invert = TRUE),
                  quote = "", comment.char = "", colClasses = "character", na.strings = character())
tab$name <- sub(":.*", "", tab$package)
tab$variant <- ifelse(grepl(":", tab$package), sub(".*:", "", tab$package), "")
# name@os in tags and sysdeps: that OS only (any_os: every OS, to check names)
on_os <- function(x, any_os = FALSE) { d <- words(x); sub("@.*", "", d[any_os | !grepl("@", d) | sub(".*@", "", d) == os]) }
labels <- function(t, any_os = FALSE) lapply(seq_len(nrow(t)), function(i) c(t$package[i], t$group[i], on_os(t$tags[i], any_os)))
named <- function(t, sel) vapply(labels(t), function(l) any(l %in% sel), NA)
targets_arg <- argv[!startsWith(argv, "--")]
skip <- if (is.null(opt("skip"))) character() else words(opt("skip"))
unknown <- setdiff(c(targets_arg, skip), c(unlist(labels(tab, any_os = TRUE)), "all"))
if (length(unknown)) stop("not in ", tsv, ": ", paste(unknown, collapse = " "), call. = FALSE)
rows <- tab[vapply(tab$oses, function(x) any(words(x) %in% c("all", os)), NA), ]
if (length(targets_arg) && !"all" %in% targets_arg) rows <- rows[named(rows, targets_arg), ]
rows <- rows[!named(rows, skip), ]
if (!nrow(rows)) stop("no rows of ", tsv, " left for ", os, ": ", paste(argv, collapse = " "), call. = FALSE)

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
# the sysdeps of every row the run installs: the selected rows, and the
# rows among their dependencies (sf installs units and s2, whose rows need
# udunits2, cmake and openssl), as the stress env holds them all
inst <- tab[tab$package %in% c(rows$package, items$package), ]
inst <- inst[vapply(inst$oses, function(x) any(words(x) %in% c("all", os)), NA), ]
needed <- sort(unique(unlist(lapply(inst$sysdeps, on_os))))
if (flag("sysdeps")) { writeLines(needed); quit(status = 0) }
if (flag("list")) {
  if (inherits(db, "error")) stop("cannot read the repositories: ", conditionMessage(db), call. = FALSE)
  items$group <- rows$group[match(items$package, rows$package)]
  items$group[is.na(items$group)] <- "(dependency)"
  print(items[, c("package", "group", "variant")], row.names = FALSE)
  quit(status = 0)
}

# --- the libraries env's platform --------------------------------------------
# The tree's libraries env (R_ZIG_EXTRA_ENV, the stress env; with --conda
# also the list of what that env's platform has) or the conda env R is in.
# Its platform must be this R's: pixi installs an env whose platforms lack
# the runner's for another one, under emulation (win-64 on win-arm64), and
# that env's zig then compiled every package for x64 against an arm64 R
# (stress run 43773932212, chore-release-11 PLAN.md finding 26).
libs <- if (dist == "conda") root else Sys.getenv("R_ZIG_EXTRA_ENV")
if (nzchar(libs) && dir.exists(libs) && !is.na(subdir)) {
  es <- env_subdir(libs)
  if (!is.na(es) && es != subdir)
    stop("the libraries env ", libs, " is ", es, ", this R is ", subdir, " (", os, " ", arch, "): pixi installed the env ",
         "for another platform (emulation); give its feature ", subdir, " in pixi.toml", call. = FALSE)
}

# --- the run directory ----------------------------------------------------------
stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
out <- opt("out", file.path("build", "stress", paste(os, arch, if (is.null(conda)) dist else "conda", stamp, sep = "-")))
if (isTRUE(out)) stop("--out needs a directory", call. = FALSE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, winslash = "/")
lib <- file.path(out, "lib")
if (!flag("resume") && length(list.files(lib))) stop(lib, " is not empty: use --resume or another --out", call. = FALSE)

# --- the classifier --------------------------------------------------------------
# The class is a suggestion from the failing part of the log; a person
# decides (README). First match wins. toolchain has rzig build's own
# failures, not the line that follows every failed compile (tier 1's
# `<source> failed (N): <command>`, tier 2's `zig build failed (N)`): the
# compiler's lines above it decide, as under make [tests-T4];
# and the install preflight's stops (patch 0009): after rzig's 127, in
# build 8's words (as universe's packages print it until phase 4) and
# today's [tests-T11]; after any other status, "this package cannot be
# built (see above)" (PHASE4 open point J a), which classify sends to
# package for a src/build.zig make cannot build.
# abi's "error: <name>: unrecognized file extension": a bare library name,
# no path and no extension, is MSVC link syntax from a conda .pc file
# (win-64 gdal.pc: `-LIBPATH:<dir> gdal`), as -LIBPATH: and /W3 are; the
# link line with -LIBPATH: comes before the error, outside the text read
# (gdalraster, stress run 43773932212, 2026-11-15). A path that zig cannot
# read stays toolchain (V8's ../.deps/v8_monolith).
patterns <- c(
  network   = "cannot open URL|cannot open the connection to '?https?:|Could not resolve host|Failed to connect|Connection (timed out|refused|reset)|Temporary failure in name resolution|status was '[45][0-9][0-9]|HTTP (error|status) [45][0-9][0-9]|HTTP/[0-9.]+ [45][0-9][0-9]|Timeout of [0-9]+ seconds was reached|curl: \\([0-9]+\\)|download (failed|error)|SSL connect error",
  resource  = "No space left on device|[Cc]annot allocate memory|[Oo]ut of memory|std::bad_alloc|Killed signal terminated|virtual memory exhausted|OutOfMemory",
  abi       = "(undefined (symbol|reference)|[Ss]ymbol not found)[^\n]*(__cxx11|B5cxx11|St3__1|std::__1|__cxa_|__gxx_personality|_Unwind_|\\?[A-Za-z_][A-Za-z0-9_@?$]*@@)|undefined symbol: _Z|could not open 'lib(MSVCRT|OLDNAMES|LIBCMT|msvcprt)\\.a'|-LIBPATH:|Windows Kits/10/Lib|/(W[0-4]|bigobj|wd[0-9]+): unrecognized file extension|(^|\\s)error: [A-Za-z][A-Za-z0-9_+-]*: unrecognized file extension",
  toolchain = "unknown CPU: '|unrecognized file extension|Could NOT find Threads|thread [0-9]+ panic: |/bin/R(term\\.exe|script\\.exe)?: No such file or directory|is not a full path to an existing compiler tool|windres: command not found|Building for: NMake Makefiles|make: invalid option -- \\?|ar(\\.exe)?: [^ ]+\\.o: No such file or directory|unsupported linker arg: |-Werror,-Wdate-time|version script assignment of '[^']+' to symbol '[^']+' failed: symbol not defined|rzig: |(zig-cc|zig-cxx|zig-fc|zig-ar|zig-ranlib): (cannot |waiting for |could not |no flang|warning: no |warning: R_ZIG_EXTRA_ENV)|rzig build: (no zig|cannot |waiting for zig build)|R_HOME/share/zig/rpkg is not installed|r-zig toolchain (is|\\(compiled code or a configure script\\), which is) (incomplete|not installed)|this package cannot be built \\(see above\\)|zig: error|error: unable to (spawn|create|open|load|parse|emit)|LLVM ERROR|PLEASE submit a bug report|unknown target CPU|unsupported option|unsupported argument '[^']*' to option '|unknown argument|compiler cannot create executables|relocation R_[A-Z0-9_]+ .*against|(undefined (symbol|reference)|[Ss]ymbol not found)[^\n]*(__(u)?(div|mod|mul)ti3|___chkstk_ms|__extend|__trunc|__emutls|__guard_(dispatch|check)_icall|__clear_cache)|invalid symbol index in addrsig section",
  crash     = "\\*\\*\\* caught (segfault|bus error|illegal operation) \\*\\*\\*|R is aborting now|An irrecoverable exception occurred",
  upstream  = "Library not loaded: (/opt/homebrew|/usr/local/(opt|Cellar))/|(system library '|cannot find -l|library not found for -l|unable to find library -l)(debug|optimized)\\b|[Tt]he specified procedure could not be found|failed to solve the environment|Cannot solve the request|[Cc]ould not solve for environment specs",
  sysdep    = "(?m)configure: error|was not found in the pkg-config search path|No package '[^']+' found|fatal error: '?[^ ']+\\.h(pp|xx)?'?( file)? not found|\\.h: No such file|cannot find -l|unable to find (dynamic |static )?system library|library not found for -l|command not found|: not found$|[Cc][Mm]ake.*not found|Could NOT find")
# a log's lines as valid UTF-8: one stray byte would stop trimws() and grep()
read_log <- function(log) iconv(tryCatch(readLines(log, warn = FALSE), error = function(e) character()), "", "UTF-8", sub = "?")
first_error <- function(log, after = NULL) {
  x <- read_log(log)
  if (length(after)) x <- tail(x, length(x) - match(after, trimws(x), 0))   # only what came after this line
  strong <- grep("(^|[^A-Za-z])(error|Error|ERROR)(:| in | at |\\[)|undefined (symbol|reference)|[Ss]ymbol not found|cannot find -l|library not found for -l|unable to find (dynamic |static )?system library|Killed signal|No space left|\\*\\*\\* caught [a-z ]+ \\*\\*\\*|thread [0-9]+ panic: |syntax error near unexpected token|windres: command not found|/bin/R(term\\.exe|script\\.exe)?: No such file or directory|ar(\\.exe)?: [^ ]+\\.o: No such file or directory", x)
  weak <- grep("not found|timed out|[Ff]ailed", x)
  hit <- c(strong, weak)[1]
  from <- if (!is.na(hit)) hit else max(1, length(x) - 40)
  line <- if (!is.na(hit)) x[hit] else tail(c("", x[nzchar(trimws(x))]), 1)
  # a load test's "package or namespace load failed" names the symbol (the
  # library, Windows' reason) two lines on
  sym <- grep("undefined symbol: |[Ss]ymbol not found: |Library not loaded: |LoadLibrary failure: ", x)
  sym <- sym[!is.na(hit) & sym > hit & sym <= hit + 3]
  if (length(sym)) line <- sub(".*(undefined symbol: |[Ss]ymbol not found: |Library not loaded: |LoadLibrary failure: )", "\\1", x[sym[1]])
  # the install preflight's stops (patch 0009) point "see above": the line
  # is rzig's last one above it, which names what is missing (zig-cc: on
  # every OS, also run as gcc.exe), not the stop itself; the 127 stop's
  # words differ between builds, its end does not [tests-T11]. After any
  # other status the stop is "this package cannot be built (see above)"
  # (PHASE4 open point J a). For a src/build.zig package make cannot build
  # it is the line with rzig's reason, which the line "the r-zig toolchain
  # is complete" follows. The failing part then starts at rzig's line,
  # which classify reads too [code-6]
  if (!is.na(hit) && (grepl("r-zig toolchain", x[hit], fixed = TRUE) && grepl("incomplete (see above)", x[hit], fixed = TRUE) ||
                      grepl("this package cannot be built (see above)", x[hit], fixed = TRUE))) {
    z <- grep("^zig-cc: ", x[seq_len(hit - 1)])
    c1 <- z[grepl("src/build.zig cannot be built by make: ", x[z], fixed = TRUE)]
    if (length(c1)) z <- c1
    if (length(z)) {
      line <- x[tail(z, 1)]
      from <- min(from, tail(z, 1))
    }
  }
  # classify on the failing part only: a benign line earlier in the log
  # (a download that was retried, a configure probe) must not decide it
  list(line = substr(trimws(line), 1, 240), text = paste(x[from:max(from, length(x))], collapse = "\n"))
}
classify <- function(text) {
  # a src/build.zig package make cannot build (rzig's line, from the hook
  # or the preflight, whose stop after it says the package cannot be
  # built): the package's own or a site's settings, not the toolchain
  # [code-6]. Any other preflight stop matches toolchain's pattern
  if (grepl("src/build.zig cannot be built by make: ", text, fixed = TRUE)) return("package")
  for (k in names(patterns)) if (grepl(patterns[[k]], text, perl = TRUE)) return(k)
  "package"
}

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
  # universe before conda-forge, as pixi.toml and README: under strict
  # channel priority flang-rt-zig's llvm-openmp (zig_*) is only visible
  # when universe comes first (2026-11-12, chore-release-11 PLAN.md)
  # libs-zig-pixi's channel right after r-zig's (zig-* are in no other)
  if (!is.null(libs_channel) && !grepl("^[a-z]+://", libs_channel)) {
    if (!dir.exists(libs_channel)) stop("no conda channel at ", libs_channel, " (--libs-channel)", call. = FALSE)
    libs_channel <- normalizePath(libs_channel, winslash = "/")
  }
  channels <- unique(c(if (channel != "https://prefix.dev/universe") channel, libs_channel, "https://prefix.dev/universe", "conda-forge"))
  if (is.na(subdir)) stop("no conda subdir for ", os, " ", arch, call. = FALSE)
  # the installed rows' sysdeps only, as a user installs what they need: a
  # conflict in one row's libraries then does not block the other rows.
  # Not those the stress env lacks on this platform: pixi.toml leaves out
  # what conda-forge has no build of for it (win-arm64: glpk, libgdal-core,
  # ...), which would fail the whole solve; the run with the conda env's R
  # reports them as sysdeps missing from the env, as the tree's run does.
  # Only when the libraries env is the stress env: another env does not
  # say what conda-forge has for the platform, so all sysdeps stay.
  absent <- if (nzchar(libs) && dir.exists(libs) && basename(libs) == "stress") setdiff(needed, env_pkgs(libs)) else character()
  # zig-* (libs-zig-pixi): from --libs-channel when given; without it only
  # when the libraries env has them (none before M5, when no channel has
  # them and the whole solve would fail)
  zig_needed <- grep("^zig-", needed, value = TRUE)
  absent <- if (!is.null(libs_channel)) setdiff(absent, zig_needed) else
    union(absent, setdiff(zig_needed, if (nzchar(libs) && dir.exists(libs)) env_pkgs(libs)))
  if (length(absent)) message("stress: not in the stress env (", libs, ") for ", subdir, ", so not in the conda env: ",
                              paste(absent, collapse = " "))
  deps <- unique(c("r-zig-slim", "r-zig-toolchain", "pkg-config", setdiff(needed, absent)))
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
  # nor what this R's etc/Renviron set for itself (its CA bundle and its
  # CMake toolchain file): the conda R keeps a value that is
  # set, and its children would use this R's files, not its own
  mine <- c("CMAKE_TOOLCHAIN_FILE", "R_ZIG_CMAKE_TOOLCHAIN_FILE", "R_ZIG_CA_BUNDLE")
  Sys.unsetenv(mine[startsWith(chartr("\\", "/", Sys.getenv(mine)), paste0(rhome, "/"))])
  # nor any variable that names the caller's conda env (its activation's:
  # CONDA_PREFIX, PKG_CONFIG_PATH, a package's own), PATH excepted, which
  # pixi run puts the new env first on: a row's configure took the
  # caller's libraries from them (K2, s2 on win-64)
  cp <- chartr("\\", "/", Sys.getenv("CONDA_PREFIX"))
  if (nzchar(cp)) {
    e <- Sys.getenv()
    Sys.unsetenv(setdiff(names(e)[grepl(cp, chartr("\\", "/", e), fixed = TRUE)], c("PATH", "Path")))
  }
  Sys.setenv(STRESS_CHANNEL = channel, STRESS_LIBS_CHANNEL = if (is.null(libs_channel)) "" else libs_channel)
  mf <- shQuote(file.path(ws, "pixi.toml"))
  elog <- file.path(out, "logs", "conda-env.log")
  message("stress: making the conda env in ", ws, " (", paste(channels, collapse = ", "), ")")
  st <- system2(pixi, c("install", "--manifest-path", mf), stdout = elog, stderr = elog)
  if (st != 0) {
    # a result too (the realistic target cannot be installed): report it
    why <- grep("[[:alnum:]]", readLines(elog, warn = FALSE), value = TRUE)
    msg <- sprintf("pixi install failed (%s) for r-zig-slim + r-zig-toolchain + %s from %s",
                   st, paste(setdiff(needed, absent), collapse = " "), paste(channels, collapse = ", "))
    cls <- classify(first_error(elog)$text)                   # upstream: the channels' packages conflict (U4)
    md <- c(sprintf("## r-zig stress: %s %s, conda", os, arch), "", sprintf("**The conda env could not be made** (class %s): %s.", cls, msg),
            "", "Its log (`logs/conda-env.log`) ends:", "", "```", tail(why, 40), "```")
    writeLines(md, file.path(out, "report.md"))
    writeLines(js(list(info = list(os = os, arch = arch, dist = "conda", channel = channel, out = out,
                                   args = paste(argv, collapse = " "), finished = TRUE, error = msg, class = cls),
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
have <- env_pkgs(sysroot)
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
# rzig build takes its default, as a user's install does: tier 1 runs no
# zig build (tier1.zig), and tier 2 keeps its zig build cache in each
# build root (N3). The caller's ZIG_LOCAL_CACHE_DIR would be zig cc's and
# tier 2's cache instead (feat-tier1-engine).
Sys.setenv(ZIG_GLOBAL_CACHE_DIR = file.path(out, "zig-cache"))
Sys.unsetenv("ZIG_LOCAL_CACHE_DIR")
# rzig's own cache is outside the run directory, where cache.zig puts it
# (an empty variable counts as unset; with no cache home, zig's global
# cache). The run removes at its end what it added there (V8's archive
# copy on macOS, a libc++ mirror per zig), never an older entry.
cache_home <- c(Sys.getenv("XDG_CACHE_HOME"), if (win) Sys.getenv("LOCALAPPDATA"),
                if (nzchar(Sys.getenv("HOME"))) file.path(Sys.getenv("HOME"), ".cache"), Sys.getenv("ZIG_GLOBAL_CACHE_DIR"))
rzig_cache <- file.path(chartr("\\", "/", cache_home[nzchar(cache_home)][1]), "r-zig")
rzig_cache_had <- dir.exists(rzig_cache)
rzig_cache_old <- list.files(rzig_cache, all.files = TRUE, no.. = TRUE)
# zig-libs: the env's libs-zig-pixi zig-* static libraries (rzig's
# environment.zig puts them first; Rcmd_environ R_ZIG_LIBS). R_TOOLS_SOFT,
# Rtools' place for libraries (sf, terra and gdalraster copy its share/gdal
# and share/proj): zig-libs when there, so the PROJ and GDAL data match
# zig-proj's and zig-gdal's libraries, else the env's Library. A tree's
# Rcmd_environ knows only R's own env's zig-libs, not R_ZIG_EXTRA_ENV's:
# here that env's .pc files go first on PKG_CONFIG_PATH and PKG_CONFIG_LIBDIR
zig_libs <- if (win && nzchar(envdir)) file.path(envdir, "zig-libs", zig_triple) else ""
if (!nzchar(zig_libs) || !dir.exists(zig_libs)) zig_libs <- ""
if (win && nzchar(envdir)) Sys.setenv(R_TOOLS_SOFT = if (nzchar(zig_libs)) zig_libs else envdir)
if (nzchar(zig_libs) && dist == "tree") {
  pcp <- Sys.getenv("PKG_CONFIG_PATH")
  pcp <- if (nzchar(pcp)) strsplit(pcp, ";", fixed = TRUE)[[1]] else file.path(envdir, c("lib/pkgconfig", "share/pkgconfig"))
  zpc <- file.path(zig_libs, "lib/pkgconfig")
  Sys.setenv(PKG_CONFIG_PATH = paste(unique(c(zpc, pcp)), collapse = ";"),
             PKG_CONFIG_LIBDIR = paste(c(zpc, file.path(envdir, c("lib/pkgconfig", "share/pkgconfig"))), collapse = ";"))
}
if (flag("trace")) Sys.setenv(RZIG_TRACE = "1")
# CMake searches Homebrew whatever PATH says: its Platform/Darwin.cmake adds
# `brew --prefix`, or /opt/homebrew on arm64 when brew is not on PATH, before
# the env's prefix (round 2: arrow's libarrow linked /opt/homebrew/lib/libsnappy.a).
# A toolchain file from the environment (CMake >= 3.21) leaves Homebrew's
# prefixes out of every find_*; a package's own -DCMAKE_TOOLCHAIN_FILE wins.
# Only for a tree without its own: build 7 on ships etc/r-zig.cmake, which
# its etc/Renviron sets, and the run then tests that one.
if (os == "macos" && !flag("keep-path") && nzchar(sysroot) && !file.exists(file.path(rhome, "etc", "r-zig.cmake"))) {
  tc <- file.path(out, "no-homebrew.cmake")
  writeLines("set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH /opt/homebrew /usr/local)", tc)
  Sys.setenv(CMAKE_TOOLCHAIN_FILE = tc)
}
# PATH: the libraries env's programs (cmake, pkg-config, make, zig, flang)
# first, then the OS's base directories, nothing else (no Homebrew, no
# Rtools or Strawberry gcc). On Linux and macOS this is scripts/env.sh's
# rule; env.sh keeps PATH on Windows, so the Windows list is this script's.
# --msys-from-tree leaves the env's MSYS (and MinGW) directories out: the
# tree's build-tools group then answers alone (feat-standalone-toolchain
# PHASE7 open point L a), the env keeping cmake and the libraries.
msys_tree <- flag("msys-from-tree") && win && dist == "tree"
if (flag("msys-from-tree") && !msys_tree)
  message("stress: --msys-from-tree is for a Windows tree; ignored (", os, ", ", dist, ")")
if (!flag("keep-path") && nzchar(sysroot)) Sys.setenv(PATH = paste(if (win) c(
  file.path(rhome, "bin/x64"), sysroot,
  file.path(sysroot, c(if (!msys_tree) c("Library/mingw-w64/bin", "Library/usr/bin"), "Library/bin", "Scripts", "bin")),
  file.path(Sys.getenv("SystemRoot", "C:/Windows"), c("System32", ""))) else c(file.path(sysroot, "bin"), "/usr/bin", "/bin"),
  collapse = .Platform$path.sep))
zig <- Sys.getenv("ZIG_BIN", Sys.which("zig"))
# the builder R CMD INSTALL takes (patch 0013), as the hook reads it
builder <- Sys.getenv("R_ZIG_PKG_BUILDER")
if (!nzchar(builder)) builder <- "auto"
info <- list(
  date = format(t_start, "%Y-%m-%d %H:%M %Z", tz = "UTC"), r = R.version.string, os = os, arch = arch, dist = dist,
  channel = Sys.getenv("STRESS_CHANNEL"), r_zig = paste(meta("^r-zig-(slim|toolchain)-.*\\.json$"), collapse = " "),
  libs_channel = Sys.getenv("STRESS_LIBS_CHANNEL"), zig_libs = zig_libs,
  zig_pkgs = paste(meta("^zig-[a-z].*\\.json$"), collapse = " "),
  r_home = rhome, libraries_env = sysroot, commit = commit, jobs = jobs, path = if (flag("keep-path")) "kept" else "narrowed",
  msys_from_tree = msys_tree,
  zig = if (nzchar(zig)) tryCatch(system2(zig, "version", stdout = TRUE, stderr = FALSE)[1], error = function(e) "") else "",
  cc = tryCatch(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "--no-user-files", "CC"), stdout = TRUE)[1], error = function(e) ""),
  # the cmake a package's configure runs under R CMD: a tree's extras group
  # (R_HOME/bin/toolchain/cmake/bin, which R puts before this PATH's
  # entries, feat-extras-group) when it has one, else the env's
  # ("none" when there is none: command -v exits 1, system2 then returns
  # character(0) with a warning, not an error)
  cmake = local({
    x <- tryCatch(suppressWarnings(system2(file.path(R.home("bin"), "R"), c("CMD", "sh", "-c", shQuote("command -v cmake")),
                                           stdout = TRUE)), error = function(e) character())
    if (length(x) && !is.na(x[1]) && nzchar(x[1])) x[1] else "none"
  }),
  builder = builder,
  sysdeps_missing = paste(sysdeps_missing, collapse = " "), tsv = tsv, out = out, rzig_cache = rzig_cache,
  rzig_cache_removed = "", rtools_libs = "", args = paste(argv, collapse = " "), minutes = 0, finished = FALSE, error = "")

# --- the report (written after every package, so a killed run keeps one) ------
results <- list()
write_report <- function(final = FALSE) {
  info$minutes <- round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 1)
  info$finished <- final
  res <- if (length(results)) do.call(rbind, lapply(results, as.data.frame, stringsAsFactors = FALSE)) else
    data.frame(package = character(), role = character(), group = character(), status = character(), class = character(),
               expect = character(), minutes = numeric(), size_mb = numeric(), first_error = character(), zig_libs = character())
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
          sprintf("zig %s; CC `%s`; cmake `%s`; libraries env `%s`%s.", info$zig, info$cc, info$cmake, sysroot,
                  if (dist == "conda") sprintf(" (%s from %s)", info$r_zig, info$channel) else ""),
          sprintf("Builder %s (R_ZIG_PKG_BUILDER).", builder),
          if (nzchar(info$zig_libs) || nzchar(info$libs_channel))
            sprintf("zig-libs `%s` (%s)%s.", if (nzchar(info$zig_libs)) info$zig_libs else "none",
                    if (nzchar(info$zig_pkgs)) info$zig_pkgs else "no zig-* package",
                    if (nzchar(info$libs_channel)) sprintf(", libs channel %s", info$libs_channel) else ""),
          if (length(sysdeps_missing)) sprintf("Sysdeps missing from the env: %s.", info$sysdeps_missing),
          if (nzchar(info$rtools_libs)) sprintf("Fallback: %s.", info$rtools_libs),
          if (nzchar(info$rzig_cache_removed)) sprintf("The run added to rzig's cache `%s`, and removed at its end: %s.",
                                                       info$rzig_cache, info$rzig_cache_removed),
          if (nzchar(info$error)) c("", sprintf("**The harness stopped: %s**", cell(info$error))), "",
          sprintf("Targets: %s. Unexpected (!): %d. Dependencies: %s.", count(tg$status), sum(tg$unexpected), count(deps$status)))
  # the zig-libs column on Windows only (the zig-* packages are Windows')
  if (nrow(tg)) md <- c(md, "", if (win) "| package | group | status | class | expect | min | MB | zig-libs | first error |" else
    "| package | group | status | class | expect | min | MB | first error |",
    if (win) "|---|---|---|---|---|---|---|---|---|" else "|---|---|---|---|---|---|---|---|",
    sprintf("| %s%s | %s | %s | %s | %s | %s | %s |%s %s |", tg$package, ifelse(tg$unexpected, " (!)", ""), tg$group, tg$status,
            tg$class, tg$expect, tg$minutes, ifelse(is.na(tg$size_mb), "", tg$size_mb),
            if (win) paste0(" ", cell(tg$zig_libs), " |") else "", cell(tg$first_error)))
  bad <- deps[deps$status != "ok", , drop = FALSE]
  if (nrow(bad)) md <- c(md, "", "Dependencies that failed:", "",
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

# --- Windows on ARM: CRAN's Rtools45 aarch64 libraries as the fallback ---------
# conda-forge has no win-arm64 build of gdal, hdf5, netcdf, gsl, gmp, mpfr,
# glpk, nlopt, udunits2, harfbuzz or libpq (chore-release-11 finding 26).
# CRAN's Rtools45 aarch64 "full" toolchain-libs tree has them, built with
# LLVM (libc++, UCRT) as zig builds packages, so its static C and C++
# libraries link with zig's libc++ (feat-winarm-gaps). CRAN's own aarch64
# builds use this tree. On by default there, so the windows-aarch64
# expects hold for every run; --no-rtools-libs turns it off. If the tree
# cannot be made ready, the rows run without it (the Fallback line). Downloaded
# from CRAN at run time and never repackaged (stress/README.md).
rtools_tarball <- list(
  name = "rtools45-toolchain-libs-full-aarch64-6768.tar.zst",
  url = "https://cloud.r-project.org/bin/windows/Rtools/rtools45/files/rtools45-toolchain-libs-full-aarch64-6768.tar.zst",
  size = 415437513,
  sha256 = "64dceac9ecdd54aa85a209a0529f5a96c4b7898ae830c165d0d05bffa5e9e8b5",
  top = "aarch64-w64-mingw32.static.posix")
# the sysdeps (packages.tsv names) the tree serves, by its lib<x>.a. Not
# imagemagick: magick takes r-windows' bundle whatever the env has. Not
# tbb-devel: RcppParallel:system-tbb is a unix row. The zig-* names
# (libs-zig-pixi) it stands in for while the env lacks them: GDAL, GEOS,
# PROJ and oneTBB (terra and gdalraster ok from the tree, stress
# 44450918935); not zig-abseil: s2's make-time pkg-config does not find the
# tree's absl_base (the s2 row)
rtools_has <- c(nlopt = "nlopt", gsl = "gsl", mpfr = "mpfr", gmp = "gmp", glpk = "glpk", hdf5 = "hdf5",
                libnetcdf = "netcdf", udunits2 = "udunits2", "libgdal-core" = "gdal", harfbuzz = "harfbuzz", libpq = "pq",
                "zig-gdal" = "gdal", "zig-geos" = "geos", "zig-proj" = "proj", "zig-onetbb" = "tbb12")

# The tree, ready: <dir>/<top> with include/, lib/, share/{gdal,proj},
# include-pinned and lib/pkgconfig-closed. Downloads the tarball into <dir> unless it is there
# with the pinned size and sha256 (R's tools::sha256sum). Extracts with
# cmake -E tar (libarchive reads zstd; R's untar() does not), else with
# the system's tar (Windows 11's bsdtar, System32/tar.exe), only the four
# directories packages use (1.4 GB of the 2.86 GB). Then include-pinned
# and the closed .pc files (rtools_pc), again when the zig changes: their
# system libraries are zig's MinGW .def files, and include-pinned leaves
# out zig's header names. Each step has its stamp.
rtools_libs <- function(dir, cmake, tar, pkgconf, zig) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir <- normalizePath(dir, winslash = "/")
  tb <- file.path(dir, rtools_tarball$name)
  good <- function() file.exists(tb) && file.size(tb) == rtools_tarball$size &&
    unname(tools::sha256sum(tb)) == rtools_tarball$sha256
  if (!good()) {
    unlink(tb)
    old <- options(timeout = max(1800, getOption("timeout"))); on.exit(options(old), add = TRUE)
    st <- tryCatch(download.file(rtools_tarball$url, tb, mode = "wb", quiet = TRUE), error = function(e) 1L)
    if (st != 0 || !good()) stop("Rtools45 libraries: ", rtools_tarball$url, " did not download, or its size or sha256 is not ",
                                 rtools_tarball$size, " ", rtools_tarball$sha256, call. = FALSE)
  }
  top <- rtools_tarball$top
  tree <- file.path(dir, top)
  extracted <- file.path(dir, paste0(rtools_tarball$name, ".extracted"))
  if (!file.exists(extracted) || !identical(readLines(extracted, warn = FALSE), rtools_tarball$sha256)) {
    unlink(c(extracted, tree), recursive = TRUE)
    members <- paste0(top, c("/include", "/lib", "/share/gdal", "/share/proj"))
    owd <- setwd(dir); on.exit(setwd(owd), add = TRUE)
    how <- character()
    for (t in list(if (nzchar(cmake)) c(cmake, "-E", "tar", "xf"), if (nzchar(tar)) c(tar, "-xf"))) {
      if (is.null(t)) next
      how <- c(how, basename(t[1]))
      st <- suppressWarnings(system2(t[1], c(t[-1], shQuote(tb), members), stdout = FALSE, stderr = FALSE))
      if (st == 0 && dir.exists(file.path(tree, "lib", "pkgconfig"))) break
      unlink(tree, recursive = TRUE)
    }
    setwd(owd)
    if (!dir.exists(file.path(tree, "lib", "pkgconfig")))
      stop("Rtools45 libraries: could not extract ", tb, " (tried: ", paste(how, collapse = ", "),
           "; a .tar.zst needs a libarchive with zstd)", call. = FALSE)
    writeLines(rtools_tarball$sha256, extracted)
  }
  zl <- zig_lib(zig)
  key <- c(rtools_tarball$sha256, tryCatch(system2(zig, "version", stdout = TRUE, stderr = FALSE)[1], error = function(e) ""), zl)
  closed <- file.path(tree, "lib", "pkgconfig-closed")
  ready <- file.path(closed, ".key")
  if (!file.exists(ready) || !identical(readLines(ready, warn = FALSE), key)) {
    unlink(closed, recursive = TRUE)
    n <- rtools_pc(tree, pkgconf, zl, closed)
    if (n$written == 0) stop("Rtools45 libraries: ", pkgconf, " wrote no closed .pc file (is it pkgconf?)", call. = FALSE)
    writeLines(sprintf("%d closed .pc files; skipped (a library the tree cannot link): %s", n$written,
                       paste(n$skipped, collapse = " ")), file.path(closed, "README"))
    writeLines(key, ready)
  }
  tree
}

# zig's lib directory, from `zig env` (ZON in 0.17: .lib_dir = "...")
zig_lib <- function(zig) {
  x <- system2(zig, "env", stdout = TRUE)
  d <- sub('.*"(.*)".*', "\\1", grep("^\\s*\\.lib_dir = ", x, value = TRUE))
  if (length(d) != 1) stop("Rtools45 libraries: no .lib_dir in `", zig, " env`", call. = FALSE)
  gsub("\\\\\\\\", "/", d)
}

# rtools_pc(tree, pkgconf, zig_lib, out): closed .pc files for the tree.
# Each holds the module's whole static closure resolved inside the tree
# alone (pkgconf --static, PKG_CONFIG_LIBDIR the tree's), with no Requires:
# a Requires would resolve wherever PKG_CONFIG_PATH finds the name first,
# and conda-forge's win-arm64 libcurl.pc names a build machine's z.lib.
# Archives are named by path: an -l would bind whichever -L directory
# comes first, a conda import library of the same name (libjpeg-turbo's
# against the tree's IJG libjpeg 9). MinGW's system libraries (a .def in
# zig's MinGW tree) and the runtime names stay -l, for zig. A module with
# any other -l (opencv's -ltegra_hal, -lSymAppl: in no archive of the
# tree) is skipped: it cannot link. No -I<tree>/include and no -L into
# the tree: that include/ holds a whole MinGW-w64 sysroot and libc++
# headers, which as an -I shadow zig's own (<cstddef> "didn't find
# libc++'s <stddef.h>"); rzig's -idirafter (R_ZIG_FALLBACK_SOFT) gives
# them after every environment's. But then a header both have comes from
# the env while the tree's archive links (conda's PROJ 9.9 proj.h with
# the tree's libproj 9.7.1, GEOS 3.15 with 3.14.1). So every closed .pc
# gets -I<tree>/include-pinned instead: a copy of include/ without the
# names zig has (its MinGW, libc++, libc++abi, libunwind and own
# headers), without c++/ and without the OpenMP headers (rzig's OpenMP
# rule: conda's libomp). Those headers then match the archives, and none
# shadows zig's. pkgconf must be pkgconf (the build-tools group's 3.0):
# conda-forge's pkg-config 0.29 stops at libgcrypt.pc ("Libs field occurs
# twice").
rtools_pc <- function(tree, pkgconf, zig_lib, out) {
  tree <- normalizePath(tree, winslash = "/")
  src <- file.path(tree, "lib", "pkgconfig")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  low <- function(x) if (win) tolower(x) else x
  inc <- file.path(tree, "include")
  pinned <- file.path(tree, "include-pinned")
  unlink(pinned, recursive = TRUE)
  dir.create(pinned)
  zig_has <- unlist(lapply(file.path(zig_lib, c("libc/include/any-windows-any", "libcxx/include", "libcxxabi/include",
                                                "libunwind/include", "include")), list.files))
  keep <- list.files(inc)
  keep <- keep[!low(keep) %in% low(c(zig_has, "c++", "flang", "omp.h", "ompx.h", "omp-tools.h", "ompt.h"))]
  if (!all(file.copy(file.path(inc, keep), pinned, recursive = TRUE, copy.date = TRUE)))
    stop("Rtools45 libraries: could not copy ", inc, " into ", pinned, call. = FALSE)
  mingw <- file.path(zig_lib, "libc", "mingw", c("lib-common", "libarm64"))
  runtime <- c("c++", "c++abi", "c++experimental", "stdc++", "unwind", "gcc", "gcc_s", "gcc_eh", "m", "mingw32",
               "mingwex", "mingwthrd", "moldname", "msvcrt", "msvcrt-os", "pthread", "winpthread", "ucrt", "ucrtbase",
               "ucrtapp", "omp", "iomp5md", "gomp")
  # (upstream zig has some only as lib-common/<n>.def.in)
  system_lib <- function(n) n %in% runtime || any(file.exists(outer(mingw, paste0(n, c(".def", ".def.in")), file.path)))
  old <- Sys.getenv(c("PKG_CONFIG_LIBDIR", "PKG_CONFIG_PATH"), unset = NA)
  on.exit(for (n in names(old)) if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, as.list(old[n])))
  Sys.setenv(PKG_CONFIG_LIBDIR = src, PKG_CONFIG_PATH = "")
  pc <- function(m, what) {
    x <- suppressWarnings(system2(pkgconf, c(paste0("--define-variable=prefix=", tree), "--static", what, m),
                                  stdout = TRUE, stderr = FALSE))
    if (!is.null(attr(x, "status"))) return(NULL)
    w <- unlist(strsplit(paste(x, collapse = " "), "[[:space:]]+"))
    chartr("\\", "/", w[nzchar(w)])
  }
  written <- 0L
  skipped <- character()
  for (f in list.files(src, "\\.pc$")) {
    m <- sub("\\.pc$", "", f)
    libs <- pc(m, "--libs"); cflags <- pc(m, "--cflags")
    if (is.null(libs) || is.null(cflags)) { skipped <- c(skipped, m); next }
    libs <- libs[!startsWith(low(libs), low(paste0("-L", tree)))]
    for (i in grep("^-l", libs)) {
      a <- file.path(tree, "lib", paste0("lib", substring(libs[i], 3), ".a"))
      if (!system_lib(substring(libs[i], 3)) && file.exists(a)) libs[i] <- a
    }
    if (any(!vapply(substring(grep("^-l", libs, value = TRUE), 3), system_lib, NA))) { skipped <- c(skipped, m); next }
    libs <- libs[!(duplicated(libs) & !startsWith(libs, "-"))]  # an archive once: lld-link reads them as a group
    cflags <- c(paste0("-I", pinned), cflags[low(cflags) != low(paste0("-I", tree, "/include"))])
    v <- pc(m, "--modversion")
    writeLines(c(sprintf("Name: %s", m), "Description: Rtools45 static library, its closure in the tree (stress.R)",
                 sprintf("Version: %s", if (length(v)) v[1] else "0"),
                 sprintf("Libs: %s", paste(libs, collapse = " ")), sprintf("Cflags: %s", paste(cflags, collapse = " "))),
               file.path(out, f))
    written <- written + 1L
  }
  list(written = written, skipped = skipped)
}

rt_tree <- NULL
served <- character()                                           # sysdeps the tree serves
if (win && arch == "aarch64" && !flag("no-rtools-libs")) {
  # Native paths (R CMD sh's `command -v` gives MSYS ones): cmake the
  # extras group's, else PATH's (the env's); pkgconf the build-tools
  # group's (not conda-forge's pkg-config 0.29); zig the one rzig runs
  # (find_zig.zig's order); tar Windows' own bsdtar
  first <- function(x) { x <- x[!is.na(x) & nzchar(x) & file.exists(x)]; if (length(x)) x[1] else "" }
  rt_cmake <- first(c(file.path(rhome, "bin/toolchain/cmake/bin/cmake.exe"), Sys.which("cmake")))
  rt_pkgconf <- first(c(file.path(rhome, "bin/toolchain/usr/bin/pkgconf.exe"), Sys.which("pkgconf")))
  rt_zig <- first(c(Sys.getenv("ZIG_BIN"), file.path(rhome, "bin/toolchain/zig/zig.exe"),
                    file.path(c(root, sysroot), "Library/bin/aarch64-w64-mingw32-zig.exe"), Sys.which("zig")))
  rt_tar <- first(file.path(Sys.getenv("SystemRoot", "C:/Windows"), "System32", "tar.exe"))
  rt_dir <- Sys.getenv("STRESS_RTOOLS_DIR", file.path(repo, "build", "rtools45"))
  # A failure (download, extraction, no pkgconf) does not stop the run:
  # the rows run without the tree, and report.md's Fallback line says why.
  t0 <- Sys.time()
  rt_tree <- tryCatch({
    if (!nzchar(rt_zig) || !nzchar(rt_pkgconf))
      stop(sprintf("Rtools45 libraries: no zig (%s) or no pkgconf (the build-tools group's: %s)", rt_zig, rt_pkgconf), call. = FALSE)
    rtools_libs(rt_dir, cmake = rt_cmake, tar = rt_tar, pkgconf = rt_pkgconf, zig = rt_zig)
  }, error = function(e) {
    info$rtools_libs <<- paste("not used:", conditionMessage(e))
    message("stress: warning: the rows run without the Rtools45 tree: ", conditionMessage(e))
    NULL
  })
}
if (!is.null(rt_tree)) {
  tree <- rt_tree
  message(sprintf("stress: the Rtools45 tree %s is ready (%.1f min)", tree, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  # PKG_CONFIG_PATH: the env's zig-libs .pc files (libs-zig-pixi) first,
  # then the tree's closed .pc files, then the env's. Tree before the env
  # gives the GDAL stack (gdal, geos, proj) its archives and,
  # through include-pinned, its headers from the tree alone, and avoids conda-forge win-arm64's proj.pc (-lproj_9; it ships
  # proj.lib) and libcurl.pc (a build machine's D:/bld .../z.lib). zig-libs
  # before the tree: rzig searches them in that order too (environment.zig).
  pcp <- Sys.getenv("PKG_CONFIG_PATH")
  pcp <- if (nzchar(pcp)) strsplit(pcp, ";", fixed = TRUE)[[1]] else file.path(rhome, "../..", c("lib/pkgconfig", "share/pkgconfig"))
  if (nzchar(envdir)) pcp <- c(pcp, file.path(envdir, c("lib/pkgconfig", "share/pkgconfig")))
  zpc <- if (nzchar(zig_libs)) file.path(zig_libs, "lib/pkgconfig")
  # R_TOOLS_SOFT: zig-libs when it has zig-gdal (its share/gdal and
  # share/proj match zig-gdal's and zig-proj's libraries), else the tree
  # (CRAN's aarch64 LOCAL_SOFT: share/gdal and share/proj match its PROJ)
  Sys.setenv(R_ZIG_FALLBACK_SOFT = tree,
             R_TOOLS_SOFT = if (!is.null(zpc) && "zig-gdal" %in% have) zig_libs else tree,
             PKG_CONFIG_PATH = paste(unique(c(zpc, file.path(tree, "lib/pkgconfig-closed"), pcp)), collapse = ";"))
  served <- names(rtools_has)[file.exists(file.path(tree, "lib", paste0("lib", rtools_has, ".a")))]
  served <- intersect(sysdeps_missing, served)
  sysdeps_missing <- setdiff(sysdeps_missing, served)
  info$sysdeps_missing <- paste(sysdeps_missing, collapse = " ")
  # whether this rzig knows the variable (build 11's ignores it): its
  # trace names the tree as an environment, `(fallback)`
  rt_cc <- file.path(rhome, "bin/toolchain/gcc.exe")
  old_trace <- Sys.getenv("RZIG_TRACE", unset = NA)
  Sys.setenv(RZIG_TRACE = "1")
  tr <- tryCatch(suppressWarnings(system2(rt_cc, "--version", stdout = TRUE, stderr = TRUE)), error = function(e) character())
  if (is.na(old_trace)) Sys.unsetenv("RZIG_TRACE") else Sys.setenv(RZIG_TRACE = old_trace)
  used <- any(grepl("environment .*\\(fallback\\)", tr))
  info$rtools_libs <- sprintf("Rtools45 tree %s (sha256 %s), %s; sysdeps from it: %s; rzig %s; PKG_CONFIG_PATH: %sthe tree's closed .pc first",
                              rtools_tarball$name, substr(rtools_tarball$sha256, 1, 12), tree,
                              if (length(served)) paste(served, collapse = " ") else "none",
                              if (used) "uses it (R_ZIG_FALLBACK_SOFT)" else "does NOT use it: an rzig without R_ZIG_FALLBACK_SOFT",
                              if (!is.null(zpc)) "zig-libs', then " else "")
  message("stress: fallback: ", info$rtools_libs)
}

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
# the most specific key wins: os-arch= (R's arch: windows-aarch64=), then
# os=, then a bare value, the default for every other platform
expected <- function(e) {
  e <- words(e)
  if (!length(e)) return("?")
  for (k in c(paste0(os, "-", arch), os)) {
    hit <- e[startsWith(e, paste0(k, "="))]
    if (length(hit)) return(sub(".*=", "", hit[1]))
  }
  bare <- e[!grepl("=", e)]
  if (length(bare)) bare[1] else "?"
}
tarball <- function(p) {
  f <- list.files(file.path(out, "src"), paste0("^", p, "_.*\\.tar\\.gz$"), full.names = TRUE)
  if (length(f)) return(f[1])
  r <- retry(function() download.packages(p, file.path(out, "src"), available = db, type = "source", quiet = TRUE))
  if (inherits(r, "error") || !NROW(r)) return(NA_character_)
  r[1, 2]
}
# A row tagged local is no CRAN package: stress.R writes it, a fresh copy
# before each of its STRESS_REPEAT installs, as R unpacks a tarball for
# each. tinyjobs is 64 one-line C files, built at the row's -j: tier1.zig's
# pool starts and ends many quick jobs, install after install, which
# guards its lifetime rule, `defer sel.cancelDiscard()` (feat-tier1-engine).
tiny_pkg <- function(p, n = 64L) {
  d <- file.path(out, "src", p)
  unlink(d, recursive = TRUE)
  dir.create(file.path(d, "src"), recursive = TRUE)
  writeLines(c(paste("Package:", p), "Version: 0.1", "Title: Many Tiny Compiles", "Description: Written by stress.R.",
               "License: GPL-3", "Author: r-zig", "Maintainer: r-zig <r-zig@example.invalid>"), file.path(d, "DESCRIPTION"))
  writeLines(sprintf("useDynLib(%s)", p), file.path(d, "NAMESPACE"))
  for (k in seq_len(n)) writeLines(c("#include <Rinternals.h>", sprintf("SEXP f%d(void) { return ScalarInteger(%d); }", k, k)),
                                   file.path(d, "src", sprintf("f%d.c", k)))
  d
}

# The report's zig-libs column (libs-zig-pixi DESIGN 7, item 8): a target's
# zig-* sysdeps, its row's and its dependencies' rows' (sf: s2's
# zig-abseil), each with its version and build from conda-meta, "Rtools
# tree" when the fallback tree stands in for it, or "missing"; then, from a
# --trace log (rzig's `lib -l<n> <file>` lines, windows.zig), the -l names
# that resolved into zig-libs and into the fallback tree. A target whose
# zig-* sysdeps are missing and not served gets the expect ?: its
# packages.tsv expect assumes them (before M5, every tree leg and a conda
# leg without --libs-channel).
row_zig <- function(name) {
  d <- c(name, if (name %in% rownames(db)) unlist(tools::package_dependencies(name, db = db, which = hard, recursive = TRUE)))
  r <- tab[tab$name %in% d & vapply(tab$oses, function(x) any(words(x) %in% c("all", os)), NA), ]
  z <- unique(unlist(lapply(r$sysdeps, on_os)))
  sort(z[startsWith(z, "zig-")])
}
zig_column <- function(z, log) {
  if (!length(z)) return("")
  b <- vapply(z, function(n) {
    m <- meta(paste0("^", gsub(".", "\\.", n, fixed = TRUE), "-[^-]+-[^-]+\\.json$"))
    if (length(m)) sub("^(.*)-([^-]+)-([^-]+)$", "\\1 \\2 \\3", m[1]) else if (n %in% served) paste(n, "Rtools tree") else paste(n, "missing")
  }, "")
  if (!file.exists(log)) return(paste(b, collapse = ", "))      # not installed (skipped, unavailable)
  x <- grep(": lib -l[^ ]+ ", read_log(log), value = TRUE)
  lib <- sub(".*: lib -l([^ ]+) .*", "\\1", x)
  file <- chartr("\\", "/", sub(".*: lib -l[^ ]+ ", "", x))
  where <- function(dir) if (nzchar(dir)) unique(lib[startsWith(tolower(file), tolower(paste0(dir, "/")))]) else character()
  zl <- unique(lib[grepl("/zig-libs/", file, fixed = TRUE)])
  fb <- where(if (is.null(rt_tree)) "" else file.path(rt_tree, "lib"))
  paste0(paste(b, collapse = ", "),
         if (!length(x)) "; -l: no trace" else sprintf("; -l from zig-libs: %s; from the fallback tree: %s",
                                                       if (length(zl)) paste(zl, collapse = " ") else "none",
                                                       if (length(fb)) paste(fb, collapse = " ") else "none"))
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
              status = "", class = "", minutes = 0, size_mb = NA, first_error = "", log = paste0("logs/", id, ".log"),
              loads = NA, zig_libs = "")
  rz <- if (it$target) row_zig(it$name) else character()
  if (length(intersect(rz, sysdeps_missing))) rec$expect <- "?"
  rec <- tryCatch({
    vlib <- if (nzchar(it$variant)) file.path(out, paste0("lib-", it$variant)) else lib
    dir.create(vlib, showWarnings = FALSE)
    env <- c(R_LIBS = paste(unique(c(vlib, lib)), collapse = .Platform$path.sep), if (nrow(row)) row_env(row$env))
    minutes <- if (nrow(row)) as.numeric(row$timeout_min) else 30
    bad_deps <- if (it$name %in% rownames(db)) intersect(unlist(tools::package_dependencies(it$name, db = db, which = hard, recursive = TRUE)), failed) else character()
    message(sprintf("[%d/%d] %s ...", i, nrow(items), it$package))
    installed <- flag("resume") && file.exists(file.path(vlib, it$name, "DESCRIPTION"))
    local_row <- nrow(row) && "local" %in% on_os(row$tags)
    src <- NA_character_
    if (installed) {
      rec$class <- "resumed"
    } else if (!local_row && !it$name %in% rownames(db)) {
      rec$status <- "unavailable"; rec$class <- "network"; rec$first_error <- "not in CRAN or Bioconductor for this R"
    } else if (length(bad_deps)) {
      rec$status <- "skipped"; rec$class <- "dependency"; rec$first_error <- paste("failed dependency:", paste(bad_deps, collapse = " "))
    } else if (is.na(src <- if (local_row) tiny_pkg(it$name) else tarball(it$name))) {
      rec$status <- "download-failed"; rec$class <- "network"; rec$first_error <- "download.packages failed 3 times"
    } else {
      reps <- if (local_row) as.integer(env[["STRESS_REPEAT"]]) else 1L
      took <- 0
      for (k in seq_len(reps)) {                               # until the first failure
        if (k > 1) tiny_pkg(it$name)
        for (attempt in 1:3) {                                 # more tries only for a network failure
          r <- run(c("CMD", "INSTALL", shQuote(paste0("--library=", vlib)), shQuote(src)), log, minutes, env)
          fe <- first_error(log)
          if (r$status == 0 || r$status == 124 || attempt == 3 || classify(fe$text) != "network") break
          file.rename(log, sub("\\.log$", paste0("-attempt", attempt, ".log"), log))
          Sys.sleep(c(30, 90)[attempt])
        }
        took <- took + r$minutes
        if (r$status != 0) break
      }
      unlink(Sys.glob(file.path(vlib, "00LOCK-*")), recursive = TRUE)   # left by a killed install
      rec$minutes <- took
      if (reps > 1 && r$status != 0) fe$line <- sprintf("install %d of %d: %s", k, reps, fe$line)
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
      # load every package; targets also run their smoke call. Then unload
      # it, as R CMD check does (here a warning, such as a failed .onUnload,
      # is an error), and let R exit: a crash in either is how Z9 shows on
      # linux (results/2026-10-08.md). gc() before the unload: the smoke
      # call's objects run their finalizers while the package's code is
      # still loaded, not after its .onUnload unloaded the DLL (a false
      # crash). The markers (stderr, unbuffered) tell which step failed. In
      # a file: no quoting issues on any OS.
      smoke <- if (nrow(row) && nzchar(row$smoke) && row$smoke != "-") row$smoke else "TRUE"
      marks <- paste("stress:", c("loaded", "smoke ok", "unloaded"))
      sf <- file.path(out, "smoke", paste0(id, ".R"))
      writeLines(c(sprintf("suppressPackageStartupMessages(library(%s))", it$name), sprintf("message(\"%s\")", marks[1]),
                   sprintf("res <- local(%s)", smoke), "print(res)", "if (isFALSE(res)) stop(\"the smoke call returned FALSE\")",
                   "rm(res); invisible(gc())", sprintf("message(\"%s\")", marks[2]), "options(warn = 2)",
                   sprintf("unloadNamespace(\"%s\")", it$name), sprintf("message(\"%s\")", marks[3])), sf)
      slog <- sub("\\.log$", "-smoke.log", log)
      # 10 min: rstan's smoke call compiles a Stan model (1.5 min on linux in round 1)
      s <- run(c("--vanilla", "--no-echo", shQuote(paste0("--file=", sf))), slog, 10, env)
      seen <- marks %in% trimws(read_log(slog))
      if (s$status == 0 && all(seen)) rec$status <- "ok" else {
        step <- if (!seen[2]) "smoke" else if (!seen[3]) "unload" else "exit"
        fe <- first_error(slog, after = switch(step, unload = marks[2], exit = marks[3]))
        rec$status <- if (step == "smoke" && s$status == 124) "timeout" else paste0(step, "-failed")
        # a signal (unix: 128 + its number) or a Windows exception code (< 0)
        rec$class <- if (s$status == 124) "timeout" else if (s$status >= 128 || s$status < 0) "crash" else classify(fe$text)
        rec$first_error <- if (nzchar(fe$line)) fe$line else sprintf("R exited with status %s", s$status)
        # it loaded, and the smoke call, the unload or the exit failed: its dependents still install
        rec$loads <- seen[1]
      }
    }
    rec$zig_libs <- zig_column(rz, log)
    rec
  }, error = function(e) { rec$status <- "error"; rec$class <- "harness"; rec$first_error <- conditionMessage(e); rec })
  # anything but ok skips the package's dependents, except a package that
  # loaded (its smoke call, unload or exit failed); variants live in their
  # own library: nothing depends on them
  if (rec$status != "ok" && !nzchar(it$variant) && !isTRUE(rec$loads)) failed <- c(failed, it$name)
  message(sprintf("[%d/%d] %s: %s%s (%s min)", i, nrow(items), it$package, rec$status,
                  if (nzchar(rec$class) && rec$status != "ok") paste0(", ", rec$class) else "", rec$minutes))
  results[[i]] <- rec
  write_report()
  # what a build left in TMPDIR (s2's abseil prefix, a killed build's tree)
  unlink(list.files(tmp, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE)
}

# what the run added to rzig's cache, and the cache itself if the run made
# it; unlink() removes a symlink (the libc++ mirror's), not what it points to
added <- setdiff(list.files(rzig_cache, all.files = TRUE, no.. = TRUE), rzig_cache_old)
unlink(c(file.path(rzig_cache, added), if (!rzig_cache_had) rzig_cache), recursive = TRUE)
info$rzig_cache_removed <- paste(added, collapse = " ")
res <- write_report(final = TRUE)
writeLines(readLines(file.path(out, "report.md")))
message("report: ", file.path(out, "report.md"))
quit(status = if (flag("strict") && any(res$unexpected)) 1 else 0)
