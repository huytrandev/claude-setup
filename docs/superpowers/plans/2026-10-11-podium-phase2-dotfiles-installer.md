# Podium Phase 2 — Dotfiles & Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the personal Claude Code setup reproducible on any machine: the repo carries the dotfiles, and one idempotent install script (`install.sh` for macOS/Linux, `install.ps1` for Windows) links them into `~/.claude`, installs the marketplaces and plugins, and creates `~/.agent-work`.

**Architecture:** `dotfiles/` mirrors the parts of `~/.claude` worth syncing. `install/lib.sh` holds pure, testable functions (link/copy with backup, plugin list parsing, dependency checks); `install.sh` is a thin CLI over it. Tests run the installer against a sandbox `HOME` with a stub `claude` on `PATH` that logs its arguments. `install.ps1` mirrors the same steps and is tested in a `pwsh` Docker container; native Windows remains a manual check (U4).

**Tech Stack:** Bash 3.2+, PowerShell 7, Docker (tests only), `jq` (tests + required at runtime by the guard hook), `claude` CLI 2.1.296.

**Spec:** `docs/superpowers/specs/2026-10-11-podium-design.md` (§7, §9.4–9.6, §2 U2–U4)

**Depends on:** Phase 1 plan `docs/superpowers/plans/2026-10-11-podium-phase1-plugin.md` completed (marketplace `claude-setup` with plugin `podium` exists).

## Global Constraints

- Sync only: `CLAUDE.md`, `settings.json`, `statusline-command.sh`, `hooks/guard-destructive.sh`, `skills/capturing-personal-knowledge/`. Never sync `history.jsonl`, `projects/`, `sessions/`, `security/`, `backups/`, `cache/`, `plugins/`, `policy-limits*`, `remote-settings.json`, `.credentials*`.
- Backups go to `~/.claude/backups/claude-setup-<YYYYmmdd-HHMMSS>/`, created only when something is moved.
- `settings.json` is **copied**, not symlinked (Claude Code rewrites it when plugins are installed or `/config` changes; a symlink would dirty the repo and may be replaced by an atomic write). All other items are symlinked on macOS/Linux and copied on Windows.
- Marketplaces: `claude-setup` (this repo, local path) and `claude-plugins-official` (`anthropics/claude-plugins-official`).
- Workspace root: `$HOME/.agent-work` (`%USERPROFILE%\.agent-work` on Windows).
- A second run with no repo changes must make zero changes and create no backup directory.
- All file content in English.
- Commits: per-task local commits only after the user has approved executing this plan with commits; never push.

## Review Focus

1. Target already a symlink pointing at the repo file → left alone, no backup (idempotency).
2. Target is a regular file identical to the repo file → still replaced by a symlink, original backed up once; second run is a no-op.
3. `jq` missing on the new machine → installer prints a loud warning that the destructive-command guard and statusline are inactive (the guard currently exits 0 silently without `jq`).
4. `claude` CLI missing → installer links dotfiles, skips plugin steps with a clear message, exits non-zero.
5. Repo cloned to a path containing spaces → links and `marketplace add` still work.

Each is pinned by a test in Task 2 or Task 3.

---

## File Structure

```
dotfiles/
├── CLAUDE.md
├── settings.json
├── statusline-command.sh
├── hooks/guard-destructive.sh
└── skills/capturing-personal-knowledge/SKILL.md
install/lib.sh                       pure functions used by install.sh
install.sh                           macOS/Linux entry point
install.ps1                          Windows entry point
tests/dotfiles/test-dotfiles.sh      dotfiles hygiene checks
tests/install/test-install-lib.sh    unit tests for install/lib.sh
tests/install/test-install-sh.sh     end-to-end install.sh in a sandbox HOME
tests/install/stub-claude            fake claude CLI that logs calls
tests/install/run-ps1-docker.sh      opt-in install.ps1 test in pwsh container
tests/install/fresh-machine.sh       opt-in Linux fresh-machine test in Docker
```

---

### Task 1: Import dotfiles

**Files:**
- Create: everything under `dotfiles/`
- Test: `tests/dotfiles/test-dotfiles.sh`

**Interfaces:**
- Produces: the five sync items at the paths above. `dotfiles/settings.json` additionally contains `"podium@claude-setup": true` in `enabledPlugins`.

