---
name: version-push
description: |
   Increase (bump) the version of an existing Helm chart, then commit and push the change to origin. Use this skill whenever the user wants to release a new chart version, bump/increment/raise a Chart.yaml version, cut a monthly chart release, or says things like "bump the keycloak chart patch version", "bump the month version for the chart and push it", "release v24.6.0", or "increment the chart version and commit" — even if they don't say the word "Helm". The user must specify the bump type as either **patch** (bug-fix increment: vYY.M.Z → vYY.M.Z+1) or **month** (new monthly CalVer release: → vYY.M.0); ask if not provided. This handles the full release motion: editing the top-level `version:` field, a Conventional Commit, and a push to the current branch. It is NOT for scaffolding new charts (use helm-expert for that).
---

# Bump a Helm chart version, commit, and push

This skill performs the small-but-fiddly release motion teams repeat constantly: raise a chart's `version`, commit it cleanly, and push. The fiddliness is real — you must edit the *right* `version:` line (not `appVersion:` or a dependency's), keep the repo's prefix/quoting style, write a tidy commit, and avoid pushing to a protected branch. The bundled script handles the version math safely; your job is to orchestrate the surrounding git steps and make good judgment calls.

By default this bumps **only the chart's own `version:`** field — not `appVersion`. `appVersion` tracks the app being deployed and changes on a different cadence, so leave it alone unless the user explicitly asks.

## Workflow

1. **Locate the chart.** If the user names a chart or path, use it. Otherwise look for `Chart.yaml` in the working directory, then for `*/Chart.yaml` / `charts/*/Chart.yaml`. If several charts match and it's ambiguous which one they mean, ask rather than guess.
2. **Identify the bump command** from the user's message (see *Choosing the bump*). The user should provide either `patch` or `month` explicitly. If neither is present, **ask before proceeding** — do not guess.
3. **Run the script** (see *Running the script*). It edits the version in place and prints the old/new versions plus a `RESULT_JSON` line you'll reuse for the commit.
4. **Eyeball the diff** with `git diff -- <Chart.yaml>`. Confirm only the `version:` line changed and that no unrelated pre-existing edits to that file are about to be swept in.
5. **Check the branch before doing anything remote.** Get it with `git rev-parse --abbrev-ref HEAD`. If it's `main`, `master`, or `HEAD` (detached), **stop and tell the user** — pushing a release straight to a protected branch is exactly what we want to avoid. Offer to create a branch like `chore/bump-<chart>-<new_version>` instead.
6. **Commit** just the chart file with a Conventional Commit (see *Commit message*).
7. **Push** to the current branch's upstream and **open a PR** in the browser (see *Push*).
8. **Report** what happened: chart, old → new version, branch, commit subject, whether the push set up a new upstream, and the PR URL (or note if none was found in the push output).

## Choosing the bump

The user must supply one of two bump commands. Map it directly to the script's `--bump` flag:

| Command | Script flag | What it does |
|---|---|---|
| `patch` | `--bump patch` | Bug-fix increment: vYY.M.Z → vYY.M.**Z+1** |
| `month` | `--bump calver` | New monthly release: → v**YY.M**.0 (recomputed from the rollout month) |

If the user has not specified `patch` or `month`, **ask them** before running the script:

> "Should I bump the patch version (bug fix: v24.5.0 → v24.5.1) or the month version (new monthly release: → v26.6.0)?"

The `month` command uses the CMP CalVer scheme (`vYY.M.PATCH`, two-digit year, month with no leading zero, leading `v` — see `references/versioning.md`). It computes `vYY.M.0` for the rollout month (default: today; pass `--month YYYY-MM` for a future window). If the chart is already on that month it falls back to a patch bump, and it refuses to move the version backwards.

For anything beyond `patch` and `month` (raw `minor`/`major` bumps, pinning an exact version with `set`), the script supports those via `--bump minor`, `--bump major`, and `--bump set --to <version>`, but they are escape hatches — the user should state that intent explicitly.

