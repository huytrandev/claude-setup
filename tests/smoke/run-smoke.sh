#!/usr/bin/env bash
# Opt-in headless scenarios. Costs real model tokens. Run: PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh
set -u
[ "${PODIUM_SMOKE:-}" = 1 ] || { echo "skipped (set PODIUM_SMOKE=1)"; exit 0; }
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
SB="$REPO/tests/smoke/.sandbox"

rm -rf "$SB"; mkdir -p "$SB/.claude" "$SB/src"
printf '{ "version": 1, "workspace": ".agent-work" }\n' > "$SB/.claude/team.json"
printf 'export function add(a: number, b: number) { return a + b; }\n' > "$SB/src/math.ts"
(cd "$SB" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)

# Optional: PODIUM_SMOKE_MODEL=sonnet|haiku|... runs the conductor (main session) on that model.
MODEL_ARGS=()
[ -n "${PODIUM_SMOKE_MODEL:-}" ] && MODEL_ARGS=(--model "$PODIUM_SMOKE_MODEL")
ask() { (cd "$SB" && claude -p --plugin-dir "$REPO/plugins/podium" --permission-mode acceptEdits --output-format json ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$1"); }
folders() { find "$SB/.agent-work" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' '; }

# S1 trivial: no workspace folder
out="$(ask 'What does src/math.ts export? One line.')"
assert_contains "$out" "add" "S1 answers"
assert_eq 0 "$(folders)" "S1 creates no task folder"

# S2 standard: folder with request, status, skeleton plan; stops for plan approval
out="$(ask 'Add subtract and multiply functions to src/math.ts with tests.')"
d="$(find "$SB/.agent-work" -name 00-request.md -exec dirname {} \; | head -n 1)"
assert_file "$d/00-request.md" "S2 request"
assert_file "$d/status.md" "S2 status"
assert_file "$d/30-plan-v1.md" "S2 plan"
assert_contains "$(cat "$d/00-request.md")" "standard" "S2 triaged standard"
assert_contains "$(cat "$d/30-plan-v1.md")" "Test intent" "S2 plan is skeleton"
assert_not_contains "$(cat "$d/30-plan-v1.md")" "return a - b" "S2 plan has no bodies"

# S3 complex: planner asks questions before any spec exists
out="$(ask 'Design a plugin system for this repo so third parties can register math operations at runtime.')"
q="$(find "$SB/.agent-work" -name '10-questions-1.md' | head -n 1)"
assert_file "$q" "S3 planner asked questions"
assert_eq "" "$(find "$SB/.agent-work" -name 20-spec.md)" "S3 no spec before answers"

finish
