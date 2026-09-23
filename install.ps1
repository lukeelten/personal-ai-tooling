#Requires -Version 5.1
<#
.SYNOPSIS
    Installs personal-ai-tooling skills and agents into opencode, Claude Code, and VS Code.

.DESCRIPTION
    Strategy per tool:
      opencode    — registers the repo's skills/ directory via skills.paths in
                    $HOME\.config\opencode\opencode.json (no symlinks needed)
      Claude Code — junction/symlink: skills/ -> $HOME\.claude\skills
                                      agents/ -> $HOME\.claude\agents
      VS Code     — junction/symlink: skills/ -> $HOME\.copilot\skills
                                      agents/ -> $HOME\.copilot\agents

    The whole parent directory is linked so new skills/agents are picked up
    automatically without re-running this script.

    Directory junctions are used by default (no elevation required).
    Symbolic links require either Developer Mode or an elevated session.

    In addition, third-party plugins and public skills declared in plugins.json
    are installed through each tool's own CLI:
      Claude Code   — claude plugin marketplace add / claude plugin install
      Copilot CLI   — copilot plugin marketplace add / copilot plugin install
      opencode      — opencode plugin add <npm-module>
      public skills — npx skills add <owner/repo> --global
    See docs/ for details on each method.

    Playwright CLI (@playwright/cli) is installed globally via npm, then its
    own `playwright-cli install --skills` registers the playwright-cli Agent
    Skill (independent of plugins.json).

.PARAMETER NoPlugins
    Only link this repo's skills/ and agents/; skip the plugins.json section.

.PARAMETER Manifest
    Path to the plugin manifest (default: <repo>\plugins.json).

.PARAMETER PlaywrightCliPackage
    npm spec for @playwright/cli (default: @playwright/cli@latest).

.PARAMETER DebugErrors
    Print the real command output/errors when an install step fails, instead
    of just the summary [warn] line.

.NOTES
    Run from the repository root or any location — the script resolves its
    own directory automatically.
