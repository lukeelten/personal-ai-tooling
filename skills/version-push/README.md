# version-push

Bump a Helm chart version, commit it with a Conventional Commit, push to origin, and open the PR in your browser — in one shot.

---

## What it does

1. Finds the `Chart.yaml` for the chart you name (or the one in the current directory).
2. Bumps only the top-level `version:` field — never `appVersion:` or dependency versions.
3. Stages **only** that file and commits with a tidy `chore(<chart>): bump chart version to <new>` message.
4. Pushes to your current branch (hard-blocked on `main` / `master`).
5. Extracts the PR/MR URL from the git push output and opens it in your default browser.

---

## How to trigger it

Just describe what you want in plain language. The skill activates on phrases like:

```
bump the keycloak chart patch version
bump the month version for platform-base and push it
release v26.6.0 for the auth chart
increment the ingress chart version and commit
```

You don't need to say "Helm" or "skill" — the description is enough.

---

## Bump types

There are two everyday commands. You must name one; if you don't, the agent will ask.

| Command | What you say | Result |
|---|---|---|
| **`patch`** | "bump the patch version" | `v24.5.0 → v24.5.1` — bug fix in the same release line |
| **`month`** | "bump the month version" | `v24.5.3 → v26.6.0` — new monthly release for the current rollout window |

The versioning scheme is CalVer-flavored: `vYY.M.PATCH` — two-digit year, month without leading zero, leading `v`, no pre-release suffixes. See [`references/versioning.md`](references/versioning.md) for the full convention.

> **Escape hatches** — `minor`, `major`, and `set` (pin an exact version) are supported via the underlying script but require explicit user intent.

---

## Protected branch guard

Pushing a release commit directly to `main` or `master` is blocked. If you're on a protected branch the agent will stop and offer to create a branch like `chore/bump-<chart>-<new-version>` for you.

---

## PR / MR in the browser

After the push, the agent parses the `remote:` lines that GitHub / GitLab print in the push output and opens the PR URL with your system default browser. Works on Linux, macOS, and Windows. If no URL appears in the push output (e.g. the branch already has an open PR), the agent skips silently and reports that no URL was found.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Python 3.8+ | The bundled script is stdlib-only — no `pip install` needed |
| Git | Any reasonably modern version |
| Remote origin configured | The push step assumes `origin`; the agent sets `-u` if no upstream exists yet |

`helm` is optional — if installed, a quick `helm lint` is run after the bump to confirm the chart still parses. A non-fatal `v`-prefix warning from `helm lint` is expected and safe to ignore.

---

## File structure

```
version-push/
├── SKILL.md                  # Agent-facing instructions (loaded by OpenCode)
├── README.md                 # This file
├── scripts/
│   └── bump_chart_version.py # Version math — edits only the version: line
├── references/
│   └── versioning.md         # CMP CalVer scheme reference
└── evals/
    └── evals.json            # Automated eval suite (4 scenarios)
```

### `bump_chart_version.py` quick reference

```
usage: bump_chart_version.py <Chart.yaml or chart-dir> [options]

--bump   patch | minor | major | calver | set   (default: patch)
--to     vYY.M.P                                 (required for --bump set)
--month  YYYY-MM                                 (calver: override rollout month)
--prefix keep | v | none                         (default: keep)
--dry-run                                        print result without writing
```

The script refuses to write a version that is not strictly greater than the current one and preserves the file byte-for-byte except for the single `version:` line.

---

## Eval results (iteration 1)

| Configuration | Score |
|---|---|
| with skill | **100 %** (4 / 4) |
| baseline (no skill) | 77.5 % |
| delta | **+22.5 pp** |

Scenarios covered: patch bump + push, new monthly CalVer release, protected-branch guard, explicit `set` version.
