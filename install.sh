#!/usr/bin/env bash
# Installs this repo's Claude Code setup into ~/.claude. Safe to re-run.
set -u
[ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 1; }
REPO="$(cd "$(dirname "$0")" && pwd)"
. "$REPO/install/lib.sh"

BACKUP="$HOME/.claude/backups/claude-setup-$(date +%Y%m%d-%H%M%S)"
MODE=link; cs_is_windows && MODE=copy
changed=0; failed=0
count() { while IFS= read -r line; do echo "$line"; case "$line" in changed*) changed=$((changed + 1)) ;; failed*) failed=$((failed + 1)) ;; esac; done; }

echo "== Dependencies"
deps_out="$(cs_check_deps)"; claude_ok=$?
[ -n "$deps_out" ] && echo "$deps_out"

echo "== Dotfiles ($MODE)"
mkdir -p "$HOME/.claude"
for item in CLAUDE.md statusline-command.sh hooks/guard-destructive.sh skills/capturing-personal-knowledge; do
  count < <(cs_link_item "$REPO/dotfiles/$item" "$HOME/.claude/$item" "$BACKUP" "$MODE")
done
count < <(cs_install_settings "$REPO/dotfiles/settings.json" "$HOME/.claude/settings.json" "$BACKUP")

echo "== Workspace"
if [ -d "$HOME/.agent-work" ]; then echo "ok $HOME/.agent-work"; else mkdir -p "$HOME/.agent-work"; echo "changed $HOME/.agent-work"; changed=$((changed + 1)); fi

if [ "$claude_ok" -eq 0 ]; then
  echo "== Plugins"
  count < <(cs_ensure_marketplace claude-setup "$REPO")
  count < <(cs_ensure_marketplace claude-plugins-official anthropics/claude-plugins-official)
  while IFS= read -r id; do
    count < <(cs_ensure_plugin "$id")
  done < <(cs_enabled_plugins "$REPO/dotfiles/settings.json")
fi

[ -d "$BACKUP" ] && echo "Backups: $BACKUP"
echo "Summary: ${changed} changed"
[ "$failed" -gt 0 ] && echo "Failures: ${failed}"
[ "$claude_ok" -eq 0 ] && [ "$failed" -eq 0 ]
