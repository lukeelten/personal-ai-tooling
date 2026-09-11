# Claude Code plugins

Installs Claude Code plugins from plugin marketplaces, declared in the
`claude` section of [`plugins.json`](../plugins.json).

A Claude plugin can bundle skills, agents, slash commands, hooks and MCP
servers. Plugins always come from a **marketplace** — a git repository
containing a `.claude-plugin/marketplace.json` index — so installation is a
two-step process: register the marketplace, then install plugins from it.

## Manifest format

```json
{
  "claude": {
    "marketplaces": [
      "anthropics/claude-plugins-official",
      { "name": "company-tools", "source": "https://github.com/acme/tools.git" }
    ],
    "plugins": [
      "superpowers@claude-plugins-official",
      { "id": "deploy-tools@company-tools", "scope": "project" }
    ]
  }
}
```

### `claude.marketplaces[]`

| Form | Description |
|---|---|
| `"owner/repo"` | Shorthand. The marketplace name is derived from the repo name (`repo`). |
| `{ "name": …, "source": … }` | Explicit. Use this when the marketplace's declared `name` differs from its repository name. |

`source` accepts anything `claude plugin marketplace add` accepts: a GitHub
`owner/repo` slug, a git URL (`https://…​.git`, `git@host:org/repo`, optionally
with a `#ref` suffix), a local directory, or a path/URL to a `marketplace.json`.

> **Getting the name right matters.** The `name` is what the installer compares
> against the already-registered marketplaces to decide whether to skip. It must
> match the `name` field inside the marketplace's `marketplace.json`. If the
> shorthand derives the wrong name the marketplace is re-added on every run
> (harmless, but noisy) — use the object form to fix it.

### `claude.plugins[]`

| Form | Description |
|---|---|
| `"plugin@marketplace"` | Installed at `user` scope. |
| `{ "id": …, "scope": … }` | `scope` is `user` (default), `project`, or `local`. |

Always qualify the plugin with `@marketplace`. A bare `"superpowers"` works
when the name is unambiguous across your registered marketplaces, but is
resolved by Claude rather than pinned by you.

## What the installer runs

```bash
claude plugin marketplace add <source> --scope user
claude plugin install <plugin>@<marketplace> --scope <scope> --yes
```

`--yes` is required whenever stdin/stdout is not a TTY (which is the case when
the installer redirects output), and it accepts the marketplace-declared
install command for plugins that are installed by running one.

## Idempotency

Before adding a marketplace, the installer reads
`~/.claude/plugins/known_marketplaces.json` and skips names already present.
Before installing a plugin, it reads `claude plugin list --json` and skips
entries whose `id` already matches.

The underlying `claude` commands are themselves idempotent (they exit 0 and
report "already installed"), so the pre-checks exist to keep the output honest
and avoid needless network calls.

## Where things land

| Path | Contents |
|---|---|
| `~/.claude/plugins/known_marketplaces.json` | Registered marketplaces and their clone locations |
| `~/.claude/plugins/marketplaces/<name>/` | Cloned marketplace repositories |
| `~/.claude/plugins/installed_plugins.json` | Install state (scope, version, commit SHA) |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | The installed plugin payload |
| `~/.claude/settings.json` → `enabledPlugins` | Enable/disable flags, keyed `plugin@marketplace` |

On Windows these live under `%USERPROFILE%\.claude`, or under `CLAUDE_CONFIG_DIR`
when that variable is set.

> Adding a marketplace declaratively via `extraKnownMarketplaces` in
> `settings.json` registers it but does **not** install its plugins — Claude
> reports them as not installed. That is why this installer shells out to
> `claude plugin install` rather than only editing JSON.

## Verifying

```bash
claude plugin marketplace list
claude plugin list
claude plugin list --json | jq -r '.[].id'
```

Restart Claude Code for newly installed plugins to load.

## Managing plugins by hand

```bash
claude plugin install <plugin>@<marketplace> --yes   # install
claude plugin update <plugin>                        # update
claude plugin disable <plugin>                       # keep installed, turn off
claude plugin enable <plugin>
claude plugin uninstall <plugin> --yes
claude plugin marketplace update                     # refresh all catalogs
claude plugin marketplace remove <name>
```

Removing an entry from `plugins.json` does **not** uninstall it — the installer
only ever adds. Uninstall explicitly with `claude plugin uninstall`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `failed to register claude marketplace …` | Bad slug/URL, private repo without git credentials, or no network. Run the `claude plugin marketplace add` command manually to see the real error. |
| `failed to install claude plugin …` | The plugin name is not in that marketplace, or the marketplace was never registered. Check `claude plugin marketplace list`, then `claude plugin list --available --json`. |
| A marketplace is re-added on every run | The derived name doesn't match the marketplace's declared `name`. Switch to the `{ "name": …, "source": … }` form. |
| Plugin installed but not active | Restart Claude Code, and check `enabledPlugins` in `~/.claude/settings.json`. |
