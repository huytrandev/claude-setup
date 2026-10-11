#!/usr/bin/env bash
# Runs install.sh against a sandbox HOME with a stub claude CLI.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.claude"; cp "$REPO/tests/install/stub-claude" "$T/bin/claude"
export STUB_LOG="$T/log"
echo "old" > "$T/home/.claude/CLAUDE.md"

run() { HOME="$T/home" PATH="$T/bin:$PATH" STUB_MARKETPLACES="${MK:-}" STUB_PLUGINS="${PL:-}" bash "$REPO/install.sh"; }

out="$(run)"; rc=$?
assert_eq 0 "$rc" "first run exits 0"
assert_eq "$REPO/dotfiles/CLAUDE.md" "$(readlink "$T/home/.claude/CLAUDE.md")" "CLAUDE.md linked"
assert_eq "$REPO/dotfiles/hooks/guard-destructive.sh" "$(readlink "$T/home/.claude/hooks/guard-destructive.sh")" "guard linked"
assert_eq "$REPO/dotfiles/skills/capturing-personal-knowledge" "$(readlink "$T/home/.claude/skills/capturing-personal-knowledge")" "skill linked"
[ -L "$T/home/.claude/settings.json" ]; assert_eq 1 "$?" "settings.json is a copy, not a link"
cmp -s "$REPO/dotfiles/settings.json" "$T/home/.claude/settings.json"; assert_eq 0 "$?" "settings.json content"
[ -d "$T/home/.agent-work" ]; assert_eq 0 "$?" "workspace created"
assert_eq "old" "$(cat "$T/home/.claude/backups/"claude-setup-*/CLAUDE.md)" "old CLAUDE.md backed up"
assert_contains "$(cat "$STUB_LOG")" "plugin marketplace add $REPO" "local marketplace added"
assert_contains "$(cat "$STUB_LOG")" "plugin marketplace add anthropics/claude-plugins-official" "official marketplace added"
assert_contains "$(cat "$STUB_LOG")" "plugin install podium@claude-setup" "podium installed"
assert_contains "$(cat "$STUB_LOG")" "plugin install superpowers@claude-plugins-official" "superpowers installed"

# second run: nothing changes, no new backup dir
sleep 1
# simulate the CLI writing extraKnownMarketplaces into settings.json (R3)
if command -v jq >/dev/null 2>&1; then
jq '. + {extraKnownMarketplaces: {"claude-setup": {source: {source: "directory", path: "/repo"}}}}' "$T/home/.claude/settings.json" > "$T/s.tmp" && mv "$T/s.tmp" "$T/home/.claude/settings.json"
fi
: > "$STUB_LOG"
backups_before="$(ls "$T/home/.claude/backups" | wc -l | tr -d ' ')"
out="$(MK="claude-setup claude-plugins-official" PL="$(jq -r '.enabledPlugins | keys[]' "$REPO/dotfiles/settings.json")" run)"
assert_contains "$out" "Summary: 0 changed" "second run is a no-op"
assert_eq "$backups_before" "$(ls "$T/home/.claude/backups" | wc -l | tr -d ' ')" "no new backup dir"
assert_not_contains "$(cat "$STUB_LOG")" "install" "no installs on second run"
if command -v jq >/dev/null 2>&1; then
assert_eq "/repo" "$(jq -r '.extraKnownMarketplaces["claude-setup"].source.path' "$T/home/.claude/settings.json")" "CLI-written marketplace kept on re-run"
fi

# claude missing (RF4): dotfiles still linked, exit 1
rm -rf "$T/home2"; mkdir -p "$T/home2"
out="$(HOME="$T/home2" PATH="/usr/bin:/bin" bash "$REPO/install.sh")"; rc=$?
assert_eq 1 "$rc" "exit 1 without claude"
assert_contains "$out" "warn: claude" "explains missing claude"
[ -L "$T/home2/.claude/CLAUDE.md" ]; assert_eq 0 "$?" "dotfiles linked without claude"

# stdin isolation: a claude that eats stdin must not swallow remaining plugin ids
rm -rf "$T/home3"; mkdir -p "$T/home3"; : > "$STUB_LOG"
out="$(HOME="$T/home3" PATH="$T/bin:$PATH" STUB_EAT_STDIN=1 bash "$REPO/install.sh" </dev/null)"
for id in $(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$REPO/dotfiles/settings.json"); do
  assert_contains "$(cat "$STUB_LOG")" "plugin install $id" "stdin-eating claude still installs $id"
done

# failed install is surfaced: exit 1 and Failures line
rm -rf "$T/home4"; mkdir -p "$T/home4"; : > "$STUB_LOG"
out="$(HOME="$T/home4" PATH="$T/bin:$PATH" STUB_FAIL_INSTALL=podium@claude-setup bash "$REPO/install.sh")"; rc=$?
assert_eq 1 "$rc" "exit 1 when a plugin install fails"
assert_contains "$out" "failed plugin podium@claude-setup" "failure line shown"
assert_contains "$out" "Failures: 1" "failure count shown"

finish
