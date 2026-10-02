#!/usr/bin/env bash
# Makeconf toolchain-contract test: compile real CRAN packages from source
# against the built R, then exercise them.
#   Rcpp       — C++ compile + runtime evalCpp (compiles C++ through Makeconf)
#   data.table — plain C package
#   minqa      — depends on Rcpp AND compiles Fortran: full mixed-toolchain
#                test (zig C/C++ + flang/gfortran) through R's package build
#   pak        — the real-world repro case behind F7.1/F7.6/F7.7 (see
#                TODO.md): its own configure script recursively
#                re-invokes R.exe/Rterm.exe (the access-violation crash
#                fixed by F7.6's Windows ReleaseSafe switch), and its
#                bundled keyring/zip sub-packages compile mbedtls with
#                a -D flag whose value is a quoted string literal (the
#                win-exec-forward.c command-line quoting bug fixed by
#                F7.7). Locks in both fixes against regression.
#   ps         — already pulled in transitively via pak, but listed and
#                exercised explicitly here since it's the actual origin
#                of the F7.8 repro (see TODO.md): its src/arch/macos/
#                apps.m is genuine Objective-C (AppKit-based running-app
#                enumeration), silently compiled as plain C before the
#                OBJC toolchain-shim fix. ps_apps() (macOS only) calls
#                straight into that compiled code; on linux/windows ps
#                has no Objective-C to exercise, so only the plain
#                load + a basic call is asserted there.
# (No backslash escapes in the R code — see smoke-test.sh.)
. "$(dirname "$0")/env.sh"

if [ "$OS" = windows ]; then
  # R_TEST_R_BIN: test a different build's Rscript.exe (e.g. the zig-build
  # prefix's) instead of the in-tree gnuwin32 default.
  R_BIN="${R_TEST_R_BIN:-$SRC_DIR/bin/x64/Rscript.exe}"
  test -x "$R_BIN" || R_BIN="$SRC_DIR/bin/Rscript.exe"
  # package builds read CC=gcc etc from etc/x64/Makeconf — the zig shim
  # names must be on PATH, as during the gnuwin32 build
  export PATH="$BUILD_DIR/win-toolchain:$PATH"
else
  # R_TEST_R_BIN: test a different build's Rscript (e.g. the zig-build
  # prefix's) instead of the autoconf objdir default. See FINALIZATION.md F1.2.
  R_BIN="${R_TEST_R_BIN:-$OBJ_DIR/bin/Rscript}"
fi
test -x "$R_BIN" || { echo "error: $R_BIN not built yet — run 'pixi run build'" >&2; exit 1; }

LIB="$BUILD_DIR/testlib-$VARIANT"
mkdir -p "$LIB"

