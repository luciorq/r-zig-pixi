#!/usr/bin/env bash
# Milestone 5 entry point: build R entirely with zig build (no autoconf, no
# make). Wraps `zig build` so the zig cache lands in the workspace and the
# prefix matches the layout the make-driven pipeline used.
. "$(dirname "$0")/env.sh"

# (macOS fd ulimit for zig's linker opening ~300 libR objects at once is
# already raised unconditionally by env.sh, sourced above.)

# On Windows, conda-forge's own `zig` is only ever installed as
# Library/bin/zig.cmd|.bat — native cmd.exe/PowerShell resolve those via
# PATHEXT automatically, but MSYS bash (what this script runs under) does
# not, so a bare `zig` fails with "command not found" even though it's on
# PATH. Same fallback toolchain/zig-cc already uses for the same reason.
ZIG="${ZIG_BIN:-$(command -v zig || command -v x86_64-w64-mingw32-zig)}"

PREFIX_ZIG="${R_INSTALL_PREFIX:-$ROOT/dist/R-$R_VERSION-$FLAVOR-zig}"

# --- R source patches (feat-no-host-paths PLAN.md, phase A2) ---------------
# Each one keeps a tier-0/1 operation (start, exit, install without
# compiling) from running an external program through /bin/sh. They are
# compiled into base.rdb/tools.rdb/utils.rdb or libR, so they have to be
# applied here, before bootstrap. Idempotent via an "r-zig" marker.

# Sys.which(): scan PATH in R, as Windows' do_syswhich does in C, instead
# of running `which` through /bin/sh once per name (upstream records the
# capture machine's `which` path as @WHICH@). The first match that is
# executable and not a directory, like `which`; a name containing "/" is
# checked as given. Replaces the whole function, including the earlier
# bin/toolchain/which patch in trees that already carry it.
sw="$SRC_DIR/src/library/base/R/unix/system.unix.R"
if [ -f "$sw" ] && ! grep -q 'r-zig: PATH scan' "$sw"; then
  sys_which_repl=$(cat <<'RCODE'
Sys.which <- function(names)
{
    ## r-zig: PATH scan in R (no /bin/sh, no `which`)
    res <- character(length(names)); names(res) <- names
    path <- Sys.getenv("PATH")
    dirs <- if (nzchar(path)) strsplit(path, ":", fixed = TRUE)[[1L]] else character()
    dirs[!nzchar(dirs)] <- "."
    for(i in seq_along(names)) {
        if(is.na(names[i])) {res[i] <- NA; next}
        if(!nzchar(names[i])) next
        cand <- if(grepl("/", names[i], fixed = TRUE)) names[i]
                else file.path(dirs, names[i])
        ok <- file.access(cand, 1L) == 0L & !dir.exists(cand)
        if(any(ok)) res[i] <- cand[ok][1L]
    }
    res
}
RCODE
  )
  awk -v repl="$sys_which_repl" '
    /^Sys\.which <- function\(names\)$/ { print repl; skip = 1; next }
    skip && /^}$/ { skip = 0; next }
    skip { next }
    { print }
  ' "$sw" > "$sw.tmp" && mv "$sw.tmp" "$sw"
  grep -q 'r-zig: PATH scan' "$sw" || { echo "error: Sys.which patch did not apply to $sw" >&2; exit 1; }
fi

# osVersion: utils' .onLoad computes it at every start by running
# Sys.which("uname") and system("uname -a") only to learn the OS name.
# Sys.info() is the same uname(2) call, in-process (webR patches this
# function too). The "uname -a" text stays the fallback for other OSes.
si="$SRC_DIR/src/library/utils/R/sessionInfo.R"
if [ -f "$si" ] && ! grep -q 'r-zig: uname(2)' "$si"; then
  sed -i \
    -e "s|} else if (nzchar(Sys.which('uname'))) { ## we could try /usr/bin/uname|} else if (!is.null(s <- Sys.info())) { ## r-zig: uname(2) in-process|" \
    -e 's|uname <- system("uname -a", intern = TRUE)|uname <- paste(s[c("sysname", "nodename", "release", "version", "machine")], collapse = " ")|' \
    "$si"
  [ "$(grep -c 'r-zig: uname(2)\|uname <- paste(s\[' "$si")" = 2 ] || { echo "error: osVersion patch did not apply to $si" >&2; exit 1; }