- [ ] **Step 1: Write the failing test**

`tests/dotfiles/test-dotfiles.sh`:
```bash
#!/usr/bin/env bash
# Hygiene checks for dotfiles/: valid JSON, no machine-specific paths, no secrets, hook paths resolvable.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
D="$REPO/dotfiles"

for f in CLAUDE.md settings.json statusline-command.sh hooks/guard-destructive.sh skills/capturing-personal-knowledge/SKILL.md; do
  assert_file "$D/$f" "dotfile $f"
done

jq empty "$D/settings.json" 2>/dev/null; assert_eq 0 "$?" "settings.json valid"
assert_eq "true" "$(jq -r '.enabledPlugins["podium@claude-setup"]' "$D/settings.json")" "podium enabled"
assert_eq "true" "$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"]' "$D/settings.json")" "superpowers enabled"

assert_eq "" "$(grep -rn -E '/Users/[A-Za-z]|/home/[A-Za-z]|C:\\\\Users' "$D" || true)" "no absolute home paths"
assert_eq "" "$(grep -rn -i -E '(api[_-]?key|secret|token|password)[\"'\'' ]*[:=]' "$D" || true)" "no secrets"

# every ~/.claude/<path> referenced by a settings command exists in dotfiles/
while IFS= read -r p; do
  assert_file "$D/$p" "settings references $p"
done < <(jq -r '.. | .command? // empty' "$D/settings.json" | grep -o '~/.claude/[^ "]*' | sed 's#~/.claude/##' | sort -u)

[ -x "$D/hooks/guard-destructive.sh" ]; assert_eq 0 "$?" "guard is executable"

finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/dotfiles/test-dotfiles.sh`
Expected: FAIL (no `dotfiles/`).

- [ ] **Step 3: Copy the current files**

```bash
mkdir -p dotfiles/hooks dotfiles/skills
cp ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/statusline-command.sh dotfiles/
cp ~/.claude/hooks/guard-destructive.sh dotfiles/hooks/
cp -R ~/.claude/skills/capturing-personal-knowledge dotfiles/skills/
chmod +x dotfiles/hooks/guard-destructive.sh dotfiles/statusline-command.sh
jq '.enabledPlugins["podium@claude-setup"] = true' dotfiles/settings.json > dotfiles/settings.json.tmp && mv dotfiles/settings.json.tmp dotfiles/settings.json
```

Read each copied file once before committing. If the secrets or absolute-path checks fail, remove the offending value from `dotfiles/` (keep it only on the machine) and note it in the commit message.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/dotfiles/test-dotfiles.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add dotfiles tests/dotfiles
git commit -m "feat(dotfiles): import personal Claude Code config"
```

---

### Task 2: Installer library

**Files:**
- Create: `install/lib.sh`
- Create: `tests/install/stub-claude`
- Test: `tests/install/test-install-lib.sh`

**Interfaces:**
- Produces (sourced, no side effects on load; every function writes human-readable status lines to stdout):
  - `cs_is_windows` → 0 under MINGW/MSYS/CYGWIN `uname`, else 1
  - `cs_link_item <src> <dest> <backup_dir> <mode>` where mode is `link` or `copy`; prints `ok <dest>` (unchanged) or `changed <dest>`; moves an existing different target into `<backup_dir>` (created on demand), preserving its path relative to `~/.claude`
  - `cs_enabled_plugins <settings.json>` → prints each `name@marketplace` whose value is `true`, one per line
  - `cs_check_deps` → prints `warn: …` lines for missing `jq`, `git`, `claude`; returns 1 if `claude` is missing, else 0
  - `cs_ensure_marketplace <name> <source>` → adds only if `claude plugin marketplace list` lacks `<name>`
  - `cs_ensure_plugin <id>` → installs only if `claude plugin list` lacks `<id>`
- Stub contract: `tests/install/stub-claude` appends `"$*"` to `$STUB_LOG`; `plugin marketplace list` prints the contents of `$STUB_MARKETPLACES`; `plugin list` prints `$STUB_PLUGINS`.

- [ ] **Step 1: Write the stub**

`tests/install/stub-claude`:
```bash
#!/usr/bin/env bash
# Fake claude CLI for installer tests: logs every call, answers list commands from env.
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "$*" in
  "plugin marketplace list"*) printf '%s\n' "${STUB_MARKETPLACES:-}" ;;
  "plugin list"*) printf '%s\n' "${STUB_PLUGINS:-}" ;;
