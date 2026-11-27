# Licence texts of packages that ship none of their software's

Every directory of copied conda files carries its packages' licence
texts: each toolchain group directory in `LICENSES/<package>/`
(zigbuild/toolchain/build.zig), and the R tree in
`share/licenses/<package>/` (Windows: `Library/share/licenses/`; the same
build file's `-Dbase`, feat-standalone-toolchain B33 a, PHASE8). They come
from the package's `info/licenses/`. A few packages ship none of the
software's own: conda-forge's m2 packages (MSYS2's binary packages,
repackaged by m2-binary-packages-feedstock), whose files the Windows
build-tools group copies into `R_HOME/bin/toolchain/usr/bin` (their
`info/licenses/` holds one file, `recipe-scripts-license.txt`,
conda-forge's BSD-3-Clause licence for the feedstock's recipe scripts:
not the licence of bash, GNU tar or the Cygwin DLL), libgcc, libstdcxx,
libgfortran5 and libfreetype6, whose libraries the linux R tree vendors
(libgfortran5: the openblas flavor's, with libquadmath), and
libstdcxx-devel_linux-64 and libstdcxx-devel_linux-aarch64, whose C++
headers the linux compilers group copies into
`R_HOME/bin/toolchain/libstdcxx` (feat-linux-libstdcxx). For a package
whose `info/licenses/` is missing, empty or holds only
`recipe-scripts-license.txt` (build 14 on: until then that file counted,
and the texts here were not installed for the `_11` m2 builds;
chore-review-consistency B1), the build installs the files
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

No build fetches these. They are taken once per pin (the m2 packages:
`take-m2.py` here does the steps below; the others by hand): a re-lock
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
| libstdcxx-devel_linux-64, libstdcxx-devel_linux-aarch64 | gcc-15.3.0.tar.gz | COPYING3, COPYING.RUNTIME |
| libfreetype6 | freetype-2.14.3.tar.gz | LICENSE.TXT, docs/FTL.TXT, docs/GPLv2.TXT |

Taken on 2026-11-07 (pixi.lock fbb64b7b...), from ftp.gnu.org and
download.savannah.gnu.org; the libstdcxx-devel ones on 2026-11-18
(feat-linux-libstdcxx), from ftp.gnu.org, the tarball checked against
the recipe's sha256 (the same texts as gcc 16.2.0's).

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
| m2-bash | bash-5.3.tar.gz | COPYING |
| m2-make | make-4.4.1.tar.gz | COPYING |
| m2-coreutils | coreutils-8.32.tar.xz | COPYING |
| m2-sed | sed-4.9.tar.xz | COPYING |
| m2-grep | grep-3.0.tar.xz | COPYING |
| m2-gawk | gawk-5.4.1.tar.gz | COPYING |
| m2-which | which-2.25.tar.gz | COPYING |
| m2-findutils | findutils-4.11.0.tar.xz | COPYING |
| m2-patch | patch-2.8.1.tar.xz | COPYING |
| m2-tar | tar-1.35.tar.xz | COPYING |
| m2-gzip | gzip-1.15.tar.xz | COPYING |
| m2-msys2-runtime | none: a bare git clone of newlib-cygwin (`msys2-runtime/`); `git --git-dir=msys2-runtime show cygwin-<ver>:<file>`, the PKGBUILD's tag | winsup/CYGWIN_LICENSE, winsup/COPYING, winsup/COPYING.LIB, COPYING.NEWLIB, COPYING.LIBGLOSS |
| m2-libintl | gettext-0.22.5.tar.gz | gettext-runtime/intl/COPYING.LIB, COPYING |
| m2-libiconv | libiconv-1.19.tar.gz | COPYING.LIB, COPYING |
| m2-libpcre | pcre-8.45.tar.bz2 | LICENCE |
| m2-gmp | gmp-6.3.0.tar.xz | COPYING.LESSERv3, COPYINGv2, COPYINGv3, COPYING |
| m2-mpfr | mpfr-4.2.2.tar.xz | COPYING.LESSER, COPYING |
| m2-libreadline | readline-8.3.tar.gz | COPYING |
| m2-ncurses | ncurses-6.6.tar.gz | COPYING |
| m2-gcc-libs | gcc-16.2.0.tar.xz (GCC's whole source, about 100 MB) | COPYING.RUNTIME, COPYING3.LIB, COPYING3, COPYING.LIB, COPYING |

Taken on 2026-11-26 for the `ha3ae583_11` builds (pixi.lock on main
77abec1; chore-review-consistency F21), all from repo.msys2.org, each
archive checked against its recipe's sha256. m2-tar and m2-gzip are new:
the group copies tar since build 11 and gzip from build 14. Of the 18
taken before, only ncurses' text changed (its copyright years).

Before that: taken on 2026-10-20 for the `hc364b38_6` builds (pixi.lock
fbb64b7b...); m2-patch's on 2026-10-21 (feat-win-link-fixes item 4). The
lock moved to `_11` on 2026-11-10, and the build did not stop: see the
`recipe-scripts-license.txt` rule above.
