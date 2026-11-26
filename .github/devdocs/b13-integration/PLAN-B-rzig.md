# Build 13 integration, group B-rzig (zigbuild/tools/rzig/** only)

## Needs applied

| Need | Result |
|---|---|
| b13-build N3 (shims gone) | applied. parity-test.sh deleted (its reference was the shims). Its 60 `check` cases (check mode, `rzig build` tiers and preflight, `rzig build --shlib`), which never ran the shims, kept as **check-test.sh**: the same cases and helpers, with no shims, uname/xcrun stubs or run_case. The cross-OS command-line comparisons (157 run_case) and the one archive-copy `check` that depended on them went with the shims; compiler.zig, windows.zig, darwin.zig, archives.zig and the other unit tests cover those rules. test.sh runs check-test.sh where it ran parity-test.sh. smoke-test.sh: no `shims=` line, no `$T/bash`, one rzig build in `$T/out-rzig` (no `for kind in bash rzig` loop), no `cmp` against out-bash, the `.fini_array` check for rzig's libraries only; header text updated. References updated: build.zig:3, link-objects-test.sh:8, groups.zig's test comment. main.zig, cmdline.zig and cache.zig doc comments about the shims left as history (N3 says so). |
| b13-env-ci 1 (Windows pip lines) | applied as the PLAN's diff: `const pip = switch (g)`; Windows takes the non-linux compilers line, `pip install r-zig-build-tools; ...` and `pip install cmake`; the three win expected texts and the report test's `this.windows` branch changed. Group A's recipe/test-preflight.R must agree (non-linux line on Windows). scripts/wheel-test-windows.py accepts both texts. |
| b13-stress F11/N2 (`(zig)` in the trace) | applied in windows.zig: `lib -l<n> (zig)` when zig serves the name itself (`zigServes`): its runtimes by name (c, m, pthread, winpthread, mingw32, mingwex, uuid, dxguid, c++, stdc++, c++abi, supc++, unwind, gcc, gcc_s, gcc_eh) and any name with a MinGW .def in zig's lib dir (libc/mingw/lib-common, then lib64 or libarm64 by R's arch). Lib dir: ZIG_LIB_DIR, else beside the zig rzig runs (`<dir>/lib` upstream/wheel, `<dir>/../lib/zig` conda); `python3 -m ziglang`: runtimes only. Trace only, argv unchanged. Evidence (delta, both zigs 0.17.1, x86_64 and aarch64 windows-gnu, a non-archive lib<n>.a first on -L): served = exactly the runtimes above plus the .def names (ws2_32, ole32, kernel32, psapi, shell32, bcrypt, ntdll; aclui/CINTIME on x86_64 only, lib64; msvcrt and synchronization on conda-forge's zig only, whose lib-common has those .def files); `foo`, `gdal`, `ucrt` and `WS2_32` (case, on linux) read the file. New unit test. stress.R needs no change (b13-stress N2). |
| b13-hosts N1 (ar.zig comment) | applied, the exact diff. |
| libs-zig-pixi (1) --disable-auto-import | applied in linker_args.zig: `--disable-auto-import` and `-disable-auto-import` dropped inside -Wl,, after -Xlinker and on their own; doc paragraph; unit test (also keeps `--enable-auto-import` and `--disable-runtime-pseudo-reloc`). Evidence: both zigs 0.17.1 (delta): `-Wl,`/`-Xlinker` forms "error: unsupported linker arg: --disable-auto-import" (and `-disable-auto-import`), bare form "unknown clang option". |
| libs-zig-pixi (2) windres for meson | applied in binutils.zig: `--version` keeps its first line (`GNU-compatible windres (rzig, zig rc, ...)`, which verify-bundle.sh matches) and adds `Takes GNU windres options; zig rc compiles.`, which meson's `^.*GNU windres.*$` (re.MULTILINE) matches. meson 1.12.1's windres call (mesonbuild/modules/windows.py): `<args> -I<dir>... @INPUT@ @OUTPUT@ --preprocessor-arg=-MD --preprocessor-arg=-MQ@OUTPUT@ --preprocessor-arg=-MF@DEPFILE@`; rzig already took all of it (the preprocessor args are dropped: zig rc has no make-style depfile, so no depfile is written; ninja reads a missing gcc depfile as no dependencies, so a change to an included header does not rebuild the resource). Unit tests for meson's form and `--include-dir=`. |

## Tests

| where | command | result |
|---|---|---|
| delta, conda-forge zig 0.17.1 | `pixi run rzig-test` | EXIT=0: 238/238 unit tests; check-test.sh 60 passed, 0 failed; link-objects-test ok |
| delta, upstream zig 0.17.1 (PyPI ziglang, uv cache) | `ZIG_BIN=<ziglang>/zig pixi run rzig-test` | EXIT=0: 238/238; 60 passed, 0 failed; link-objects ok |
| delta | `pixi run bash zigbuild/tools/rzig/smoke-test.sh` (part 1, no prefix) | 0: four ok lines (build and run, SONAMEs/libstdc++/glibc 2.14, .fini_array, dlclose) |
| delta | `zig fmt --check zigbuild/tools/rzig/` | clean |
| delta | meson 1.12.1 + ninja (`pixi exec`), cross file x86_64-windows-gnu (`zig cc`), `windres =` a copy of the new rzig, project with `windows.compile_resources('app.rc', include_directories: 'inc', args: ['-DFROM_ARGS=1'])` | setup: "Windows resource compiler: Takes GNU windres options; zig rc compiles."; ninja built app.rc_app.o (350 bytes) and app.exe. Scratch removed |
| delta | `-l<n>` probe above (F11 rule) | as in the table |

Not run: smoke-test.sh part 2 (needs a tree with this rzig; part 2 is unchanged); kappa/omicron (nothing host-specific changed: the trace and windres text were checked by unit tests and the cross build).

## Open

- scripts/pkg-parity.sh:275 (not this group's file) still names parity-test.sh in a comment; pixi.toml's rzig-test comment is b13-build N1's.
- windres under meson writes no depfile (above). If wanted later: zig rc's `/:depfile` (JSON) converted by rzig to make syntax.
