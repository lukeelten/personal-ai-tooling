# Copilot instructions for personal-ai-tooling

This repo is a personal collection of **agent skills and agents** shared across
AI coding tools (opencode, Claude Code, VS Code/GitHub Copilot). There is no
application code, build step, or test suite in the traditional sense — the
"product" is the Markdown/JSON/script content under `skills/` and `agents/`.

## Repository layout

- `skills/<skill-name>/SKILL.md` — the skill itself: YAML frontmatter (`name`,
  `description`) + Markdown instructions. The `description` is the *only*
  triggering mechanism, so it must state both what the skill does and the
  specific phrases/contexts that should invoke it.
- `skills/<skill-name>/README.md` — human-facing overview (optional, separate
  from SKILL.md).
- `skills/<skill-name>/scripts/` — helper scripts (usually dependency-free
  Python) the skill shells out to.
- `skills/<skill-name>/references/` — supporting docs the skill links to.
- `skills/<skill-name>/evals/evals.json` — eval cases: each has `prompt`,
  `expected_output`, and a list of `expectations` (assertions used to grade a
  run). Not every skill has evals.
- `agents/`, `prompts/` — currently empty placeholders (`.gitkeep`) for future
  custom agents/prompts.
- `install.sh` / `install.ps1` — install the whole `skills/` and `agents/`
  directories into each tool:
  - **opencode**: registers `skills/` via `skills.paths` in
    `~/.config/opencode/opencode.json` (no symlinks).
  - **Claude Code**: symlinks/junctions `skills/` → `~/.claude/skills`,
    `agents/` → `~/.claude/agents`.
  - **VS Code/Copilot**: symlinks/junctions `skills/` → `~/.copilot/skills`,
    `agents/` → `~/.copilot/agents`.
  - The scripts are idempotent (skip if already linked/registered, back up
    real files as `.bak` before relinking) and also handle downloading
    `helm_ls` for the Helm-related skills.

## Working on a skill

- Use the **skill-creator** skill (`skills/skill-creator/`) when creating a
  new skill, editing an existing one, or running/authoring evals — it owns
  the full draft → test → eval → iterate workflow and has scripts for
  running evals, packaging, and improving descriptions
  (`skills/skill-creator/scripts/*.py`).
- Skill descriptions should be a bit "pushy": include the literal phrases a
  user is likely to say, not just an abstract capability statement (models
  tend to under-trigger skills otherwise).
- Keep a skill's "when to use" guidance entirely inside the frontmatter
  `description`; put "how to do it" details in the Markdown body.
- If a skill wraps a script, prefer dependency-free stdlib Python (see
  `skills/version-push/scripts/bump_chart_version.py` for the pattern:
  reads/writes files in place, prints a final `RESULT_JSON` line the calling
  agent parses to drive commit messages/reports).
- Skills that perform git operations (e.g. `version-push`) must treat
  `main`/`master`/detached HEAD as a hard stop before pushing, and stage only
  the files relevant to the change (never `git add -A`).

## Validating changes

There is no CI/build/test command to run. To sanity-check a skill:

```bash
# Validate SKILL.md frontmatter/structure
python3 skills/skill-creator/scripts/quick_validate.py skills/<skill-name>

# Optimize/re-check a skill's triggering description against its evals/evals.json
# (run as a module from inside skills/skill-creator/, since scripts/ is a package)
cd skills/skill-creator && python -m scripts.run_loop \
  --eval-set ../<skill-name>/evals/evals.json \
  --skill-path ../<skill-name> \
  --model <model-id>
```

For install-script changes, run `bash install.sh` (or the relevant function)
in a scratch `$HOME` and confirm it's idempotent (re-running prints `skip`
for everything already linked/registered).
