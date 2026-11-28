#!/usr/bin/env bash
# Compares zigbuild/launchers/Rscript with R's compiled Rscript
# (src/unix/Rscript.c) case by case (b14-review B4):
#
#   bash zigbuild/launchers/rscript-test.sh <R_HOME of a reference R>
#
# The reference is an R installed by R's own make (conda-forge's r-base,
# for one), whose bin/Rscript is the compiled one. Both front ends run a
# stub bin/R in a scratch tree that prints the arguments and the
# variables it receives: the compiled one through RHOME, the launcher
# from its own location in that tree (lib/R/bin, bin, a symlink to it).
# Their stdout, stderr and exit status must be equal. Then a few cases
# run the reference's real R through both. The shell running the
# launcher is $SH (default /bin/sh).
set -u
ref=${1:?usage: rscript-test.sh <R_HOME of a reference R>}
ref=$(cd -P "$ref" && pwd)
here=$(cd -P "$(dirname "$0")" && pwd)
SH=${SH:-/bin/sh}
rs_ref=$ref/bin/Rscript
[ -x "$rs_ref" ] || rs_ref=$ref/../../bin/Rscript
if [ ! -x "$rs_ref" ] || [ "$(head -c 2 "$rs_ref")" = '#!' ]; then
  echo "rscript-test: $rs_ref is not a compiled Rscript" >&2; exit 2
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(cd -P "$T" && pwd)
home=$T/x/lib/R
mkdir -p "$home/bin" "$home/include" "$T/x/bin" "$T/link" "$T/wd"
cp "$ref/include/Rversion.h" "$home/include/"
cat > "$home/bin/R" <<'EOF'
#!/bin/sh
for a in "$@"; do printf 'arg [%s]\n' "$a"; done
for v in R_DEFAULT_PACKAGES R_HOME R_ARCH; do
  eval "if [ -n \"\${$v+set}\" ]; then printf '%s=[%s]\n' $v \"\$$v\"; else echo $v unset; fi"
done
exit 3
EOF
chmod +x "$home/bin/R"
for d in "$home/bin" "$T/x/bin"; do
  { printf '#!%s\n' "$SH"; tail -n +2 "$here/Rscript"; } > "$d/Rscript"
  chmod +x "$d/Rscript"
done
ln -s "$T/x/bin/Rscript" "$T/link/Rscript"

pass=0; fail=0
# run <name> <launcher> <env assignments...> -- <args...>
run_case() {
  local name=$1 ours=$2; shift 2
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  local clean=(-u R_DEFAULT_PACKAGES -u R_SCRIPT_DEFAULT_PACKAGES -u R_SCRIPT_LEGACY -u R_HOME -u RHOME -u R_ARCH)
  (cd "$T/wd" && env "${clean[@]}" RHOME="$home" ${envs[@]+"${envs[@]}"} "$rs_ref" "$@") > "$T/a.out" 2> "$T/a.err"; local ea=$?
  (cd "$T/wd" && env "${clean[@]}" ${envs[@]+"${envs[@]}"} "$ours" "$@") > "$T/b.out" 2> "$T/b.err"; local eb=$?
  if [ "$ea" = "$eb" ] && cmp -s "$T/a.out" "$T/b.out" && cmp -s "$T/a.err" "$T/b.err"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $name: exit $ea (Rscript.c) vs $eb (launcher)"
    diff "$T/a.out" "$T/b.out" | sed 's/^/  stdout /'
    diff "$T/a.err" "$T/b.err" | sed 's/^/  stderr /'
  fi
}
L=$home/bin/Rscript
c() { run_case "$1" "$L" "${@:2}"; }

