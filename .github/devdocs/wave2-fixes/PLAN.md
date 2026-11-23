# wave2-fixes: fixes found by the build-12 CI wave

Fixes on top of main f5a6c84 (PR #54), found by its CI, plus small notes.

## Decisions

| # | Question | Chosen | Reason | Who, date |
|---|---|---|---|---|
| X1 | verify-tree's new legacy-encoding check (fix-verify-scripts M-8) fails macos-15-intel: SSE4.1 in R's Fortran code | Allow SSE3, SSSE3 and SSE4.1 on macOS; flag SSE4.2, POPCNT, LZCNT, MOVBE, BMI1/2 | flang compiles for LLVM's macOS default CPU, penryn (SSE4.1), as Apple's clang does; zig's C code stays core2 (verify-bundle.sh). Every Mac that runs macOS 13 has SSE4.2 and AVX2, so the shipped code runs everywhere the package installs. The binaries are as before: the old check counted VEX only | default, 2026-11-23 |

## Findings

**X-F1 V.** build-r 45275675601 (main push, f5a6c84) and 45275124907
(#54's full tier): macos-15-intel / default fails at "Verify the
installed tree": `lib/R/lib/libRlapack.dylib` 844, `libRblas.dylib` 61,
`libR.dylib` 12, `library/stats/libs/stats.so` 78 instructions, every one
SSE4.1 (blendvpd 26, blendpd 6, pextrb 6, pinsrd 2 among the listed
lines), all in Fortran routines (_dqrdc_, _zbdsqr_, _optra_, ...).

**X-F2 V.** The new pattern, evaluated as verify-tree.sh builds it: on
macOS blendvpd, pinsrd, pextrb, pshufb, haddpd pass and pcmpestri,
crc32q, popcntq, lzcntl are flagged; on linux all nine are flagged;
pextrw, andnps, pmaxsw (baseline) are flagged on neither.

## Also

- stress/README.md: the first r-zig build that searches zig-libs is 12
  (libs-zig-pixi asked, 2026-11-23; its CONTRACT.md 6 says the same).

## Not verified

- The fixed check on a macos-15-intel runner (the next CI run).
