#!/usr/bin/env bash
# Validates the marketplace and plugin manifests with the Claude Code CLI.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"

out="$(claude plugin validate --strict "$REPO" 2>&1)"; rc=$?
assert_eq 0 "$rc" "marketplace validates strictly: $out"

out="$(claude plugin validate --strict "$REPO/plugins/podium" 2>&1)"; rc=$?
assert_eq 0 "$rc" "plugin validates strictly: $out"

finish
