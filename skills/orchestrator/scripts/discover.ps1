<#
.SYNOPSIS
  Finds every AI agent CLI on this machine and prints it as JSON for the
  orchestrator brain. Read-only: runs only each CLI's version command, with a
  timeout, and never sends a prompt, logs in, or changes configuration.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File discover.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File discover.ps1 -Table
#>
[CmdletBinding()]
param(
  [int]$TimeoutSec = 15,
  [switch]$Table
)
$ErrorActionPreference = 'Continue'

# name -> kind. kind: agent (usable worker), brain (never a worker),
# gateway (messaging/automation platform, excluded unless the user opts in),
# local (local model runner, no tools).
$Known = [ordered]@{
  'grok' = 'agent'; 'agy' = 'agent'; 'opencode' = 'agent'; 'gemini' = 'agent'
  'qwen' = 'agent'; 'kimi' = 'agent'; 'mimo' = 'agent'; 'codex' = 'agent'
  'crush' = 'agent'; 'aider' = 'agent'; 'cursor-agent' = 'agent'; 'copilot' = 'agent'
  'amp' = 'agent'; 'goose' = 'agent'; 'droid' = 'agent'; 'auggie' = 'agent'
  'cline' = 'agent'; 'kilocode' = 'agent'; 'kilo' = 'agent'; 'plandex' = 'agent'
  'openhands' = 'agent'; 'hermes' = 'agent'; 'cn' = 'agent'; 'q' = 'agent'
  'kiro-cli' = 'agent'; 'jules' = 'agent'; 'codebuff' = 'agent'; 'qodo' = 'agent'
  'iflow' = 'agent'; 'vibe' = 'agent'; 'letta' = 'agent'; 'trae' = 'agent'
  'llm' = 'agent'; 'aichat' = 'agent'; 'sgpt' = 'agent'; 'tgpt' = 'agent'
  'mods' = 'agent'; 'fabric' = 'agent'
  'claude' = 'brain'
  'openclaw' = 'gateway'
  'ollama' = 'local'; 'lms' = 'local'; 'llamafile' = 'local'
}
$VersionArgs = @{ 'grok' = @('--no-auto-update', '--version') }
$Keywords = 'agent|agentic|\bai\b|llm|copilot|assistant|coding|claude|gpt|gemini|codex|chatbot'

function Get-Version([string]$path, [string[]]$vargs) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $ext = [IO.Path]::GetExtension($path).ToLower()
  $quoted = ($vargs | ForEach-Object { '"' + $_ + '"' }) -join ' '
  if ($ext -eq '.ps1') {
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$path`" $quoted"
  } elseif ($ext -eq '.cmd' -or $ext -eq '.bat') {
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = "/d /c `"`"$path`" $quoted`""
  } else {
    $psi.FileName = $path
    $psi.Arguments = $quoted
  }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $true
  $psi.CreateNoWindow = $true
  try {
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
      try { $p.Kill() } catch {}
      return @{ ok = $false; text = "timeout after ${TimeoutSec}s" }
    }
    $text = ($outTask.Result + "`n" + $errTask.Result)
    $line = ($text -split "`r?`n" | Where-Object { $_ -match '\d+\.\d+' -and $_ -notmatch 'Warning|DeprecationWarning|migration' } | Select-Object -First 1)
    if (-not $line) { $line = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1) }
    $bad = $text -match 'not a valid application|postinstall script was not run|is not recognized'
    return @{ ok = (($p.ExitCode -eq 0) -and -not $bad); text = "$line".Trim() }
  } catch {
    return @{ ok = $false; text = $_.Exception.Message }
  }
}

function Resolve-Cli([string]$name) {
  $cmds = @(Get-Command $name -All -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -in 'Application', 'ExternalScript' })
  if ($cmds.Count -eq 0) { return $null }
  # Prefer a real executable or .cmd shim over a .ps1 shim.
  $pick = $cmds | Sort-Object { switch ([IO.Path]::GetExtension($_.Source).ToLower()) { '.exe' { 0 } '.cmd' { 1 } '.bat' { 2 } default { 3 } } } | Select-Object -First 1
  return $pick.Source
}

$results = New-Object System.Collections.ArrayList
$seen = @{}

foreach ($name in $Known.Keys) {
  $path = Resolve-Cli $name
  if (-not $path) { continue }
  $vargs = if ($VersionArgs.ContainsKey($name)) { $VersionArgs[$name] } else { @('--version') }
  $v = Get-Version $path $vargs
  [void]$results.Add([pscustomobject]@{
    name = $name; kind = $Known[$name]; known = $true; source = 'path'
    path = $path; runs = $v.ok; version = $v.text
  })
  $seen[$name] = $true
}

# Unknown candidates: global npm packages whose name/description look like an AI CLI.
$npm = Get-Command npm -ErrorAction SilentlyContinue
if ($npm) {
  $root = (& npm root -g 2>$null | Select-Object -First 1)
  if ($root -and (Test-Path $root)) {
    $pkgDirs = @()
    foreach ($d in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
      if ($d.Name.StartsWith('@')) { $pkgDirs += Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue }
      else { $pkgDirs += $d }
    }
    foreach ($d in $pkgDirs) {
      $pj = Join-Path $d.FullName 'package.json'
      if (-not (Test-Path $pj)) { continue }
      try { $j = Get-Content -Raw -LiteralPath $pj | ConvertFrom-Json } catch { continue }
      if (-not $j.bin) { continue }
      $bins = if ($j.bin -is [string]) { @($j.name.Split('/')[-1]) } else { @($j.bin.PSObject.Properties.Name) }
      $text = "$($j.name) $($j.description) $(@($j.keywords) -join ' ')"
      foreach ($b in $bins) {
        if ($seen.ContainsKey($b)) { continue }
        if ($text -notmatch $Keywords) { continue }
        $path = Resolve-Cli $b
        if (-not $path) { continue }
        $v = Get-Version $path @('--version')
        [void]$results.Add([pscustomobject]@{
          name = $b; kind = 'candidate'; known = $false; source = "npm:$($j.name)"
          path = $path; runs = $v.ok; version = $v.text
        })
        $seen[$b] = $true
      }
    }
  }
}

if ($Table) {
  $results | Format-Table name, kind, runs, version, source -AutoSize
} else {
  ConvertTo-Json -InputObject @($results) -Depth 3
}
