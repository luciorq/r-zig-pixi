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

# The Sys.which source patch from configure-r.sh must be present in the
# source tree for relocatable installs (see PLAN.md of feat-initial-setup).
sw="$SRC_DIR/src/library/base/R/unix/system.unix.R"
if [ -f "$sw" ] && ! grep -q 'bin/toolchain/which' "$sw"; then
  sed -i \
    's|which <- "@WHICH@"|which <- { w <- file.path(R.home(), "bin", "toolchain", "which"); if (file.exists(w)) w else "@WHICH@" }|' \
    "$sw"
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

exec "$ZIG" build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "$@"