fi

# Session temp directory: removed at exit with `rm -Rf` through
# R_system(), so /bin/sh + rm on every exit. R_unlink() is already the
# fallback for paths with shell-special characters and what Windows uses.
pf="$SRC_DIR/src/main/platform.c"
if [ -f "$pf" ] && ! grep -q 'r-zig: always R_unlink' "$pf"; then
  sed -i 's|^\tif (!hasspecial) {$|\tif (0 \&\& !hasspecial) { /* r-zig: always R_unlink(), no rm through the shell */|' "$pf"
  grep -q 'r-zig: always R_unlink' "$pf" || { echo "error: temp dir patch did not apply to $pf" >&2; exit 1; }
fi

# R CMD INSTALL (tools/R/install.R): on unix it moves the finished package
# into place, backs up and restores the previous version with `mv -f`, and
# installs binary packages with `cp -R .` (falling back to a tar pipe), all
# through the shell. The WINDOWS branches already do the same with
# file.rename()/file.copy()/unlink(); take them on every OS. The move keeps
# unix's patch_rpaths() step before it.
ir="$SRC_DIR/src/library/tools/R/install.R"
if [ -f "$ir" ] && ! grep -q 'r-zig: no mv' "$ir"; then
  awk '
    function next_line() { if ((getline nxt) <= 0) nxt = ""; return nxt }
    /^ *if ?\(WINDOWS\) \{$/ {
      line = $0; n = next_line()
      if (n ~ /file\.copy\(lp, dirname\(pkgdir\), recursive = TRUE,$/ ||
          n ~ /file\.copy\(instdir, lockdir, recursive = TRUE,$/) {
        sub(/WINDOWS/, "TRUE", line); line = line " # r-zig: no mv"
      } else if (n ~ /unlink\(final_instdir, recursive = TRUE\) # needed for file\.rename$/) {
        sub(/if ?\(WINDOWS\) \{$/, "if (!WINDOWS) patch_rpaths() # r-zig: no mv", line)
        match($0, /^ */); line = line "\n" substr($0, 1, RLENGTH) "if (TRUE) {"
      }
      print line; print n; next
    }
    /^ *system\(paste\("mv -f", shQuote\(instdir\),$/ {
      line = $0; n = next_line()
      if (n ~ /^ *shQuote\(file\.path\(lockdir, pkg\)\)\)\)$/) {
        match(line, /^ */)
        print substr(line, 1, RLENGTH) "file.rename(instdir, file.path(lockdir, pkg)) # r-zig: no mv"
      } else { print line; print n }
      next
    }
    /^ *TAR <- Sys\.getenv\("TAR", .tar.\)$/ {
      line = $0; n = next_line()
      if (n ~ /^ *res <- system\(paste\("cp -R \.", shQuote\(instdir\),$/) {
        while (n !~ /^ *\)\)$/ && n != "") n = next_line()
        match(line, /^ */); ind = substr(line, 1, RLENGTH)
        print ind "## r-zig: no cp/tar through the shell"
        print ind "res <- !all(file.copy(list.files(\".\", all.files = TRUE, no.. = TRUE),"
        print ind "                      instdir, overwrite = TRUE, recursive = TRUE,"
        print ind "                      copy.date = TRUE))"
      } else { print line; print n }
      next
    }
    { print }
  ' "$ir" > "$ir.tmp" && mv "$ir.tmp" "$ir"
  [ "$(grep -c 'r-zig: no mv' "$ir")" = 4 ] && grep -q 'r-zig: no cp/tar' "$ir" ||
    { echo "error: install.R patch did not apply to $ir" >&2; exit 1; }
fi

# Compile preflight (phase T: the toolchain is a separate package). A
# package needs it when it has compiled code (src/) or a configure
# script; without bin/toolchain/zig-cc (the toolchain package fills that
# directory, Makeconf points at it, and a package manager can leave it
# behind empty) and without the compiler Makeconf's CC names (an unstaged
# build tree, which CI's contract step uses, names the repo's
# toolchain/zig-cc directly), stop with one message naming the package
# to install, from R_ZIG_TOOLCHAIN_HINT, which each distribution sets in
# etc/Renviron, instead of failing deep in configure or make. A user
# Makevars (their own compiler) or R_ZIG_NO_PREFLIGHT skips the check.
# Inserted before the configure step; binary packages (no src/) never
# reach it.
if [ -f "$ir" ] && ! grep -q 'r-zig: compile preflight' "$ir"; then
  preflight=$(cat <<'RCODE'
        ## r-zig: compile preflight (the toolchain is a separate package)
        if (((install_libs && dir.exists("src") &&
              length(dir("src", all.files = TRUE)) > 2L) ||
             (use_configure && (file.exists("configure") ||
                                (WINDOWS && (file.exists("configure.win") ||
                                             file.exists("configure.ucrt")))))) &&
            !file.exists(file.path(R.home(), "bin", "toolchain", "zig-cc")) &&
            ## the compiler Makeconf names, when it is a plain path (an
            ## unstaged build tree names the repo's toolchain/zig-cc)
            !tryCatch({
                cc <- grep("^CC *=", readLines(file.path(R.home("etc"), "Makeconf")), value = TRUE)
                cc <- strsplit(sub("^CC *= *", "", cc[1L]), " ", fixed = TRUE)[[1L]][1L]
                file.exists(gsub("$(R_HOME)", R.home(), cc, fixed = TRUE))
            }, error = function(e) FALSE) &&
            !length(makevars_user()) && !nzchar(Sys.getenv("R_ZIG_NO_PREFLIGHT")))
            pkgerrmsg(paste0("this package has compiled code, and the r-zig toolchain is not installed: ",
                             Sys.getenv("R_ZIG_TOOLCHAIN_HINT",
                                        "install the r-zig toolchain package for this R")),
                      pkg_name)

RCODE
  )
  PREFLIGHT="$preflight" awk '
    /^        if \(use_configure\) \{$/ && !done { print ENVIRON["PREFLIGHT"]; done = 1 }
    { print }
  ' "$ir" > "$ir.tmp" && mv "$ir.tmp" "$ir"
  grep -q 'r-zig: compile preflight' "$ir" || { echo "error: preflight patch did not apply to $ir" >&2; exit 1; }
fi

# R CMD config (src/scripts/config) evaluates Makeconf through make, so
# without the toolchain it died with "make: not found"; pkgbuild and pak
# call it to detect a compiler. Check for make first and say what is
# missing.
rcfg="$SRC_DIR/src/scripts/config"
if [ -f "$rcfg" ] && ! grep -q 'r-zig: make check' "$rcfg"; then
  cfg_check=$(cat <<'SHCODE'
## r-zig: make check (make comes with the r-zig toolchain package)
if ! command -v "${MAKE%% *}" > /dev/null 2>&1; then
  echo "ERROR: 'R CMD config' needs make, which comes with the r-zig toolchain: ${R_ZIG_TOOLCHAIN_HINT:-install the r-zig toolchain package for this R}" >&2
  exit 1
fi

SHCODE
  )
  CFG_CHECK="$cfg_check" awk '
    /^makefiles="-f \$\{R_HOME\}\/etc\$\{R_ARCH\}\/Makeconf/ && !done { print ENVIRON["CFG_CHECK"]; done = 1 }
    { print }
  ' "$rcfg" > "$rcfg.tmp" && mv "$rcfg.tmp" "$rcfg"
  grep -q 'r-zig: make check' "$rcfg" || { echo "error: config make-check patch did not apply to $rcfg" >&2; exit 1; }
fi

# install.packages(Ncpus > 1) writes a Makefile and runs `make -k -j`,
# then `cat` to show a failed package's output. Without make (the base
# package has no toolchain), install one at a time instead, as Ncpus = 1
# does; show the output with readLines().
p2="$SRC_DIR/src/library/utils/R/packages2.R"
if [ -f "$p2" ] && ! grep -q 'r-zig: make optional' "$p2"; then
  sed -i \
    -e 's|^        if (Ncpus > 1L \&\& nrow(update) > 1L) {$|        if (Ncpus > 1L \&\& nrow(update) > 1L \&\& # r-zig: make optional\n            nzchar(Sys.which(strsplit(Sys.getenv("MAKE", "make"), " ", fixed = TRUE)[[1L]][1L]))) {|' \
    -e 's|^\( *\)system2("cat", outfile)$|\1writeLines(readLines(outfile)) # r-zig: no cat|' \
    "$p2"
  grep -q 'r-zig: make optional' "$p2" && grep -q 'r-zig: no cat' "$p2" ||
    { echo "error: packages2.R patch did not apply to $p2" >&2; exit 1; }
fi

# R_LIBS_USER_default() (library.R) is R core's own OS-aware default for
# the per-user package library — same "compiled into base.rdb, can't be
# sed-patched after the fact" constraint as the Sys.which() patch above, so
# it has to happen here, before bootstrap builds base.rdb. Requested
# directly, not a bug — revised twice from R core's stock defaults (first
# to a conda-platform-tagged "R/<conda-subdir>-zig" scheme keeping R
# core's own top-level "R" dir, then to this: unix (Linux/macOS alike)
# follows the XDG base directory spec — $XDG_DATA_HOME if set and
# non-empty, else ~/.local/share — instead of R core's own per-OS
# defaults (macOS's ~/Library/R/... in particular). Windows has no XDG
# equivalent; LOCALAPPDATA (non-roaming, machine-local) is already the
# right semantic match and R core already uses it, so it's unchanged.
# This project only ships linux-64/osx-arm64/win-64, so those three
# conda-style platform tags are hardcoded; anything else falls back to R
# core's own platform string, "-zig"-tagged. Replaces the whole function
# body (not a single-line sed) via awk, matched between the function's own
# opening/closing lines — safe because the body has no nested braces, so
# the first "    }" line after the opening is unambiguously this
# function's own close. Idempotent (checked via the distinctive
# "win-64-zig" literal, which no unpatched/differently-patched R source
# has).
lu="$SRC_DIR/src/library/base/R/library.R"
if [ -f "$lu" ] && ! grep -q '"win-64-zig"' "$lu"; then
  r_libs_user_repl=$(cat <<'RCODE'
    R_LIBS_USER_default <- function() {
        home <- normalizePath("~", mustWork = FALSE)  # possibly /nonexistent
        ## FIXME: could re-use v from "above".
        x.y <- paste(R.version$major, sep=".",
                     strsplit(R.version$minor, ".", fixed=TRUE)[[1L]][1L])
        if(.Platform$OS.type == "windows" && s["machine"] == "x86-64")
            file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-64-zig", x.y)
        else if (.Platform$OS.type == "windows") # including aarch64
            file.path(Sys.getenv("LOCALAPPDATA"), "R",
                      paste0("win-", s["machine"], "-zig"), x.y)
        else {
            xdg <- Sys.getenv("XDG_DATA_HOME")
            data_home <- if (nzchar(xdg)) xdg else file.path(home, ".local", "share")
            plat <- if (s["sysname"] == "Darwin")
                        paste0("osx-", if (s["machine"] == "arm64") "arm64" else "64", "-zig")
                    else if (s["sysname"] == "Linux") "linux-64-zig"
                    else paste0(R.version$platform, "-zig")
            file.path(data_home, "R", plat, x.y)
        }
    }
RCODE
  )
  awk -v repl="$r_libs_user_repl" '
    BEGIN { in_block=0 }
    /R_LIBS_USER_default <- function\(\) \{/ { print repl; in_block=1; next }
    in_block && /^    \}$/ { in_block=0; next }
    in_block { next }
    { print }
  ' "$lu" > "$lu.tmp" && mv "$lu.tmp" "$lu"
fi

# bin/R (src/scripts/R.sh.in), phase A3: parse arguments with POSIX
# parameter expansion instead of `echo ... | sed`, so starting R runs no
# sed (three times per `R -e`) and needs no bash: configure-only.sh pins
# R_SHELL=/bin/sh, and `echo` is also gone from the -e/-f path because
# dash's echo rewrites backslashes. The argument loop is replaced whole
# (from "### Argument loop" to its "done"); cases other than the sed
# ones are upstream's, except that `R CMD` runs Rcmd with /bin/sh rather
# than a PATH lookup of `sh`. SED stays exported for rtags and
# javareconf, as a bare name found on PATH (tier 3).
rsh="$SRC_DIR/src/scripts/R.sh.in"
if [ -f "$rsh" ] && ! grep -q 'r-zig: no sed' "$rsh"; then
  r_args_repl=$(cat <<'SHCODE'
### Argument loop
## r-zig: no sed. has_value: the next word exists and isn't an option.
## replace_all STRING FROM TO sets _r to STRING with every FROM replaced.
has_value () { case "${1}" in ""|-*) return 1 ;; esac; }
replace_all () {
  _s="${1}"; _r=
  while :; do
    case "${_s}" in
      *"${2}"*) _r="${_r}${_s%%"${2}"*}${3}"; _s="${_s#*"${2}"}" ;;
      *) _r="${_r}${_s}"; return 0 ;;
    esac
  done
}
NL='
'
TAB='	'
args=
debugger=
debugger_args=
gui=
while test -n "${1}"; do
  case ${1} in
    RHOME|--print-home)
      printf '%s\n' "${R_HOME}"; exit 0 ;;
    CMD)
      shift;
      export R_ARCH
      . "${R_HOME}/etc${R_ARCH}/ldpaths"
      exec /bin/sh "${R_HOME}/bin/Rcmd" "${@}" ;;
    -g|--gui)
      if has_value "${2}"; then
	gui="${2}"
        args="${args} ${1} ${2}"
	shift
      else
	error "option '${1}' requires an argument"
      fi
      ;;
    --gui=*)
      gui="${1#*=}"
      args="${args} ${1}"
      ;;
    -d|--debugger)
      if has_value "${2}"; then
	debugger="${2}"; shift
      else
	error "option '${1}' requires an argument"
      fi
      ;;
    --debugger=*)
      debugger="${1#*=}" ;;
    --debugger-args=*)
      debugger_args="${1#*=}" ;;
    -h|--help)
      printf '%s\n' "${usage}"; exit 0 ;;
    --args)
      break ;;
    --arch)
      if has_value "${2}"; then
	R_ARCH="/${2}"
        shift
      else
        error "option '${1}' requires an argument"
      fi
      ## check sub-architecture here for a better error message
      if ! test -d ${R_HOME}/etc${R_ARCH}; then
        error "sub-architecture '${1}' is not installed"
      fi
      ;;
    --arch=*)
      r_arch="${1#*=}"
      R_ARCH="/${r_arch}"
      ## check sub-architecture here for a better error message
      if ! test -d ${R_HOME}/etc${R_ARCH}; then
        error "sub-architecture '${r_arch}' is not installed"
      fi
      ;;
    -e)
      if has_value "${2}"; then
        replace_all "${2}" "${NL}" "~n~"
        replace_all "${_r}" " " "~+~"
        replace_all "${_r}" "${TAB}" "~t~"
        a="${_r}"
        shift
      else
	error "option '${1}' requires a non-empty argument"
      fi
      args="${args} -e $a"
      ;;
    -f)
      if has_value "${2}"; then
	replace_all "${2}" " " "~+~"; a="${_r}"; shift
      else
	error "option '${1}' requires a filename argument"
      fi
      args="${args} -f $a"
      ;;
    --file=*)
      replace_all "${1#*=}" " " "~+~"; a="${_r}"
      args="${args} --file=$a"
      ;;
    --no-environ)
      R_ENVIRON=''
      export R_ENVIRON
      R_ENVIRON_USER=''
      export R_ENVIRON_USER
      args="${args} ${1}"
      ;;
    --no-site-file)
      R_PROFILE=''
      export R_PROFILE
      args="${args} ${1}"
      ;;
    --no-init-file)
      R_PROFILE_USER=''
      export R_PROFILE_USER
      args="${args} ${1}"
      ;;
    --vanilla)
      R_ENVIRON=''
      export R_ENVIRON
      R_ENVIRON_USER=''
      export R_ENVIRON_USER
      R_PROFILE=''
      export R_PROFILE
      R_PROFILE_USER=''
      export R_PROFILE_USER
      args="${args} ${1}"
      ;;
    *)
      args="${args} ${1}" ;;
  esac
  shift
