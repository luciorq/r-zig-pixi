# Single direction for the zig + pixi + conda-forge project family (2026-09-19)

**Scope**: one coherent direction for every project depending on zig /
`zig build` in this ecosystem: `r-zig-pixi` (this repo), `flang-pixi`,
`blast-zig-pixi`, `zig-pixi-build-backend`, and `r-zig-packages`.
Grounded in a real survey of each project's docs and state (2026-09-19),
plus the `flang-zig-validation` worktree findings
(`FLANG_ZIG_VALIDATION.md`, this directory). The three reference
projects are knowledge sources — **no code changes are planned in them
by this document**.

## The map: who does what

| Project | Role in the family | State |
|---|---|---|
| **flang-pixi** | Toolchain layer: `lld-zig`/`flang-zig`/`flang-rt-zig` 23.1.1, zig-built, published to `universe` for **six** subdirs (incl. win-arm64). Its MinGW-ABI Windows flang exists nowhere else. `llvm-zig` stays build-time-only (never published). | Shipping; Windows OpenMP leg (flang-rt build 4) just landed, uncommitted docs pending |
| **r-zig-pixi** | Flagship consumer: R itself via pure `zig build`, vendored-configure. Proves the toolchain end-to-end (contract suite, `lapack.R`). Publishes `r-zig-slim` to `universe`. | PR #6 merged 2026-09-19; r-zig-slim 4.6.1 build 1 published to `universe` for all five subdirs via OIDC — Phase 0 done |
| **r-zig-packages** | Downstream layer: `rz-*` R packages compiled against `r-zig-slim`. | POC done, linux-64 only, parked — unblocs as r-zig-slim's platform list grows |
| **blast-zig-pixi** | Application template: foreign build system (NCBI autotools) + zig shims + `pixi-build-rattler-build`; distribution patterns (v3 flags/extras + repodata-v2 twin packages, microarch variants). | Shipping to `universe`, 5 platforms |
| **zig-pixi-build-backend** | Future-facing: recipe-free `pixi_build_zig` backend (pixi fork), cross-first (~18 platforms). The bet on where the ecosystem goes. | Working PoC, unpublished, needs fork checkout |

Three build-approach poles, deliberately kept distinct: shims over a
foreign build system (blast), vendored-config + `zig build` (R), and
native recipe-free `zig build` (backend). Convergence is in
**conventions**, not in forcing one approach.

## Shared conventions (the actual "single direction")

Every project in the family adopts, or already has, these:

1. **One channel**: `universe` on prefix.dev (now public). One
   toolchain generation at a time on it; superseded builds get deleted
   (tooling: r-zig-pixi's `conda-channel-list`/`-delete`).
2. **zig pinned by exact version, never by build number** (`0.16.0`
   today). Rationale is flang-pixi's 2026-09-03 logf128 incident: zig's
   generated glibc link stubs changed **between build numbers** of the
   same version (stub ceiling 2.31 → 2.17), breaking configure-time
   feature detection. The zig conda feedstock is load-bearing in ways
   normal compiler packages are not (bundled clang/libc++/MinGW
   CRT/glibc stubs) — see flang-pixi `docs/13-zig-feedstock-coupling.md`
   for the full defense-in-depth. Any zig version bump = rebuild the
   whole family + re-validate.
3. **glibc 2.17 floor AND ceiling, both enforced**: explicit
   `-target <arch>-linux-gnu.2.17` (never rely on the wrapper/feedstock
   default) plus a build- or verify-time `objdump -T` ceiling tripwire.
   r-zig-pixi: floor pinned in build.zig, ceiling check now in
   `verify-bundle.sh` (ported from the validation worktree). flang-pixi:
   both already. blast: floor via triple.
4. **Baseline CPU codegen for shipped artifacts** (`-Dcpu=baseline` /
   `.cpu_model = .baseline`): channel artifacts run on arbitrary
   consumer machines. blast's microarch-variant work (x86_64_v2/v3 with
   `__archspec` gating) is the sanctioned way to ship optimized
   variants, not native codegen.
5. **Windows = MinGW ABI (`-windows-gnu`), everywhere, explicitly.**
   conda-forge's `zig_win-64` wrappers default to MSVC; every project
   must override. flang-pixi's MinGW flang + R's gnuwin32 heritage +
   blast's `-windows-gnu` all align. (The backend's `windows-abi = gnu`
   default matches; conda-forge's own choice of MSVC is a tracked
   ecosystem divergence.)
