#!/usr/bin/env bash
# Checks the team.json schema is valid JSON and declares exactly the spec's keys.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
S="$REPO/plugins/podium/schema/team.schema.json"

jq empty "$S" 2>/dev/null; assert_eq 0 "$?" "schema is valid JSON"
assert_eq "planner,critic,builder,scout" "$(jq -r '.properties.slots.properties | keys_unsorted | join(",")' "$S")" "slot keys"
assert_eq "false" "$(jq -r '.properties.slots.additionalProperties' "$S")" "no unknown slots"
assert_eq "1" "$(jq -r '.properties.version.const' "$S")" "version const"
assert_eq "string,null" "$(jq -r '.properties.workspace.type | join(",")' "$S")" "workspace type"

finish
