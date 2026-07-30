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

exec "$ZIG" build --prefix "$PREFIX_ZIG" -Dvariant="$VARIANT" -Dblas="$BLAS" "$@"
