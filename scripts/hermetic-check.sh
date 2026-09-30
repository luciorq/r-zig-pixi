#!/usr/bin/env bash
# Tier-0/1 hermetic check (feat-no-host-paths PLAN.md, phase A6): the
# packaged standalone tree must start R and install packages that need
# no compiling with nothing from the machine but /bin/sh. Runs the
# extracted artifact with an empty environment and PATH set to the
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
# directory left behind). Unix only for now; Windows starts programs
# without a shell already.
. "$(dirname "$0")/env.sh"

case "$OS" in
  linux)
    case "$(uname -m)" in x86_64) plat=linux-64 ;; aarch64) plat=linux-aarch64 ;; *) plat="linux-$(uname -m)" ;; esac ;;
  macos)
    case "$(uname -m)" in arm64) plat=osx-arm64 ;; x86_64) plat=osx-64 ;; *) plat="osx-$(uname -m)" ;; esac ;;
  *)
    echo "hermetic-check: unix only" >&2; exit 0 ;;
esac
export R_INSTALL_PREFIX="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"
artifact="$ROOT/dist/R-$R_VERSION-$FLAVOR-$plat.tar.gz"
test -f "$artifact" || { echo "error: $artifact not found; run 'pixi run package' first" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$artifact" -C "$WORK"
T="$WORK/$(basename "$R_INSTALL_PREFIX")"
test -x "$T/bin/R" || { echo "error: $T/bin/R missing from the extracted tree" >&2; exit 1; }
mkdir -p "$WORK/lib" "$WORK/tmp" "$WORK/pk"

for p in hermeticA hermeticB; do
  mkdir -p "$WORK/pk/$p/R"
  printf 'Package: %s\nVersion: 0.1\nTitle: Hermetic Check\nDescription: Tier-1 test package.\nLicense: MIT\nAuthor: r-zig\nMaintainer: r-zig <r-zig@example.org>\n' "$p" > "$WORK/pk/$p/DESCRIPTION"
  echo 'export(hi)' > "$WORK/pk/$p/NAMESPACE"
  echo 'hi <- function() "hi"' > "$WORK/pk/$p/R/hi.R"
done

cat > "$WORK/check.R" <<'RCODE'
stopifnot(!is.null(utils::osVersion), nzchar(utils::osVersion))
stopifnot(!nzchar(Sys.which("make")))   # the scenario is "no toolchain"
lib <- normalizePath("lib")
.libPaths(c(lib, .libPaths()))
install.packages("pk/hermeticA", repos = NULL, type = "source", lib = lib,
                 INSTALL_opts = "--build")
## linux: hermeticA_0.1_R_<platform>.tar.gz; macOS: hermeticA_0.1.tgz
bin <- list.files(".", "^hermeticA_0[.]1(_R_.*[.]tar[.]gz|[.]tgz)$")
stopifnot(length(bin) == 1L)
remove.packages("hermeticA", lib = lib)
install.packages(bin, repos = NULL, lib = lib)            # binary package
stopifnot(hermeticA::hi() == "hi")
install.packages(c("pk/hermeticA", "pk/hermeticB"), repos = NULL,
                 type = "source", lib = lib, Ncpus = 2)
stopifnot(hermeticB::hi() == "hi")
remove.packages(c("hermeticA", "hermeticB"), lib = lib)
stopifnot(!length(list.files(lib)))
repo <- "https://cloud.r-project.org"
online <- tryCatch(length(curlGetHeaders(repo)) > 0L, error = function(e) FALSE)
if (online) {
    install.packages("R6", repos = repo, lib = lib, type = "source")
    stopifnot(requireNamespace("R6", lib.loc = lib))
    remove.packages("R6", lib = lib)
    cat("CRAN: R6 installed from source and removed\n")
} else cat("CRAN: offline, skipped\n")
cat("tier 0/1 scenario OK\n")
RCODE

run() {
  (cd "$WORK" && env -i HOME="$WORK" TMPDIR="$WORK/tmp" PATH="$T/bin" "$@" \
    "$T/bin/R" --vanilla --no-echo -f check.R)
}

strace_bin=""
if [ "$OS" = linux ] && command -v strace > /dev/null 2>&1 &&
   strace -f -qq -e trace=execve -o /dev/null /bin/true 2> /dev/null; then
  strace_bin="$(command -v strace)"
fi

if [ -n "$strace_bin" ]; then
  # strace itself runs outside env -i: the traced command is env, which
  # clears the environment and then starts R.
  (cd "$WORK" && "$strace_bin" -f -qq -e trace=execve -o "$WORK/execve.tr" \
    env -i HOME="$WORK" TMPDIR="$WORK/tmp" PATH="$T/bin" \
    "$T/bin/R" --vanilla --no-echo -f check.R)
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
echo "== hermetic tier 0/1 verified ($OS/$FLAVOR): PATH=<tree>/bin, empty environment"
