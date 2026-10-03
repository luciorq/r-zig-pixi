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
#   - installs R6 from CRAN when it is reachable (download, TLS, R's
#     internal untar),
#   - requires R to have removed its session temp directories.
# On linux, where strace can trace, every program started must be
# /bin/sh or one of R's own launchers: an undeclared tool fails the job
# even when R swallows the error (Sys.which() returning "", a temp
# directory left behind).
#
# Windows: R starts programs without a shell (CreateProcess), so there is
# no /bin/sh to allow. The environment keeps only what Windows itself
# needs (SYSTEMROOT, WINDIR) and PATH is R's bin\x64 plus System32. The
# binary package comes from CRAN (win.binary), since --build needs an
# external zip there. No execve trace: the empty PATH is the check, as on
# macOS. The Windows tree runs on its own only once package-standalone.sh
# has vendored its DLLs into bin/x64 (vendor-libs.sh does that for unix
# at build time, not for Windows), so there this runs after `package`.
#
# The installed tree, not the archive (F1.6): CI runs this before
# packaging, and the copy proves the same relocation. It lacks only what
# package-standalone.sh adds (the CA bundle; fontconfig's configuration),
# which tier 0/1 does not need: without R_ZIG_CA_BUNDLE, libcurl keeps
# its compiled-in trust (the build env's) for the CRAN step here, and
# verify-bundle.sh checks the shipped trust on the archive.
. "$(dirname "$0")/env.sh"

case "$OS" in
  linux|macos|windows) ;;
  *) echo "hermetic-check: unsupported OS '$OS'" >&2; exit 1 ;;
esac
TREE="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
command -v cygpath > /dev/null 2>&1 && TREE="$(cygpath -u "$TREE")"
if [ "$OS" = windows ]; then rh="Library/lib/R"; else rh="lib/R"; fi
test -d "$TREE/$rh" || { echo "error: no R tree at $TREE; run 'pixi run build' first" >&2; exit 1; }
# Resolved, so that cp -a below copies the directory and not a symlink
# to it (which would put R back in its original place and let the
# toolchain removal hit the real tree).
TREE="$(cd "$TREE" && pwd -P)"
# Windows: package-standalone.sh vendors the DLLs R.dll needs (and
# creates R_HOME/Tcl on every run); without them Rscript.exe only fails
# with a loader error.
if [ "$OS" = windows ] && [ ! -d "$TREE/$rh/Tcl" ]; then
  echo "error: the Windows tree has no vendored DLLs/Tcl yet; run 'pixi run package' first" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A copy: the scenario removes the toolchain below, and R must not rely
# on the place it was built in.
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
# Tiers 0/1 are the base package: no toolchain (phase T). Remove the
# directory the toolchain package provides, so the scenario is exactly
# what a base-only install has, and so the compile preflight fires.
if [ "$OS" = windows ]; then rm -rf "$T/Library/lib/R/bin/toolchain"; else rm -rf "$T/lib/R/bin/toolchain"; fi

for p in hermeticA hermeticB hermeticSrc; do
  mkdir -p "$WORK/pk/$p/R"
  printf 'Package: %s\nVersion: 0.1\nTitle: Hermetic Check\nDescription: Tier-1 test package.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$p" > "$WORK/pk/$p/DESCRIPTION"
  echo 'export(hi)' > "$WORK/pk/$p/NAMESPACE"
  echo 'hi <- function() "hi"' > "$WORK/pk/$p/R/hi.R"
done
mkdir -p "$WORK/pk/hermeticSrc/src"
echo 'int hermetic_one(void) { return 1; }' > "$WORK/pk/hermeticSrc/src/one.c"

cat > "$WORK/check.R" <<'RCODE'
stopifnot(!is.null(utils::osVersion), nzchar(utils::osVersion))
stopifnot(!nzchar(Sys.which("make")))   # the scenario is "no toolchain"
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
## Negative test (phase T): compiled code without the toolchain stops with
## the preflight message, and R CMD config says make is missing.
out <- suppressWarnings(system2(file.path(R.home("bin"), "R"),
                                c("CMD", "INSTALL", "-l", shQuote(lib), "pk/hermeticSrc"),
                                stdout = TRUE, stderr = TRUE))
if (!any(grepl("r-zig toolchain is not installed", out, fixed = TRUE)) ||
    dir.exists(file.path(lib, "hermeticSrc")))
    stop("no compile preflight:\n", paste(out, collapse = "\n"))
cat("preflight: compiled package refused without the toolchain\n")
if (!windows) {
    cfg <- suppressWarnings(system2(file.path(R.home("bin"), "R"), c("CMD", "config", "CC"),
                                    stdout = TRUE, stderr = TRUE))
    if (is.null(attr(cfg, "status")) || !any(grepl("needs make", cfg, fixed = TRUE)))
        stop("R CMD config without make:\n", paste(cfg, collapse = "\n"))
    cat("R CMD config: fails cleanly without make\n")
}
if (online) {
    install.packages("R6", repos = repo, lib = lib, type = "source")
    stopifnot(requireNamespace("R6", lib.loc = lib))
    remove.packages("R6", lib = lib)
    cat("CRAN: R6 installed from source and removed\n")
} else cat("CRAN: offline, skipped\n")
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
  [ "$OS" = linux ] && echo "   note: strace unavailable; checked with an empty PATH only"
fi

left="$(ls -A "$WORK/tmp")"
if [ -n "$left" ]; then
  echo "error: R left temp directories behind: $left" >&2
  exit 1
fi
echo "== hermetic tier 0/1 verified ($OS/$FLAVOR): PATH=${R_BINDIR#$T/}${sysdir:+ + System32}, empty environment"