esac
exit 0
```
Then `chmod +x tests/install/stub-claude`.

- [ ] **Step 2: Write the failing tests**

`tests/install/test-install-lib.sh`:
```bash
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

finish
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash tests/install/test-install-lib.sh`
Expected: FAIL — `install/lib.sh: No such file or directory`.

- [ ] **Step 4: Implement `install/lib.sh`**

```bash
# Installer functions for claude-setup. Sourced by install.sh and the tests; no side effects on load.

cs_is_windows() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# Moves dest into backup_dir, keeping its path relative to .claude/ (basename outside .claude/).
_cs_backup() { # $1=dest $2=backup_dir
  local rel
  case "$1" in */.claude/*) rel="${1##*/.claude/}" ;; *) rel="$(basename "$1")" ;; esac
  mkdir -p "$(dirname "$2/$rel")"
  mv "$1" "$2/$rel"
}

cs_link_item() {
  local src="$1" dest="$2" backup="$3" mode="$4"
  if [ "$mode" = link ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "ok $dest"; return 0
  fi
  if [ "$mode" = copy ] && [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
    echo "ok $dest"; return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then _cs_backup "$dest" "$backup"; fi
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = link ]; then ln -s "$src" "$dest"; else cp -R "$src" "$dest"; fi
  echo "changed $dest"
}

cs_enabled_plugins() {
  tr -d '\n' < "$1" | grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' | sed 's/^"\([^"]*\)".*/\1/'
}

cs_check_deps() {
  local rc=0
  command -v git >/dev/null 2>&1 || echo "warn: git not found — needed to clone and update this repo."
  command -v jq >/dev/null 2>&1 || echo "warn: jq not found — the destructive-command guard hook and the statusline are INACTIVE until jq is installed."
  command -v claude >/dev/null 2>&1 || { echo "warn: claude CLI not found — plugin steps skipped. Install Claude Code, then re-run."; rc=1; }
  return "$rc"
}

cs_ensure_marketplace() {
  if claude plugin marketplace list 2>/dev/null | grep -q -F "$1"; then echo "ok marketplace $1"; return 0; fi
  claude plugin marketplace add "$2" && echo "changed marketplace $1"
}

cs_ensure_plugin() {
  if claude plugin list 2>/dev/null | grep -q -F "$1"; then echo "ok plugin $1"; return 0; fi
  claude plugin install "$1" && echo "changed plugin $1"
}
```

`_cs_backup` keeps the path relative to `.claude/`, so `hooks/guard-destructive.sh` is backed up as `<backup>/hooks/guard-destructive.sh`.

- [ ] **Step 5: Run to verify it passes**

Run: `bash tests/install/test-install-lib.sh`
Expected: `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh tests/install/stub-claude tests/install/test-install-lib.sh
git commit -m "feat(install): add installer library with backup-safe linking"
```

---

### Task 3: `install.sh`

**Files:**
- Create: `install.sh` (executable)
- Test: `tests/install/test-install-sh.sh`

**Interfaces:**
- Consumes: all `cs_*` functions from Task 2.
- Produces: `./install.sh` — exit 0 on success; exit 1 if `claude` is missing (dotfiles still linked). Final line `Summary: <N> changed`.

- [ ] **Step 1: Write the failing test**

`tests/install/test-install-sh.sh`:
```bash
#!/usr/bin/env bash
# Runs install.sh against a sandbox HOME with a stub claude CLI.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/tests/lib/assert.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.claude"; cp "$REPO/tests/install/stub-claude" "$T/bin/claude"
export STUB_LOG="$T/log"
echo "old" > "$T/home/.claude/CLAUDE.md"

run() { HOME="$T/home" PATH="$T/bin:$PATH" STUB_MARKETPLACES="${MK:-}" STUB_PLUGINS="${PL:-}" bash "$REPO/install.sh"; }

