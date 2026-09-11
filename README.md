# personal-ai-tooling
Personal AI Tools to share across workspaces

Skills and agents in this repo are shared across opencode, Claude Code and
GitHub Copilot. Third-party plugins and public skills are provisioned from a
single declarative manifest.

## Install

```bash
./install.sh                 # link this repo + install everything in plugins.json
./install.sh --no-plugins    # link this repo only
./install.sh --help
```

```powershell
.\install.ps1
.\install.ps1 -NoPlugins
```

The installer is idempotent — re-run it any time.

## What it does

1. **Links this repo's content.** `skills/` and `agents/` are symlinked
   (junctioned on Windows) into `~/.claude` and `~/.copilot`, and `skills/` is
   registered with opencode via `skills.paths`. New skills are picked up
   automatically without re-running the installer.
2. **Installs third-party plugins and public skills** declared in
   [`plugins.json`](plugins.json), via each tool's own CLI.

## Layout

| Path | Contents |
|---|---|
| `skills/<name>/SKILL.md` | A skill: YAML frontmatter + instructions |
| `agents/` | Custom agents |
| `prompts/` | Reusable prompts |
| `plugins.json` | Third-party plugins and public skills to install |
| `docs/` | Documentation for each installation method |
| `install.sh`, `install.ps1` | Installers |

## Plugins and public skills

Edit [`plugins.json`](plugins.json) and re-run the installer:

```json
{
  "claude":   { "marketplaces": ["anthropics/claude-plugins-official"],
                "plugins": ["superpowers@claude-plugins-official"] },
  "copilot":  { "marketplaces": [], "plugins": ["cache-stats@awesome-copilot"] },
  "opencode": { "plugins": ["opencode-models-discovery@1.5.3"] },
  "skills":   ["vercel-labs/agent-skills"]
}
```

Each installation method has its own document:

| Method | Document |
|---|---|
| Claude Code plugins | [docs/claude-plugins.md](docs/claude-plugins.md) |
| GitHub Copilot CLI plugins | [docs/copilot-plugins.md](docs/copilot-plugins.md) |
| opencode plugins | [docs/opencode-plugins.md](docs/opencode-plugins.md) |
| Public skills via npx | [docs/public-skills-npx.md](docs/public-skills-npx.md) |

Start with [docs/README.md](docs/README.md) for the manifest format and
installer options.