6. **Hermetic zig caches**: `ZIG_GLOBAL_CACHE_DIR`/`ZIG_LOCAL_CACHE_DIR`
   inside the workspace, always (sandboxes lack HOME; conda activation
   presets a HOME-based one; zig 0.17 removes the CLI flag).
7. **CI on GitHub-hosted runners only** (self-hosted fleet
   decommissioned 2026-09-19). omicron/kappa remain SSH targets for
   interactive validation only. win-arm64: cross-built where feasible
   (flang-pixi does), never emulated in CI (blast measured it: cannot
   fit the 6h ceiling); native win-arm64 zig upstream is "not planned",
   so cross-only is confirmed policy.
8. **v3 package specs with a v2 compatibility story**: blast already
   ships v3 (`flags`, `extras`) with repodata-v2 twin packages for old
   clients. This resolves the compatibility concern that deferred v3 in
   r-zig-pixi (`feat-prefix-publish/V3_PACKAGE_SPECS.md`) — when
   r-zig-pixi adopts v3 (slim/full via flags), reuse blast's
   `repack_v2.py` twin pattern.
9. **zig upstream lives on Codeberg** (moved 2025-11-26): issues get
   filed there, not github.com/ziglang.
10. **conda's cross sysroot never reaches a runtime library path.** On
    every gfortran platform, autoconf copies gfortran's implicit search
    dirs into FLIBS — including `<conda>/<triple>/sysroot/lib64`, which
    ships a full glibc (libc.so.6, ld-linux). Anything that turns those
    into LD_LIBRARY_PATH (R's etc/ldpaths did) loads a foreign libc under
    the host ld.so and dies at exec. Strip `/sysroot/` entries at capture
    time (r-zig-pixi: gen-subst.sh); flang platforms never had them.

## The one big structural decision: Fortran

**Direction: converge r-zig-pixi's Fortran toolchain on `flang-zig`
across all platforms, phased, with gfortran as the per-platform
fallback until each platform passes the full bar.**

Why (from flang-pixi `docs/11-r-zig-integration.md` + validation):
- osx-arm64: gfortran 15.2 **silently miscompiles** R's complex LAPACK
  at -O2 (`zgesdd`, wrong results, `info=0`) — the reason for the
  global macOS `-O1` cap. flang-zig removes the cap: that's numerical
  correctness + performance, not tidiness.
- osx-64 / linux-aarch64: conda-forge has no flang at all there today.
- win-64: conda-forge flang is MSVC-ABI (useless for R); flang-pixi's
  MinGW flang is the only one in existence.
- Proven: linux-64 R + flang-zig 23.1.1 passes `pixi run build`,
  `check` incl. `lapack.R` at -O2 (flang-pixi docs/10, 2026-09-18), and
  the validation worktree additionally holds a full contract-suite
  testlib (Rcpp/data.table/minqa/pak/ps — see FLANG_ZIG_VALIDATION.md;
  this result should be written back to flang-pixi's status log).

What it takes in r-zig-pixi (flang-pixi docs/15 §2.8 has the exact
list): `fortranOne` gains flang branches per (os, arch); `findFlangRt`
generalized (same clang-resource-dir shape everywhere; under
`Library/lib/clang` on Windows); `linkFortranRt` links
`flang_rt.runtime` instead of gfortran's runtime set; pixi.toml swaps
`gfortran` → `flang-zig` + `flang-rt-zig` per target (+1.5 GiB closure).
The four interface contracts (binary named `flang`; runtime stays in
the clang resource dir; explicit FLIBS; no name collisions) hold as-is.

Bar per platform before flipping its default (docs/11's own): build +
`lapack.R` via `check` + full contract suite, **at -O2**. Anything less
"has delivered nothing".

Honest cost note (also flang-pixi's own): the full zig-built LLVM stack
is strictly required only for win-64/win-arm64; osx/linux-aarch64 could
in principle use a conda-forge-style flang if one ever appears. Mixing
per platform is compatible with how R consumes it — the convergence is
on the *interface contracts*, not on one provenance forever.

## Sequenced plan

**Phase 0 — land what's open (r-zig-pixi PR #6).**
Get PR #6 mergeable and merged. Its three CI failure classes were
root-caused and fixed on the branch 2026-09-19 (record:
`feat-cross-platform-standardization/TODO.md`, last section): linux-
aarch64 = conda's cross **sysroot** lib dirs (which ship a glibc) leaking
from gfortran's FLIBS into R_LD_LIBRARY_PATH → foreign libc.so.6 at
startup; osx-64 = conda-forge's osx-64 `zig ar` cannot create a new
archive (wrapper seeds an empty one); win-64 = `core.autocrlf=true` on
hosted runners turning subst.txt into CRLF (`.gitattributes` + parser).
These are prerequisites for everything downstream (r-zig-packages
multi-platform, flang consumption CI). The consolidation docs (this
directory) ride in the same PR. Trusted-publisher registration on
prefix.dev before merge.

**Phase 1 — absorb the validation branch, clean the tree.**
verify-bundle glibc ceiling: already ported to the PR branch. Record
the contract-suite pass in flang-pixi's status log (user's repo/commit).
Then remove the `flang-zig-validation` worktree + branch (procedure in
FLANG_ZIG_VALIDATION.md). Watch item: pango 1.58 / harfbuzz 14.3 break
R 4.6.1's cairo compile — pin before the next lockfile refresh.

**Phase 2 — Fortran convergence, platform by platform.** *(progress:
`PHASE2_FORTRAN.md` — osx-arm64 done 2026-09-19, full bar at -O2; CI
green on PR #7 2026-09-20. Next: win-64.)*
Order by value: osx-arm64 first (kills the -O1 cap; CRAN's own
experimental flang-23 build is the parity reference), then win-64
(MinGW flang, unblocks dropping gfortran+gcc_impl there), then
linux-aarch64 / osx-64. Each platform: build.zig flang branch → local
validation vs bar → flip pixi.toml + recipe defaults → CI green →
publish. linux-64 stays on conda-forge flang as the parity reference
(flang-pixi's own framing) until there's a reason to move it.

**Phase 3 — downstream + distribution.**
r-zig-packages: resume once r-zig-slim ships ≥3 platforms from hosted
CI; adopt the family conventions from day one (it mostly does). v3
adoption for r-zig-slim (flags for slim/full, blast's v2-twin pattern)
— the naming decision (`r-zig` + flags vs `r-zig-slim` name) documented
in V3_PACKAGE_SPECS.md should be made *before* the channel accumulates
more consumers.

**Phase 4 — the backend bet (watch, don't block).**
`pixi_build_zig` stays the long-term direction for *native zig*
packages; nothing in phases 0–3 depends on it. Revisit when
pixi-build-backends' successor story upstream clarifies. Its two
ecosystem asks that matter to this family: split build/target platform
support in `pixi build`, and the conda-forge zig compiler-axis (CFEP)
maturing.

## Cross-project debts this plan creates/tracks

- [x] r-zig-pixi PR #6: three CI failure classes — root-caused + fixed on the branch 2026-09-19; round 2 (glibc-ceiling tiers, osx-64 headerpad, aarch64 libmvec) also fixed; **CI fully green on run 35446891595 (all 16 jobs, 2026-09-19)**; merged to main; first OIDC publish succeeded for all five subdirs (run 35465461827). **Phase 0 complete.**
- [ ] r-zig-pixi: package-side libmvec exposure on gfortran platforms (Makeconf FFLAGS vs >= 2.30 sysroots) — see TODO.md round 2 item 6.
- [x] prefix.dev trusted-publisher registration — done 2026-09-19; first OIDC publish of r-zig-slim for all five subdirs succeeded (run 35465461827, `workflow_dispatch` on main after the merge push's publish step failed with "GitHub publisher not found").
- [ ] flang-pixi: contract-suite validation result drafted into docs/10 2026-09-19 (uncommitted, user's repo/commit).
- [ ] flang-pixi: its own uncommitted Windows-OpenMP status/runbook entries (user's repo).
- [x] Remove flang-zig-validation worktree + branch — done 2026-09-19 (uncommitted diff preserved at /data/gamma/luciorq/workspaces/temp/r-zig-validation-uncommitted.patch).
- [x] pango/harfbuzz pin ahead of next lockfile refresh — r-zig-pixi pixi.toml pinned 2026-09-19 (pango 1.56.*, harfbuzz 14.2.*; lockfile unchanged). Still open for any other R-building repo.
- [ ] universe channel hygiene: delete superseded flang-rt `_1.._3` + wrong-metadata pixi-built files (needs delete-scoped key).
- [ ] gamma/omicron: stop + remove leftover `actions.runner.*` services (fleet decommissioned).
- [ ] omicron/kappa: `r-zig-pixi-test` scratch dirs — keep or remove (user call).
