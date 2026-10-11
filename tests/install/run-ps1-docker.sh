#!/usr/bin/env bash
# Opt-in: runs install.ps1 in a pwsh container with a stub claude. Requires Docker.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
docker run --rm -v "$REPO:/repo:ro" mcr.microsoft.com/powershell:7.4-ubuntu-22.04 bash -c '
  set -e
  mkdir -p /stub && cp /repo/tests/install/stub-claude /stub/claude && chmod +x /stub/claude
  export PATH=/stub:$PATH STUB_LOG=/tmp/log
  mkdir -p /h/.claude && echo old > /h/.claude/CLAUDE.md
  pwsh -NoProfile -File /repo/install.ps1 -HomeDir /h | tee /tmp/run1
  grep -q "plugin install podium@claude-setup" /tmp/log
  cmp /repo/dotfiles/CLAUDE.md /h/.claude/CLAUDE.md
  ls /h/.claude/backups/claude-setup-*/CLAUDE.md
  test -d /h/.agent-work
  sleep 1; : > /tmp/log
  # simulate the CLI writing extraKnownMarketplaces into settings.json (R3)
  pwsh -NoProfile -Command "\$s = Get-Content /h/.claude/settings.json -Raw | ConvertFrom-Json; \$s | Add-Member -NotePropertyName extraKnownMarketplaces -NotePropertyValue ([pscustomobject]@{\"claude-setup\" = [pscustomobject]@{source = [pscustomobject]@{source = \"directory\"; path = \"/repo\"}}}); \$s | ConvertTo-Json -Depth 20 | Set-Content /h/.claude/settings.json"
  export STUB_MARKETPLACES="claude-setup claude-plugins-official"
  export STUB_PLUGINS="$(grep -o "\"[^\"]*@[^\"]*\": *true" /repo/dotfiles/settings.json | cut -d\" -f2 | tr "\n" " ")"
  pwsh -NoProfile -File /repo/install.ps1 -HomeDir /h | tee /tmp/run2
  grep -q "Summary: 0 changed" /tmp/run2
  ! grep -q "plugin install" /tmp/log
  grep -q "\"path\": \"/repo\"" /h/.claude/settings.json
  # failed plugin install: exit 1 and Failures line
  mkdir -p /h2; rc=0
  STUB_MARKETPLACES= STUB_PLUGINS= STUB_FAIL_INSTALL=podium@claude-setup pwsh -NoProfile -File /repo/install.ps1 -HomeDir /h2 > /tmp/run3 || rc=$?
  cat /tmp/run3
  test "$rc" = 1
  grep -q "failed plugin podium@claude-setup" /tmp/run3
  grep -q "^Failures: 1$" /tmp/run3
  echo PS1_OK
'
