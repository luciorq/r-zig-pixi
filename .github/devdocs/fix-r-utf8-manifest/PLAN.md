# fix-r-utf8-manifest — R's Windows front-ends embed R's UTF-8 manifest

**Status (2026-10-21).** Branch fix-r-utf8-manifest, from main at
d11dee1 (the merge of feat-shared-build-runner, PR #27). Checked on
linux-64 (gamma): the manifest resource with both zigs, build.zig with
both zigs, verify-tree's new check. Checked on kappa (Windows 11 x64,
ANSI code page 1252) with conda-forge's zig: the real build, its six
front-ends, the non-ASCII path and the full chain (see "Tested"). The
real Windows build with upstream zig is UNVERIFIED until CI's
upstream-zig leg runs; the PR carries the labels full-ci and
upstream-zig (the user, 2026-10-21).

**Build number and merge order.** No build-number bump: the conda
packages keep build 8, whose build strings are the files already on
universe (see "Tested"), so main's publish (`--skip-existing`) uploads
nothing for this PR and conda users get the fix with the next bump,
phase 7 of feat-standalone-toolchain's 8 → 9. That holds only if this
PR reaches main before phase 7's bump commit. rattler-build's build
string is `h<variant hash>_<number>` and this PR changes no variant
input, so merged after phase 7 it renders phase 7's `_9` strings,
`--skip-existing` skips them, and the channel's `_9` files lack the
manifest (the same way the channel kept the gfortran builds,
consolidation/PHASE2_FORTRAN.md). Merged after phase 7, this PR needs
its own bump, to the number after universe's newest. When phase 7 is
rebased onto a main with this fix, its bump comment (recipe.yaml,
8 → 9) names it: "the Windows front-ends embed R's UTF-8 manifest
(fix-r-utf8-manifest)".

## What

build.zig gives each Windows front-end R's own application manifest,
the source tree's file, through zig's `win32_manifest` (winManifest):

| installed | built as | manifest (src/gnuwin32/front-ends/) |
|---|---|---|
| bin/x64/Rterm.exe | Rterm | Rterm64.manifest |
| bin/x64/Rscript.exe | Rscript | Rscript64.exe.manifest |
| bin/x64/R.exe, bin/x64/Rcmd.exe | winCmdFrontend | Rcmd64.exe.manifest |
| bin/R.exe, bin/Rscript.exe | winRfe (Rfe) | Rcmd64.exe.manifest |

verify-tree.sh's CRAN-layout check (Windows) fails a tree whose six
front-ends lack `<activeCodePage ...>UTF-8</activeCodePage>`.

## Why

gnuwin32 embeds these manifests in every program it builds from
front-ends/: each .rc there names its manifest as resource 1 of type
RT_MANIFEST (`CREATEPROCESS_MANIFEST_RESOURCE_ID RT_MANIFEST
"Rterm64.manifest"` under `WN64`), and front-ends/Makefile, with WIN=64,
links rtico.o into Rterm.exe, rsico.o into Rscript.exe and rcico.o into
R.exe, Rcmd.exe, Rfe.exe (bin/R.exe, bin/Rscript.exe), RSetReg.exe and
Rpwd.exe; Rgui.exe gets RGui64.manifest, open.exe none. All four say
activeCodePage UTF-8 (R >= 4.2), longPathAware true and heapType
SegmentHeap; Rterm's, Rscript's and Rgui's also name common controls 6
and supportedOS (Vista to Windows 10).

r-zig's build compiled none of those .rc files ("cosmetic", the icon),
so its front-ends had no manifest, and the manifest is not cosmetic:
without activeCodePage a process's ANSI code page is the system's. On
kappa (ACP 1252) r-zig-slim build 8's Rterm and Rscript under
`C:\Users\admin\rz-p7a\r ü中\` stop with "Fatal error: unable to open
the base package"; the same R under an ASCII path with a space works
(phase 7a kappa RESULTS.md, "Space path (SP) and its non-ASCII twin").

zig embeds a `.manifest` as that same resource (type 24, id 1, language
1033), byte for byte, so nothing else is compiled: the .rc files' icon
and VERSIONINFO stay out, as before (the user, 2026-10-21: cosmetic,
no follow-up planned). Their `#include "../../include/Rversion.h"`
would need build.zig's generated Rversion.h placed beside a copy of
front-ends/. CRAN's Rterm.exe carries 5 ICONs, GROUP_ICON RTERM and
VERSIONINFO besides the manifest; r-zig's carries only the manifest.
RSetReg.exe, Rpwd.exe, Rgui.exe and open.exe are not built.

## Tested

