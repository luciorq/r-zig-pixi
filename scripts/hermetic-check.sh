#!/usr/bin/env bash
# Tier-0/1 hermetic check (feat-no-host-paths PLAN.md, phase A6): the
# standalone tree must start R and install packages that need no
# compiling with nothing from the machine but /bin/sh. Runs a copy of the
# installed tree (zig-build.sh's prefix: the tree that ships, F1) in a
# temporary directory, with an empty environment and PATH set to the
# tree's own bin/ only, then:
#   - starts R (osVersion must be set: it used to come from `uname`),
#   - installs two R-only source packages, one at a time and with
#     Ncpus = 2 (no make on PATH), builds a binary package with
#     --build, installs that binary and removes everything again,
#   - the install preflight (patch 0009): a package with C code stops
#     in it with rzig's text for the compilers group, since the tree is
#     the base alone (rzig, no zig and no build tools;
#     feat-standalone-toolchain B26, B35); unix: R CMD config CC fails
#     with rzig's text for the build tools (patch 0010),
#   - installs R6 from CRAN when it is reachable (download, TLS, R's
#     internal untar),
#   - Windows: loads tcltk, whose Tcl/Tk must then come from the tree's
#     own R_HOME/Tcl,
#   - requires R to have removed its session temp directories.
# On linux, where strace can trace, every program started must be
# /bin/sh, one of R's own launchers or rzig (the preflight's check mode):
# an undeclared tool fails the job even when R swallows the error
# (Sys.which() returning "", a temp directory left behind). strace comes
# from the env (pixi.toml); in CI a missing or blocked strace fails the
# check (cannot_check).
#
# Windows: R starts programs without a shell (CreateProcess), so there is
# no /bin/sh to allow. The environment keeps only what Windows itself
# needs (SYSTEMROOT, WINDIR) and PATH is R's bin\x64 plus System32. The
# binary package comes from CRAN (win.binary), since --build needs an
# external zip there. No execve trace: the empty PATH is the check, as on
# macOS.
#
# The installed tree, not the archive (F1.6, F1.7): it is the tree that
# ships on every OS, so CI runs this before packaging, and the copy proves
# the same relocation. zig build installs the env's runtime data into it
# (unix: the CA bundle and R_ZIG_CA_BUNDLE, so the CRAN step here goes
# through the shipped trust rule; Windows: Tcl/Tk) and zig-build.sh's
# vendor-libs.sh copies the env's shared libraries (Windows: conda's DLLs
# into bin/x64) after every build; package-standalone.sh only archives it.
# verify-bundle.sh runs it once more on the extracted base archive
# (R_INSTALL_PREFIX; PHASE3 section 8, scenario 1).
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/verify-helpers.sh"

case "$OS" in
  linux|macos|windows) ;;
  *) echo "hermetic-check: unsupported OS '$OS'" >&2; exit 1 ;;
esac
TREE="$PREFIX"
command -v cygpath > /dev/null 2>&1 && TREE="$(cygpath -u "$TREE")"
rh="$RH"
test -d "$TREE/$rh" || { echo "error: no R tree at $TREE; run 'pixi run build' first" >&2; exit 1; }
# Resolved, so that cp -a below copies the directory and not a symlink
# to it (which would put R back in its original place).
TREE="$(cd "$TREE" && pwd -P)"
# Windows: with PATH reduced to bin\x64 and System32 below, R.dll's conda
# DLLs must sit in bin/x64, where vendor-libs.sh copies them after every
# build; without them Rscript.exe fails with only a loader error. (The
# whole closure is verify-tree.sh's.)
if [ "$OS" = windows ]; then
  missing=""
  for d in $(needed_of "$TREE/$rh/bin/x64/R.dll"); do
    [ -f "$TREE/$rh/bin/x64/$d" ] || win_system_dll "$d" || missing="$missing $d"
  done
  if [ -n "$missing" ]; then
    echo "error: R.dll's DLLs are not in $rh/bin/x64:$missing; run 'pixi run build' (zig-build.sh runs vendor-libs.sh after zig build)" >&2
    exit 1
  fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A copy: R must not rely on the place it was built in. It is the base
# as it ships, R_HOME/bin/toolchain holding rzig alone (B19, B30):
# nothing is removed from it (B26: the preflight asks rzig what is
# missing).
cp -a "$TREE" "$WORK/"
T="$WORK/$(basename "$TREE")"
if [ "$OS" = windows ]; then
  R_BINDIR="$T/Library/lib/R/bin/x64"
  R_START=("$R_BINDIR/Rscript.exe" --vanilla check.R)
  sysdir="$(cygpath -u "${SYSTEMROOT:-C:\Windows}")"
  w() { cygpath -w "$1"; }
  HERMETIC_ENV=(SYSTEMROOT="$(w "$sysdir")" WINDIR="$(w "$sysdir")"
    USERPROFILE="$(w "$WORK")" HOME="$(w "$WORK")" LOCALAPPDATA="$(w "$WORK")"
    TMPDIR="$(w "$WORK/tmp")" TMP="$(w "$WORK/tmp")" TEMP="$(w "$WORK/tmp")"
    PATH="$R_BINDIR:$sysdir/System32")