c no-args --
c help -- --help
c version -- --version
c help-plus -- --help x.R
c version-plus -- --version x.R
c file -- x.R
c file-args -- x.R a b --c -e d
c file-space -- 'my file.R' 'an arg'
c file-empty -- ''
c file-dash -- -x a
c file-missing -- --vanilla
c file-missing-1 -- --a
c double-dash -- -- x.R
c opts-file -- --vanilla --no-environ x.R --x
c expr -- -e 1
c expr-args -- -e 'commandArgs(TRUE)' --foo x
c expr-two -- -e a -e b c
c expr-opt-between -- -e a --vanilla -e b
c expr-missing -- -e
c expr-missing-2 -- -e a -e
c expr-empty -- -e ''
c opts-expr -- --vanilla -e x y
c expr-dp-after -- -e x --default-packages=foo
c expr-then-file -- x.R -e y
c verbose-file -- --verbose x.R a
c verbose-expr -- --verbose -e x
c verbose-dp -- --verbose --default-packages=utils x.R
c dp-verbose -- --default-packages=utils --verbose x.R
c dp -- --default-packages=utils,stats -e x
c dp-null -- --default-packages=NULL -e x
c dp-empty -- --default-packages= -e x
c dp-odd -- --default-packagesXutils -e x
c dp-twice -- --default-packages=a --default-packages=b -e x
c shebang -- '--vanilla --default-packages=NULL' x.R a
c shebang-tabs -- "--vanilla  	--no-environ " 'my file.R' a
c shebang-one-trailing -- '--vanilla ' x.R
c shebang-help -- '--help --verbose'
c shebang-version-trailing -- '--version '
c shebang-help-alone -- '--help '
c shebang-expr -- '--vanilla -e' 'x' y
c shebang-glob -- '--a * --b' x.R
c not-shebang -- 'x.R --vanilla' a
c specials -- -e 'cat("a\\nb")' '*' '\t' '$HOME' '`id`' "it's" '-n' '-e'
c newline -- -e "$(printf 'a\nb')" "$(printf 'c\nd')"
c env-sdp R_SCRIPT_DEFAULT_PACKAGES=stats -- -e x
c env-sdp-empty R_SCRIPT_DEFAULT_PACKAGES= -- -e x
c env-sdp-cmd R_SCRIPT_DEFAULT_PACKAGES=stats -- --default-packages=utils -e x
c env-sdp-dp R_SCRIPT_DEFAULT_PACKAGES=stats R_DEFAULT_PACKAGES=foo -- -e x
c env-dp R_DEFAULT_PACKAGES=foo -- -e x
c env-legacy R_SCRIPT_LEGACY=yes -- -e x
c env-legacy-dp R_SCRIPT_LEGACY=yes R_DEFAULT_PACKAGES=foo -- -e x
c env-legacy-dpempty R_SCRIPT_LEGACY=yes R_DEFAULT_PACKAGES= -- -e x
c env-legacy-cmd R_SCRIPT_LEGACY=yes -- --default-packages=utils -e x
c env-legacy-no R_SCRIPT_LEGACY=no -- -e x
c env-legacy-sdp R_SCRIPT_LEGACY=yes R_SCRIPT_DEFAULT_PACKAGES=stats -- -e x
c env-rhome R_HOME=/elsewhere -- -e x
# An empty RHOME is ignored: Rscript.c then runs its compiled-in R_HOME,
# the launcher its own tree.
if env RHOME= "$L" -e x 2>&1 | grep -qx 'arg \[x\]'; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL env-rhome-empty: the launcher did not run its own bin/R"; fi
# R_HOME naming the launcher's own tree through a symlink, with a
# trailing "/", or as its bin/R's physical path: unset before bin/R runs
# (this tree's bin/R compares R_HOME physically and would not warn, but
# an RHOME tree's bin/R that compares strings would, for the first two).
# Launcher only: the compiled Rscript passes R_HOME on unchanged.
ln -s "$T/x" "$T/xlink"
for rh in "$T/xlink/lib/R" "$home/" "$home" "$T/x/lib/R/bin/.."; do
  if env -u RHOME R_HOME="$rh" "$L" -e x 2>&1 | grep -qx 'R_HOME unset'; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL env-rhome-same $rh: R_HOME reached bin/R"; fi
done
# ... and through RHOME's tree; an R_HOME that does not exist is passed on.
if env R_HOME="$T/xlink/lib/R/" RHOME="$home" "$L" -e x 2>&1 | grep -qx 'R_HOME unset'; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL env-rhome-same-rhome: R_HOME reached bin/R"; fi
if env -u RHOME R_HOME="$T/none" "$L" -e x 2>&1 | grep -qxF "R_HOME=[$T/none]"; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL env-rhome-missing: R_HOME not passed on"; fi
run_case prefix-bin "$T/x/bin/Rscript" -- --verbose -e x a
run_case symlink "$T/link/Rscript" -- --verbose x.R a
run_case symlink-version "$T/link/Rscript" -- --version
# RHOME names another tree: both run its bin/R
mkdir -p "$T/y/bin"; cp "$home/bin/R" "$T/y/bin/R"
run_case rhome-other "$L" RHOME="$T/y" -- --verbose -e x
run_case rhome-missing "$L" RHOME="$T/none" -- -e x

# The reference's real R through both front ends (RHOME points the
# launcher at it).
real() {
  local name=$1; shift
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  local clean=(-u R_DEFAULT_PACKAGES -u R_SCRIPT_DEFAULT_PACKAGES -u R_SCRIPT_LEGACY -u R_HOME -u RHOME)
  (cd "$T/wd" && env "${clean[@]}" ${envs[@]+"${envs[@]}"} "$rs_ref" "$@") > "$T/a.out" 2> "$T/a.err"; local ea=$?
  (cd "$T/wd" && env "${clean[@]}" RHOME="$ref" ${envs[@]+"${envs[@]}"} "$L" "$@") > "$T/b.out" 2> "$T/b.err"; local eb=$?
  if [ "$ea" = "$eb" ] && cmp -s "$T/a.out" "$T/b.out" && cmp -s "$T/a.err" "$T/b.err"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL real $name: exit $ea (Rscript.c) vs $eb (launcher)"
    diff "$T/a.out" "$T/b.out" | sed 's/^/  stdout /'
    diff "$T/a.err" "$T/b.err" | sed 's/^/  stderr /'
  fi
}
printf 'cat(commandArgs(), sep = "\\n"); quit(status = 4)\n' > "$T/wd/s.R"
printf '#!%s --vanilla --default-packages=utils\ncat(search(), sep = "\\n")\n' "$L" > "$T/wd/sb.R"
real r-expr-args -- -e 'print(commandArgs(TRUE))' --foo x
real r-file -- --vanilla s.R a --b
real r-sdp R_SCRIPT_DEFAULT_PACKAGES=NULL -- -e 'cat(search(), sep = "\n")'
real r-dp -- --default-packages=stats -e 'cat(search(), sep = "\n")'
real r-shebang -- '--vanilla --default-packages=utils' sb.R
real r-version -- --version
real r-error -- -e 'stop("boom")'

echo "rscript-test ($SH): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
