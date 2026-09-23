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
#
# In addition, third-party plugins and public skills declared in plugins.json
# are installed via each tool's own CLI:
#   Claude Code   — claude plugin marketplace add / claude plugin install
#   Copilot CLI   — copilot plugin marketplace add / copilot plugin install
#   opencode      — opencode plugin add <npm-module>
#   public skills — npx skills add <owner/repo> --global
#
# Playwright CLI (@playwright/cli) is installed globally via npm, then its
# own `playwright-cli install --skills` registers the playwright-cli Agent
# Skill (independent of plugins.json).
# See docs/ for details on each method.
#
# Usage: ./install.sh [--no-plugins] [--debug]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${REPO_DIR}/skills"
AGENTS_SRC="${REPO_DIR}/agents"
PLUGINS_MANIFEST="${PAI_PLUGINS_MANIFEST:-${REPO_DIR}/plugins.json}"
SKILLS_CLI_PKG="${PAI_SKILLS_CLI:-skills@latest}"
PLAYWRIGHT_CLI_PKG="${PAI_PLAYWRIGHT_CLI:-@playwright/cli@latest}"
INSTALL_PLUGINS="true"
DEBUG="false"
HELM_LS_LOCAL_BIN_DIR="${HOME}/.local/share/personal-ai-tooling/bin"
HELM_LS_LOCAL_BIN="${HELM_LS_LOCAL_BIN_DIR}/helm_ls"
HELM_LS_CMD=""

# ── helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ ok ]\033[0m  %s\n' "$*"; }
skip()  { printf '\033[1;33m[skip]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
debug() { [[ "$DEBUG" == "true" ]] && printf '\033[1;36m[dbg ]\033[0m  %s\n' "$*" >&2 || true; }

# run_cmd <command> [args...]
# Runs a command with stdin detached, capturing its combined stdout/stderr.
# Returns the command's exit code. When --debug is set, prints the captured
# output (and the exact command line) on failure so the real error is visible
# instead of being silently swallowed by the caller's `>/dev/null 2>&1`.
run_cmd() {
    local output status
    output="$("$@" </dev/null 2>&1)"
    status=$?
    if [[ $status -ne 0 && "$DEBUG" == "true" ]]; then
        debug "command failed (exit ${status}): $*"
        if [[ -n "$output" ]]; then
            local line
            while IFS= read -r line; do
                debug "  ${line}"
            done <<<"$output"
        fi
    fi
    return $status
}

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

# ── plugin manifest helpers ──────────────────────────────────────────────────

# plugins_manifest_ready
# Returns 0 when plugins.json exists, is valid JSON, and jq is available.
plugins_manifest_ready() {
    if [[ ! -f "$PLUGINS_MANIFEST" ]]; then
        skip "no plugin manifest at ${PLUGINS_MANIFEST}"
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        warn "jq not found — skipping plugin installation"
        return 1
    fi
    if ! jq -e . "$PLUGINS_MANIFEST" >/dev/null 2>&1; then
        warn "${PLUGINS_MANIFEST} is not valid JSON — skipping plugin installation"
        return 1
    fi
    return 0
}

# manifest_query <jq-filter>
# Runs a jq filter against the manifest, emitting one record per line.
manifest_query() {
    jq -r "$1" "$PLUGINS_MANIFEST" 2>/dev/null || true
}

# jq prelude shared by the manifest queries below.
#   entry   — normalises a "owner/repo" string or {name, source} object
#   pname   — derives a plugin name from a source specifier
MANIFEST_JQ_PRELUDE='
def basename($s): ($s | sub("\\.git$"; "") | sub(".*/"; ""));
def entry: if type == "string"
           then {name: basename(.), source: .}
           else {name: (.name // basename(.source)), source: .source} end;
def pname($s): ($s
    | (if test("^[a-zA-Z][a-zA-Z0-9+.-]*://") then . else sub(":.*$"; "") end)
    | sub("@.*$"; "")
    | basename(.));
'

# module_base <npm-module>
# Strips a trailing @version from an npm module name, keeping any @scope/ prefix.
module_base() {
    local m="$1" lead=""
    if [[ "$m" == @* ]]; then
        lead="@"
        m="${m:1}"
    fi
    printf '%s%s' "$lead" "${m%%@*}"
}

# ── Claude Code plugins ──────────────────────────────────────────────────────
# Marketplaces are registered with `claude plugin marketplace add`, then plugins
# are installed as <plugin>@<marketplace>.  Installed state lives in
# ~/.claude/plugins/known_marketplaces.json and `claude plugin list --json`.

install_claude_plugins() {
    info "Claude Code — plugins from ${PLUGINS_MANIFEST}"

    if ! command -v claude &>/dev/null; then
        skip "claude CLI not found — skipping Claude Code plugins"
        return
    fi

    local known="${HOME}/.claude/plugins/known_marketplaces.json"
    local name source
    while IFS=$'\t' read -r name source; do
        [[ -z "${name:-}" ]] && continue
        if [[ -f "$known" ]] && jq -e --arg n "$name" 'has($n)' "$known" >/dev/null 2>&1; then
            skip "claude marketplace ${name} (already registered)"
            continue
        fi
        if run_cmd claude plugin marketplace add "$source" --scope user; then
            ok "claude marketplace registered: ${name} (${source})"
        else
            warn "failed to register claude marketplace ${source}"
        fi
    done < <(manifest_query "${MANIFEST_JQ_PRELUDE}"'
        (.claude.marketplaces // [])[] | entry | "\(.name)\t\(.source)"')

    local installed
    installed="$(claude plugin list --json 2>/dev/null || echo '[]')"
    jq -e . <<<"$installed" >/dev/null 2>&1 || installed='[]'

    local id scope
    while IFS=$'\t' read -r id scope; do
        [[ -z "${id:-}" ]] && continue
        if jq -e --arg id "$id" \
            'any(.[]?; .id == $id or (.id | split("@")[0]) == ($id | split("@")[0]))' \
            <<<"$installed" >/dev/null 2>&1; then
            skip "claude plugin ${id} (already installed)"
            continue
        fi
        if run_cmd claude plugin install "$id" --scope "$scope" --yes; then
            ok "claude plugin installed: ${id}"
        else
            warn "failed to install claude plugin ${id}"
        fi
    done < <(manifest_query '
        (.claude.plugins // [])[]
        | (if type == "string" then {id: .} else . end)
        | "\(.id)\t\(.scope // "user")"')
}

# ── GitHub Copilot CLI plugins ───────────────────────────────────────────────
# The copilot CLI ships with the copilot-plugins and awesome-copilot
# marketplaces; extra ones are added with `copilot plugin marketplace add`.
# Plugins install from a marketplace, a GitHub repo, a repo subdirectory
# (owner/repo:path) or a git URL.

install_copilot_plugins() {
    info "GitHub Copilot — plugins from ${PLUGINS_MANIFEST}"

    if ! command -v copilot &>/dev/null; then
        skip "copilot CLI not found — skipping Copilot plugins"
        return
    fi

    local markets
    markets="$(copilot plugin marketplace list 2>/dev/null || true)"

    local name source
    while IFS=$'\t' read -r name source; do
        [[ -z "${name:-}" ]] && continue
        if grep -qE "(^|[[:space:]])${name}[[:space:]]*\(" <<<"$markets"; then
            skip "copilot marketplace ${name} (already registered)"
            continue
        fi
        if run_cmd copilot plugin marketplace add "$source"; then
            ok "copilot marketplace registered: ${name} (${source})"
            markets="$(copilot plugin marketplace list </dev/null 2>/dev/null || true)"
        else
            warn "failed to register copilot marketplace ${source}"
        fi
    done < <(manifest_query "${MANIFEST_JQ_PRELUDE}"'
        (.copilot.marketplaces // [])[] | entry | "\(.name)\t\(.source)"')

    local installed
    installed="$(copilot plugin list 2>/dev/null || true)"

    while IFS=$'\t' read -r name source; do
        [[ -z "${source:-}" ]] && continue
        if grep -qE "(^|[^[:alnum:]_-])${name}([^[:alnum:]_-]|$)" <<<"$installed"; then
            skip "copilot plugin ${name} (already installed)"
            continue
        fi
        if run_cmd copilot plugin install "$source"; then
            ok "copilot plugin installed: ${name} (${source})"
            installed="$(copilot plugin list </dev/null 2>/dev/null || true)"
        else
            warn "failed to install copilot plugin ${source}"
        fi
    done < <(manifest_query "${MANIFEST_JQ_PRELUDE}"'
        (.copilot.plugins // [])[]
        | (if type == "string" then {source: .} else . end)
        | "\(.name // pname(.source))\t\(.source)"')
}

# ── opencode plugins ─────────────────────────────────────────────────────────
# `opencode plugin add <npm-module>` downloads the module and records it in
# the "plugins" array of ~/.config/opencode/opencode.json.

install_opencode_plugins() {
    info "opencode — plugins from ${PLUGINS_MANIFEST}"

    if ! command -v opencode &>/dev/null; then
        skip "opencode CLI not found — skipping opencode plugins"
        return
    fi

    local cfg="${HOME}/.config/opencode/opencode.json"
    local module base existing found entry

    while IFS= read -r module; do
        [[ -z "${module:-}" ]] && continue
        base="$(module_base "$module")"

        found="false"
        if [[ -f "$cfg" ]]; then
            existing="$(jq -r '(.plugins // [])[]?' "$cfg" 2>/dev/null || true)"
            while IFS= read -r entry; do
                [[ -z "${entry:-}" ]] && continue
                if [[ "$(module_base "$entry")" == "$base" ]]; then
                    found="true"
                    break
                fi
            done <<<"$existing"
        fi

        if [[ "$found" == "true" ]]; then
            skip "opencode plugin ${base} (already configured)"
            continue
        fi

        if run_cmd opencode plugin add "$module"; then
            ok "opencode plugin installed: ${module}"
        else
            warn "failed to install opencode plugin ${module}"
        fi
    done < <(manifest_query '
        (.opencode.plugins // [])[]
        | if type == "string" then . else .module end')
}

# ── public skills via npx ────────────────────────────────────────────────────
# The `skills` CLI (npx skills) installs public Agent Skills from GitHub repos
# and links them into every detected agent's skills directory.

install_public_skills() {
    info "public skills — from ${PLUGINS_MANIFEST}"

    local count
    count="$(manifest_query '(.skills // []) | length')"
    if [[ -z "${count:-}" || "$count" == "0" ]]; then
        skip "no public skills declared"
        return
    fi

    if ! command -v npx &>/dev/null; then
        warn "npx not found — skipping public skills (install Node.js and re-run)"
        return
    fi

    local installed
    installed="$(npx -y "$SKILLS_CLI_PKG" list --global --json 2>/dev/null || echo '[]')"
    jq -e . <<<"$installed" >/dev/null 2>&1 || installed='[]'

    local source names agents scope scope_flag
    while IFS=$'\t' read -r source names agents scope; do
        [[ -z "${source:-}" ]] && continue

        if jq -e --arg s "$source" \
            'any(.[]?; ((.source // "") | contains($s)) or ((.sourceUrl // "") | contains($s)))' \
            <<<"$installed" >/dev/null 2>&1; then
            skip "public skills ${source} (already installed)"
            continue
        fi

        scope_flag="--global"
        [[ "$scope" == "project" ]] && scope_flag="--project"

        if run_cmd npx -y "$SKILLS_CLI_PKG" add "$source" "$scope_flag" \
            --skill "$names" --agent "$agents" --yes; then
            ok "public skills installed: ${source} (skills=${names}, agents=${agents})"
        else
            warn "failed to install public skills from ${source}"
        fi
    done < <(manifest_query '
        (.skills // [])[]
        | (if type == "string" then {source: .} else . end)
        | "\(.source)\t\(.skills // "*")\t\(.agents // "*")\t\(.scope // "global")"')
}

# ── Playwright CLI ───────────────────────────────────────────────────────────
# Installs @playwright/cli globally via npm, then runs its own
# `playwright-cli install --skills` to register the playwright-cli Agent Skill.
# Tries a real global install via sudo first (works when the default npm
# prefix is root-owned); if sudo is unavailable/denied, falls back to a
# user-local npm prefix ($HOME/.npm-global) so the install never requires
# elevated privileges to succeed.

ensure_playwright_cli() {
    info "playwright-cli — from npm (${PLAYWRIGHT_CLI_PKG})"

    if ! command -v npm &>/dev/null; then
        warn "npm not found — skipping playwright-cli (install Node.js and re-run)"
        return
    fi

    if command -v playwright-cli &>/dev/null; then
        skip "playwright-cli already installed ($(command -v playwright-cli))"
    else
        local installed="false"

        if command -v sudo &>/dev/null; then
            info "attempting 'sudo npm install -g' (may prompt for your password)"
            if run_cmd sudo npm install -g "$PLAYWRIGHT_CLI_PKG"; then
                installed="true"
            else
                debug "sudo install failed or unavailable, falling back to user-local install"
            fi
        fi

        if [[ "$installed" != "true" ]]; then
            local npm_prefix="$HOME/.npm-global"
            mkdir -p "$npm_prefix"
            if run_cmd npm install -g --prefix "$npm_prefix" "$PLAYWRIGHT_CLI_PKG"; then
                installed="true"
                export PATH="${npm_prefix}/bin:${PATH}"
                info "installed to ${npm_prefix} — add '${npm_prefix}/bin' to your PATH to use playwright-cli in new shells"
            fi
        fi

        if [[ "$installed" == "true" ]]; then
            ok "installed ${PLAYWRIGHT_CLI_PKG} via npm"
        else
            warn "failed to install ${PLAYWRIGHT_CLI_PKG} via npm (sudo and user-local install both failed)"
            return
        fi
    fi

    if run_cmd playwright-cli install --skills; then
        ok "playwright-cli skills installed"
    else
        warn "failed to run 'playwright-cli install --skills'"
    fi
}

# install_plugins
# Runs every manifest-driven installation method.
install_plugins() {
    if [[ "$INSTALL_PLUGINS" != "true" ]]; then
        skip "plugin installation disabled (--no-plugins)"
        return
    fi
    plugins_manifest_ready || return 0

    install_claude_plugins
    echo
    install_copilot_plugins
    echo
    install_opencode_plugins
    echo
    install_public_skills
}

# ── main ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --no-plugins   Only link this repo's skills/ and agents/; skip installing the
                 third-party plugins and public skills declared in plugins.json
  --debug        Print the real command output/errors when an install step
                 fails, instead of just the summary [warn] line
  -h, --help     Show this help

Environment:
  PAI_PLUGINS_MANIFEST  Path to the plugin manifest (default: <repo>/plugins.json)
  PAI_SKILLS_CLI        npm spec for the public-skills CLI (default: skills@latest)
  PAI_PLAYWRIGHT_CLI    npm spec for @playwright/cli (default: @playwright/cli@latest)
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-plugins) INSTALL_PLUGINS="false" ;;
            --debug) DEBUG="true" ;;
            -h|--help) usage; return 0 ;;
            *) warn "unknown option: $1"; usage; return 1 ;;
        esac
        shift
    done

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
    ensure_playwright_cli
    echo
    install_plugins
    echo

    info "Done."
    info "Restart opencode / VS Code / Claude Code for changes to take effect."
}

main "$@"
