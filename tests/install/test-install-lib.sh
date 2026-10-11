#!/usr/bin/env bash
# Unit tests for install/lib.sh.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
. "$REPO/install/lib.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src dir" "$T/home/.claude"
echo one > "$T/src dir/a.md"
B="$T/home/.claude/backups/run1"

# new target → link
out="$(cs_link_item "$T/src dir/a.md" "$T/home/.claude/a.md" "$B" link)"
assert_contains "$out" "changed" "new link reported"
assert_eq "$T/src dir/a.md" "$(readlink "$T/home/.claude/a.md")" "symlink target (path with spaces — RF5)"
[ -d "$B" ]; assert_eq 1 "$?" "no backup dir when nothing moved"

# already linked → untouched (RF1)
out="$(cs_link_item "$T/src dir/a.md" "$T/home/.claude/a.md" "$B" link)"
assert_contains "$out" "ok" "existing link ok"
[ -d "$B" ]; assert_eq 1 "$?" "still no backup dir"

# identical regular file → backed up then linked (RF2)
rm "$T/home/.claude/a.md"; echo one > "$T/home/.claude/a.md"
out="$(cs_link_item "$T/src dir/a.md" "$T/home/.claude/a.md" "$B" link)"
assert_contains "$out" "changed" "regular file replaced"
assert_file "$B/a.md" "original backed up"
[ -L "$T/home/.claude/a.md" ]; assert_eq 0 "$?" "now a symlink"

# copy mode: identical copy → ok; different → backup + copy
out="$(cs_link_item "$T/src dir/a.md" "$T/home/.claude/c.md" "$B" copy)"
assert_contains "$out" "changed" "copy created"
out="$(cs_link_item "$T/src dir/a.md" "$T/home/.claude/c.md" "$B" copy)"
assert_contains "$out" "ok" "identical copy ok"
echo two > "$T/home/.claude/c.md"
out="$(cs_link_item "$T/src dir/a.md" "$T/home/.claude/c.md" "$B" copy)"
assert_contains "$out" "changed" "different copy replaced"
assert_eq "two" "$(cat "$B/c.md")" "different copy backed up"
assert_eq "one" "$(cat "$T/home/.claude/c.md")" "copy content"

# nested destination dirs are created; directories can be linked
mkdir -p "$T/src dir/skill"; echo s > "$T/src dir/skill/SKILL.md"
cs_link_item "$T/src dir/skill" "$T/home/.claude/skills/skill" "$B" link >/dev/null
assert_file "$T/home/.claude/skills/skill/SKILL.md" "dir link resolves"

# failed link: read-only parent -> "failed <dest>", return 1
mkdir -p "$T/ro"; chmod 555 "$T/ro"
if [ ! -w "$T/ro" ]; then
  out="$(cs_link_item "$T/src dir/a.md" "$T/ro/x.md" "$B" link 2>/dev/null)"; rc=$?
  assert_eq "failed $T/ro/x.md" "$out" "unwritable parent reported as failed"
  assert_eq 1 "$rc" "failed link returns 1"
  out="$(cs_link_item "$T/src dir/a.md" "$T/ro/x.md" "$B" copy 2>/dev/null)"; rc=$?
  assert_eq "failed $T/ro/x.md" "$out" "unwritable parent reported as failed (copy)"
  assert_eq 1 "$rc" "failed copy returns 1"
fi
chmod 755 "$T/ro"

# enabled plugins
printf '{ "enabledPlugins": { "a@m": true, "b@m": false, "c@n": true } }\n' > "$T/s.json"
assert_eq "a@m c@n" "$(cs_enabled_plugins "$T/s.json" | tr '\n' ' ' | sed 's/ $//')" "enabled plugins"

