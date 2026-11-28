# Project conventions

Rules that hold across branches. A branch's own decisions stay in its
directory here (`.github/devdocs/<branch>/`).

## Goals and principles

What the project aims for (the user, 2026-11-26):

- **R built with one toolchain everywhere.** R and R packages compile
  with Zig (`zig cc`, LLVM flang) on Linux, macOS and Windows, x86_64
  and arm64.
- **Installable without system setup.** R comes as conda packages on
  prefix.dev `universe` (`r-zig-slim` plus add-on groups) or as a
  standalone archive. No Rtools, Xcode command line tools or system
  compiler. One exception, macOS: building R itself needs the macOS SDK
  (build.zig runs `xcrun --sdk macosx --show-sdk-path` and stops
  without it), and rzig adds the SDK's `System/Library/Frameworks` and
  `usr/lib` to package compiles when `xcrun` finds one, and warns on a
  link when it finds none (rzig darwin.zig; b13-rzig D3, D4). Installing
  the published packages needs no SDK.
- **Packages just build.** CRAN and Bioconductor packages, with C++,
  Fortran or system libraries, install from source. On Windows the
  system libraries come from zig-built `zig-*` packages
  (libs-zig-pixi).
- **Binary packages where they help.** A curated linux binary package
  repository, and native Windows build tools without MSYS2.

How the work is done:

- **Simplicity first.** One build path on every OS, in `build.zig` and
  Zig tools. No OS-specific shell tricks, sed post-processing or extra
  wrappers. Small stubs are Zig, not assembly or C.
- **No host leakage.** A build uses no host path, compiler or library.
  Everything comes from the env or the toolchain.
- **Layered toolchain.** A minimal base (R, `r-zig-slim`) plus
  optional groups (compilers, build tools, extras) and add-ons (the
  recommended packages, tcltk, Windows' native tools; the native tools
  are a separate package on conda only, and in the standalone
  toolchain they are `native/` in the build-tools archive). A user installs
  only what they need.
- **Both zigs.** Everything works with conda-forge zig and with
  upstream zig (PyPI ziglang), the reference. A conda-forge quirk gets
  an isolated workaround.
- **Evidence over job status.** Stress suites build hundreds of real
  packages per OS. Results are read row by row; every expected failure
  is recorded with its cause.
- **Careful releases.** One build number per publish, all subdirs
  together, a preflight before the upload, checks after it, and no
  `_N` deleted before `_N+1` is out ([RELEASE.md](RELEASE.md)).
- **Decisions on record.** Every decision and finding goes in the
  branch's `PLAN.md` here, with the options, the reason and the
  evidence.

## Skip tags

`[skip ci]` is allowed in one place only: the merge commit of a pull
request whose head already ran CI on the same tree, so that main does
not run it twice. Never on a commit pushed to a pull request (as its
newest commit it skips the whole push: #15's merge of main went
untested that way), and not on docs-only commits, which the workflows'
path filters skip already (chore-ci-tiers CI1). The user,
2026-11-26 (chore-review-consistency M2).

## Commit messages

Conventional Commits, with one of these types only (the user,
2026-11-11):

| Type | For |
| --- | --- |
| `feat` | a new capability: a platform, a toolchain group, an rzig applet |
| `fix` | a defect, including a failing CI leg's cause |
| `chore` | CI workflows, locks, version and build-number bumps, temporary diagnostics |
| `docs` | records under `.github/devdocs/`, README |
| `test` | tests and test scripts alone |
| `refactor` | a change of structure with the same behaviour |

Not `ci`, `build`, `perf` or `style`. A workflow change is `chore`, and a
scope may say so: `chore(ci): ...`. A build-number bump is `chore`.

Earlier commits on main that predate this rule: `d749a92` and `228af6a`
(`build:`, the build-number bumps for 9 and 10), `f7d1558` (`build:`,
zig 0.17, 2026-11-10) and `9d87132` (`ci:`).

No attribution lines in commit messages or pull request bodies: no
`Co-Authored-By`, no session links.
