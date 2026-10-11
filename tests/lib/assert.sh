# Minimal assertion helpers for podium's bash tests.
PASS=0
FAIL=0

_report() {
  if [ "$1" = ok ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $2" >&2; fi
}

assert_eq() {
  if [ "$1" = "$2" ]; then _report ok; else _report fail "$3 (expected '$1', got '$2')"; fi
}

assert_contains() {
  case "$1" in *"$2"*) _report ok ;; *) _report fail "$3 (missing '$2')" ;; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) _report fail "$3 (unexpected '$2')" ;; *) _report ok ;; esac
}

assert_file() {
  if [ -f "$1" ]; then _report ok; else _report fail "$2 (no file $1)"; fi
}

finish() {
  echo "$(basename "$0"): ${PASS} passed, ${FAIL} failed"
  [ "$FAIL" -eq 0 ]
}
