#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Reads the tool-call JSON on stdin and guards
# against destructive shell commands.
#   - permissionDecision "deny" : catastrophic / irreversible -> hard block
#   - permissionDecision "ask"  : risky but sometimes legitimate -> force a confirm
#   - no output                 : let the normal permission flow proceed
# The hook must never exit with code 2 and must never block on its own errors.

input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

low=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')

emit() { # $1=decision  $2=reason
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

m() { printf '%s' "$low" | grep -Eq "$1"; }   # match against lowercased command

# ---------------- DENY: catastrophic, irreversible ----------------
m ':[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|'  && emit deny "Fork bomb detected."
m 'no-preserve-root'                                                        && emit deny "rm --no-preserve-root would wipe the whole filesystem."
m '\bmkfs(\.[a-z0-9]+)?\b'                                                  && emit deny "mkfs formats a filesystem."
m '\bdd\b[^;|&]*\bof=/dev/'                                                 && emit deny "dd writing directly to a raw device."
m 'diskutil[[:space:]]+(erase|reformat|partitiondisk)'                      && emit deny "diskutil erase/reformat destroys a disk."
m '>[[:space:]]*/dev/(disk|r?disk|sd|nvme)'                                 && emit deny "Overwriting a raw block device."

# ---------------- rm -rf detection ----------------
is_rm_rf() {
  m '(^|[;&|(]|[[:space:]])(sudo[[:space:]]+)?rm([[:space:]]|$)' || return 1
  m 'rm[[:space:]]+([^;|&]*[[:space:]])?(-[a-z]*r|--recursive)'  || return 1   # recursive
  m 'rm[[:space:]]+([^;|&]*[[:space:]])?(-[a-z]*f|--force)'      || return 1   # force
  return 0
}
if is_rm_rf; then
  # Deny when the target is root / home / a top-level wildcard.
  if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])(/|/\*|~|~/\*?|\$HOME|\$\{HOME\}|\$HOME/\*?|\*)([[:space:]]|;|$)'; then
    emit deny "Recursive force-delete targeting / , ~, \$HOME or a top-level * — refusing."
  fi
  emit ask "Recursive force-delete (rm -rf). Double-check the target path before continuing."
fi

# ---------------- ASK: risky but sometimes legitimate ----------------
if m 'git[[:space:]]+push' && m '(--force([[:space:]]|=|$)|[[:space:]]-[a-z]*f([[:space:]]|$))' && ! m 'force-with-lease'; then
  emit ask "git push --force can overwrite remote history (prefer --force-with-lease)."
fi
m 'git[[:space:]]+reset[[:space:]]+([^;|&]*[[:space:]])?--hard'   && emit ask "git reset --hard discards uncommitted work."
m 'git[[:space:]]+clean[[:space:]]+([^;|&]*)?-[a-z]*f'            && emit ask "git clean -f permanently deletes untracked files."
m '(curl|wget)[[:space:]][^;|&]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)\b' && emit ask "Piping a downloaded script straight into a shell."
m 'chmod[[:space:]]+([^;|&]*[[:space:]])?(-[a-z]*r|--recursive)'  && emit ask "Recursive chmod can break permissions across a tree."

exit 0