out="$(run)"; rc=$?
assert_eq 0 "$rc" "first run exits 0"
assert_eq "$REPO/dotfiles/CLAUDE.md" "$(readlink "$T/home/.claude/CLAUDE.md")" "CLAUDE.md linked"
assert_eq "$REPO/dotfiles/hooks/guard-destructive.sh" "$(readlink "$T/home/.claude/hooks/guard-destructive.sh")" "guard linked"
assert_eq "$REPO/dotfiles/skills/capturing-personal-knowledge" "$(readlink "$T/home/.claude/skills/capturing-personal-knowledge")" "skill linked"
[ -L "$T/home/.claude/settings.json" ]; assert_eq 1 "$?" "settings.json is a copy, not a link"
cmp -s "$REPO/dotfiles/settings.json" "$T/home/.claude/settings.json"; assert_eq 0 "$?" "settings.json content"
[ -d "$T/home/.agent-work" ]; assert_eq 0 "$?" "workspace created"
assert_eq "old" "$(cat "$T/home/.claude/backups/"claude-setup-*/CLAUDE.md)" "old CLAUDE.md backed up"
assert_contains "$(cat "$STUB_LOG")" "plugin marketplace add $REPO" "local marketplace added"
assert_contains "$(cat "$STUB_LOG")" "plugin marketplace add anthropics/claude-plugins-official" "official marketplace added"
assert_contains "$(cat "$STUB_LOG")" "plugin install podium@claude-setup" "podium installed"
assert_contains "$(cat "$STUB_LOG")" "plugin install superpowers@claude-plugins-official" "superpowers installed"

# second run: nothing changes, no new backup dir
sleep 1
: > "$STUB_LOG"
backups_before="$(ls "$T/home/.claude/backups" | wc -l | tr -d ' ')"
out="$(MK="claude-setup claude-plugins-official" PL="$(jq -r '.enabledPlugins | keys[]' "$REPO/dotfiles/settings.json")" run)"
assert_contains "$out" "Summary: 0 changed" "second run is a no-op"
assert_eq "$backups_before" "$(ls "$T/home/.claude/backups" | wc -l | tr -d ' ')" "no new backup dir"
assert_not_contains "$(cat "$STUB_LOG")" "install" "no installs on second run"

# claude missing (RF4): dotfiles still linked, exit 1
rm -rf "$T/home2"; mkdir -p "$T/home2"
out="$(HOME="$T/home2" PATH="/usr/bin:/bin" bash "$REPO/install.sh")"; rc=$?
assert_eq 1 "$rc" "exit 1 without claude"
assert_contains "$out" "warn: claude" "explains missing claude"
[ -L "$T/home2/.claude/CLAUDE.md" ]; assert_eq 0 "$?" "dotfiles linked without claude"

finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/install/test-install-sh.sh`
Expected: FAIL (no `install.sh`).

- [ ] **Step 3: Implement `install.sh`**

```bash
#!/usr/bin/env bash
# Installs this repo's Claude Code setup into ~/.claude. Safe to re-run.
set -u
REPO="$(cd "$(dirname "$0")" && pwd)"
. "$REPO/install/lib.sh"

BACKUP="$HOME/.claude/backups/claude-setup-$(date +%Y%m%d-%H%M%S)"
MODE=link; cs_is_windows && MODE=copy
changed=0
count() { while IFS= read -r line; do echo "$line"; case "$line" in changed*) changed=$((changed + 1)) ;; esac; done; }

echo "== Dependencies"
deps_out="$(cs_check_deps)"; claude_ok=$?
[ -n "$deps_out" ] && echo "$deps_out"

echo "== Dotfiles ($MODE)"
mkdir -p "$HOME/.claude"
for item in CLAUDE.md statusline-command.sh hooks/guard-destructive.sh skills/capturing-personal-knowledge; do
  count < <(cs_link_item "$REPO/dotfiles/$item" "$HOME/.claude/$item" "$BACKUP" "$MODE")
done
count < <(cs_link_item "$REPO/dotfiles/settings.json" "$HOME/.claude/settings.json" "$BACKUP" copy)

echo "== Workspace"
if [ -d "$HOME/.agent-work" ]; then echo "ok $HOME/.agent-work"; else mkdir -p "$HOME/.agent-work"; echo "changed $HOME/.agent-work"; changed=$((changed + 1)); fi

