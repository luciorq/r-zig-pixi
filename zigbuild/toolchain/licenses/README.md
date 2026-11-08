# Licence texts of packages that ship none

Every directory of copied conda files carries its packages' licence
texts: each toolchain group directory in `LICENSES/<package>/`
(zigbuild/toolchain/build.zig), and the R tree in
`share/licenses/<package>/` (Windows: `Library/share/licenses/`; the same
build file's `-Dbase`, feat-standalone-toolchain B33 a, PHASE8). They come
from the package's `info/licenses/`. A few packages ship none:
conda-forge's m2 packages (MSYS2's binary packages, repackaged by
m2-binary-packages-feedstock), whose files the Windows build-tools group
copies into `R_HOME/bin/toolchain/usr/bin`, and libgcc, libstdcxx,
libgfortran5 and libfreetype6, whose libraries the linux R tree vendors
(libgfortran5: the openblas flavor's, with libquadmath). For a package
whose `info/licenses/` is missing or empty, the build installs the files
of this directory's `<package>/` instead, after checking that its
`VERSION` equals the record's `<version> <build>` (an m2 package: MSYS2's
release is in the build) or `<version>` (the others: the build differs per
platform, the source does not); SOURCES then says `licenses: from <the
source archive>` (PHASE7 open point E a, PHASE8 open point H a).

Each `<package>/` holds:

- the licence files, at their path in the upstream source;
- `VERSION`: `<version> <build>` or `<version>` of the conda package the
  texts are for;
- `ORIGIN`: the package and conda-meta's licence, the source archive
  (`source:`, the recipe's URL and sha256; `mirror:`, conda-forge's copy),
  a `file:` line per text (its path here, its sha256, and where it is in
  the archive), and a `note:` where the texts name another licence than
  conda-meta's `license:` (SOURCES keeps conda-meta's), or where the
  package's own files hold one of them.

No code fetches these. They are taken by hand, once per pin: a re-lock
that moves such a package's version (an m2 package's build too) stops the
build until its directory is taken again ("... does not hold its texts").

## How to take them

The gcc packages and libfreetype6: the source archive is the first `url:`
of the package's `info/recipe/meta.yaml` `source:` (gcc-<ver>.tar.gz;
freetype-<ver>.tar.gz), checked against the `sha256:` beside it; the files
come from its top directory.

| package | archive | files |
|---|---|---|
| libgcc, libstdcxx, libgfortran5 | gcc-16.2.0.tar.gz | COPYING3, COPYING.RUNTIME |
| libfreetype6 | freetype-2.14.3.tar.gz | LICENSE.TXT, docs/FTL.TXT, docs/GPLv2.TXT |

Taken on 2026-11-07 (pixi.lock fbb64b7b...), from ftp.gnu.org and
download.savannah.gnu.org.

The m2 packages:

1. The source archive: the second `url:` entry of the package's
   `info/recipe/rendered_recipe.yaml` `finalized_sources` (the
   `.src.tar.zst` under `repo.msys2.org/msys/sources/`, or the same file
   in m2-binary-packages-feedstock's GitHub release when MSYS2 has moved
   on). Check it against the `sha256:` beside it.
2. Unpack it (`zstd -dc <archive> | tar -x`). It holds MSYS2's PKGBUILD,
   its patches and the upstream source tarball; take the files below from
   that tarball's top directory (`tar -xOf <tarball> <top>/<file>`).
3. Write `VERSION` and `ORIGIN` as the others are written, then check every
   `file:` line's sha256 against the file here.

| package | upstream tarball in the archive | files |
|---|---|---|
| m2-bash | bash-5.2.tar.gz | COPYING |
| m2-make | make-4.4.1.tar.gz | COPYING |
| m2-coreutils | coreutils-8.32.tar.xz | COPYING |
| m2-sed | sed-4.9.tar.xz | COPYING |
| m2-grep | grep-3.0.tar.xz | COPYING |
| m2-gawk | gawk-5.3.2.tar.gz | COPYING |
| m2-which | which-2.23.tar.gz | COPYING |
| m2-findutils | findutils-4.9.0.tar.xz | COPYING |
| m2-patch | patch-2.7.6.tar.xz | COPYING |
| m2-msys2-runtime | none: a bare git clone of newlib-cygwin (`msys2-runtime/`); `git --git-dir=msys2-runtime show cygwin-<ver>:<file>`, the PKGBUILD's tag | winsup/CYGWIN_LICENSE, winsup/COPYING, winsup/COPYING.LIB, COPYING.NEWLIB, COPYING.LIBGLOSS |
| m2-libintl | gettext-0.22.5.tar.gz | gettext-runtime/intl/COPYING.LIB, COPYING |
| m2-libiconv | libiconv-1.18.tar.gz | COPYING.LIB, COPYING |
| m2-libpcre | pcre-8.45.tar.bz2 | LICENCE |
| m2-gmp | gmp-6.3.0.tar.xz | COPYING.LESSERv3, COPYINGv2, COPYINGv3, COPYING |
| m2-mpfr | mpfr-4.2.2.tar.xz | COPYING.LESSER, COPYING |
| m2-libreadline | readline-8.2.tar.gz | COPYING |
| m2-ncurses | ncurses-6.5-20240831.tgz | COPYING |
| m2-gcc-libs | gcc-13.3.0.tar.xz (GCC's whole source, about 90 MB) | COPYING.RUNTIME, COPYING3.LIB, COPYING3, COPYING.LIB, COPYING |

Taken on 2026-10-20 for the `hc364b38_6` builds (pixi.lock fbb64b7b...);
m2-patch's on 2026-10-21 (feat-win-link-fixes item 4), from
repo.msys2.org.
grep's and findutils' archives were no longer on repo.msys2.org then (404)
and came from the mirror, with the same sha256.
