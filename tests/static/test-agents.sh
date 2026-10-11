#!/usr/bin/env bash
# Checks agent frontmatter: name matches filename, pinned model, required skills.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
A="$REPO/plugins/podium/agents"

fm() { sed -n '2,/^---$/p' "$1"; }
field() { fm "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1; }

check() {
  local f="$A/$1.md"
  assert_file "$f" "$1 exists"
  [ -f "$f" ] || return
  assert_eq "$1" "$(field "$f" name)" "$1 name"
  assert_eq "$2" "$(field "$f" model)" "$1 model"
  assert_contains "$(field "$f" description)" "Podium" "$1 description names its podium slot"
  assert_contains "$(cat "$f")" "STATUS:" "$1 body states the STATUS contract"
}

check composer claude-opus-5-5
check critic claude-opus-5-5
check performer claude-sonnet-5-5
check scout claude-haiku-5-5

assert_contains "$(fm "$A/composer.md")" "podium:skeleton-plan" "composer preloads skeleton-plan"
assert_contains "$(fm "$A/composer.md")" "superpowers:writing-plans" "composer preloads writing-plans"
assert_contains "$(fm "$A/performer.md")" "superpowers:test-driven-development" "performer preloads TDD"

finish
