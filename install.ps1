<#
.SYNOPSIS
  Installs (or removes) the OrkestraKu /orchestrator skill for Claude Code.

.DESCRIPTION
  Downloads the skill (SKILL.md, references/, scripts/) from GitHub into
  ~/.claude/skills/orchestrator/ (user scope, default) or
  .claude/skills/orchestrator/ in the current folder (project scope).
  Changed files are backed up to ~/.claude/orchestra/backups/<timestamp>/.
  Then it scans the machine for AI agent CLIs (read-only: version commands only).

  One-liner (PowerShell):
    irm https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.ps1 | iex

  With options:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.ps1))) -Scope project
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/yoelkh/orkestraku/main/install.ps1))) -Uninstall

.PARAMETER Scope
  user (default): ~/.claude/skills  |  project: ./.claude/skills

.PARAMETER Ref
  Git branch, tag, or commit to install from. Default: main.

.PARAMETER Source
  Install from a local skill folder (the one containing SKILL.md) instead of
  downloading. For development.

.PARAMETER Uninstall
  Remove the installed skill files (backups and the worker cache are kept).

.PARAMETER NoScan
  Skip the CLI scan at the end.
#>
[CmdletBinding()]
param(
  [ValidateSet('user', 'project')]
  [string]$Scope = 'user',
  [string]$Ref = 'main',
  [string]$Source,
  [switch]$Uninstall,
  [switch]$NoScan
)

$ErrorActionPreference = 'Stop'
$Repo = 'yoelkh/orkestraku'
$SkillName = 'orchestrator'
$Files = @('SKILL.md', 'references/workers.md', 'scripts/discover.ps1', 'scripts/discover.sh')

function Write-Step($msg) { Write-Host "  $msg" }
function Write-Ok($msg)   { Write-Host "  [OK] " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-No($msg)   { Write-Host "  [--] " -ForegroundColor DarkGray -NoNewline; Write-Host $msg }

if ($Scope -eq 'project') {
  $Base = Join-Path (Get-Location) '.claude\skills'
} else {
  $Base = Join-Path $HOME '.claude\skills'
}
$Target = Join-Path $Base $SkillName

Write-Host ''
Write-Host '  OrkestraKu' -ForegroundColor Cyan -NoNewline
Write-Host '  /orchestrator skill for Claude Code'
Write-Host ''

if ($Uninstall) {
  $removed = 0
  foreach ($f in $Files) {
    $p = Join-Path $Target ($f -replace '/', '\')
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $removed++ }
  }
  foreach ($d in @('references', 'scripts', '')) {
    $p = if ($d) { Join-Path $Target $d } else { $Target }
    if ((Test-Path -LiteralPath $p) -and @(Get-ChildItem -LiteralPath $p -Force).Count -eq 0) {
      Remove-Item -LiteralPath $p -Force
    }
  }
  if ($removed -gt 0) { Write-Ok "Removed $removed file(s) from $Target" } else { Write-No "Nothing to remove at $Target" }
  if (Test-Path -LiteralPath $Target) { Write-Step "Kept other files in $Target" }
  Write-Host ''
  return
}

# --- get every file into a staging folder first (nothing changes on failure) --
$stage = Join-Path ([IO.Path]::GetTempPath()) ("orkestraku-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
  if (-not $Source) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Step "Downloading from github.com/$Repo ($Ref)"
  } else {
    Write-Ok "Using local source $Source"
  }
  foreach ($f in $Files) {
    $dst = Join-Path $stage ($f -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    if ($Source) {
      Copy-Item -LiteralPath (Join-Path $Source ($f -replace '/', '\')) -Destination $dst
    } else {
      Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repo/$Ref/skills/$SkillName/$f" -OutFile $dst -UseBasicParsing
    }
    if ((Get-Item -LiteralPath $dst).Length -eq 0) { throw "$f is empty. Aborting; nothing was changed." }
  }

  $skill = [IO.File]::ReadAllText((Join-Path $stage 'SKILL.md'))
  if (-not ($skill.StartsWith('---') -and $skill -match "(?m)^name:\s*$SkillName\s*$")) {
    throw "SKILL.md does not look like the $SkillName skill. Aborting; nothing was changed."
  }

  # --- install, backing up files that differ ---------------------------------
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = Join-Path $HOME ".claude\orchestra\backups\$stamp"
  $installed = 0; $updated = 0; $same = 0
  foreach ($f in $Files) {
    $rel = $f -replace '/', '\'
    $src = Join-Path $stage $rel
    $dst = Join-Path $Target $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    if (Test-Path -LiteralPath $dst) {
      if ((Get-FileHash -LiteralPath $dst).Hash -eq (Get-FileHash -LiteralPath $src).Hash) { $same++; continue }
      $b = Join-Path $backup $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $b) | Out-Null
      Copy-Item -LiteralPath $dst -Destination $b
      Copy-Item -LiteralPath $src -Destination $dst -Force
      $updated++
    } else {
      Copy-Item -LiteralPath $src -Destination $dst -Force
      $installed++
    }
  }
  if ($updated -gt 0) { Write-Ok "Backed up $updated changed file(s) to $backup" }
  if ($installed + $updated -eq 0) { Write-Ok "Already up to date: $Target" }
  else { Write-Ok "Installed $Target  ($installed new, $updated updated, $same unchanged)" }
} finally {
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

# --- scan for AI agent CLIs (read-only) ---------------------------------------
if (-not $NoScan) {
  # Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'.
  $ErrorActionPreference = 'Continue'
  Write-Host ''
  Write-Host '  AI CLIs found on this machine' -ForegroundColor Cyan
  $scan = Join-Path $Target 'scripts\discover.ps1'
  try {
    $rows = & powershell -NoProfile -ExecutionPolicy Bypass -File $scan | Out-String | ConvertFrom-Json
    foreach ($r in @($rows)) {
      $label = '{0,-12} {1,-9}' -f $r.name, $r.kind
      if ($r.kind -eq 'brain' -or $r.kind -eq 'gateway') { Write-No "$label $($r.version)  (not used as a worker)" }
      elseif ($r.runs) { Write-Ok "$label $($r.version)" }
      else { Write-Host "  [!!] " -ForegroundColor Yellow -NoNewline; Write-Host "$label fails to start: $($r.version)" }
    }
    Write-Ok ('{0,-12} {1,-9} Claude subagents (always available)' -f 'sub', 'agent')
  } catch {
    Write-No "Scan skipped: $($_.Exception.Message)"
  }
}

Write-Host ''
Write-Host '  Next: open Claude Code and run ' -NoNewline
Write-Host '/orchestrator setup' -ForegroundColor Cyan -NoNewline
Write-Host ' to analyze your CLIs and get setup advice, then ' -NoNewline
Write-Host '/orchestrator <task>' -ForegroundColor Cyan
Write-Host '  Sign-in and API keys stay your call; the skill never installs or logs in anything for you.'
Write-Host ''
