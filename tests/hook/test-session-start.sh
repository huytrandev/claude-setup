#!/usr/bin/env bash
# End-to-end tests: run the hook as Claude Code would and check its JSON output.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
F="$REPO/tests/hook/fixtures"
HOOK="$REPO/plugins/podium/hooks/run-hook.cmd"

run_hook() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" HOME="$F/home" CLAUDE_PLUGIN_ROOT="$REPO/plugins/podium" bash "$HOOK" session-start); }

out="$(run_hook "$F/proj-valid")"; rc=$?
assert_eq 0 "$rc" "exit 0"
assert_eq "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "event name"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "| planner | agora-ta |" "context carries bound planner"

# Review Focus 4: no git repo, no .claude dir
tmp="$(mktemp -d)"
out="$(run_hook "$tmp")"; rc=$?
assert_eq 0 "$rc" "exit 0 outside repo"
printf '%s' "$out" | jq empty 2>/dev/null; assert_eq 0 "$?" "valid JSON outside repo"
assert_contains "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')" "Team source: podium defaults" "defaults outside repo"

# Review Focus 5: quotes and backslashes in a bound value survive as valid JSON
mkdir -p "$tmp/.claude/agents"
printf -- '---\nname: we"ird\\name\n---\n' > "$tmp/.claude/agents/w.md"
printf '{ "version": 1, "slots": { "scout": "we\\"ird" } }\n' > "$tmp/.claude/team.json"
out="$(run_hook "$tmp")"
printf '%s' "$out" | jq empty 2>/dev/null; assert_eq 0 "$?" "valid JSON with quotes in values"
rm -rf "$tmp"

assert_eq 0 "$(jq -e '.hooks.SessionStart[0].hooks[0].command | test("run-hook.cmd")' "$REPO/plugins/podium/hooks/hooks.json" >/dev/null; echo $?)" "hooks.json registers run-hook.cmd"

finish
