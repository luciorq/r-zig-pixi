# Helpers shared by verify-tree.sh and verify-bundle.sh. Source this after
# env.sh (which sets OS and holds MACOS_MIN, macho_minos and version_gt);
# do not execute it. Each reads what a binary needs and where it looks for
# it from the file itself: patchelf on linux, otool on macOS.

# The libraries a binary names, one per line: DT_NEEDED on linux; on macOS
# its LC_*_DYLIB entries (a dylib's own install name first). Empty when the
# file cannot be read.
needed_of() {
  if [ "$OS" = linux ]; then
    patchelf --print-needed "$1" 2>/dev/null || true
  else
    otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}' || true
  fi
}

# Where it looks for them: its RUNPATH/RPATH entries (ELF) or LC_RPATH
# paths (Mach-O), one per line.
rpaths_of() {
  if [ "$OS" = linux ]; then
    patchelf --print-rpath "$1" 2>/dev/null | tr ':' '\n' | grep -v '^$' || true
  else
    otool -l "$1" | awk '/cmd LC_RPATH/ {r = 1} r && / path / {sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; r = 0}'
  fi
}

# A shared C++ runtime among the libraries it names (libc++, libstdc++);
# empty when there is none. libc++ is static everywhere (decided
# 2026-09-30), in R's own binaries and in packages compiled with rzig.
cxx_deps() {
  if [ "$OS" = linux ]; then
    needed_of "$1" | grep -E '^lib(c\+\+|stdc\+\+)\.so' || true
  else
    needed_of "$1" | grep -E '(^|/)lib(c\+\+|stdc\+\+)[.0-9]*\.dylib$' || true
  fi
}

# macOS: succeeds, printing the file's minos ("none" when it has none),
# when a Mach-O file is above the MACOS_MIN floor or carries no minos at
# all; fails when it is at or below the floor.
minos_over_floor() {
  local m
  m="$(macho_minos "$1")"
  if [ -z "$m" ] || version_gt "$m" "$MACOS_MIN"; then
    echo "${m:-none}"
    return 0
  fi
  return 1
}