| what | result |
|---|---|
| zig 0.16.0, conda-forge's and upstream's: a scratch build with the same `win32_manifest` option and R 4.6.1's files (tarball sha256 4da6e61d…, the recipe's), x86_64-windows-gnu; `llvm-readobj --coff-resources` (LLVM 21.1.8) | each exe has one resource, MANIFEST (ID 24), name ID 1, language 1033, whose bytes' sha256 equals its source file's (Rterm64 1923 B, Rscript64 1924 B, Rcmd64 1027 B); the control exe without the option has none |
| `zig fmt --check build.zig`, both zigs; build.zig compiled on linux (`zig build --help` up to its CONDA_PREFIX check; a broken winManifest fails that compile) | clean; compiles |
| verify-tree.sh's Windows block on a stand-in tree from those exes; `bash -n` | passes; with Rterm.exe swapped for the control: `bin/x64/Rterm.exe(no UTF-8 manifest)`, exit 1 |
| rattler-build `--render-only`, win-64 and linux-64 | r-zig-slim h9490d1a_8 / hb0f4dca_8, r-zig-toolchain hbceaa80_8 / hc48ad4c_8: the files already on universe, so main's publish (`--skip-existing`) uploads nothing |
| kappa 2026-10-21 (Windows 11 x64 build 22621, ACP 1252, conda-forge's zig): the six front-ends, `llvm-readobj --coff-resources` | 6/6 carry R 4.6.1's manifest for that program: MANIFEST 24/1/1033, bytes equal to R's source file and to CRAN's installed R 4.6.1 (Rcmd64 1027 B, Rscript64 1924 B, Rterm64 1923 B); d11dee1's build.zig: no resources. The exes are byte-identical in the build, a rebuild and the compile tree |
| kappa: verify-tree on both trees | this branch: `the front-ends' UTF-8 manifest` verified, rc=0; d11dee1's tree: `bin/R.exe(no UTF-8 manifest)` and the same for the other five, rc=1 |
| kappa: locale through 5 entry points (x64 Rscript, Rterm, R; bin Rscript, R) | `l10n_info()`, `Sys.getlocale()` and `localeToCharset()` as CRAN's R 4.6.1 on the same machine: codepage 65001, `English_United States.utf8` (LC_NUMERIC=C), "UTF-8"; d11dee1's: 1252. "Running under:" is now "Windows 11 x64 (build 22621)", as CRAN's; without the manifest (no supportedOS) it was "Windows 8 x64 (build 9200)" |
| kappa: the tree, library, TMP, rzig and zig caches under `r ü中`, and under `r z` | 5 front-ends start; glue (C code) installs through Rterm, Rscript and `bin\R.exe CMD INSTALL` (`rzig build: tier 1`), loads and runs; under `r ü中` also with PATH = bin\x64 + System32. d11dee1's tree under `r ü中`: Rterm and Rscript stop with `Fatal error: 'R_TempDir' contains space`, bin\Rscript.exe prints `The system cannot find the path specified.` |
| kappa: the chain (lock-check, install, build, verify-tree, smoke, twin, check, toolchain, compile-tree, contract, hermetic) | each rc=0; check: 68 OK and phase 6's tools-Ex NOTE, its body byte-identical; phase 6's stats-Ex NOTE is OK under UTF-8; every contract row OK |
| kappa: nothing else changed (this branch against d11dee1's build.zig, same sources and path) | R CMD config (`--all`, 14 variables, `bin\R.exe CMD config CC`) byte-identical; `capabilities()`, `extSoftVersion()`, `La_version()`, `La_library()`, `grSoftVersion()` identical; of 2947 files 40 differ: the 6 front-ends and 34 library files that also differ between two builds of the same sources (build times, methods' `dateCreated`, the Rd2HTML stamp), methods' package.rds also by the References line break below |
| upstream zig: the real Windows build | UNVERIFIED (CI's upstream-zig leg) |

kappa's record: the tester's
/data/gamma/luciorq/workspaces/temp/r-zig-pixi/utf8/test-kappa/RESULTS.md
(sections 2-7), logs in its final/logs/.

## Known, not this fix: methods' package.rds References

On kappa, methods' `Meta/package.rds` `References` breaks its line in
a different place in this branch's tree (`"John M. Chambers (2008)
``Software for Data Analysis:\nProgramming with R''; Springer NY."`)
than in d11dee1's tree, CRAN's R 4.6.1 and r-zig's linux trees
(`"John M. Chambers (2008)\n``Software for Data Analysis: Programming
with R''; Springer NY."`). The installed DESCRIPTION and `read.dcf()`
of it are the same in all of them. The cause is inferred, not
reproduced: build.zig's "descriptions as RDS" step runs
`tools:::.vinstall_package_descriptions_as_RDS`, which skips a package
only when its package.rds is newer than its DESCRIPTION (R's
tools/R/admin.R, `file_test("-nt", ...)`). In d11dee1's tree methods'
package.rds is 0.015633 s newer, one Windows clock tick; when both
writes fall in the same tick the rds is rewritten from the installed
DESCRIPTION, whose References write.dcf re-wrapped. methods is the only
base package with such a field. Nothing there reads the code page, and
the step order is zig's parallel scheduling, so it is a build
reproducibility item for later (the user, 2026-10-21), not part of
this PR. It only changes `packageDescription("methods")$References`'s
line break.
