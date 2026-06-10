# skill-creator

A meta-skill for building, testing, and iteratively improving OpenCode skills. It guides you through the full lifecycle: capturing intent, drafting the skill, running sandboxed evaluations, reviewing results, and shipping the final artifact.

---

## What it does

- **Creates** new skills from scratch via a structured interview → draft → test → iterate loop.
- **Improves** existing skills by running side-by-side comparisons (new vs. old) and reviewing outputs in a browser-based viewer.
- **Benchmarks** skill performance with quantitative pass rates, timing, and token usage across test cases.
- **Optimizes** the skill description so it triggers reliably — using an automated loop that tests candidate descriptions against a curated eval set.

---

## How to trigger it

```
Create a skill to bump a Helm chart version and push it
Turn this workflow into a skill
My existing skill isn't triggering reliably — help me fix the description
Run evals on the draft skill in skills/my-skill/
Benchmark skill performance with variance analysis
```

---

## The core loop

```
Capture intent → Draft SKILL.md → Run test cases (with-skill + baseline)
→ Grade assertions → Review in browser → Improve → Repeat
```

Each iteration lives in `<skill-name>-workspace/iteration-N/`. You keep iterating until the user is happy or feedback goes empty.

---

## Workflow overview

### 1. Capture intent
Answer four questions:
1. What should this skill enable the agent to do?
2. When should it trigger?
3. What's the expected output format?
4. Should we set up test cases?

### 2. Draft the skill
Produces a `SKILL.md` with YAML frontmatter (`name`, `description`) and markdown instructions. Bundled resources (`scripts/`, `references/`, `assets/`) are added as needed.

### 3. Run evaluations
For each test case, two subagents are spawned in parallel:
- **with-skill** — agent has access to the skill
- **baseline** — no skill (new skill) or previous version (improvement)

Results are saved to `<workspace>/iteration-N/eval-<ID>/<config>/outputs/`.

### 4. Grade & benchmark
Assertions are graded against outputs. The aggregation script produces `benchmark.json` and `benchmark.md` with pass rates, timing, and token usage per configuration.

```bash
python -m scripts.aggregate_benchmark <workspace>/iteration-N --skill-name <name>
```

### 5. Review in browser
A self-contained HTML viewer is generated for human review — qualitative outputs on one tab, benchmark stats on another.

```bash
python <skill-creator-path>/eval-viewer/generate_review.py \
  <workspace>/iteration-N \
  --skill-name "my-skill" \
  --benchmark <workspace>/iteration-N/benchmark.json
```

In headless / Cowork environments, add `--static <output_path>` to write a standalone HTML file instead of starting a server.

### 6. Improve & repeat
Feedback from the viewer feeds the next revision of `SKILL.md`. Iterate until quality is satisfactory.

### 7. Optimize the description (optional)
After the skill is stable, run the description optimizer to maximize triggering accuracy:

```bash
python -m scripts.run_loop \
  --eval-set <path-to-trigger-eval.json> \
  --skill-path <path-to-skill> \
  --model <model-id> \
  --max-iterations 5 \
  --verbose
```

The loop splits the eval set 60/40 train/test, evaluates the current description, proposes improvements, and returns `best_description` selected by held-out test score.

---

## File structure

```
skill-creator/
├── SKILL.md                        # Agent-facing instructions
├── README.md                       # This file
├── LICENSE.txt
├── agents/
│   ├── grader.md                   # Instructions for assertion-grading subagent
│   ├── comparator.md               # Instructions for blind A/B comparison subagent
│   └── analyzer.md                 # Instructions for benchmark analysis subagent
├── scripts/
│   ├── aggregate_benchmark.py      # Aggregates run results → benchmark.json + .md
│   ├── run_loop.py                 # Description optimization loop
│   ├── run_eval.py                 # Runs a single eval query against a skill
│   ├── improve_description.py      # Proposes description improvements
│   ├── package_skill.py            # Packages skill folder → .skill file
│   ├── quick_validate.py           # Sanity-checks skill structure
│   ├── generate_report.py          # Report generation helper
│   └── utils.py                    # Shared utilities
├── references/
│   └── schemas.md                  # JSON schemas for evals.json, grading.json, benchmark.json
├── assets/
│   └── eval_review.html            # HTML template for the trigger-eval reviewer
└── eval-viewer/
    └── generate_review.py          # Generates the browser-based output/benchmark viewer
```

---

## Skill anatomy

Every skill has the same minimal structure:

```
my-skill/
├── SKILL.md          # Required. YAML frontmatter + markdown instructions.
└── (optional)
    ├── scripts/      # Executable helpers bundled with the skill
    ├── references/   # Docs loaded into context on demand
    └── assets/       # Templates, icons, static files used in output
```

SKILL.md frontmatter fields:

| Field | Required | Purpose |
|---|---|---|
| `name` | Yes | Skill identifier (matches directory name) |
| `description` | Yes | Primary triggering mechanism — "when to use" info goes here |
| `compatibility` | No | Required tools or runtime dependencies |

---

## Eval workspace layout

```
<skill-name>-workspace/
└── iteration-1/
    ├── benchmark.json
    ├── benchmark.md
    └── eval-0/
        ├── eval_metadata.json       # Prompt + assertions for this eval
        ├── with_skill/
        │   ├── outputs/             # Files produced by the with-skill run
        │   ├── grading.json         # Assertion results
        │   └── timing.json          # Tokens + duration
        └── without_skill/
            ├── outputs/
            ├── grading.json
            └── timing.json
```

---

## Platform notes

| Environment | Notes |
|---|---|
| **Claude Code** | Full support — subagents, browser, CLI tools all available |
| **Cowork** | Use `--static` for the viewer; no browser display available |
| **Claude.ai** | No subagents — run test cases sequentially; skip baseline and benchmarking |