if [ "$claude_ok" -eq 0 ]; then
  echo "== Plugins"
  count < <(cs_ensure_marketplace claude-setup "$REPO")
  count < <(cs_ensure_marketplace claude-plugins-official anthropics/claude-plugins-official)
  while IFS= read -r id; do
    count < <(cs_ensure_plugin "$id")
  done < <(cs_enabled_plugins "$REPO/dotfiles/settings.json")
fi

[ -d "$BACKUP" ] && echo "Backups: $BACKUP"
echo "Summary: ${changed} changed"
[ "$claude_ok" -eq 0 ]
```

`count < <(…)` keeps `changed` in the current shell (a pipe would run `count` in a subshell and lose the total). Then `chmod +x install.sh`.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/install/test-install-sh.sh && bash tests/run.sh`
Expected: `0 failed` everywhere.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/install/test-install-sh.sh
git commit -m "feat(install): add idempotent install.sh"
```

---

### Task 4: `install.ps1`

**Files:**
- Create: `install.ps1`
- Create: `tests/install/run-ps1-docker.sh` (opt-in, not `test-*.sh`)

**Interfaces:**
- Consumes: same item list and marketplace/plugin steps as `install.sh`.
- Produces: `pwsh install.ps1 [-HomeDir <path>]` — `-HomeDir` defaults to `$env:USERPROFILE`, falling back to `$HOME`. Always copies (no symlinks). Final line `Summary: <N> changed`; exit 1 if `claude` missing.

- [ ] **Step 1: Write the Docker test**

`tests/install/run-ps1-docker.sh`:
```bash
#!/usr/bin/env bash
# Opt-in: runs install.ps1 twice in a pwsh container with a stub claude. Requires Docker.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
docker run --rm -v "$REPO:/repo:ro" mcr.microsoft.com/powershell:7.4-ubuntu-22.04 bash -c '
  set -e
  mkdir -p /stub && cp /repo/tests/install/stub-claude /stub/claude && chmod +x /stub/claude
  export PATH=/stub:$PATH STUB_LOG=/tmp/log
  mkdir -p /h/.claude && echo old > /h/.claude/CLAUDE.md
  pwsh -NoProfile -File /repo/install.ps1 -HomeDir /h | tee /tmp/run1
  grep -q "plugin install podium@claude-setup" /tmp/log
  cmp /repo/dotfiles/CLAUDE.md /h/.claude/CLAUDE.md
  ls /h/.claude/backups/claude-setup-*/CLAUDE.md
  test -d /h/.agent-work
  sleep 1; : > /tmp/log
  export STUB_MARKETPLACES="claude-setup claude-plugins-official"
  export STUB_PLUGINS="$(grep -o "\"[^\"]*@[^\"]*\": *true" /repo/dotfiles/settings.json | cut -d\" -f2 | tr "\n" " ")"
  pwsh -NoProfile -File /repo/install.ps1 -HomeDir /h | tee /tmp/run2
  grep -q "Summary: 0 changed" /tmp/run2
  ! grep -q "plugin install" /tmp/log
  echo PS1_OK
