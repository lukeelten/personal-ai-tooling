# Installation methods

`install.sh` / `install.ps1` do two separate jobs:

1. **Link this repo's own content** — `skills/` and `agents/` are symlinked
   (junctioned on Windows) into Claude Code and Copilot, and registered with
   opencode via `skills.paths`. Nothing to configure.
2. **Install third-party plugins and public skills** declared in
   [`../plugins.json`](../plugins.json), using each tool's own CLI.

This directory documents job 2 — one document per installation method:

| Document | Method | Underlying command |
|---|---|---|
| [claude-plugins.md](claude-plugins.md) | Claude Code plugins | `claude plugin marketplace add` / `claude plugin install` |
| [copilot-plugins.md](copilot-plugins.md) | GitHub Copilot CLI plugins | `copilot plugin marketplace add` / `copilot plugin install` |
| [opencode-plugins.md](opencode-plugins.md) | opencode plugins | `opencode plugin <npm-module> --global` |
| [public-skills-npx.md](public-skills-npx.md) | Public skills via npx | `npx skills add <owner/repo> --global` |

## The manifest

Everything is driven by `plugins.json` at the repo root:

```json
{
  "claude":   { "marketplaces": [], "plugins": [] },
  "copilot":  { "marketplaces": [], "plugins": [] },
  "opencode": { "plugins": [] },
  "skills":   []
}
```

Every section is optional — an absent or empty section is simply skipped.
Each list accepts a **short string form** and a **long object form**; see the
per-method documents for the exact fields.

## Running it

```bash
./install.sh                 # link repo content + install everything in plugins.json
./install.sh --no-plugins    # link repo content only
./install.sh --help
```

```powershell
.\install.ps1
.\install.ps1 -NoPlugins
.\install.ps1 -Manifest C:\path\to\plugins.json
```

### Options

| Bash | PowerShell | Meaning |
|---|---|---|
| `--no-plugins` | `-NoPlugins` | Skip the whole `plugins.json` section |
| `PAI_PLUGINS_MANIFEST=<path>` | `-Manifest <path>` | Use a different manifest |
| `PAI_SKILLS_CLI=<npm-spec>` | `-SkillsCliPackage <spec>` | Pin the public-skills CLI (default `skills@latest`) |

## Behaviour guarantees

- **Idempotent.** Every method checks the tool's own installed-state before
  acting and prints `[skip]` instead of reinstalling. Re-running the installer
  on a fully provisioned machine performs no writes.
- **Non-fatal.** A missing CLI prints `[skip]`; a failing install prints
  `[warn]` and the installer continues with the next entry. One broken plugin
  never aborts the run.
- **Non-interactive.** Every command is invoked with its non-interactive flag
  (`--yes`, `--scope user`, …) and with stdin detached, so the installer is
  safe to run unattended.

## Prerequisites

| Needed for | Requirement |
|---|---|
| All plugin sections | `jq` (bash only — the PowerShell script uses `ConvertFrom-Json`) |
| Claude plugins | `claude` on `PATH` |
| Copilot plugins | `copilot` on `PATH` |
| opencode plugins | `opencode` on `PATH` |
| Public skills | `npx` (Node.js) on `PATH` |

Anything missing is skipped with a message rather than failing the run.
