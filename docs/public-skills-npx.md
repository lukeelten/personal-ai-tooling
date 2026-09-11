# Public skills via npx

Installs public Agent Skills from GitHub repositories using the
[`skills`](https://www.npmjs.com/package/skills) CLI
([vercel-labs/skills](https://github.com/vercel-labs/skills)), declared in the
top-level `skills` array of [`plugins.json`](../plugins.json).

This is the cross-tool method: `skills` fetches a repository of `SKILL.md`
files and links them into **every agent it detects** on the machine — Claude
Code, GitHub Copilot, opencode, Cursor and others — so one entry provisions a
skill everywhere at once.

Use this for skills that are published as a plain repo rather than packaged as
a Claude or Copilot plugin.

## Manifest format

```json
{
  "skills": [
    "vercel-labs/agent-skills",
    {
      "source": "owner/repo",
      "skills": "pr-review,commit",
      "agents": "claude-code",
      "scope":  "global"
    }
  ]
}
```

### `skills[]`

| Field | Default | Description |
|---|---|---|
| `source` | — | `owner/repo` slug or a full GitHub URL |
| `skills` | `"*"` | Comma-separated skill names to install, or `"*"` for all |
| `agents` | `"*"` | Comma-separated agent ids to install into, or `"*"` for all detected |
| `scope` | `"global"` | `global` (user-level) or `project` (current directory) |

The string form `"owner/repo"` is shorthand for
`{ "source": "owner/repo", "skills": "*", "agents": "*", "scope": "global" }`.

To discover what a repo offers before committing to it:

```bash
npx skills add owner/repo --list
npx skills find                 # interactive search
npx skills find --owner vercel-labs
```

## What the installer runs

```bash
npx -y skills@latest add <source> --global --skill <skills> --agent <agents> --yes
```

Pin the CLI version with the `PAI_SKILLS_CLI` environment variable
(`-SkillsCliPackage` in PowerShell) if you don't want `@latest`:

```bash
PAI_SKILLS_CLI='skills@1.5.25' ./install.sh
```

## ⚠️ Interaction with this repo's symlinks

The main installer symlinks this repo's `skills/` directory to
`~/.claude/skills` and `~/.copilot/skills`. The `skills` CLI installs
user-level skills into exactly those locations — which means **a global install
targeting `claude-code` or `github-copilot` writes into this repository's
working tree**, where it shows up as an untracked directory:

```console
$ git status --short
?? skills/vercel-optimize/
```

Pick one of these, depending on what you want:

- **Vendor it.** Commit the skill so every machine gets it from this repo. Then
  remove the entry from `plugins.json` — it's part of the repo now.
- **Keep it external.** Add the skill directory to `.gitignore` so the repo
  stays clean while the skill remains installed.
- **Avoid the collision.** Target agents that don't resolve to this repo, e.g.
  `"agents": "opencode"`.

Note that the `skills` CLI resolves the home directory from the OS, not from
`$HOME`, so overriding `HOME` does *not* redirect where it writes.

## Idempotency

The installer reads `npx skills list --global --json` and skips any entry whose
recorded `source`/`sourceUrl` contains the manifest's `source`:

```json
{ "name": "vercel-optimize", "scope": "global", "source": "vercel-labs/agent-skills",
  "path": "/home/you/.claude/skills/vercel-optimize", "agents": ["Claude Code"] }
```

Consequences worth knowing:

- Because the match is per-**source**, adding more names to an existing entry's
  `skills` list won't pull them in — the source is already present, so it is
  skipped. Install the extra ones manually, or remove the source first.
- Skills created locally (this repo's own) have `source: null` and therefore
  never collide with these checks.

## Verifying

```bash
npx skills list --global
npx skills list --global --json | jq -r '.[] | "\(.name)\t\(.source)"'
npx skills list --global --agent claude-code
```

## Managing skills by hand

```bash
npx skills add owner/repo --global --all         # everything, no prompts
npx skills add owner/repo --skill pr-review -g   # one skill
npx skills update                                # update all
npx skills update -g -y                          # update global, no prompts
npx skills remove <name> --global
npx skills remove --all -g                       # remove every installed skill
npx skills use owner/repo@skill                  # print a prompt without installing
```

`--all` is shorthand for `--skill '*' --agent '*' --yes`.

Removing an entry from `plugins.json` does not uninstall anything — use
`npx skills remove`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `failed to install public skills from …` | Repo doesn't exist, is private, or has no `SKILL.md`. Check with `npx skills add <source> --list`. |
| `npx not found` | Install Node.js; the section is skipped without it. |
| Skill installed but an agent doesn't see it | That agent wasn't detected at install time. Re-run with an explicit `--agent`, then restart the agent. |
| Unexpected `?? skills/<name>/` in `git status` | Expected — see the symlink note above. |
| Nested skills aren't found | The repo has a root `SKILL.md` that stops the search. Add `--full-depth`. |
