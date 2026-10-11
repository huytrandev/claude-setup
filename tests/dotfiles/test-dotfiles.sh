#!/usr/bin/env bash
# Hygiene checks for dotfiles/: valid JSON, no machine-specific paths, no secrets, hook paths resolvable.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
D="$REPO/dotfiles"

for f in CLAUDE.md settings.json statusline-command.sh hooks/guard-destructive.sh skills/capturing-personal-knowledge/SKILL.md; do
  assert_file "$D/$f" "dotfile $f"
done

jq empty "$D/settings.json" 2>/dev/null; assert_eq 0 "$?" "settings.json valid"
assert_eq "true" "$(jq -r '.enabledPlugins["podium@claude-setup"]' "$D/settings.json")" "podium enabled"
assert_eq "true" "$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"]' "$D/settings.json")" "superpowers enabled"

assert_eq "" "$(grep -rn -E '/Users/[A-Za-z]|/home/[A-Za-z]|C:\\\\Users' "$D" || true)" "no absolute home paths"
assert_eq "" "$(grep -rn -i -E '(api[_-]?key|secret|token|password)[\"'\'' ]*[:=]' "$D" || true)" "no secrets"

# every ~/.claude/<path> referenced by a settings command exists in dotfiles/
while IFS= read -r p; do
  assert_file "$D/$p" "settings references $p"
done < <(jq -r '.. | .command? // empty' "$D/settings.json" | grep -o '~/.claude/[^ "]*' | sed 's#~/.claude/##' | sort -u)

[ -x "$D/hooks/guard-destructive.sh" ]; assert_eq 0 "$?" "guard is executable"

finish
