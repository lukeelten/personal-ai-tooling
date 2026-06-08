#!/usr/bin/env bash
# install.sh — install skills and agents into opencode, Claude Code, and VS Code
#
# Strategy per tool:
#   opencode      — registers the repo's skills/ and agents/ directories via
#                   skills.paths in ~/.config/opencode/opencode.json (no symlinks)
#   Claude Code   — symlinks skills/ → ~/.claude/skills
#                              agents/ → ~/.claude/agents
#   VS Code       — symlinks skills/ → ~/.copilot/skills
#                              agents/ → ~/.copilot/agents
#
# The whole parent directory is linked so newly added skills/agents are picked
# up automatically without re-running this script.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${REPO_DIR}/skills"
AGENTS_SRC="${REPO_DIR}/agents"

# ── helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ ok ]\033[0m  %s\n' "$*"; }
skip()  { printf '\033[1;33m[skip]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }

# link_dir <src> <dst>
# Symlinks <dst> → <src>.  Idempotent; backs up collisions.
link_dir() {
    local src="$1" dst="$2"

    if [[ -L "$dst" ]]; then
        if [[ "$(readlink "$dst")" == "$src" ]]; then
            skip "${dst} (already linked)"
            return
        fi
        warn "${dst} points elsewhere — relinking"
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        local bak="${dst}.bak"
        warn "${dst} exists — backing up to ${bak}"
        mv "$dst" "$bak"
    fi

    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "${dst} → ${src}"
}

# json_has_path <file> <jq-path>
# Returns 0 if the jq path is non-null in the JSON file.
json_has_path() {
    local file="$1" path="$2"
    [[ "$(jq -r "${path} // \"__MISSING__\"" "$file")" != "__MISSING__" ]]
}

# ── opencode ─────────────────────────────────────────────────────────────────
# opencode supports skills.paths — a list of parent directories it scans for
# skill subdirs.  We just register the repo paths in the global config instead
# of creating any symlinks.

install_opencode() {
    local cfg_dir="${HOME}/.config/opencode"
    local cfg="${cfg_dir}/opencode.json"

    info "opencode — updating ${cfg}"

    mkdir -p "$cfg_dir"

    # Seed an empty config if none exists yet
    if [[ ! -f "$cfg" ]]; then
        printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > "$cfg"
    fi

    # Ensure jq is available
    if ! command -v jq &>/dev/null; then
        warn "jq not found — skipping opencode config update (install jq and re-run)"
        return
    fi

    local tmp
    tmp="$(mktemp)"

    # Add skills path if not already present
    if jq -e '.skills.paths // [] | map(. == "'"${SKILLS_SRC}"'") | any' "$cfg" | grep -q true; then
        skip "opencode skills path already registered"
    else
        jq --arg p "${SKILLS_SRC}" \
            '.skills.paths = ((.skills.paths // []) + [$p] | unique)' \
            "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        ok "opencode skills.paths += ${SKILLS_SRC}"
    fi

    ok "opencode config updated"
}

# ── Claude Code ───────────────────────────────────────────────────────────────

install_claude() {
    local base="${HOME}/.claude"
    info "Claude Code — linking into ${base}"
    link_dir "${SKILLS_SRC}" "${base}/skills"
    link_dir "${AGENTS_SRC}" "${base}/agents"
}

# ── VS Code ───────────────────────────────────────────────────────────────────

install_vscode() {
    local base="${HOME}/.copilot"
    info "VS Code — linking into ${base}"
    link_dir "${SKILLS_SRC}" "${base}/skills"
    link_dir "${AGENTS_SRC}" "${base}/agents"
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
    info "personal-ai-tooling installer"
    info "Repo: ${REPO_DIR}"
    echo

    install_opencode
    echo
    install_claude
    echo
    install_vscode
    echo

    info "Done."
    info "Restart opencode / VS Code / Claude Code for changes to take effect."
}

main "$@"
