#!/usr/bin/env bash
# Runs every tests/**/test-*.sh and fails if any of them fails.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
status=0
while IFS= read -r t; do
  bash "$t" || status=1
done < <(find "$ROOT" -name 'test-*.sh' -type f | sort)
exit "$status"
