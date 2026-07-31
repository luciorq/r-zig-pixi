# Plan: self-hosted CI for the conda-package build + publish pipeline (2026-07-30)

**Status: planned, approved, not yet implemented.** Deliberately postponed
until after the `worktree-feat-zig-build` branch merges back to `main` —
a cleaner base for CI changes than an in-progress feature branch, and it
lets the newly-added `pixi run contract` (`pak`) checks and the F7.6/F7.7/
F7.8 fixes land on `main` before anything about the release pipeline
itself changes.

## Context

Every conda-package release so far (build numbers 2 through 8) has been
produced the same fully manual way: SSH into kappa/omicron (gamma is the
same machine this whole project's Linux work runs on directly — confirmed
via `hostname`), scp changed files over one by one, run `rattler-build
build`, then `rattler-build upload prefix`. This has repeatedly hit real
friction: quoting bugs across the SSH → PowerShell → bash chain (see
`feat-zig-build/TODO.md`'s F7.7 for one concrete example that cost real
debugging time), stale-process-tracking issues (a background SSH wrapper
reporting "completed" while the actual spawned R/gcc process tree was
still running), and transient `prefix.dev` network errors needing manual
retries.

`.github/workflows/build.yml` already has a full build+test matrix
(`build`, `build-windows`, `build-legacy`, `build-windows-legacy`) on
GitHub-**hosted** runners, triggered automatically on push/PR — that part
already works and isn't the pain point. The gap is narrow: the
`conda-package` job builds and tests the conda package on hosted runners
but **never publishes it**. This plan closes that gap.

See `PLAN.md` (this same folder) for the comparison against Option A
(OIDC trusted publishing on hosted runners) — this doc covers only the
chosen approach (Option B: self-hosted runners) in implementation detail.

**Woodpecker CI was considered and rejected** (asked directly, mid-
planning): this repo already lives on GitHub with a working `build.yml` —
self-hosted GitHub runners reuse it (a `runs-on` swap + one new step)
instead of a rewrite in a different YAML dialect. Woodpecker also needs
its own server + database to stand up and maintain, where GitHub Actions
self-hosted runners need none (GitHub itself is the coordinator).
Woodpecker's main strength is Docker-native pipelines, which doesn't help
2 of the 3 platforms here — macOS and native Windows builds aren't
meaningfully containerizable — so its flagship benefit wouldn't even
apply.

## Phase 1 — provision runners on gamma, omicron, kappa

Needs a GitHub Actions runner registration token per machine (repo-admin
access required to generate one — `gh api
repos/<owner>/<repo>/actions/runners/registration-token`, or manually via
the repo's Settings → Actions → Runners → "New self-hosted runner" page;
tokens expire in ~1 hour so generate right before each machine's setup
step, not all three in advance).

On each machine:
1. Download the matching `actions-runner` release archive (linux-x64 for
   gamma, osx-arm64 for omicron, win-x64 for kappa) into a dedicated
   directory (e.g. `~/actions-runner`), extract it.
2. `./config.sh --url https://github.com/<owner>/<repo> --token <token> --labels self-hosted,<os>,<machine-name>`
   (`config.cmd` on kappa) — e.g. `linux,gamma` / `macos,omicron` /
   `windows,kappa`, so workflows can target an exact machine or just an OS.
3. Install as a persistent background service so it survives
   reboot/disconnect without needing to be manually started:
   `sudo ./svc.sh install && sudo ./svc.sh start` (gamma/omicron), the
   Windows service-install equivalent (kappa) — run under the same user
   account already used for all this project's pixi/rattler-build work,
   so it inherits the existing auth + caches automatically.

This is the one genuinely hard-to-reverse step in this plan (installing
OS-level persistent services on 3 real machines, two of which aren't the
machine driving the work) — get explicit go-ahead immediately before
running the install/service commands on kappa and omicron specifically,
even though the overall plan has already been approved.