done
SHCODE
  )
  # ENVIRON, not -v: awk -v would turn the printf '%s\n' into a newline.
  R_ARGS_REPL="$r_args_repl" awk '
    /^SED=@SED@$/ { print "SED=sed # r-zig: bin/R itself uses no sed"; next }
    /^### Argument loop$/ { print ENVIRON["R_ARGS_REPL"]; skip = 1; next }
    skip && /^done$/ { skip = 0; next }
    skip { next }
    { print }
  ' "$rsh" > "$rsh.tmp" && mv "$rsh.tmp" "$rsh"
  grep -q 'r-zig: no sed' "$rsh" && grep -q 'r-zig: bin/R itself uses no sed' "$rsh" &&
    ! grep -q '| \${SED}' "$rsh" || { echo "error: R.sh.in patch did not apply to $rsh" >&2; exit 1; }
fi

# bin/Rcmd (src/scripts/Rcmd.in), every `R CMD` (INSTALL included):
# exports each variable etc/Renviron sets with `export \`sed ...\``. The
# same with the shell's own read: the name before the first "=" on each
# line that is an identifier (comment lines never are).
rc="$SRC_DIR/src/scripts/Rcmd.in"
if [ -f "$rc" ] && ! grep -q 'r-zig: no sed' "$rc"; then
  rcmd_repl=$(cat <<'SHCODE'
## r-zig: no sed
while IFS= read -r _l || test -n "${_l}"; do
  case "${_l}" in
    *=*) _n="${_l%%=*}"
         case "${_n}" in ''|[0-9]*|*[!A-Za-z0-9_]*) ;; *) export "${_n}" ;; esac ;;
  esac
