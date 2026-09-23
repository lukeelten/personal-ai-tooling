# opencode plugins

Installs opencode plugins from npm, declared in the `opencode` section of
[`plugins.json`](../plugins.json).

opencode plugins are plain **npm packages**. There is no marketplace: you name
a package, opencode downloads it and records it in the `plugins` array of your
global config.

## Manifest format

```json
{
  "opencode": {
    "plugins": [
      "opencode-models-discovery@1.5.3",
      "@langfuse/opencode-observability-plugin",
      { "module": "@mastra/opencode" }
    ]
  }
}
```

### `opencode.plugins[]`

| Form | Description |
|---|---|
| `"<npm-module>"` | Package name, optionally `@version` |
| `{ "module": "<npm-module>" }` | Equivalent long form |

Both plain (`opencode-models-discovery`) and scoped (`@mastra/opencode`)
packages are supported, with or without a version suffix:

| Spec | Resolves to |
|---|---|
| `opencode-plugin-foo` | latest |
| `opencode-plugin-foo@1.0.0` | pinned |
| `@scope/pkg` | latest |
| `@scope/pkg@2.3.4` | pinned |

**Pin versions for reproducible machines.** Without a version, opencode records
whatever was latest at install time and the installer will then skip it forever
(see below).

## What the installer runs

```bash
opencode plugin add <module>
```

This writes to `~/.config/opencode/opencode.json` (opencode's global config).

## Idempotency

The installer reads the `plugins` array from `~/.config/opencode/opencode.json`
and compares **base package names** — the `@version` suffix is stripped from
both sides, with any `@scope/` prefix preserved. If the package is already
listed under any version, it is skipped.

This means **changing the version in `plugins.json` does not upgrade an
installed plugin**, because the base name still matches. To move to a new
version, run it explicitly:

```bash
opencode plugin remove opencode-models-discovery
opencode plugin add opencode-models-discovery@1.6.0
```

(or `opencode plugin update opencode-models-discovery` to bump to latest).

## Where things land

`~/.config/opencode/opencode.json` (the same file the main installer uses for
`skills.paths` and the Helm LSP):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    "opencode-models-discovery@1.5.3",
    "@mastra/opencode"
  ],
  "skills": { "paths": ["/path/to/personal-ai-tooling/skills"] }
}
```

On Windows opencode follows the same convention:
`%USERPROFILE%\.config\opencode\opencode.json`.

Local, unpublished plugins don't belong in this manifest — drop a `.ts`/`.js`
file into `~/.config/opencode/plugin/` and opencode loads it automatically.

## Verifying

```bash
jq '.plugins' ~/.config/opencode/opencode.json
opencode --print-logs 2>&1 | grep -i plugin     # confirm they load
opencode --pure                                  # start with external plugins disabled
```

`--pure` is the fastest way to tell whether a misbehaving session is caused by
a plugin.

## Managing plugins by hand

```bash
opencode plugin add <module>       # install / register
opencode plugin remove <module>    # unregister
opencode plugin update [<module>]  # update one plugin, or all if omitted
opencode plugin list               # show configured plugins
```

`opencode plugin remove <module>` is the supported way to unregister a
plugin — you don't need to hand-edit `opencode.json` for that.

## Finding plugins

```bash
npm search opencode-plugin
```

Most community plugins follow the `opencode-plugin-*` naming convention or are
published under a vendor scope (`@langfuse/…`, `@mastra/…`).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `failed to install opencode plugin …` | Package doesn't exist, version doesn't exist, or npm is unreachable. Verify with `npm view <module> version`. |
| Version change in `plugins.json` had no effect | Base-name match caused a skip. Run `opencode plugin remove <module>` then `opencode plugin add <module>@<version>` (or `opencode plugin update <module>`) to move to the new version. |
| Plugin listed in config but not loading | Restart opencode. Check `opencode --print-logs` for load errors, and make sure the package actually exports an opencode plugin. |
| Config file got mangled | The installer only ever adds to the `plugins` array; a `.bak` is not created for this file, so keep `opencode.json` under version control if you edit it heavily. |
