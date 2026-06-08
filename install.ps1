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

.NOTES
    Run from the repository root or any location — the script resolves its
    own directory automatically.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── paths ────────────────────────────────────────────────────────────────────

$RepoDir   = $PSScriptRoot
$SkillsSrc = Join-Path $RepoDir 'skills'
$AgentsSrc = Join-Path $RepoDir 'agents'

# ── console helpers ──────────────────────────────────────────────────────────

function Write-Info  { param([string]$Msg) Write-Host "[info]  $Msg" -ForegroundColor Cyan    }
function Write-Ok    { param([string]$Msg) Write-Host "[ ok ]  $Msg" -ForegroundColor Green   }
function Write-Skip  { param([string]$Msg) Write-Host "[skip]  $Msg" -ForegroundColor Yellow  }
function Write-Warn  { param([string]$Msg) Write-Host "[warn]  $Msg" -ForegroundColor Yellow  }
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

Write-Info "Done."
Write-Info "Restart opencode / VS Code / Claude Code for changes to take effect."