done < "${R_HOME}/etc${R_ARCH}/Renviron"
SHCODE
  )
  RCMD_REPL="$rcmd_repl" awk '
    /^export `sed .*Renviron"`$/ { print ENVIRON["RCMD_REPL"]; next }
    { print }
  ' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
  grep -q 'r-zig: no sed' "$rc" || { echo "error: Rcmd.in patch did not apply to $rc" >&2; exit 1; }
fi

# CA trust for the standalone tree and the wheel. Their vendored libcurl
# and OpenSSL are conda-forge's, with the build env's CA paths compiled
# in, so package-standalone.sh ships a Mozilla bundle and sets
# R_ZIG_CA_BUNDLE in etc/Renviron. Setting CURL_CA_BUNDLE there instead
# would leak into every program R starts (curl, Python's requests, ...)
# and override their own trust, so R's libcurl.c reads the r-zig
# variable itself: CURL_CA_BUNDLE as upstream, then, only when
# R_ZIG_CA_BUNDLE is set, SSL_CERT_FILE, the distribution bundles
# (certificates added with update-ca-certificates, e.g. for TLS-
# inspecting proxies, live there) and last the shipped file. Conda and
# Windows builds don't set R_ZIG_CA_BUNDLE and behave as upstream.
# Compiled into the internet module, so patched here like the R code
# above; idempotent via the helper's name.
lc="$SRC_DIR/src/modules/internet/libcurl.c"
if [ -f "$lc" ] && ! grep -q 'R_zig_ca_bundle' "$lc"; then
  ca_helper=$(cat <<'CCODE'
/* r-zig: see scripts/zig-build.sh ("CA trust"). */
static const char *R_zig_ca_bundle(void)
{
    const char *p = getenv("CURL_CA_BUNDLE");
    if (p && p[0]) return p;
#ifndef Win32
    const char *shipped = getenv("R_ZIG_CA_BUNDLE");
    if (!shipped || !shipped[0]) return p; /* conda: upstream behaviour */
    const char *ssl = getenv("SSL_CERT_FILE");
    if (ssl && ssl[0] && access(ssl, R_OK) == 0) return ssl;
    static const char *const sys[] = {
	"/etc/ssl/certs/ca-certificates.crt", /* Debian, Ubuntu, Arch */
	"/etc/pki/tls/certs/ca-bundle.crt",   /* Fedora, RHEL */
	"/etc/ssl/ca-bundle.pem",             /* openSUSE */
	"/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", /* RHEL 7+ */
	"/etc/ssl/cert.pem",                  /* Alpine, macOS */
	NULL
    };
    for (int i = 0; sys[i]; i++)
	if (access(sys[i], R_OK) == 0) return sys[i];
    return shipped;
#else
    return p;
#endif
}

CCODE
  )
  awk -v helper="$ca_helper" '
    $0 == "static" {
      if ((getline nxt) > 0) {
        if (nxt ~ /^void curlCommon\(CURL \*hnd/) print helper
        print; line = nxt
        if (line ~ /const char \*capath = getenv\("CURL_CA_BUNDLE"\);/)
          sub(/getenv\("CURL_CA_BUNDLE"\)/, "R_zig_ca_bundle()", line)
        print line; next
      }
    }
    /const char \*capath = getenv\("CURL_CA_BUNDLE"\);/ {
      sub(/getenv\("CURL_CA_BUNDLE"\)/, "R_zig_ca_bundle()")
    }
    { print }
  ' "$lc" > "$lc.tmp" && mv "$lc.tmp" "$lc"
  grep -q 'capath = R_zig_ca_bundle()' "$lc" || { echo "error: CA patch did not apply to $lc" >&2; exit 1; }
fi

# libc++ is linked statically, everywhere (decided 2026-09-30): R itself
# (libR, bin/exec/R, the modules) and, through toolchain/zig-cc|zig-cxx,
# every package compiled with it. Upstream zig does that on its own;
# conda-forge's zig links a shared libc++ whenever one sits in
# <zig lib dir>/../../lib (feedstock patch Lld.zig-prefer-shared-libcxx),
# which a macOS conda env always has. A ZIG_LIB_DIR mirror without it
# beside defeats the probe (flang-pixi handoff section 6). zig build's
# cache is not keyed on the probe's result, so a warm cache would hand
# back the shared-libc++ links: the mirror build gets its own local cache.
zl="${ZIG_LIB_DIR:-}"
[ -z "$zl" ] && [ -f "${ZIG%/*}/../lib/zig/std/std.zig" ] && zl="${ZIG%/*}/../lib/zig"
if [ -n "$zl" ]; then
  shared_cxx=""
  for e in libc++.1.dylib libc++.dylib libc++.so.1 libc++.so libc++.dll.a; do
    [ -e "$zl/../../lib/$e" ] && shared_cxx="$zl/../../lib/$e" && break
  done
  if [ -n "$shared_cxx" ] && [ "$OS" = windows ]; then
    # MSYS's ln -s copies, so no mirror here; no win-64 env has one today.
    echo "error: $shared_cxx would make zig link a shared libc++; remove the libcxx package from this env" >&2
    exit 1
  elif [ -n "$shared_cxx" ]; then
    zl="$(cd "$zl" && pwd -P)"
    mirror="$BUILD_DIR/zig-lib-static"
    rm -rf "$mirror"
    mkdir -p "$mirror/lib/zig"
    for e in "$zl"/*; do ln -s "$e" "$mirror/lib/zig/"; done
    export ZIG_LIB_DIR="$mirror/lib/zig"
    export ZIG_LOCAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR-static-libcxx"
    echo "r-zig: static libc++ (zig lib dir mirrored from $zl)"
  fi
fi

"$ZIG" build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "$@"

# The installed tree runs on its own (F1.3): R's rpaths are relative
# (build.zig relRPaths), so the env's libraries it needs go into
# <prefix>/lib. A no-op for the conda build, whose prefix is the env.
R_INSTALL_PREFIX="$PREFIX_ZIG" bash "$(dirname "$0")/vendor-libs.sh"