## Running the script

The script is dependency-free (Python 3.8+) and only touches the top-level `version:` line, preserving comments, key order, the `v` prefix, and quoting.

```bash
python3 <skill-dir>/scripts/bump_chart_version.py <path-to-Chart.yaml-or-dir> [--bump MODE] [options]
```

```bash
# Default patch bump
python3 scripts/bump_chart_version.py charts/keycloak/Chart.yaml

# New monthly release for the current month (vYY.M.0)
python3 scripts/bump_chart_version.py charts/keycloak --bump calver

# A future maintenance window
python3 scripts/bump_chart_version.py charts/keycloak --bump calver --month 2026-09

# Pin an exact version
python3 scripts/bump_chart_version.py charts/keycloak --bump set --to v24.6.0

# Preview without writing
python3 scripts/bump_chart_version.py charts/keycloak --dry-run
```

Capture the `RESULT_JSON` line — its `chart_name`, `old_version`, and `new_version` feed the commit message and your final report. If the script exits non-zero (e.g. a backwards calver target, or no `version:` found), read the message and resolve it with the user instead of forcing the edit by hand.

## Commit message

Use Conventional Commits so release tooling and changelogs can parse it. Scope is the chart name from `RESULT_JSON`:

```
chore(<chart_name>): bump chart version to <new_version>
```

**Example:** `chore(keycloak): bump chart version to v26.6.0`

Stage **only the chart file** so the release commit stays focused:

```bash
git add charts/keycloak/Chart.yaml
git commit -m "chore(keycloak): bump chart version to v26.6.0"
```

If the chart name is missing for some reason, drop the scope: `chore: bump chart version to v26.6.0`.

## Push

Push to the branch the user is on (never force-push). Capture the combined output so you can extract the PR URL that git prints:

```bash
PUSH_OUT=$(git push 2>&1)
echo "$PUSH_OUT"
```

If no upstream is set yet, add `-u`:

```bash
PUSH_OUT=$(git push -u origin <branch> 2>&1)
echo "$PUSH_OUT"
```

Surface any push rejection (e.g. the remote moved ahead) to the user rather than reaching for `--force`.

### Opening the PR in the browser

After a push to a new branch, git prints a URL in its `remote:` output — GitHub renders it as:

```
remote: Create a pull request for 'branch-name' on GitHub by visiting:
remote:      https://github.com/org/repo/pull/new/branch-name
```

GitLab uses a similar format. Extract that URL and open it with the system default browser:

```bash
PR_URL=$(echo "$PUSH_OUT" | grep -Eo 'https?://[^[:space:]]+' | tail -1)
if [ -n "$PR_URL" ]; then
  python3 -m webbrowser "$PR_URL"
fi
```

`python3 -m webbrowser` is stdlib and works on Linux, macOS, and Windows without extra dependencies. If no URL appears in the push output (e.g. the branch already had an open PR, or the remote doesn't emit one), skip silently and report the URL as "none found in push output".

## Verification

If `helm` is installed, a quick `helm lint <chart-dir>` confirms the bumped Chart.yaml still parses. Note that a **leading `v` triggers a non-fatal lint *warning*** ("version 'v24.6.0' is not a valid SemVer") because strict SemVer omits the `v` — this is expected for the CMP scheme and does not fail the lint or `helm package`. Don't strip the team's `v` prefix just to silence it.

## Gotchas

- **Don't touch `appVersion`** unless asked — it's a separate field with a separate lifecycle.
- **Protected branches** (`main`/`master`/detached HEAD) are a hard stop for the push step; offer a feature branch instead.
- **Preserve existing format.** The script keeps the chart's current prefix and quoting; only override with `--prefix` if the user explicitly wants to add or remove the `v`.
- **Focused commit.** Stage the single Chart.yaml, not `git add -A`, so unrelated working-tree changes don't ride along.