## Phase 2 — add self-hosted build+publish to `.github/workflows/build.yml`

Change the existing `conda-package` job:
- `runs-on: ${{ matrix.os }}` (today: `[ubuntu-latest, macos-latest,
  windows-latest]`) → a matrix over the new self-hosted labels
  (`[self-hosted, linux]` / `[self-hosted, macos]` / `[self-hosted,
  windows]`).
- Drop the `prefix-dev/setup-pixi@v0.10.0` step — the self-hosted
  machines already have pixi installed and the `pkg` env resolvable from
  cache; no need to reinstall it every run the way a hosted runner would.
- Keep the existing `pixi run -e pkg conda-package` step unchanged.
- Add a publish step reusing `pixi.toml`'s already-existing per-platform
  `conda-publish` task (`[feature.pkg.target.<platform>.tasks]` already
  resolves the right `dist/conda/<platform>/*.conda` glob automatically —
  no new task needed):
  ```yaml
  - name: Publish to prefix.dev
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    run: pixi run -e pkg conda-publish
  ```
  Gated to push-on-main only, never PRs — matches this doc's own stated
  intent above, and is extra conservative given these are personal
  machines (the repo is private, so the fork-PR risk GitHub warns about
  for self-hosted runners doesn't apply, but no reason to publish
  speculative PR builds either).

No new GitHub secrets — auth is the already-established local
`rattler-build auth login` session on each machine (see `PLAN.md`'s
"Interim strategy" section for how that was set up).

The `recipe.yaml` build-number bump before a real release stays a manual
step, same as today — `--skip-existing` makes a forgotten bump a safe
no-op rather than a broken publish. A real auto-versioning scheme is a
separate, still-open decision (see `PLAN.md`'s implementation sketch
history), out of scope here.

## Phase 3 — verify end-to-end for real

- Trigger a real run (push to main, or `workflow_dispatch` if added)
  after bumping `recipe.yaml`'s build number, and watch it land on the
  self-hosted runners, build+test+publish, and confirm the new artifact
  actually appears on prefix.dev — same "verify for real, not just YAML
  review" discipline as everything else in this project.
- Confirm none of this session's leftover manual-testing state on
  kappa/omicron (stray `dist/testlib`, `00LOCK-*` dirs, the
  `test-pixi-r-zig` project, etc.) interferes with the runner's own
  checkout directory — the runner uses its own `actions-runner/_work/`
  tree, separate from `r-zig-pixi-zig-build`, so this should already be
  naturally isolated; confirm rather than assume.

## Phase 4 — docs

- Update `PLAN.md`'s "End goal" section status once implemented (currently
  marked "planned, not yet implemented").
- Record the three runners' labels/machine mapping here for future
  reference once registered.

## Phase 1 — done (2026-07-30)

All three runners provisioned, registered, and confirmed `online` via
`gh api repos/luciorq/r-zig-pixi/actions/runners`:

| machine | os      | labels                               | service                                                              |
|---------|---------|---------------------------------------|-----------------------------------------------------------------------|
| gamma   | linux   | `self-hosted,linux,gamma`            | systemd, installed via `sudo ./svc.sh install && sudo ./svc.sh start` (user ran directly, sudo needs a TTY) |
| omicron | macOS   | `self-hosted,macos,omicron`          | per-user LaunchAgent via `./svc.sh install && ./svc.sh start` — **must not** run under `sudo`, `svc.sh` refuses it outright |
| kappa   | windows | `self-hosted,windows,kappa`          | Windows Service via `config.cmd --runasservice`, runs as `NT AUTHORITY\NETWORK SERVICE` |