echo "Contract test (variant: $VARIANT, os: $OS)"
echo "Compiling Rcpp + data.table + minqa + quadprog + pak + ps from source..."
R_CONTRACT_LIB="$LIB" R_CONTRACT_VARIANT="$VARIANT" "$R_BIN" --vanilla -e '
  lib <- Sys.getenv("R_CONTRACT_LIB")
  pkgs <- c("Rcpp", "data.table", "minqa", "quadprog", "pak", "ps")
  # CRAN mirror hiccups are real (main-branch openblas leg, 2026-09-20:
  # "SSL connect error" downloading Rcpp, then minqa failed on the
  # missing dependency): bounded retries, and fail *here* with a clear
  # message rather than three packages later. install.packages() itself
  # only warns on a failed download.
  options(timeout = 300)
  for (attempt in 1:3) {
    install.packages(pkgs, repos = "https://cloud.r-project.org",
                     lib = lib, type = "source", Ncpus = 4)
    missing <- setdiff(pkgs, rownames(installed.packages(lib.loc = lib)))
    if (!length(missing)) break
    message("contract: attempt ", attempt, " left ", paste(missing, collapse = ", "),
            " uninstalled", if (attempt < 3) "; retrying in 30 s" else "")
    if (attempt < 3) Sys.sleep(30)
  }
  if (length(missing)) stop("contract: could not install ", paste(missing, collapse = ", "))
  .libPaths(lib)
  library(Rcpp); library(data.table); library(minqa); library(quadprog); library(pak); library(ps)
  stopifnot(evalCpp("2 + 2") == 4)
  dt <- data.table(g = rep(1:3, 4), x = 1:12)
  stopifnot(identical(dt[, sum(x), by = g][[2]], c(22L, 26L, 30L)))
  # OpenMP proof, machine-independent: data.table prints "OpenMP version"
  # only when compiled with OpenMP. (Do NOT assert getDTthreads() > 1 —
  # its default is 50% of cores, which is 1 on small CI runners.)
  # minimal is built without OpenMP and its Makeconf offers none, so there
  # the proof runs the other way: the profile property is the empty
  # SHLIB_OPENMP_* flags. data.table follows them on linux, but on macOS
  # its configure probes -Xclang -fopenmp itself and links -lomp, which
  # succeeds wherever a libomp is reachable (conda llvm-openmp in the dev
  # env, which zigbuild/dev.Makevars puts on the -L and rpath). That is the
  # package opting in, not R offering OpenMP, so there it is reported only.
  th_info <- capture.output(getDTthreads(verbose = TRUE))
  cat(th_info, sep = "\n")
  if (Sys.getenv("R_CONTRACT_VARIANT") == "minimal") {
    mk <- readLines(file.path(R.home("etc"), "Makeconf"))
    omp <- grep("^SHLIB_OPENMP_(C|CXX|F)FLAGS *=", mk, value = TRUE)
    stopifnot(length(omp) == 3L, all(grepl("= *$", omp)))
    if (Sys.info()[["sysname"]] != "Darwin")
      stopifnot(!any(grepl("OpenMP version", th_info)))
  } else {
    stopifnot(any(grepl("OpenMP version", th_info)))
  }
  fit <- bobyqa(c(1, 1), function(x) sum((x - 3)^2))
  stopifnot(max(abs(fit$par - c(3, 3))) < 1e-4)
  # quadprog: a *pure-Fortran* package (no C/C++ sources at all) — the one
  # shape minqa cannot cover, since its C++ sends the link through
  # SHLIB_CXXLD. Here R CMD SHLIB compiles every file with $(FC) (flang on
  # every platform since Phase 2) and links through SHLIB_LD, the zig-cc
  # shim, with $(FLIBS) appended — the resolved-at-build-time flang
  # runtime dir, the runtime archive/dylib, and on Windows libc++. (R
  # only links via the Fortran driver itself when a package opts in with
  # USE_FC_TO_LINK in Makevars; that path is not exercised here.)
  # minimize (1/2) t(x) D x - t(d) x subject to x >= 0, with D = 2I and
  # d = (2, 6): the solution is x = (1, 3). (No apostrophes in this R
  # program: it sits inside a single-quoted shell string.)
  qp <- solve.QP(Dmat = diag(2, 2), dvec = c(2, 6), Amat = diag(2), bvec = c(0, 0))
  stopifnot(max(abs(qp$solution - c(1, 3))) < 1e-8)
  # pak: no network calls here (this test is about the compiled-code
  # toolchain contract, not pak own package-manager functionality) —
  # loading it successfully already proves its compiled sub-packages
  # (keyring, pkgdepends tree-sitter/yaml C code) built and link-loaded
  # correctly; packageVersion() is a real call into the loaded package.
  stopifnot(is.character(as.character(packageVersion("pak"))))
  # ps: a plain call proves the package loaded/link-loaded on every OS;
  # on macOS specifically, ps_apps() calls straight into apps.m -- the
  # genuine Objective-C source behind the F7.8 OBJC-toolchain-shim fix.
  stopifnot(ps::ps_pid(ps::ps_handle()) == Sys.getpid())
  if (ps::ps_os_type()[["MACOS"]]) {
    # nrow not asserted > 0 -- omicron is an SSH-only session with no
    # guaranteed GUI apps running; a successful, non-crashing data frame
    # already proves the compiled apps.m call worked end-to-end.
    apps <- ps::ps_apps()
    stopifnot(is.data.frame(apps))
  }
  # Makeconf names no build path (feat-no-host-paths F1.5): FLIBS is the
  # bare runtime the shims resolve, and LDFLAGS has no rpath outside the
  # conda package. --no-user-files: the pixi env points R_MAKEVARS_USER at
  # zigbuild/dev.Makevars, which adds the env -I/-L/-rpath on top.
  cfg <- function(v) tools::Rcmd(c("config", "--no-user-files", v), stdout = TRUE)
  stopifnot(grepl("-lflang_rt.runtime", cfg("FLIBS"), fixed = TRUE),
            !grepl("libflang_rt", cfg("FLIBS"), fixed = TRUE),
            !grepl("-rpath", cfg("LDFLAGS"), fixed = TRUE))
  cat("Rcpp evalCpp (runtime C++ compile via Makeconf): OK\n")
  cat("data.table grouped aggregation: OK\n")
  cat("minqa (Rcpp-dependent + package Fortran) bobyqa: OK\n")
  cat("quadprog (pure Fortran: flang compile, FLIBS link through the zig-cc shim) solve.QP: OK\n")
  cat("pak (recursive R.exe invocation + mbedtls quoted -D flags): OK\n")
  cat("ps (process introspection", if (ps::ps_os_type()[["MACOS"]]) "+ apps.m Objective-C ps_apps()" else "", "): OK\n")