'
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/install/run-ps1-docker.sh`
Expected: FAIL (no `install.ps1`).

- [ ] **Step 3: Implement `install.ps1`**

```powershell
# Installs this repo's Claude Code setup into ~/.claude on Windows (copies, no symlinks). Safe to re-run.
param([string]$HomeDir = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }))
$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$Claude = Join-Path $HomeDir '.claude'
$Backup = Join-Path $Claude ("backups/claude-setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:Changed = 0

function Write-Status([string]$State, [string]$What) {
  Write-Output "$State $What"
  if ($State -eq 'changed') { $script:Changed++ }
}

function Test-SameContent([string]$A, [string]$B) {
  if (-not (Test-Path $B)) { return $false }
  if ((Get-Item $A).PSIsContainer) {
    $left = Get-ChildItem $A -Recurse -File | ForEach-Object { $_.FullName.Substring($A.Length) + ':' + (Get-FileHash $_.FullName).Hash }
    $right = Get-ChildItem $B -Recurse -File | ForEach-Object { $_.FullName.Substring($B.Length) + ':' + (Get-FileHash $_.FullName).Hash }
    return -not (Compare-Object @($left) @($right))
  }
  return (Get-FileHash $A).Hash -eq (Get-FileHash $B).Hash
}

function Copy-Item-Backed([string]$Rel) {
  $src = Join-Path $Repo "dotfiles/$Rel"
  $dest = Join-Path $Claude $Rel
  if (Test-SameContent $src $dest) { Write-Status ok $dest; return }
  if (Test-Path $dest) {
    $bak = Join-Path $Backup $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
    Move-Item $dest $bak
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Copy-Item $src $dest -Recurse
  Write-Status changed $dest
}

Write-Output '== Dependencies'
$claudeOk = [bool](Get-Command claude -ErrorAction SilentlyContinue)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output 'warn: git not found - needed to clone and update this repo.' }
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) { Write-Output 'warn: jq not found - the destructive-command guard hook and the statusline are INACTIVE until jq is installed.' }
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { Write-Output 'warn: bash not found - install Git for Windows; hooks and the statusline need Git Bash.' }
if (-not $claudeOk) { Write-Output 'warn: claude CLI not found - plugin steps skipped. Install Claude Code, then re-run.' }

Write-Output '== Dotfiles (copy)'
foreach ($rel in 'CLAUDE.md', 'settings.json', 'statusline-command.sh', 'hooks/guard-destructive.sh', 'skills/capturing-personal-knowledge') {
  Copy-Item-Backed $rel
}

Write-Output '== Workspace'
$ws = Join-Path $HomeDir '.agent-work'
if (Test-Path $ws) { Write-Status ok $ws } else { New-Item -ItemType Directory -Path $ws | Out-Null; Write-Status changed $ws }

if ($claudeOk) {
  Write-Output '== Plugins'
  $markets = (& claude plugin marketplace list 2>$null) -join "`n"
  foreach ($m in @(@('claude-setup', $Repo), @('claude-plugins-official', 'anthropics/claude-plugins-official'))) {
    if ($markets -like "*$($m[0])*") { Write-Status ok "marketplace $($m[0])" }
    else { & claude plugin marketplace add $m[1]; Write-Status changed "marketplace $($m[0])" }
  }
  $installed = (& claude plugin list 2>$null) -join "`n"
  $settings = Get-Content (Join-Path $Repo 'dotfiles/settings.json') -Raw | ConvertFrom-Json
  foreach ($p in $settings.enabledPlugins.PSObject.Properties) {
    if (-not $p.Value) { continue }
    if ($installed -like "*$($p.Name)*") { Write-Status ok "plugin $($p.Name)" }
    else { & claude plugin install $p.Name; Write-Status changed "plugin $($p.Name)" }
  }
}

if (Test-Path $Backup) { Write-Output "Backups: $Backup" }
Write-Output "Summary: $script:Changed changed"
if (-not $claudeOk) { exit 1 }
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/install/run-ps1-docker.sh`
Expected: last line `PS1_OK`.

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/install/run-ps1-docker.sh
git commit -m "feat(install): add Windows install.ps1"
```

---

### Task 5: Fresh-machine test, unverified items, README

**Files:**
- Create: `tests/install/fresh-machine.sh` (opt-in)
- Modify: `README.md` (add "Set up a new machine")
- Modify: `docs/superpowers/specs/2026-10-11-podium-design.md` (§2: record U2, U3, U4 outcomes)

**Interfaces:**
- Consumes: `install.sh`, the Phase 1 plugin.
- Produces: recorded outcomes; README instructions for a new machine.

- [ ] **Step 1: Write and run the fresh-machine test**

`tests/install/fresh-machine.sh`:
```bash
#!/usr/bin/env bash
# Opt-in: clean Linux container, real Claude Code CLI, install.sh run twice. Needs Docker and network.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
docker run --rm -v "$REPO:/src:ro" ubuntu:24.04 bash -c '
  set -e
  apt-get update -qq && apt-get install -y -qq curl git jq ca-certificates >/dev/null
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
  cp -R /src "/root/claude setup"
  "/root/claude setup/install.sh"
  "/root/claude setup/install.sh" | tee /tmp/run2
  grep -q "Summary: 0 changed" /tmp/run2
  claude plugin list | grep -q podium@claude-setup
  echo FRESH_OK
'
```
Run: `bash tests/install/fresh-machine.sh`
Expected: `FRESH_OK`. The copy to `/root/claude setup` exercises the path-with-spaces case (RF5) with the real CLI. If `claude plugin` commands need login inside the container, record that in the README requirements and in U3, and verify the dotfile-linking part only.

