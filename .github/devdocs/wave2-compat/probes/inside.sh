#!/usr/bin/env bash
# Runs inside a container (run.sh mounts /probe, /chan, /dist).
# Usage: inside.sh conda|standalone|rpy2-host
set -u
mode="$1"
log() { printf '== %s\n' "$*"; }
os_install() { # packages by distro family
  if command -v apt-get > /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null && apt-get install -y -qq --no-install-recommends "$@" > /dev/null
  else
    dnf install -y -q "$@" > /dev/null
  fi
}
host_facts() {
  log "host: $(. /etc/os-release; echo "$PRETTY_NAME"), $(getconf GNU_LIBC_VERSION)"
  so="$(ls /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib64/libstdc++.so.6 2>/dev/null | head -1)"
  [ -n "$so" ] && log "host libstdc++: $(readlink -f "$so"), newest $(grep -ao 'GLIBCXX_3\.4\.[0-9]*' "$so" | sort -t. -k3,3n -u | tail -1)"
}
export PROBE_NCPUS=8 MAKEFLAGS=-j8
case "$mode" in
  conda)
    os_install curl ca-certificates
    host_facts
    curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash > /dev/null 2>&1
    export PATH="$HOME/.pixi/bin:$PATH"; log "$(pixi --version)"
    mkdir -p /w && cd /w
    cat > pixi.toml << 'EOF'
[workspace]
name = "probe"
channels = ["/chan", "https://prefix.dev/universe", "conda-forge"]
platforms = ["linux-64"]

[dependencies]
r-zig-toolchain = "*"
EOF
    pixi install 2>&1 | tail -3
    pixi list 2>/dev/null | grep -E '^(r-zig|libstdcxx|libgcc|zig|flang) ' | sed 's/^/  /'
    PROBE_LIB=/w/lib pixi run Rscript /probe/probe.R 2>&1
    ;;
  standalone)
    os_install ${EXTRA_PKGS:-} xz-utils ca-certificates 2>/dev/null || os_install ${EXTRA_PKGS:-} xz ca-certificates
    host_facts
    mkdir -p /opt && cd /opt
    for a in /dist/R-*-slim-linux-64.tar.gz /dist/R-*-linux-64-compilers.tar.xz /dist/R-*-linux-64-build-tools.tar.gz; do
      tar -xf "$a" || { log "FAIL extract $a"; exit 1; }
    done
    T="$(ls -d /opt/R-*-zig)"; log "tree $T"
    if [ -n "${SYS_HEADERS:-}" ]; then
      # M-13 experiment: the distro's library headers (never glibc's) as
      # an R_ZIG_EXTRA_ENV, whose include/ rzig passes with -I and lib/ with -L
      mkdir -p /opt/sys/include
      for h in $SYS_HEADERS; do ln -s "/usr/include/$h" /opt/sys/include/; done
      ln -s /usr/lib/x86_64-linux-gnu /opt/sys/lib
      export R_ZIG_EXTRA_ENV=/opt/sys; log "R_ZIG_EXTRA_ENV=/opt/sys: $(ls /opt/sys/include | tr '\n' ' ')"
    fi
    "$T/bin/R" --version | head -1
    PROBE_LIB=/opt/lib "$T/bin/Rscript" /probe/probe.R 2>&1
    log "cxx1.so / Rcpp.so GLIBCXX needs:"
    for f in $(find /tmp /opt/lib -name 'cxx1.so' -o -name 'Rcpp.so' -o -name 'terra.so' -o -name 'sf.so' -o -name 'magick.so' 2>/dev/null); do
      echo "  $f: $(grep -ao 'GLIBCXX_3\.4\.[0-9]*' "$f" | sort -t. -k3,3n -u | tail -1)"
    done
    ;;
  rpy2-host) # M-14: the distro's python3 + pip rpy2, embedding the standalone tree's libR
    os_install xz-utils ca-certificates python3 python3-venv python3-pip
    host_facts
    mkdir -p /opt && cd /opt
    for a in /dist/R-*-slim-linux-64.tar.gz /dist/R-*-linux-64-compilers.tar.xz /dist/R-*-linux-64-build-tools.tar.gz; do tar -xf "$a"; done
    T="$(ls -d /opt/R-*-zig)"
    export PATH="$T/bin:$PATH" R_HOME="$T/lib/R" PROBE_LIB=/opt/lib
    mkdir -p "$PROBE_LIB"
    "$T/bin/Rscript" -e 'install.packages("Rcpp", lib = "/opt/lib", repos = "https://cloud.r-project.org", type = "source", quiet = TRUE); library(Rcpp, lib.loc = "/opt/lib")' 2>&1 | tail -n 3
    python3 -m venv /opt/venv && /opt/venv/bin/pip install -q rpy2 2>&1 | tail -n 5
    /opt/venv/bin/pip list 2>/dev/null | grep -i rpy2
    log "rpy2, nothing preloaded"; /opt/venv/bin/python -I /probe/probe-rpy2.py 2>&1
    log "rpy2, host libstdc++ loaded first"; /opt/venv/bin/python -I /probe/probe-rpy2.py host-first 2>&1
    ;;
esac