else
  R_BINDIR="$T/bin"
  R_START=("$T/bin/R" --vanilla --no-echo -f check.R)
  HERMETIC_ENV=(HOME="$WORK" TMPDIR="$WORK/tmp" PATH="$T/bin")
fi
test -x "${R_START[0]}" || { echo "error: ${R_START[0]} missing from the copied tree" >&2; exit 1; }
mkdir -p "$WORK/lib" "$WORK/tmp" "$WORK/pk"

for p in hermeticA hermeticB hermeticSrc; do
  mkdir -p "$WORK/pk/$p/R"
  printf 'Package: %s\nVersion: 0.1\nTitle: Hermetic Check\nDescription: Tier-1 test package.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$p" > "$WORK/pk/$p/DESCRIPTION"
  echo 'export(hi)' > "$WORK/pk/$p/NAMESPACE"
  echo 'hi <- function() "hi"' > "$WORK/pk/$p/R/hi.R"
done
mkdir -p "$WORK/pk/hermeticSrc/src"
echo 'int hermetic_one(void) { return 1; }' > "$WORK/pk/hermeticSrc/src/one.c"
# No configure script with a marker (configure_marker,
# verify-helpers.sh): with the base alone the install's R CMD config
# (patch 0010) fails before a configure would run, wherever the
# preflight sits, so the marker could not tell. verify-bundle.sh's
# scenario 3 tells the order (B26, C26).

cat > "$WORK/check.R" <<'RCODE'
stopifnot(!is.null(utils::osVersion), nzchar(utils::osVersion))
stopifnot(!nzchar(Sys.which("make")))   # the scenario is the base alone: no build tools
windows <- .Platform$OS.type == "windows"
lib <- normalizePath("lib")
.libPaths(c(lib, .libPaths()))
repo <- "https://cloud.r-project.org"
online <- tryCatch(length(curlGetHeaders(repo)) > 0L, error = function(e) FALSE)
if (!windows) {
    install.packages("pk/hermeticA", repos = NULL, type = "source", lib = lib,
                     INSTALL_opts = "--build")
    ## linux: hermeticA_0.1_R_<platform>.tar.gz; macOS: hermeticA_0.1.tgz
    bin <- list.files(".", "^hermeticA_0[.]1(_R_.*[.]tar[.]gz|[.]tgz)$")
    stopifnot(length(bin) == 1L)
    remove.packages("hermeticA", lib = lib)
    install.packages(bin, repos = NULL, lib = lib)            # binary package
    stopifnot(hermeticA::hi() == "hi")
    remove.packages("hermeticA", lib = lib)
} else if (online) {
    ## binary package: CRAN's Windows build (it has a DLL; loads with our R.dll)
    install.packages("jsonlite", repos = repo, lib = lib, type = "win.binary")
    stopifnot(jsonlite::toJSON(1L) == "[1]")
    ## Windows cannot delete a DLL that is loaded: unload it first.
    dll <- getLoadedDLLs()[["jsonlite"]]
    unloadNamespace("jsonlite")
    if (!is.null(dll) && "jsonlite" %in% names(getLoadedDLLs()))
        dyn.unload(dll[["path"]])
    remove.packages("jsonlite", lib = lib)
    cat("CRAN: jsonlite win.binary installed and removed\n")
}
install.packages(c("pk/hermeticA", "pk/hermeticB"), repos = NULL,
                 type = "source", lib = lib, Ncpus = 2)
stopifnot(hermeticA::hi() == "hi", hermeticB::hi() == "hi")
remove.packages(c("hermeticA", "hermeticB"), lib = lib)
left <- list.files(lib)
if (length(left)) stop("left in the library after removal: ", paste(left, collapse = ", "))
## Negative test (phase T; feat-standalone-toolchain B26, B35): compiled
## code with the base alone stops in the preflight with rzig's text for
## the compilers group (no zig: nothing names one here), and R CMD config
## with its text for the build tools (no make).
out <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
                                c("CMD", "INSTALL", "-l", shQuote(lib), "pk/hermeticSrc"),
                                stdout = TRUE, stderr = TRUE))