One real gotcha hit on kappa: the runner was first installed under
`C:\Users\admin\actions-runner-kappa`. `NETWORK SERVICE` cannot traverse a
user profile directory (`C:\Users\admin` itself is ACL'd against it), so
the service installed and reported "started successfully" but the listener
process crashed immediately on every launch with
`UnauthorizedAccessException: Access to the path 'C:\Users\admin' is
denied.` (visible in `_diag/Runner_*.log`, not in the install-time
console output). Fixed by removing the runner (`config.cmd remove
--token <removal-token>`) and reinstalling at `C:\actions-runner-kappa`
instead — outside any user profile, so the default `NETWORK SERVICE` ACLs
work unmodified. Takeaway for any future Windows runner: install to a
plain top-level path, not under `C:\Users\<name>\...`.

Also observed: right after (re)registering, `gh api .../runners` can
report a freshly-connected runner as `offline` for up to ~15-20s even
though its own `_diag` log already shows `Listening for Jobs` with no
errors — a GitHub-side status-propagation lag, not a real disconnect.
Confirmed by polling 3x at 15s intervals until all three settled on
`online` consistently. Don't chase this by restarting services unless the
process log itself shows an actual error/crash.

A second, related gotcha found while wiring up Phase 2 (dropping
`setup-pixi` means jobs rely on each runner's own `.path` file to find
`pixi` — the GitHub Actions runner reads a `.path` file in its root dir,
one entry per line, and prepends it to the job's `PATH`):
- **omicron**: `.path` existed but only had system dirs, missing
  `/Users/luciorq/.pixi/bin` — fixed by rewriting it to include that.
- **kappa**: `.path` didn't exist at all, and pixi lived at
  `C:\Users\admin\AppData\Local\pixi\bin\pixi.exe` — the *exact same*
  `NETWORK SERVICE`-can't-read-a-user-profile problem as the runner
  install path above (`icacls` confirmed no ACL entry for `NETWORK
  SERVICE` on that file). Fixed the same way: copied `pixi.exe` to
  `C:\pixi\bin\pixi.exe` (a fresh top-level dir, default ACLs grant
  `Authenticated Users` — which includes `NETWORK SERVICE` — read+execute),
  and pointed kappa's new `.path` file at `C:\pixi\bin`. Not yet verified
  under an actual queued job (only ACLs inspected) — first real
  `conda-package / windows` run is the real test.
- **gamma**: already had a correct `.path` from earlier setup, no change
  needed.

## Phase 2 — done (2026-07-30)

`.github/workflows/build.yml`'s `conda-package` job now matrixes over
`labels: [self-hosted, linux|macos|windows]` instead of hosted-runner
`os:` strings, drops the `prefix-dev/setup-pixi` step, and adds a
`Publish to prefix.dev` step gated to `github.ref ==
'refs/heads/main' && github.event_name == 'push'` (reuses `pixi.toml`'s
existing per-platform `conda-publish` tasks, confirmed present for all 4
platform targets — no new task needed). Matrix keys renamed
`matrix.os` → `matrix.name` (`linux`/`macos`/`windows`) since `runs-on`
now needs the `labels` array, not a bare os string; the Windows-only
`Fresh-env consume test` step's `if:` condition was updated to match
(`matrix.name == 'windows'`).

Committed and pushed by the user (2026-07-30). First real run
(`30572259051`) surfaced two genuine bugs, both specific to a self-hosted
runner that already has pixi installed for interactive use (unlike a
fresh hosted VM):

- **omicron (macOS)**: job failed with `pixi: command not found`. The
  `.path` file (see Phase 1's writeup above) was correct on disk, but a
  GitHub Actions runner only reads `.path` at the *listener/service*
  process's own startup, not per-job — it had been written after the
  LaunchAgent was already running, so the fix never actually took effect
  until the service was restarted (`launchctl kickstart -k
  gui/$(id -u)/actions.runner.luciorq-r-zig-pixi.omicron`). Lesson: any
  `.path`/`.env` edit on an already-running self-hosted runner needs an
  explicit restart, not just the file write.
- **kappa (Windows)**: failed even earlier than pixi resolution —
  `running scripts is disabled on this system`
  (`PSSecurityException`/`UnauthorizedAccess`). The runner service (as
  `NETWORK SERVICE`) invokes each step's generated `.ps1` via
  `powershell -command ". '{0}'"`; `Get-ExecutionPolicy -List` showed
  every scope `Undefined`, which defaults to `Restricted` — blocks all
  script execution regardless of account. Fixed with `Set-ExecutionPolicy
  -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force` (must be
  `LocalMachine` scope specifically — `CurrentUser`/`Process` scope set
  from an interactive admin session doesn't apply to the `NETWORK
  SERVICE` account's own effective policy).

A third, unrelated regression from mid-flight manual debugging: someone
added a `prefix-dev/setup-pixi@v0.10.0` step directly to `conda-package`
in-between runs, trying to fix the "not found" error above — this made
things worse (`Destination file path /Users/luciorq/.pixi/bin/pixi
already exists`, since the action isn't designed to run against a
runner that already has pixi installed globally). Reverted; the fix is
the `.path` file + service restart above, not adding `setup-pixi` back.

Next real run after these three fixes surfaced two more, genuinely
distinct bugs on kappa specifically — both about long paths, but at two
different layers:

- **`dlltool` vs. Windows' 260-char `MAX_PATH`**: `x86_64-w64-mingw32-
  dlltool` builds each import-lib "head file" temp name by flattening
  the *entire* resolved absolute output path into one string (separators
  replaced with `_`), then opens that flat name in the current working
  directory — so the final open call is roughly `2×cwd_len +
  output_arg_len`, not just `cwd_len`. With the runner's default
  `_work\r-zig-pixi\r-zig-pixi\dist\conda\bld\rattler-
  build_r-zig-slim_<timestamp>\work` as cwd (107 chars), that blew past
  260 for real (`failed to open temporary head file: ...`, confirmed
  reproduced directly on kappa, not just in CI). Confirmed this is
  **not** the OS-level `MAX_PATH` — flipping `HKLM\SYSTEM\
  CurrentControlSet\Control\FileSystem\LongPathsEnabled` to `1` changed
  nothing (old mingw-w64 binutils uses a fixed-size internal buffer, not
  a Win32 API call that the modern long-path policy patches). Fixed by
  shortening the two things that actually compound: reconfigured kappa's
  runner with a short `--work C:\w` (via `config.cmd remove` +
  reconfigure, same maneuver as the profile-directory fix in Phase 1),
  and added `--no-build-id` to `pixi.toml`'s `conda-package` task (drops
  rattler-build's own `_<timestamp>` suffix from its `bld/` directory
  name). Verified directly on kappa: a manual `rattler-build build
  --no-build-id` under the new short `C:\w\...` tree completed with zero
  `dlltool` errors, all the way through packaging.
- **git-for-windows vs. the same 260-char limit, at a different layer**:
  once the build itself got past the dlltool issue, the *next* run's
  checkout step failed to clean up the previous run's deep `dist/conda/`
  tree (`hint: Setting core.longPaths may allow the deletion to
  succeed`), and `actions/checkout`'s own fallback (delete-and-recreate
  the whole workspace) hung indefinitely (confirmed: the job sat
  `in_progress` for 44+ minutes, `node`/`Runner.Worker` on kappa idle at
  0% CPU — not slow, genuinely stuck). Root cause: git-for-windows has
  its *own* long-path opt-in, `core.longpaths`, entirely separate from
  the OS-level `LongPathsEnabled` policy above — it was unset. Fixed with
  `git config --system core.longpaths true` (system scope, so it applies
  to `NETWORK SERVICE` too, not just the interactive admin account).
  Also cleaned up `C:\w\r-zig-pixi` by hand — the stuck run's directory
  contained leftovers from the manual `dlltool` reproduction above (same
  `C:\w` root, since that's the runner's real `--work` dir), which is
  most likely what the real checkout step choked on in the first place.

Both fixes are infra-only (runner reconfiguration, git config) plus the
one-line `--no-build-id` in `pixi.toml` — no `build.zig` changes needed
for either.

A fourth bug, unrelated to any path-length work above and actually the
very first Windows failure seen (present before any of today's fixes,
just never reached root-cause since later stages kept failing first):
`rattler-build`'s own source-fetch step failed to extract R's source
tarball — `Failed to unpack ...\src_cache\...\R-4.6.1\src\library\
Recommended\cluster.tgz`. Root cause, confirmed via `tar -tvzf` on the
real downloaded tarball: R ships its 15 "Recommended" packages (cluster,
class, survival, MASS, ...) as **symlinks** (e.g. `cluster.tgz ->
cluster_2.1.8.2.tar.gz`) — a completely ordinary Unix packaging
convention that Windows can't replicate without either
`SeCreateSymbolicLinkPrivilege` or Developer Mode enabled; `NETWORK
SERVICE` has neither by default, so the Rust `tar` crate's symlink-
creation call fails on the first such entry it hits (`cluster.tgz` sorts
first alphabetically — every one of the 15 would have failed the same
way, one at a time, if patched around individually instead of at the
root cause).

First attempted fix — `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\
AppModelUnlock\AllowDevelopmentWithoutDevMode = 1` (the registry-level
equivalent of enabling Developer Mode, which lets `CreateSymbolicLinkW`
succeed unprivileged *if the caller passes
`SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE`*) — did **not** work: a
real CI run hit the exact same `cluster.tgz` error afterward, byte for
byte. Root cause of *that*: PowerShell's own `New-Item
-ItemType SymbolicLink` (used to verify the registry change) does pass
that flag, but rattler-build's underlying Rust `tar`-extraction code
apparently doesn't — so Developer Mode alone was never going to help
here regardless of how it was enabled. The actually-effective fix:
directly grant `NETWORK SERVICE` (`*S-1-5-20`) the real
`SeCreateSymbolicLinkPrivilege` local security right via `secedit`
(`secedit /export /cfg C:\secpol.cfg /areas USER_RIGHTS`, append
`,*S-1-5-20` to the `SeCreateSymbolicLinkPrivilege` line, `secedit
/configure ... /areas USER_RIGHTS`), which works unconditionally,
independent of whether the calling code requests the unprivileged flag.
Needed a runner **service restart** afterward — local security rights
are baked into a process's logon token at token-creation time, so the
already-running service's token didn't have it until a fresh one was
created. Verified for real: a subsequent CI run's `conda-package /
windows` leg ran for 12+ minutes (vs. ~1 minute for every prior
`cluster.tgz` failure) and got all the way through fetching, building,
and packaging with zero extraction errors.

A fifth, unrelated bug surfaced immediately after — the first time the
Windows leg has ever gotten this far in an automated run. rattler-
build's own package-test phase failed with `Script failed with status
9009` (cmd.exe's "command not found"). Cause: `recipe/recipe.yaml`'s
Windows test script literally read `$PREFIX/Library/lib/R/bin/x64/
Rscript.exe test-win.R` — bash variable syntax (`$PREFIX`), meaningless
to cmd.exe, which tried to run a program named that verbatim. This line
already existed *before* today specifically because `%PREFIX%` (the
correct cmd.exe syntax) had separately been found not to expand either
in this sandbox (see the file's own long-standing comment about an
`echo %PATH%` probe) — but nobody had caught that its replacement used
the wrong shell's syntax entirely, since no automated Windows run had
ever gotten far enough to exercise this exact line before today. Fixed
by dropping PREFIX substitution entirely in favor of a plain relative
path (`../../../../../Library/lib/R/bin/x64/Rscript.exe`) — the test's
cwd is always exactly 5 levels below the test-env root
(`<test_run_env>/etc/conda/test-files/r-zig-slim/0`, both segments
fixed for this recipe), so this works identically regardless of which
shell dialect actually executes it.

Next real run after all five fixes is the actual Phase 3 check.