- [ ] **Step 2: Check U2 — do user and project hooks both run?**

The user-level guard denies any command containing `no-preserve-root`; `echo no-preserve-root` is harmless if it does run.
```bash
T="$(mktemp -d)"; mkdir -p "$T/.claude"
cat > "$T/.claude/settings.json" <<EOF
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "touch $T/project-hook-ran" } ] } ] } }
EOF
(cd "$T" && claude -p --permission-mode acceptEdits "Run exactly this bash command and report its output: echo no-preserve-root") | tee "$T/out"
ls "$T/project-hook-ran"; grep -i -E "wipe|denied|blocked" "$T/out"
rm -rf "$T"
```
Expected if hooks merge: the marker file exists **and** the output reports the guard's denial. Record the outcome under U2 in spec §2.

- [ ] **Step 3: Record U3 and U4**

- U3: the installer does not rely on `enabledPlugins` auto-install (it calls the CLI). Record "not relied on; installer uses `claude plugin install`" plus anything Step 1 showed.
- U4: record "install.ps1 verified in pwsh/Linux container (Task 4); native Windows + Git Bash hook execution not yet verified — manual check: run install.ps1 on Windows, start `claude`, confirm the `<podium>` block appears (ask: 'what slots does podium list?')".

- [ ] **Step 4: Add README section**

Append to `README.md`:
````markdown
## Set up a new machine

Requirements: git, jq, Claude Code (logged in). Windows: Git for Windows (Git Bash) and PowerShell 7.

```bash
git clone <this-repo> ~/Workspace/claude-setup
~/Workspace/claude-setup/install.sh          # macOS / Linux
pwsh ~/Workspace/claude-setup/install.ps1    # Windows
```

The installer backs up anything it replaces to `~/.claude/backups/claude-setup-<timestamp>/` and is safe to re-run.
`settings.json` is copied, not linked: edit `dotfiles/settings.json` in the repo and re-run the installer to apply changes.

Synced: `CLAUDE.md`, `settings.json`, `statusline-command.sh`, `hooks/guard-destructive.sh`, `skills/capturing-personal-knowledge/`.
Never synced: history, projects, sessions, credentials, caches.
````

- [ ] **Step 5: Run all tests**

Run: `bash tests/run.sh`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add tests/install/fresh-machine.sh README.md docs/superpowers/specs/2026-10-11-podium-design.md
git commit -m "test(install): add fresh-machine check and record U2-U4 outcomes"
```

---

### Task 6: Apply on this machine + project binding check (needs user confirmation)

**Files:** none in the repo, unless outcomes need recording in the spec.

- [ ] **Step 1: Ask the user before running the installer on this machine**

It replaces `~/.claude/CLAUDE.md`, `statusline-command.sh`, `hooks/guard-destructive.sh` and the skill with symlinks, and overwrites `settings.json` with the repo copy (originals backed up). Proceed only on an explicit yes.

- [ ] **Step 2: Run it twice**

```bash
~/Workspace/claude-setup/install.sh
~/Workspace/claude-setup/install.sh | tail -n 1
```
Expected: second run `Summary: 0 changed`. Start a new `claude` session in any directory and confirm the `<podium>` block lists the four default agents.

- [ ] **Step 3: Project binding check (spec §9.5) — ask the user first**

This writes an untracked `.claude/team.json` into a work repo. With approval, in `~/Workspace/work/Agora`:
```bash
printf '{ "version": 1, "slots": { "critic": "plan-review" } }\n' > .claude/team.json
```
Start `claude` there; confirm the `<podium>` block shows `| critic | plan-review |` and no warnings. Then remove the file (`rm .claude/team.json`) unless the user wants to keep it. The `agora-ba` / `agora-ta` / `agora-senior-dev` agents are not on this machine; bind them on the machine where they exist.
