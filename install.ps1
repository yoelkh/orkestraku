<#
.SYNOPSIS
  Installs (or removes) the OrkestraKu /orchestrator skill for Claude Code.

.DESCRIPTION
  Downloads skills/orchestrator/SKILL.md from GitHub into
  ~/.claude/skills/orchestrator/ (user scope, default) or
  .claude/skills/orchestrator/ in the current folder (project scope),
  backs up any different existing copy, then checks which worker CLIs
  (grok, agy, opencode) are available.

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
  Install from a local SKILL.md instead of downloading (for development).

.PARAMETER Uninstall
  Remove the installed skill (backups are kept).
#>
[CmdletBinding()]
param(
  [ValidateSet('user', 'project')]
  [string]$Scope = 'user',
  [string]$Ref = 'main',
  [string]$Source,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$Repo = 'yoelkh/orkestraku'
$SkillName = 'orchestrator'

function Write-Step($msg) { Write-Host "  $msg" }
function Write-Ok($msg)   { Write-Host "  [OK] " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn2($msg){ Write-Host "  [!!] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-No($msg)   { Write-Host "  [--] " -ForegroundColor DarkGray -NoNewline; Write-Host $msg }

if ($Scope -eq 'project') {
  $Base = Join-Path (Get-Location) '.claude\skills'
} else {
  $Base = Join-Path $HOME '.claude\skills'
}
$Target = Join-Path $Base $SkillName
$SkillFile = Join-Path $Target 'SKILL.md'

Write-Host ''
Write-Host '  OrkestraKu' -ForegroundColor Cyan -NoNewline
Write-Host '  /orchestrator skill for Claude Code'
Write-Host ''

if ($Uninstall) {
  if (Test-Path $SkillFile) {
    Remove-Item -LiteralPath $SkillFile -Force
    Write-Ok "Removed $SkillFile"
    $left = @(Get-ChildItem -LiteralPath $Target -Force -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) { Remove-Item -LiteralPath $Target -Force; Write-Ok "Removed empty $Target" }
    else { Write-Step "Kept $($left.Count) backup file(s) in $Target" }
  } else {
    Write-No "Nothing to remove at $SkillFile"
  }
  Write-Host ''
  return
}

# --- get the skill ----------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("orkestraku-" + [guid]::NewGuid().ToString('N') + '.md')
try {
  if ($Source) {
    Copy-Item -LiteralPath $Source -Destination $tmp
    Write-Ok "Using local source $Source"
  } else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $url = "https://raw.githubusercontent.com/$Repo/$Ref/skills/$SkillName/SKILL.md"
    Write-Step "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
  }

  $content = [IO.File]::ReadAllText($tmp)
  if (-not ($content.StartsWith('---') -and $content -match "(?m)^name:\s*$SkillName\s*$")) {
    throw "Downloaded file does not look like the $SkillName skill. Aborting; nothing was changed."
  }

  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  if (Test-Path $SkillFile) {
    $old = [IO.File]::ReadAllText($SkillFile)
    if ($old -eq $content) {
      Write-Ok "Already up to date: $SkillFile"
    } else {
      $bak = "$SkillFile.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
      Copy-Item -LiteralPath $SkillFile -Destination $bak
      Write-Ok "Backed up previous version to $bak"
      Copy-Item -LiteralPath $tmp -Destination $SkillFile -Force
      Write-Ok "Updated $SkillFile"
    }
  } else {
    Copy-Item -LiteralPath $tmp -Destination $SkillFile -Force
    Write-Ok "Installed $SkillFile"
  }
} finally {
  if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force }
}

# --- worker check (read-only) -----------------------------------------------
Write-Host ''
Write-Host '  Workers' -ForegroundColor Cyan

function Test-Worker($name, $cmd, $versionArgs, $hint) {
  # Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'.
  $ErrorActionPreference = 'Continue'
  $c = Get-Command $cmd -ErrorAction SilentlyContinue
  if (-not $c) { Write-No "$name  not installed  ($hint)"; return }
  try {
    $v = (& $cmd @versionArgs 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $v -match 'not a valid application|postinstall') {
      Write-Warn2 "$name  found but failed to run. If it was installed with npm, run its postinstall: cd `"$env:APPDATA\npm\node_modules\opencode-ai`"; node postinstall.mjs"
    } else {
      Write-Ok "$name  $(($v -split "`n")[0])"
    }
  } catch {
    $m = $_.Exception.Message
    if ($m -match 'not a valid application') {
      Write-Warn2 "$name  found but failed to run. If it was installed with npm, run its postinstall: cd `"$env:APPDATA\npm\node_modules\opencode-ai`"; node postinstall.mjs"
    } else {
      Write-Warn2 "$name  found but failed to run: $m"
    }
  }
}

Test-Worker 'grok    ' 'grok'     @('--no-auto-update', '--version') 'https://x.ai  -> then run: grok login'
Test-Worker 'agy     ' 'agy'      @('--version')                      'Antigravity CLI (Gemini)'
Test-Worker 'opencode' 'opencode' @('--version')                      'npm i -g opencode-ai'
Write-Ok   "sub       Claude subagents (always available inside Claude Code)"

Write-Host ''
Write-Host '  Next: open Claude Code and run ' -NoNewline
Write-Host '/orchestrator <your task>' -ForegroundColor Cyan
Write-Host '  Missing workers are skipped automatically; the skill never installs or logs in anything for you.'
Write-Host ''
