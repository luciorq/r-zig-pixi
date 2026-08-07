# Phase 7 dry run: osx-64 and linux-aarch64, without hardware (2026-08-05)

Per `PLAN.md`'s Phase 7 — proves the remaining osx-64/linux-aarch64
placeholders `build.zig` deliberately fails loudly on (Phase 2) can be
resolved from real package inspection alone, no hardware required, and
records exactly what's left once that hardware/CI does arrive.

## 1. `pixi.lock` already has both platforms fully solved

Confirmed (already noted in `PLAN.md`'s Findings section, re-confirmed
here): `pixi.lock` contains 631 osx-64 lines and 676 linux-aarch64 lines
— pixi solves lockfiles for every platform declared in `pixi.toml`'s
`platforms = [...]`, regardless of which platform is running the solve.
Real, current conda-forge package refs, e.g.:

```
https://conda.anaconda.org/conda-forge/osx-64/gfortran_impl_osx-64-15.2.0-h3603427_19.conda
https://conda.anaconda.org/conda-forge/linux-aarch64/gfortran_impl_linux-aarch64-15.2.0-h2d9b6d1_19.conda
```

## 2. Real package inspection (not guessed)

Downloaded both `.conda` files directly (they're zip containers around an
inner `pkg-*.tar.zst`; extracted with Python's `zipfile` + `tar --zstd`,
no conda/pixi env needed to fetch or unpack a `.conda` package):

```sh
curl -sL -o gfortran_impl_osx-64.conda \
  https://conda.anaconda.org/conda-forge/osx-64/gfortran_impl_osx-64-15.2.0-h3603427_19.conda
python3 -c "import zipfile; zipfile.ZipFile('gfortran_impl_osx-64.conda').extractall('x')"
tar --zstd -tf x/pkg-gfortran_impl_osx-64-15.2.0-h3603427_19.tar.zst | grep lib/gcc/
```

**osx-64 real Darwin triple**: `x86_64-apple-darwin13.4.0` — genuinely
different from a naive pattern-substitution guess off the existing
`arm64-apple-darwin20.0.0` (the kernel-version component, 13 vs. 20,
isn't derivable by analogy — confirms Phase 2 was right not to guess it).
Full layout matches exactly what `findGfortranLibDir` already expects,
no changes needed to that function itself:

```
lib/gcc/x86_64-apple-darwin13.4.0/15.2.0/libgfortran.a
lib/gcc/x86_64-apple-darwin13.4.0/15.2.0/libgfortran.dylib
lib/gcc/x86_64-apple-darwin13.4.0/15.2.0/libgfortran.spec
```

**linux-aarch64 real triple**: `aarch64-conda-linux-gnu` — conda-forge's
own custom sysroot triple, not a generic `aarch64-unknown-linux-gnu`/
`aarch64-linux-gnu` (would also have been wrong to guess). Same layout
shape:

```
lib/gcc/aarch64-conda-linux-gnu/15.2.0/libgfortran.a
lib/gcc/aarch64-conda-linux-gnu/15.2.0/libgfortran.so
lib/gcc/aarch64-conda-linux-gnu/15.2.0/libgfortran.spec
```

## 3. The one-line diffs (reference only — NOT applied to build.zig)

Per the plan's own instruction, these are recorded as a reviewable
reference, not committed — Phase 2's loud-failure placeholders stay as
they are. Even with the gcc-root path corrected, `checkConfigFreshness`
would still fail immediately afterward with no
`zigbuild/config/osx-64-*`/`linux-aarch64-*` directory to find (§4) — so
applying just this piece wouldn't make either platform buildable anyway,
and this project's own established discipline is "verified on real
hardware," not "verified by inspection alone," before trusting a change
that ships.

```diff
         .macos => switch (arch) {
             .aarch64 => try findGfortranLibDir(b, io, b.fmt("{s}/lib/gcc/arm64-apple-darwin20.0.0", .{conda}), "libgfortran.a"),
-            .x86_64 => {
-                std.debug.print("error: osx-64 (Intel Mac) gfortran lib dir not yet verified — see Phase 7 of feat-cross-platform-standardization/PLAN.md\n", .{});
-                return error.UnverifiedOsx64GfortranDir;
-            },
+            .x86_64 => try findGfortranLibDir(b, io, b.fmt("{s}/lib/gcc/x86_64-apple-darwin13.4.0", .{conda}), "libgfortran.a"),
         },
```

```diff
             .linux => switch (arch) {
                 .x86_64 => "",
-                .aarch64 => {
-                    std.debug.print("error: linux-aarch64 gfortran lib dir not yet verified — see Phase 7 of feat-cross-platform-standardization/PLAN.md\n", .{});
-                    return error.UnverifiedLinuxAarch64GfortranDir;
-                },
+                .aarch64 => try findGfortranLibDir(b, io, b.fmt("{s}/lib/gcc/aarch64-conda-linux-gnu", .{conda}), "libgfortran.a"),
             },
```

## 4. What's still genuinely hardware-gated

Per `PLAN.md`'s Phase 0 (restored `configure`-only script + `gen-subst.sh`,
already generic for macOS/Linux, `gen-subst.sh:31-41`, no script changes
needed for a new arch on an OS it already supports):

1. Run `pixi run configure` on real osx-64 (or linux-aarch64) hardware —
   produces `build/obj-4.6.1-slim/config.status` for that platform.
2. Run `gen-subst.sh` there — writes `zigbuild/config/osx-64-slim/
   subst.txt` (or `linux-aarch64-slim/`), fully mechanically, from
   already-generic code.
3. Copy `config.h`/`Rconfig.h` from the same objdir, bump
   `GENERATED_FROM` — same 2-file copy + 1-line edit as every existing
   platform.
4. Apply §3's one-line diff above.
5. Run the full trust bar (`build`/`smoke`/`contract`/`check`/`install`/
   `package`/`verify-package`) for real, the same discipline as every
   other phase in this milestone — genuinely can't be skipped or
   simulated; this is the one step in the whole procedure that actually
   needs the hardware.

That's the complete remaining list. Everything else — `Arch` enum
plumbing, `config_dir` resolution, `gen-subst.sh`, the gcc-root lookup —
is confirmed mechanical and already reviewed/merged as of this milestone.

## Cleanup

Downloaded `.conda` files and extracted contents were scratch-only
(`$CLAUDE_JOB_DIR/tmp/phase7/`), not committed to the repo.
