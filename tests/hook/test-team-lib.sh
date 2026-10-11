#!/usr/bin/env bash
# Unit tests for plugins/podium/hooks/lib/team.sh.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
. "$REPO/plugins/podium/hooks/lib/team.sh"
F="$REPO/tests/hook/fixtures"
P="$F/plugin"; H="$F/home"

# defaults
assert_eq "podium:composer" "$(podium_default_agent planner)" "default planner"
assert_eq "podium:performer" "$(podium_default_agent builder)" "default builder"
podium_default_agent nope >/dev/null; assert_eq 1 "$?" "unknown slot fails"

# json string extraction (pretty and minified — Review Focus 1)
assert_eq "agora-ta" "$(podium_json_string "$F/proj-valid/.claude/team.json" planner)" "pretty planner"
assert_eq "" "$(podium_json_string "$F/proj-valid/.claude/team.json" critic)" "absent key empty"
assert_eq "agora-ta" "$(podium_json_string "$F/proj-minified/.claude/team.json" planner)" "minified planner"
assert_eq "podium:critic" "$(podium_json_string "$F/proj-minified/.claude/team.json" critic)" "minified critic"
assert_eq "claude-sonnet-5-5" "$(podium_json_string "$F/proj-minified/.claude/team.json" fallbackModel)" "minified fallback"
assert_eq "" "$(podium_json_string "$F/proj-valid/.claude/team.json" workspace)" "null workspace empty"

# json validity
podium_json_valid "$F/proj-valid/.claude/team.json"; assert_eq 0 "$?" "valid json"
podium_json_valid "$F/proj-invalid/.claude/team.json"; assert_eq 1 "$?" "invalid json"
( PATH="/nonexistent"; podium_json_valid "$F/proj-valid/.claude/team.json"; exit $? ); assert_eq 2 "$?" "no checker available"

# agent existence (Review Focus 2: frontmatter name, not filename)
podium_agent_exists agora-ta "$F/proj-valid" "$P" "$H"; assert_eq 0 "$?" "project agent by frontmatter name"
podium_agent_exists ta "$F/proj-valid" "$P" "$H"; assert_eq 1 "$?" "filename alone does not count"
podium_agent_exists user-helper "$F/proj-valid" "$P" "$H"; assert_eq 0 "$?" "user-level agent"
podium_agent_exists ghost-dev "$F/proj-missing" "$P" "$H"; assert_eq 1 "$?" "missing agent"
podium_agent_exists podium:critic "$F/proj-none" "$P" "$H"; assert_eq 0 "$?" "podium agent"
podium_agent_exists podium:ghost "$F/proj-none" "$P" "$H"; assert_eq 1 "$?" "missing podium agent"
podium_agent_exists other-plugin:thing "$F/proj-none" "$P" "$H"; assert_eq 0 "$?" "foreign plugin agent trusted"

# workspace (Review Focus 3)
assert_eq "$H/.agent-work" "$(podium_workspace "$F/proj-valid/.claude/team.json" "$F/proj-valid" "$H")" "null workspace → default"
assert_eq "$H/.agent-work" "$(podium_workspace "$F/proj-none/.claude/team.json" "$F/proj-none" "$H")" "no team.json → default"
assert_eq "$F/proj-workspace/.agent-work" "$(podium_workspace "$F/proj-workspace/.claude/team.json" "$F/proj-workspace" "$H")" "relative workspace"

# escaping (Review Focus 5)
assert_eq 'a\"b\\c\nd\te' "$(podium_json_escape "$(printf 'a"b\\c\nd\te')")" "json escape"

# context block
ctx="$(podium_build_context "$F/proj-valid" "$P" "$H")"
assert_contains "$ctx" "| planner | agora-ta |" "bound planner"
assert_contains "$ctx" "| critic | podium:critic |" "unbound critic default"
assert_contains "$ctx" "| scout | user-helper |" "user-level scout"
assert_contains "$ctx" "Team source: .claude/team.json" "team source"
assert_contains "$ctx" "Warnings: none" "no warnings"
assert_contains "$ctx" "podium:conduct" "points at conduct skill"

ctx="$(podium_build_context "$F/proj-missing" "$P" "$H")"
assert_contains "$ctx" "| builder | podium:performer |" "missing agent falls back"
assert_contains "$ctx" "Slot 'builder' binds missing agent 'ghost-dev'" "missing agent warning"

ctx="$(podium_build_context "$F/proj-invalid" "$P" "$H")"
assert_contains "$ctx" "| planner | podium:composer |" "invalid json → defaults"
assert_contains "$ctx" "not valid JSON" "invalid json warning"

ctx="$(podium_build_context "$F/proj-none" "$P" "$H")"
assert_contains "$ctx" "Team source: podium defaults" "no team.json source"
assert_contains "$ctx" "Fallback model: none" "no fallback"

ctx="$(podium_build_context "$F/proj-minified" "$P" "$H")"
assert_contains "$ctx" "Fallback model: claude-sonnet-5-5" "fallback model shown"

finish