#>
[CmdletBinding()]
param(
    [switch]$NoPlugins,
    [string]$Manifest,
    [string]$SkillsCliPackage = 'skills@latest',
    [string]$PlaywrightCliPackage = '@playwright/cli@latest',
    [switch]$DebugErrors
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── paths ────────────────────────────────────────────────────────────────────

$RepoDir   = $PSScriptRoot
$SkillsSrc = Join-Path $RepoDir 'skills'
$AgentsSrc = Join-Path $RepoDir 'agents'

if (-not $Manifest) { $Manifest = Join-Path $RepoDir 'plugins.json' }

# ── console helpers ──────────────────────────────────────────────────────────

function Write-Info  { param([string]$Msg) Write-Host "[info]  $Msg" -ForegroundColor Cyan    }
function Write-Ok    { param([string]$Msg) Write-Host "[ ok ]  $Msg" -ForegroundColor Green   }
function Write-Skip  { param([string]$Msg) Write-Host "[skip]  $Msg" -ForegroundColor Yellow  }
function Write-Warn  { param([string]$Msg) Write-Host "[warn]  $Msg" -ForegroundColor Yellow  }
function Write-Dbg   { param([string]$Msg) Write-Host "[dbg ]  $Msg" -ForegroundColor DarkCyan }
function Write-Err   { param([string]$Msg) Write-Host "[err ]  $Msg" -ForegroundColor Red     }

# ── link helper ──────────────────────────────────────────────────────────────
# Link-Dir <Src> <Dst>
#
# Creates a directory junction at <Dst> pointing to <Src>.
# Junctions work without elevation on all modern Windows versions.
# Idempotent: skips if already linked correctly; backs up collisions.

function Link-Dir {
    param(
        [string]$Src,
        [string]$Dst
    )

    # Already a junction/symlink pointing at the right place?
    if (Test-Path -LiteralPath $Dst) {
        $item = Get-Item -LiteralPath $Dst -Force
        $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

        if ($isLink) {
            # .Target may be an array on junctions — take the first element
            $rawTarget = $item.Target
            $target = if ($rawTarget -is [array]) { $rawTarget[0] } else { $rawTarget }
            # Normalize both paths for comparison
            $srcNorm = (Resolve-Path -LiteralPath $Src).Path.TrimEnd('\')
            $dstNorm = $target.TrimEnd('\')
            if ($srcNorm -eq $dstNorm) {
                Write-Skip "$Dst (already linked)"
                return
            }
            Write-Warn "$Dst points elsewhere — relinking"
            Remove-Item -LiteralPath $Dst -Force
        } else {
            $bak = "${Dst}.bak"
            Write-Warn "$Dst exists — backing up to $bak"
            Move-Item -LiteralPath $Dst -Destination $bak -Force
        }
    }

    # Ensure parent directory exists
    $parent = Split-Path $Dst -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Create junction (no elevation required)
    New-Item -ItemType Junction -Path $Dst -Value $Src | Out-Null
    Write-Ok "$Dst -> $Src"
}

# ── opencode ─────────────────────────────────────────────────────────────────

function Install-Opencode {
    # opencode on Windows follows the same XDG convention as on Linux/macOS:
    # global config lives in $HOME\.config\opencode\opencode.json
    $CfgDir = Join-Path $HOME '.config\opencode'
    $Cfg    = Join-Path $CfgDir 'opencode.json'

    Write-Info "opencode — updating $Cfg"

    if (-not (Test-Path -LiteralPath $CfgDir)) {
        New-Item -ItemType Directory -Path $CfgDir -Force | Out-Null
    }

    # Seed an empty config if none exists
    if (-not (Test-Path -LiteralPath $Cfg)) {
        @{ '$schema' = 'https://opencode.ai/config.json' } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $Cfg -Encoding UTF8
    }

    # Read and parse existing config
    $json = Get-Content -LiteralPath $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json

    # Ensure skills object exists
    if ($null -eq $json.skills) {
        $json | Add-Member -NotePropertyName 'skills' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if ($null -eq $json.skills.paths) {
        $json.skills | Add-Member -NotePropertyName 'paths' -NotePropertyValue @() -Force
    }

    # Normalise to a plain array of strings
    $paths = @($json.skills.paths)

    if ($paths -contains $SkillsSrc) {
        Write-Skip "opencode skills path already registered"
    } else {
        $paths += $SkillsSrc
        $json.skills.paths = $paths
        $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Cfg -Encoding UTF8
        Write-Ok "opencode skills.paths += $SkillsSrc"
    }

    Write-Ok "opencode config updated"
}

# ── Claude Code ───────────────────────────────────────────────────────────────

function Install-Claude {
    $Base = Join-Path $HOME '.claude'
    Write-Info "Claude Code — linking into $Base"
    Link-Dir $SkillsSrc (Join-Path $Base 'skills')
    Link-Dir $AgentsSrc (Join-Path $Base 'agents')
}

# ── VS Code ───────────────────────────────────────────────────────────────────

function Install-VSCode {
    $Base = Join-Path $HOME '.copilot'
    Write-Info "VS Code — linking into $Base"
    Link-Dir $SkillsSrc (Join-Path $Base 'skills')
    Link-Dir $AgentsSrc (Join-Path $Base 'agents')
}

# ── plugin manifest helpers ──────────────────────────────────────────────────

# Invoke an external CLI without letting it inherit/consume our pipeline input.
# Returns a result object with ExitCode and combined Output. When -DebugErrors
# is set, a non-zero exit prints the real captured output so the caller's
# generic "[warn] failed to ..." line isn't the only visible diagnostic.
function Invoke-Cli {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Arguments = @()
    )

    $out = ''
    try {
        $out = (& $File @Arguments 2>&1 | Out-String)
    } catch {
        $out = "$_"
        if ($DebugErrors) {
            Write-Dbg "command failed: $File $($Arguments -join ' ')"
            Write-Dbg $out.TrimEnd()
        }
        return [PSCustomObject]@{ ExitCode = 1; Output = $out }
    }
    $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    if ($code -ne 0 -and $DebugErrors) {
        Write-Dbg "command failed (exit ${code}): $File $($Arguments -join ' ')"
        if ($out.Trim()) { Write-Dbg $out.TrimEnd() }
    }
    return [PSCustomObject]@{ ExitCode = $code; Output = $out }
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Reads the manifest, or $null when it is missing/invalid.
function Get-PluginManifest {
    if (-not (Test-Path -LiteralPath $Manifest)) {
        Write-Skip "no plugin manifest at $Manifest"
        return $null
    }
    try {
        return Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "$Manifest is not valid JSON — skipping plugin installation"
        return $null
    }
}

# Safe property access on a PSCustomObject under StrictMode.
function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return $prop.Value
}

# Strips ".git" and any directory prefix from a source specifier.
function Get-BaseName {
    param([string]$Source)
    $s = $Source -replace '\.git$', ''
    return ($s -replace '.*/', '')
}

# Normalises "owner/repo" or {name, source} into a {Name, Source} pair.
function ConvertTo-MarketplaceEntry {
    param($Entry)
    if ($Entry -is [string]) {
        return [PSCustomObject]@{ Name = (Get-BaseName $Entry); Source = $Entry }
    }
    $src  = Get-Prop $Entry 'source'
    $name = Get-Prop $Entry 'name' (Get-BaseName $src)
    return [PSCustomObject]@{ Name = $name; Source = $src }
}

# Derives a plugin name from a source specifier
# (plugin@marketplace, owner/repo, owner/repo:path, or a git URL).
function Get-PluginName {
    param([string]$Source)
    $s = $Source
    if ($s -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $s = $s -replace ':.*$', '' }
    $s = $s -replace '@.*$', ''
    return (Get-BaseName $s)
}

# Strips a trailing @version from an npm module, keeping any @scope/ prefix.
function Get-ModuleBase {
    param([string]$Module)
    $lead = ''
    $m = $Module
    if ($m.StartsWith('@')) { $lead = '@'; $m = $m.Substring(1) }
    $idx = $m.IndexOf('@')
    if ($idx -ge 0) { $m = $m.Substring(0, $idx) }
    return "$lead$m"
}

# ── Claude Code plugins ──────────────────────────────────────────────────────

function Install-ClaudePlugins {
    param($Data)

    Write-Info "Claude Code — plugins from $Manifest"

    if (-not (Test-Command 'claude')) {
        Write-Skip "claude CLI not found — skipping Claude Code plugins"
        return
    }

    $claude = Get-Prop $Data 'claude'
    $known  = Join-Path $HOME '.claude\plugins\known_marketplaces.json'

    $knownNames = @()
    if (Test-Path -LiteralPath $known) {
        try {
            $kj = Get-Content -LiteralPath $known -Raw -Encoding UTF8 | ConvertFrom-Json
            $knownNames = @($kj.PSObject.Properties.Name)
        } catch { $knownNames = @() }
    }

    foreach ($raw in @(Get-Prop $claude 'marketplaces' @())) {
        $m = ConvertTo-MarketplaceEntry $raw
        if ($knownNames -contains $m.Name) {
            Write-Skip "claude marketplace $($m.Name) (already registered)"
            continue
        }
        $r = Invoke-Cli 'claude' @('plugin', 'marketplace', 'add', $m.Source, '--scope', 'user')
        if ($r.ExitCode -eq 0) {
            Write-Ok "claude marketplace registered: $($m.Name) ($($m.Source))"
            $knownNames += $m.Name
        } else {
            Write-Warn "failed to register claude marketplace $($m.Source)"
        }
    }

    $installedIds = @()
    $listed = Invoke-Cli 'claude' @('plugin', 'list', '--json')
    if ($listed.ExitCode -eq 0) {
        try { $installedIds = @((ConvertFrom-Json $listed.Output) | ForEach-Object { $_.id }) } catch { }
    }

    foreach ($raw in @(Get-Prop $claude 'plugins' @())) {
        if ($raw -is [string]) { $id = $raw; $scope = 'user' }
        else { $id = Get-Prop $raw 'id'; $scope = Get-Prop $raw 'scope' 'user' }
        if (-not $id) { continue }

        $shortId = ($id -split '@')[0]
        $already = @($installedIds | Where-Object { $_ -eq $id -or (($_ -split '@')[0]) -eq $shortId })
        if ($already.Count -gt 0) {
            Write-Skip "claude plugin $id (already installed)"
            continue
        }

        $r = Invoke-Cli 'claude' @('plugin', 'install', $id, '--scope', $scope, '--yes')
        if ($r.ExitCode -eq 0) {
            Write-Ok "claude plugin installed: $id"
            $installedIds += $id
        } else {
            Write-Warn "failed to install claude plugin $id"
        }
    }
}

# ── GitHub Copilot CLI plugins ───────────────────────────────────────────────

function Install-CopilotPlugins {
    param($Data)

    Write-Info "GitHub Copilot — plugins from $Manifest"

    if (-not (Test-Command 'copilot')) {
        Write-Skip "copilot CLI not found — skipping Copilot plugins"
        return
    }

    $copilot = Get-Prop $Data 'copilot'

    $markets = (Invoke-Cli 'copilot' @('plugin', 'marketplace', 'list')).Output
    foreach ($raw in @(Get-Prop $copilot 'marketplaces' @())) {
        $m = ConvertTo-MarketplaceEntry $raw
        if ($markets -match "(^|\s)$([regex]::Escape($m.Name))\s*\(") {
            Write-Skip "copilot marketplace $($m.Name) (already registered)"
            continue
        }
        $r = Invoke-Cli 'copilot' @('plugin', 'marketplace', 'add', $m.Source)
        if ($r.ExitCode -eq 0) {
            Write-Ok "copilot marketplace registered: $($m.Name) ($($m.Source))"
            $markets = (Invoke-Cli 'copilot' @('plugin', 'marketplace', 'list')).Output
        } else {
            Write-Warn "failed to register copilot marketplace $($m.Source)"
        }
    }

    $installed = (Invoke-Cli 'copilot' @('plugin', 'list')).Output
    foreach ($raw in @(Get-Prop $copilot 'plugins' @())) {
        if ($raw -is [string]) { $source = $raw; $name = Get-PluginName $raw }
        else {
            $source = Get-Prop $raw 'source'
            $name   = Get-Prop $raw 'name' (Get-PluginName $source)
        }
        if (-not $source) { continue }

        if ($installed -match "(^|[^\w-])$([regex]::Escape($name))([^\w-]|$)") {
            Write-Skip "copilot plugin $name (already installed)"
            continue
        }
        $r = Invoke-Cli 'copilot' @('plugin', 'install', $source)
        if ($r.ExitCode -eq 0) {
            Write-Ok "copilot plugin installed: $name ($source)"
            $installed = (Invoke-Cli 'copilot' @('plugin', 'list')).Output
        } else {
            Write-Warn "failed to install copilot plugin $source"
        }
    }
}

# ── opencode plugins ─────────────────────────────────────────────────────────

function Install-OpencodePlugins {
    param($Data)

    Write-Info "opencode — plugins from $Manifest"

    if (-not (Test-Command 'opencode')) {
        Write-Skip "opencode CLI not found — skipping opencode plugins"
        return
    }

    $cfg = Join-Path $HOME '.config\opencode\opencode.json'

    foreach ($raw in @(Get-Prop (Get-Prop $Data 'opencode') 'plugins' @())) {
        $module = if ($raw -is [string]) { $raw } else { Get-Prop $raw 'module' }
        if (-not $module) { continue }
        $base = Get-ModuleBase $module

        $existing = @()
        if (Test-Path -LiteralPath $cfg) {
            try {
                $cj = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
                $existing = @(Get-Prop $cj 'plugins' @())
            } catch { $existing = @() }
        }

        $found = @($existing | Where-Object { (Get-ModuleBase $_) -eq $base })
        if ($found.Count -gt 0) {
            Write-Skip "opencode plugin $base (already configured)"
            continue
        }

        $r = Invoke-Cli 'opencode' @('plugin', 'add', $module)
        if ($r.ExitCode -eq 0) {
            Write-Ok "opencode plugin installed: $module"
        } else {
            Write-Warn "failed to install opencode plugin $module"
        }
    }
}

# ── public skills via npx ────────────────────────────────────────────────────

function Install-PublicSkills {
    param($Data)

    Write-Info "public skills — from $Manifest"

    $entries = @(Get-Prop $Data 'skills' @())
    if ($entries.Count -eq 0) {
        Write-Skip "no public skills declared"
        return
    }

    if (-not (Test-Command 'npx')) {
        Write-Warn "npx not found — skipping public skills (install Node.js and re-run)"
        return
    }

    $installed = @()
    $listed = Invoke-Cli 'npx' @('-y', $SkillsCliPackage, 'list', '--global', '--json')
    if ($listed.ExitCode -eq 0) {
        try { $installed = @(ConvertFrom-Json $listed.Output) } catch { $installed = @() }
    }

    foreach ($raw in $entries) {
        if ($raw -is [string]) {
            $source = $raw; $names = '*'; $agents = '*'; $scope = 'global'
        } else {
            $source = Get-Prop $raw 'source'
            $names  = Get-Prop $raw 'skills' '*'
            $agents = Get-Prop $raw 'agents' '*'
            $scope  = Get-Prop $raw 'scope'  'global'
        }
        if (-not $source) { continue }

        $match = @($installed | Where-Object {
            $s = Get-Prop $_ 'source' ''
            $u = Get-Prop $_ 'sourceUrl' ''
            ("$s".Contains($source)) -or ("$u".Contains($source))
        })
        if ($match.Count -gt 0) {
            Write-Skip "public skills $source (already installed)"
            continue
        }

        $scopeFlag = if ($scope -eq 'project') { '--project' } else { '--global' }
        $r = Invoke-Cli 'npx' @('-y', $SkillsCliPackage, 'add', $source, $scopeFlag,
                                '--skill', $names, '--agent', $agents, '--yes')
        if ($r.ExitCode -eq 0) {
            Write-Ok "public skills installed: $source (skills=$names, agents=$agents)"
        } else {
            Write-Warn "failed to install public skills from $source"
        }
    }
}

# ── Playwright CLI ───────────────────────────────────────────────────────────
# Installs @playwright/cli globally via npm, then runs its own
# `playwright-cli install --skills` to register the playwright-cli Agent Skill.
# Tries a real global install via `sudo` first (present on Win11+/macOS/Linux
# when running pwsh); if sudo is unavailable/denied, falls back to a
# user-local npm prefix ($HOME/.npm-global) so the install never requires
# elevated privileges to succeed.

function Ensure-PlaywrightCli {
    Write-Info "playwright-cli — from npm ($PlaywrightCliPackage)"

    if (-not (Test-Command 'npm')) {
        Write-Warn "npm not found — skipping playwright-cli (install Node.js and re-run)"
        return
    }

    if (Test-Command 'playwright-cli') {
        Write-Skip "playwright-cli already installed"
    } else {
        $installed = $false

        if (Test-Command 'sudo') {
            Write-Info "attempting 'sudo npm install -g' (may prompt for your password)"
            $r = Invoke-Cli 'sudo' @('npm', 'install', '-g', $PlaywrightCliPackage)
            if ($r.ExitCode -eq 0) {
                $installed = $true
            } elseif ($DebugErrors) {
                Write-Dbg "sudo install failed or unavailable, falling back to user-local install"
            }
        }

        if (-not $installed) {
            $npmPrefix = Join-Path $HOME '.npm-global'
            New-Item -ItemType Directory -Force -Path $npmPrefix | Out-Null
            $r = Invoke-Cli 'npm' @('install', '-g', '--prefix', $npmPrefix, $PlaywrightCliPackage)
            if ($r.ExitCode -eq 0) {
                $installed = $true
                $env:PATH = "$(Join-Path $npmPrefix 'bin')$([IO.Path]::PathSeparator)$env:PATH"
                Write-Info "installed to $npmPrefix — add '$(Join-Path $npmPrefix 'bin')' to your PATH to use playwright-cli in new shells"
            }
        }

        if ($installed) {
            Write-Ok "installed $PlaywrightCliPackage via npm"
        } else {
            Write-Warn "failed to install $PlaywrightCliPackage via npm (sudo and user-local install both failed)"
            return
        }
    }

    $r = Invoke-Cli 'playwright-cli' @('install', '--skills')
    if ($r.ExitCode -eq 0) {
        Write-Ok "playwright-cli skills installed"
    } else {
        Write-Warn "failed to run 'playwright-cli install --skills'"
    }
}

function Install-Plugins {
    if ($NoPlugins) {
        Write-Skip "plugin installation disabled (-NoPlugins)"
        return
    }
    $data = Get-PluginManifest
    if ($null -eq $data) { return }

    Install-ClaudePlugins $data
    Write-Host ""
    Install-CopilotPlugins $data
    Write-Host ""
    Install-OpencodePlugins $data
    Write-Host ""
    Install-PublicSkills $data
}

# ── main ─────────────────────────────────────────────────────────────────────

Write-Info "personal-ai-tooling installer"
Write-Info "Repo: $RepoDir"
Write-Host ""

Install-Opencode
Write-Host ""
Install-Claude
Write-Host ""
Install-VSCode
Write-Host ""
Ensure-PlaywrightCli
Write-Host ""
Install-Plugins
Write-Host ""

Write-Info "Done."
Write-Info "Restart opencode / VS Code / Claude Code for changes to take effect."
