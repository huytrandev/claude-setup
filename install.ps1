# Installs this repo's Claude Code setup into ~/.claude on Windows (copies, no symlinks). Safe to re-run.
param([string]$HomeDir = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }))
$ErrorActionPreference = 'Stop'
if (-not $HomeDir) { Write-Output 'Home directory could not be determined; pass -HomeDir <path>.'; exit 1 }
$Repo = $PSScriptRoot
$Claude = Join-Path $HomeDir '.claude'
$Backup = Join-Path $Claude ("backups/claude-setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:Changed = 0
$script:Failed = 0

function Write-Status([string]$State, [string]$What) {
  Write-Output "$State $What"
  if ($State -eq 'changed') { $script:Changed++ }
  if ($State -eq 'failed') { $script:Failed++ }
}

function Test-SameContent([string]$A, [string]$B) {
  if (-not (Test-Path $B)) { return $false }
  if ((Get-Item $A).PSIsContainer) {
    if (-not (Get-Item $B).PSIsContainer) { return $false }
    $hashes = {
      param($Root)
      (Get-ChildItem $Root -Recurse -File | ForEach-Object { $_.FullName.Substring($Root.Length) + ':' + (Get-FileHash $_.FullName).Hash } | Sort-Object) -join "`n"
    }
    return (& $hashes $A) -ceq (& $hashes $B)
  }
  if ((Get-Item $B).PSIsContainer) { return $false }
  return (Get-FileHash $A).Hash -eq (Get-FileHash $B).Hash
}

function Move-ToBackup([string]$Dest, [string]$Rel) {
  if (-not (Test-Path $Dest)) { return }
  $bak = Join-Path $Backup $Rel
  New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
  Move-Item $Dest $bak
}

function Copy-Item-Backed([string]$Rel) {
  $src = Join-Path $Repo "dotfiles/$Rel"
  $dest = Join-Path $Claude $Rel
  if (Test-SameContent $src $dest) { Write-Status ok $dest; return }
  Move-ToBackup $dest $Rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Copy-Item $src $dest -Recurse
  Write-Status changed $dest
}

# Recursively sorts object properties so JSON comparison ignores key order.
function ConvertTo-Sorted($Value) {
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $sorted = [ordered]@{}
    foreach ($p in ($Value.PSObject.Properties | Sort-Object Name)) { $sorted[$p.Name] = ConvertTo-Sorted $p.Value }
    return [pscustomobject]$sorted
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    return , @($Value | ForEach-Object { ConvertTo-Sorted $_ })
  }
  return $Value
}

function Get-CanonicalJson($Value) { ConvertTo-Json (ConvertTo-Sorted $Value) -Depth 20 -Compress }

# settings.json: copy, but keep extraKnownMarketplaces (written by the Claude CLI) from the target and ignore it when comparing.
function Install-Settings {
  $src = Join-Path $Repo 'dotfiles/settings.json'
  $dest = Join-Path $Claude 'settings.json'
  if (-not (Test-Path $dest -PathType Leaf)) { Copy-Item-Backed 'settings.json'; return }
  try {
    $new = Get-Content $src -Raw | ConvertFrom-Json
    $old = Get-Content $dest -Raw | ConvertFrom-Json
  } catch { Copy-Item-Backed 'settings.json'; return }
  if ($old.PSObject.Properties['extraKnownMarketplaces']) {
    $new | Add-Member -NotePropertyName extraKnownMarketplaces -NotePropertyValue $old.extraKnownMarketplaces -Force
  }
  if ((Get-CanonicalJson $new) -ceq (Get-CanonicalJson $old)) { Write-Status ok $dest; return }
  Move-ToBackup $dest 'settings.json'
  $new | ConvertTo-Json -Depth 20 | Set-Content -Path $dest -Encoding utf8
  Write-Status changed $dest
}

Write-Output '== Dependencies'
$claudeOk = [bool](Get-Command claude -ErrorAction SilentlyContinue)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output 'warn: git not found - needed to clone and update this repo.' }
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) { Write-Output 'warn: jq not found - the destructive-command guard hook and the statusline are INACTIVE until jq is installed.' }
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { Write-Output 'warn: bash not found - install Git for Windows; hooks and the statusline need Git Bash.' }
if (-not $claudeOk) { Write-Output 'warn: claude CLI not found - plugin steps skipped. Install Claude Code, then re-run.' }

Write-Output '== Dotfiles (copy)'
New-Item -ItemType Directory -Force -Path $Claude | Out-Null
foreach ($rel in 'CLAUDE.md', 'statusline-command.sh', 'hooks/guard-destructive.sh', 'skills/capturing-personal-knowledge') {
  Copy-Item-Backed $rel
}
Install-Settings

Write-Output '== Workspace'
$ws = Join-Path $HomeDir '.agent-work'
if (Test-Path $ws) { Write-Status ok $ws } else { New-Item -ItemType Directory -Path $ws | Out-Null; Write-Status changed $ws }

if ($claudeOk) {
  Write-Output '== Plugins'
  $markets = (& claude plugin marketplace list 2>$null | Out-String)
  foreach ($m in @(@('claude-setup', $Repo), @('claude-plugins-official', 'anthropics/claude-plugins-official'))) {
    if ($markets.Contains($m[0])) { Write-Status ok "marketplace $($m[0])"; continue }
    & claude plugin marketplace add $m[1]
    if ($LASTEXITCODE -eq 0) { Write-Status changed "marketplace $($m[0])" } else { Write-Status failed "marketplace $($m[0])" }
  }
  $installed = (& claude plugin list 2>$null | Out-String)
  $settings = Get-Content (Join-Path $Repo 'dotfiles/settings.json') -Raw | ConvertFrom-Json
  foreach ($p in $settings.enabledPlugins.PSObject.Properties) {
    if (-not $p.Value) { continue }
    if ($installed.Contains($p.Name)) { Write-Status ok "plugin $($p.Name)"; continue }
    & claude plugin install $p.Name
    if ($LASTEXITCODE -eq 0) { Write-Status changed "plugin $($p.Name)" } else { Write-Status failed "plugin $($p.Name)" }
  }
}

if (Test-Path $Backup) { Write-Output "Backups: $Backup" }
Write-Output "Summary: $script:Changed changed"
if ($script:Failed -gt 0) { Write-Output "Failures: $script:Failed" }
if (-not $claudeOk -or $script:Failed -gt 0) { exit 1 }