if (is.null(attr(out, "status")) ||
    !any(startsWith(out, "Compiling needs the r-zig compilers for R ")) ||
    dir.exists(file.path(lib, "hermeticSrc")))
    stop("no compile preflight with rzig's compilers text:\n", paste(out, collapse = "\n"))
cat("preflight: compiled package stopped:", grep("^Compiling needs", out, value = TRUE), "\n")
if (!windows) {
    ## its exit status is rzig's, 127, which system2(stdout = TRUE) would
    ## turn into an R error: into a file instead
    log <- file.path(tempdir(), "config.log")
    st <- suppressWarnings(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "CC"),
                                   stdout = log, stderr = log))
    cfg <- readLines(log)
    if (st == 0L || !any(startsWith(cfg, "Building packages needs the r-zig build tools for R ")))
        stop("R CMD config without make: exit ", st, ", not rzig's build-tools text:\n", paste(cfg, collapse = "\n"))
    cat("R CMD config: exit", st, "with rzig's build-tools text:", grep("^Building packages", cfg, value = TRUE), "\n")
}
if (online) {
    install.packages("R6", repos = repo, lib = lib, type = "source")
    stopifnot(requireNamespace("R6", lib.loc = lib))
    remove.packages("R6", lib = lib)
    cat("CRAN: R6 installed from source and removed\n")
} else cat("CRAN: offline, skipped\n")
if (windows) {
    ## tcltk as the shipped tree loads it: MY_TCLTK is unset here, so
    ## .onLoad takes the Tcl/Tk DLLs from R_HOME/Tcl/bin, and Tcl finds its
    ## scripts beside them; with nothing on PATH but bin\x64 and System32,
    ## no other Tcl can stand in.
    library(tcltk)
    ## (case-insensitive, as Windows paths are)
    tcl_home <- tolower(normalizePath(R.home("Tcl"), "/"))
    for (lib in c(tclvalue(tcl("info", "library")), tclvalue(tcl("set", "tk_library"))))
        if (!startsWith(tolower(normalizePath(lib, "/")), paste0(tcl_home, "/")))
            stop("Tcl/Tk scripts from outside R_HOME/Tcl: ", lib)
    cat("tcltk: Tcl/Tk", tclvalue(tcl("info", "patchlevel")), "from R_HOME/Tcl\n")
}
cat("tier 0/1 scenario OK\n")
RCODE

run() {
  (cd "$WORK" && "$@" env -i "${HERMETIC_ENV[@]}" "${R_START[@]}")
}

strace_bin=""
if [ "$OS" = linux ] && command -v strace > /dev/null 2>&1 &&
   strace -f -qq -e trace=execve -o /dev/null /bin/true 2> /dev/null; then
  strace_bin="$(command -v strace)"
fi

if [ -n "$strace_bin" ]; then
  # strace itself runs outside env -i: the traced command is env, which
  # clears the environment and then starts R.
  run "$strace_bin" -f -qq -e trace=execve -o "$WORK/execve.tr"
  # Successful execs only: a failed one is either a PATH probe or a
  # shebang-less R CMD script (bin/INSTALL) that the shell then runs itself.
  started="$(grep 'execve(' "$WORK/execve.tr" | grep -v '= -1' | grep -o 'execve("[^"]*"' |
    sed 's/^execve("//; s/"$//' | sort -u)"
  bad=""
  while IFS= read -r prog; do
    case "$prog" in
      /bin/sh|"$T/bin/R"|"$T/bin/Rscript"|"$T/bin/../lib/R/bin/R"|"$T/lib/R/bin/R"|"$T/lib/R/bin/Rscript"|"$T/lib/R/bin/exec/R") ;;
      # rzig's check mode, which the preflight and R CMD config run as
      # R_HOME/bin/toolchain/zig-cc (bin/R resolves R_HOME, cd -P)
      "$T/lib/R/bin/toolchain/zig-cc") ;;
      "$(command -v env)"|/usr/bin/env|/bin/env) ;;   # the harness's own env -i
      *) bad="$bad $prog" ;;
    esac
  done <<< "$started"
  if [ -n "$bad" ]; then
    echo "error: tier 0/1 started programs outside R and /bin/sh:$bad" >&2
    exit 1
  fi
  echo "   programs started: $(echo "$started" | sed "s|$T|<tree>|g" | tr '\n' ' ')"
else
  run
  [ "$OS" != linux ] || cannot_check "strace unavailable or cannot trace; checked with an empty PATH only"
fi

left="$(ls -A "$WORK/tmp")"
if [ -n "$left" ]; then
  echo "error: R left temp directories behind: $left" >&2
  exit 1
fi
echo "== hermetic tier 0/1 verified ($OS/$FLAVOR): PATH=${R_BINDIR#$T/}${sysdir:+ + System32}, empty environment"
