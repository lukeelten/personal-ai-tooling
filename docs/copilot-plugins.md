# GitHub Copilot CLI plugins

Installs GitHub Copilot CLI plugins, declared in the `copilot` section of
[`plugins.json`](../plugins.json).

Copilot plugins extend the CLI with additional skills, agents, hooks, MCP
servers and LSP servers. Unlike Claude, Copilot can install a plugin **directly
from any GitHub repository** — a marketplace is only needed for the
`plugin@marketplace` shorthand.

Two marketplaces ship with the CLI and never need to be added:

| Name | Repository |
|---|---|
| `copilot-plugins` | `github/copilot-plugins` |
| `awesome-copilot` | `github/awesome-copilot` |

## Manifest format

```json
{
  "copilot": {
    "marketplaces": [
      { "name": "acme-marketplace", "source": "acme/copilot-plugin-marketplace" }
    ],
    "plugins": [
      "cache-stats@awesome-copilot",
      "owner/repo",
      { "name": "my-plugin", "source": "owner/repo:plugins/my-plugin" }
    ]
  }
}
```

### `copilot.marketplaces[]`

Same two forms as everywhere else: `"owner/repo"` shorthand, or
`{ "name": …, "source": … }`. A marketplace is a GitHub repository containing a
`marketplace.json` that indexes its plugins.

Leave this empty if you only install from the two built-in marketplaces or
directly from repositories.

### `copilot.plugins[]`

`source` is parsed in this order:

| Source | Meaning |
|---|---|
| `plugin@marketplace` | From a registered (or built-in) marketplace |
| `owner/repo` | Directly from a GitHub repository |
| `owner/repo:path` | From a subdirectory inside a repository |
| `https://…​.git` | From a git URL |

| Form | Description |
|---|---|
| `"<source>"` | Plugin name is derived from the source |
| `{ "name": …, "source": … }` | Explicit name |

**Use the object form for `owner/repo:path` sources.** The derived name comes
from the repository (`repo`), not the subdirectory, so it will not match the
plugin's real name and the installer would try to reinstall it on every run.
Set `name` to the plugin's actual name (usually the last path segment):

```json
{ "name": "my-plugin", "source": "owner/repo:plugins/my-plugin" }
```

## What the installer runs

```bash
copilot plugin marketplace add <source>
copilot plugin install <source>
```

## Idempotency

`copilot plugin marketplace add` is **not** idempotent — re-adding an existing
marketplace fails. The installer therefore always pre-checks: it parses
`copilot plugin marketplace list` (which covers both the built-in and the
registered marketplaces) and skips names already listed.

For plugins it parses `copilot plugin list` and skips a source whose plugin name
already appears there.

Because both checks are name-based, an accurate `name` is what keeps the run
clean — see the note above.

## Where things land

| Path | Contents |
|---|---|
| `~/.copilot/installed-plugins/` | Installed plugin payloads |
| `~/.copilot/installed-plugins.lock` | Resolved plugin versions |
| `~/.copilot/settings.json` | `enabledPlugins`, `extraKnownMarketplaces` |
| `~/.copilot/skills/`, `~/.copilot/agents/` | Personal skills/agents (this repo links these) |

On Windows these live under `%USERPROFILE%\.copilot`.

## Verifying

```bash
copilot plugin marketplace list
copilot plugin list
copilot plugins                          # inspect configured plugins across kinds
copilot plugin marketplace browse awesome-copilot
```

Restart the Copilot CLI for newly installed plugins to load.

## Managing plugins by hand

```bash
copilot plugin install <source>
copilot plugin update [name]
copilot plugin uninstall <name>
copilot plugin marketplace add <source>
copilot plugin marketplace update [name]
copilot plugin marketplace remove <name>
```

Removing an entry from `plugins.json` does not uninstall it; run
`copilot plugin uninstall <name>` explicitly.

## Related: skills, not plugins

This repo's own skills are linked into `~/.copilot/skills` by the main
installer, so they need no plugin entry. To pull in a *single* external skill
without a plugin:

```bash
copilot skill add https://example.com/my-skill/SKILL.md   # from a URL
copilot skill add ./my-skill/SKILL.md                     # from a file
copilot skill add ~/my-custom-skills                      # register a directory
copilot skill list
```

For installing whole public skill repositories, see
[public-skills-npx.md](public-skills-npx.md).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `failed to register copilot marketplace …` | Already registered under a different name, bad slug, or the repo has no `marketplace.json`. Check `copilot plugin marketplace list`. |
| `failed to install copilot plugin …` | Unknown plugin name, unregistered marketplace, or a `owner/repo:path` that doesn't contain a plugin manifest. Run the install command manually for the real error. |
| A plugin reinstalls on every run | The derived name doesn't match the installed name. Use the `{ "name": …, "source": … }` form. |
| Plugin installed but its tools don't appear | Restart the CLI; some plugins contribute MCP servers that are only loaded at startup. |
