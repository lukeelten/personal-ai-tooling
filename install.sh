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
HELM_LS_LOCAL_BIN_DIR="${HOME}/.local/share/personal-ai-tooling/bin"
HELM_LS_LOCAL_BIN="${HELM_LS_LOCAL_BIN_DIR}/helm_ls"
HELM_LS_CMD=""

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

# Download the latest helm_ls release for Linux into a user-local path.
# Sets HELM_LS_CMD to the executable path when available.
ensure_helm_ls() {
    local existing_helm_ls=""
    local local_helm_ls_installed="false"

    if [[ -x "$HELM_LS_LOCAL_BIN" ]]; then
        local_helm_ls_installed="true"
    fi

    if command -v helm_ls &>/dev/null; then
        existing_helm_ls="$(command -v helm_ls)"
    fi

    # Respect system-managed installs. Only auto-update binaries managed in the
    # local user path.
    if [[ -n "$existing_helm_ls" && "$existing_helm_ls" != "$HELM_LS_LOCAL_BIN" && "$local_helm_ls_installed" != "true" ]]; then
        skip "system helm_ls found at ${existing_helm_ls} — skipping download/update"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if [[ "$local_helm_ls_installed" == "true" ]]; then
        info "local helm_ls found at ${HELM_LS_LOCAL_BIN} — checking latest release"
    elif [[ -z "$existing_helm_ls" ]]; then
        info "helm_ls not found — installing local copy"
    fi

    if [[ "$(uname -s)" != "Linux" ]]; then
        skip "helm_ls auto-install is only supported on Linux"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if ! command -v curl &>/dev/null; then
        warn "curl not found — skipping helm_ls download"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if ! command -v jq &>/dev/null; then
        warn "jq not found — skipping helm_ls download"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armv6l|arm) arch="arm" ;;
        *)
            warn "unsupported architecture for helm_ls auto-install: $(uname -m)"
            HELM_LS_CMD="$existing_helm_ls"
            return
            ;;
    esac

    local release_json
    if ! release_json="$(mktemp)"; then
        warn "failed to create temp file for helm_ls download"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if ! curl -fsSL "https://api.github.com/repos/mrjosh/helm-ls/releases/latest" -o "$release_json"; then
        warn "failed to query latest helm_ls release"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    local tag asset_name asset_url checksum_url
    if ! tag="$(jq -r '.tag_name // empty' "$release_json")"; then
        warn "failed to parse helm_ls release metadata"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi
    asset_name="helm_ls_linux_${arch}"
    if ! asset_url="$(jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .browser_download_url' "$release_json")"; then
        warn "failed to parse helm_ls asset URL"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi
    if ! checksum_url="$(jq -r --arg name "${asset_name}.sha256sum" '.assets[]? | select(.name == $name) | .browser_download_url' "$release_json")"; then
        checksum_url=""
    fi

    if [[ -z "$asset_url" ]]; then
        warn "no ${asset_name} asset found in latest helm_ls release"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if ! mkdir -p "$HELM_LS_LOCAL_BIN_DIR"; then
        warn "failed to create local helm_ls directory ${HELM_LS_LOCAL_BIN_DIR}"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    local tmp_bin tmp_checksum
    if ! tmp_bin="$(mktemp)"; then
        warn "failed to create temp file for helm_ls binary"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if ! curl -fsSL "$asset_url" -o "$tmp_bin"; then
        warn "failed to download ${asset_name} from ${tag:-latest}"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi

    if [[ -n "$checksum_url" ]] && command -v sha256sum &>/dev/null; then
        tmp_checksum="$(mktemp)"
        if curl -fsSL "$checksum_url" -o "$tmp_checksum"; then
            local expected actual
            expected="$(awk '{print $1}' "$tmp_checksum" | head -n1)"
            actual="$(sha256sum "$tmp_bin" | awk '{print $1}')"
            if [[ -n "$expected" && "$expected" != "$actual" ]]; then
                warn "checksum validation failed for helm_ls download"
                HELM_LS_CMD="$existing_helm_ls"
                return
            fi
        else
            warn "failed to download checksum for helm_ls; continuing without checksum validation"
        fi
    fi

    if ! chmod +x "$tmp_bin"; then
        warn "failed to mark helm_ls binary executable"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi
    if ! mv "$tmp_bin" "$HELM_LS_LOCAL_BIN"; then
        warn "failed to install helm_ls to ${HELM_LS_LOCAL_BIN}"
        HELM_LS_CMD="$existing_helm_ls"
        return
    fi
    HELM_LS_CMD="$HELM_LS_LOCAL_BIN"
    if [[ "$local_helm_ls_installed" == "true" ]]; then
        ok "updated local helm_ls to ${tag:-latest} at ${HELM_LS_LOCAL_BIN}"
    else
        ok "installed helm_ls ${tag:-latest} to ${HELM_LS_LOCAL_BIN}"
    fi
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

    # Apply only helm-related JSON changes so unrelated existing config remains
    # unchanged.
    if [[ -z "$HELM_LS_CMD" ]]; then
        if jq -e '.lsp["helm-lsp"] == null and (.lsp["yaml-ls"].disabled // false) == true' "$cfg" >/dev/null 2>&1; then
            skip "opencode helm-lsp already absent and yaml-ls already disabled"
        elif jq '
            .lsp = (.lsp // {})
            | del(.lsp["helm-lsp"])
            | .lsp["yaml-ls"] = ((.lsp["yaml-ls"] // {}) + {"disabled": true})
        ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"; then
            skip "helm_ls not found — removed helm-lsp and kept yaml-ls disabled"
        else
            warn "failed to update opencode helm-lsp settings; continuing"
        fi
    else
        if jq -e --arg cmd "$HELM_LS_CMD" '
            .lsp["helm-lsp"].command == [$cmd, "serve"]
            and .lsp["helm-lsp"].extensions == [".yaml", ".yml", ".tpl"]
            and (.lsp["yaml-ls"].disabled // false) == true
        ' "$cfg" >/dev/null 2>&1; then
            skip "opencode helm-lsp already configured"
        elif jq --arg cmd "$HELM_LS_CMD" '
            .lsp = (.lsp // {})
            | .lsp["helm-lsp"] = ((.lsp["helm-lsp"] // {}) + {
                "command": [$cmd, "serve"],
                "extensions": [".yaml", ".yml", ".tpl"]
              })
            | .lsp["yaml-ls"] = ((.lsp["yaml-ls"] // {}) + {"disabled": true})
        ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"; then
            ok "helm_ls found — configured helm-lsp in opencode config"
        else
            warn "failed to configure helm-lsp in opencode config; continuing"
        fi
    fi

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

    ensure_helm_ls
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
