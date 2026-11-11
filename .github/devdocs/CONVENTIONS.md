# Project conventions

Rules that hold across branches. A branch's own decisions stay in its
directory here (`.github/devdocs/<branch>/`).

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
(`build:`, the build-number bumps for 9 and 10) and `9d87132` (`ci:`).

No attribution lines in commit messages or pull request bodies: no
`Co-Authored-By`, no session links.
