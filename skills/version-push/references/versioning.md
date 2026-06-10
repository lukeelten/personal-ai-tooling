# CMP chart versioning scheme

Reference for the `version-push` skill. This captures the chart-relevant
rules of the team's versioning convention so the bump produces a version that fits
how the charts are actually released.

## Format: `vYY.M.PATCH`

The team uses a CalVer-flavored scheme (documented at calver.org) where the
SemVer slots carry calendar meaning:

- **Major** = two-digit year — e.g. `24` for 2024, `26` for 2026.
- **Minor** = month of the year — e.g. `5` for May, `12` for December.
- **Patch** = incremented for bug fixes or minor changes within that release line.

So `v24.5.0` is the first release intended to roll out in May 2024, and `v24.5.1`
is a bug-fix release in that same line.

### Rules

- A leading **`v`** prefixes the version (e.g. `v24.5.0`).
- **No leading zeros** — write `v24.5.0`, never `v24.05.0`; May is `5`, not `05`.
- **No pre-release modifiers** — no `-alpha`, `-beta`, or `-rc` suffixes.

## When each component moves

- **Patch bump** — bug fixes or minor changes that don't warrant a new monthly
  release line. `v24.5.0 → v24.5.1`. This is the everyday default.
- **Minor / major bump** — happens when the rollout lands in a maintenance window.
  The new version should reflect the **month it is scheduled to roll out**, so a
  new monthly release recomputes `vYY.M.0` from that target month. A new year rolls
  the major automatically (it's just the two-digit year).

This is why the skill's `calver` mode resolves a *rollout month* to `vYY.M.0`
rather than blindly incrementing a number: the version is meant to communicate
*when* the release ships.

## How this maps to the bump script

| Intent | Script invocation | Result example |
|---|---|---|
| Routine bug-fix release | `--bump patch` (default) | `v24.5.0 → v24.5.1` |
| New release for the current month | `--bump calver` | `v24.5.3 → v26.6.0` (run in Jun 2026) |
| New release for a scheduled future window | `--bump calver --month 2026-09` | `→ v26.9.0` |
| Another release within the same month | `--bump calver` | `v26.6.0 → v26.6.1` |
| Pin an exact, deliberate version | `--bump set --to v26.7.0` | `→ v26.7.0` |

The script keeps the `v` prefix and refuses to write a version that isn't strictly
greater than the current one, which guards against accidentally rolling a chart
backwards when the calendar target is behind where the chart already is.

## Helm and the `v` prefix

Helm tolerates the leading `v` everywhere that matters: chart loading, `helm template`,
`helm lint`, and `helm package` all accept `v24.5.0` (the Masterminds semver parser
treats the `v` as optional). The packaged artifact is named literally, e.g.
`mychart-v24.5.0.tgz`.

The one cosmetic wrinkle: `helm lint` emits a **non-fatal warning** that the
`v`-prefixed value "is not a valid SemVer" because *strict* SemVer omits the `v`.
That warning does not fail the lint or the package step. Keep the `v` prefix to stay
consistent with the team convention; don't strip it just to silence the warning.

## Out of scope here

The broader CMP convention also covers Docker image tags (in-house images mirror this
`vYY.M.PATCH` scheme; upstream-adopted images mirror the upstream tag plus a `-c<N>`
suffix). That's not this skill's concern — this skill only bumps the Helm chart's
`version:` field.