# deps (RF3, RF4)
out="$(PATH="/usr/bin:/bin" cs_check_deps)"; rc=$?
assert_contains "$out" "warn: claude" "missing claude warned"
assert_eq 1 "$rc" "missing claude fails"
mkdir -p "$T/bin"; cp "$REPO/tests/install/stub-claude" "$T/bin/claude"
out="$(PATH="$T/bin:/usr/bin:/bin" cs_check_deps)"; rc=$?
assert_eq 0 "$rc" "claude present passes"
if ! PATH="/usr/bin:/bin" command -v jq >/dev/null; then
  assert_contains "$out" "warn: jq" "missing jq warned"
  assert_contains "$out" "guard" "jq warning names the guard hook"
fi

# marketplace / plugin idempotency via stub
export STUB_LOG="$T/log"; : > "$STUB_LOG"
STUB_MARKETPLACES="claude-plugins-official" PATH="$T/bin:$PATH" cs_ensure_marketplace claude-plugins-official anthropics/claude-plugins-official >/dev/null
assert_eq "plugin marketplace list" "$(cat "$STUB_LOG")" "existing marketplace not re-added"
: > "$STUB_LOG"
STUB_MARKETPLACES="" PATH="$T/bin:$PATH" cs_ensure_marketplace claude-setup "$T/src dir" >/dev/null
assert_contains "$(cat "$STUB_LOG")" "plugin marketplace add $T/src dir" "missing marketplace added"
: > "$STUB_LOG"
STUB_PLUGINS="podium@claude-setup" PATH="$T/bin:$PATH" cs_ensure_plugin podium@claude-setup >/dev/null
assert_not_contains "$(cat "$STUB_LOG")" "plugin install" "installed plugin skipped"
: > "$STUB_LOG"
STUB_PLUGINS="" PATH="$T/bin:$PATH" cs_ensure_plugin podium@claude-setup >/dev/null
assert_contains "$(cat "$STUB_LOG")" "plugin install podium@claude-setup" "missing plugin installed"
: > "$STUB_LOG"
out="$(STUB_PLUGINS="" STUB_FAIL_INSTALL=bad@m PATH="$T/bin:$PATH" cs_ensure_plugin bad@m)"; rc=$?
assert_eq "failed plugin bad@m" "$out" "failed install reported"
assert_eq 1 "$rc" "failed install returns 1"

# settings.json: CLI-written extraKnownMarketplaces preserved and ignored (R3)
if command -v jq >/dev/null 2>&1; then
  printf '{ "theme": "dark" }\n' > "$T/src dir/settings.json"
  out="$(cs_install_settings "$T/src dir/settings.json" "$T/home/.claude/settings.json" "$B")"
  assert_contains "$out" "changed" "settings first install"
  jq '. + {extraKnownMarketplaces: {m: {source: {source: "directory", path: "/x"}}}}' "$T/home/.claude/settings.json" > "$T/s.tmp" && mv "$T/s.tmp" "$T/home/.claude/settings.json"
  out="$(cs_install_settings "$T/src dir/settings.json" "$T/home/.claude/settings.json" "$B")"
  assert_contains "$out" "ok" "CLI-added marketplaces ignored"
  printf '{ "theme": "light" }\n' > "$T/src dir/settings.json"
  out="$(cs_install_settings "$T/src dir/settings.json" "$T/home/.claude/settings.json" "$B")"
  assert_contains "$out" "changed" "repo change applied"
  assert_eq "light" "$(jq -r .theme "$T/home/.claude/settings.json")" "new value written"
  assert_eq "/x" "$(jq -r '.extraKnownMarketplaces.m.source.path' "$T/home/.claude/settings.json")" "marketplaces preserved"
fi

# settings.json without jq: plain copy with a warning (only when jq is not in /usr/bin:/bin)
if ! PATH="/usr/bin:/bin" command -v jq >/dev/null 2>&1; then
  printf '{ "theme": "dark" }\n' > "$T/src dir/s2.json"; echo '{}' > "$T/home/.claude/s2.json"
  out="$(PATH="/usr/bin:/bin" cs_install_settings "$T/src dir/s2.json" "$T/home/.claude/s2.json" "$B")"
  assert_contains "$out" "warn: jq not found — settings.json copied without preserving extraKnownMarketplaces" "no-jq fallback warns"
  assert_contains "$out" "changed" "no-jq fallback still copies"
fi

finish