'
# Static libc++ everywhere (decided 2026-09-30): no compiled package may
# depend on a shared C++ runtime. zig links its own libc++ statically, but
# conda-forge's zig switches to a shared one whenever a libc++ sits beside
# it (always in a macOS conda env; on linux with any `libcxx` package);
# toolchain/zig-cc|zig-cxx defeat that with a ZIG_LIB_DIR mirror.
if [ "$OS" = linux ] || [ "$OS" = macos ]; then
  shared_cxx=""
  for so in "$LIB"/*/libs/*.so; do
    if [ "$OS" = linux ]; then
      hit="$(patchelf --print-needed "$so" 2>/dev/null | grep -E '^lib(c\+\+|stdc\+\+)\.so' || true)"
    else
      hit="$(otool -L "$so" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E '(^|/)lib(c\+\+|stdc\+\+)[.0-9]*\.dylib$' || true)"
    fi
    [ -z "$hit" ] || shared_cxx="$shared_cxx ${so#$LIB/}->$hit"
  done
  if [ -n "$shared_cxx" ]; then
    echo "error: compiled packages depend on a shared C++ runtime:$shared_cxx" >&2
    exit 1
  fi
  echo "C++ runtime: static in every compiled package"
fi
# macOS: every compiled package at or below the deployment target the
# shims pass (MACOS_MIN), and the SDK's lib dir last on their link lines:
# data.table's zlib.h comes from the env, so its libz must too, not the
# SDK's older stub in /usr/lib.
if [ "$OS" = macos ]; then
  bad=""
  for so in "$LIB"/*/libs/*.so; do
    m="$(macho_minos "$so")"
    if [ -z "$m" ] || version_gt "$m" "$MACOS_MIN"; then bad="$bad ${so#$LIB/}=${m:-none}"; fi
  done
  if [ -n "$bad" ]; then
    echo "error: compiled packages above the macOS $MACOS_MIN floor:$bad" >&2
    exit 1
  fi
  if otool -L "$LIB/data.table/libs/data_table.so" | grep -q '/usr/lib/libz\.'; then
    echo "error: data.table linked the SDK's libz stub (the SDK -L is not last in the shims)" >&2
    exit 1
  fi
  echo "macOS floor: every compiled package at minos <= $MACOS_MIN"
fi
echo "Contract test passed ($VARIANT/$OS)."
