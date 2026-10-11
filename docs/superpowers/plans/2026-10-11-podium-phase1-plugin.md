# Podium Phase 1 — Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `podium` Claude Code plugin — four model-pinned agents, the `conduct` and `skeleton-plan` skills, a SessionStart hook that resolves the active team from `.claude/team.json` — served from a local marketplace in this repo.

**Architecture:** The repo root is a marketplace (`claude-setup`) containing one plugin at `plugins/podium/`. A pure-bash SessionStart hook (`hooks/session-start` + `hooks/lib/team.sh`, Windows-wrapped by `run-hook.cmd`) injects a `<podium>` context block naming the agent bound to each slot. Agents and skills are Markdown; behavior is verified by bash unit tests (hook), static checks (`claude plugin validate --strict` + frontmatter tests), and opt-in headless smoke tests (`claude -p --plugin-dir`).

**Tech Stack:** Bash 3.2+ (macOS default), Claude Code 2.1.296 plugin format, `jq` (tests only), `claude` CLI.

**Spec:** `docs/superpowers/specs/2026-10-11-podium-design.md`

## Global Constraints

- Model IDs, exactly: planner/critic `claude-opus-5-5`, builder `claude-sonnet-5-5`, scout `claude-haiku-5-5`.
- Slot names, exactly: `planner`, `critic`, `builder`, `scout`. Default agents: `podium:composer`, `podium:critic`, `podium:performer`, `podium:scout`.
- Marketplace name `claude-setup`; plugin name `podium`; install id `podium@claude-setup`.
- Default workspace root: `$HOME/.agent-work`.
- Return contract line, exactly: `STATUS: <DONE|NEEDS_INPUT|BLOCKED|ESCALATE> <relative/path/to/output.md>`.
- The hook must run with no dependencies beyond bash + coreutils (`sed`, `grep`); `jq`/`python3` are optional and only used for JSON syntax checking.
- All file content in English.
- Commits: per-task local commits only after the user has approved executing this plan with commits; never push.

## Review Focus

1. `team.json` present but minified onto one line → slot values still resolve correctly.
2. `team.json` binds a slot to an agent whose file exists but whose frontmatter `name:` differs from the filename → resolved by frontmatter name, not filename.
3. `team.json` with `"workspace": null` or the key absent → default `$HOME/.agent-work`, not an empty path.
4. Session started outside any git repo / with no `.claude/` dir → hook still emits valid JSON with defaults and exits 0.
5. Agent description or team value containing double quotes / backslashes / newlines → hook output is still valid JSON.

Each is pinned by a test in Task 3 or Task 4.

---

## File Structure

```
.claude-plugin/marketplace.json            marketplace manifest (repo root)
.gitignore
plugins/podium/
├── .claude-plugin/plugin.json             plugin manifest
├── hooks/
│   ├── hooks.json                         registers SessionStart
│   ├── run-hook.cmd                       Windows/Unix polyglot launcher
│   ├── session-start                      entry point (extensionless, see run-hook.cmd)
│   └── lib/team.sh                        pure functions: JSON helpers, slot resolution, context text
├── schema/team.schema.json                editor/documentation schema for team.json
├── skills/
│   ├── conduct/SKILL.md                   conductor protocol
│   └── skeleton-plan/SKILL.md             writing-plans override
└── agents/
    ├── composer.md                        planner (opus)
    ├── critic.md                          critic (opus)
    ├── performer.md                       builder (sonnet)
    └── scout.md                           scout (haiku)
tests/
├── run.sh                                 runs every tests/**/test-*.sh
├── lib/assert.sh                          assertion helpers
├── hook/test-team-lib.sh                  unit tests for lib/team.sh
├── hook/test-session-start.sh             end-to-end hook output tests
├── hook/fixtures/…                        fixture project + home dirs
├── static/test-manifests.sh               claude plugin validate --strict
├── static/test-agents.sh                  frontmatter checks
└── smoke/run-smoke.sh                     opt-in headless scenarios (PODIUM_SMOKE=1)
```

---

### Task 1: Marketplace + plugin skeleton + test harness

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/podium/.claude-plugin/plugin.json`
- Create: `.gitignore`
- Create: `tests/run.sh`, `tests/lib/assert.sh`
- Test: `tests/static/test-manifests.sh`

**Interfaces:**
- Produces: `tests/lib/assert.sh` functions `assert_eq <expected> <actual> <label>`, `assert_contains <haystack> <needle> <label>`, `assert_not_contains <haystack> <needle> <label>`, `assert_file <path> <label>`, `finish` (prints summary, exits 1 on any failure). `tests/run.sh` runs every `tests/**/test-*.sh` and exits non-zero if any fails.

- [ ] **Step 1: Write the test harness**

`tests/lib/assert.sh`:
```bash
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
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
# Runs every tests/**/test-*.sh and fails if any of them fails.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
status=0
while IFS= read -r t; do
  bash "$t" || status=1
done < <(find "$ROOT" -name 'test-*.sh' -type f | sort)
exit "$status"
```

- [ ] **Step 2: Write the failing manifest test**

`tests/static/test-manifests.sh`:
```bash
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
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/static/test-manifests.sh`
Expected: FAIL on both assertions (no manifests yet).

- [ ] **Step 4: Create the manifests and .gitignore**

`.claude-plugin/marketplace.json`:
```json
{
  "name": "claude-setup",
  "description": "Personal Claude Code setup: the podium multi-agent team plugin",
  "owner": { "name": "hyouwhy" },
  "plugins": [
    {
      "name": "podium",
      "description": "Model-pinned agent team (composer, critic, performer, scout) routed by a model-agnostic conductor",
      "version": "0.1.0",
      "source": "./plugins/podium"
    }
  ]
}
```

`plugins/podium/.claude-plugin/plugin.json`:
```json
{
  "name": "podium",
  "description": "Model-pinned agent team (composer, critic, performer, scout) routed by a model-agnostic conductor",
  "version": "0.1.0",
  "author": { "name": "hyouwhy" },
  "license": "MIT",
  "keywords": ["agents", "orchestration", "superpowers"]
}
```

`.gitignore`:
```
.DS_Store
tests/smoke/.sandbox/
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bash tests/static/test-manifests.sh`
Expected: `test-manifests.sh: 2 passed, 0 failed`. If `--strict` reports a missing recommended field (e.g. `homepage`), add it with a real value or drop the field the warning names — do not disable `--strict`.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin plugins/podium/.claude-plugin .gitignore tests/run.sh tests/lib tests/static/test-manifests.sh
git commit -m "feat(podium): add marketplace, plugin manifest and test harness"
```

---

### Task 2: team.json schema

**Files:**
- Create: `plugins/podium/schema/team.schema.json`
- Test: `tests/static/test-schema.sh`

**Interfaces:**
- Produces: schema `$id` `podium/team.schema.json`; keys `version` (const 1), `slots.{planner,critic,builder,scout}` (string), `workspace` (string|null), `fallbackModel` (string|null). Consumed by humans/editors only; the hook does not depend on it.

- [ ] **Step 1: Write the failing test**

`tests/static/test-schema.sh`:
```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/static/test-schema.sh`
Expected: FAIL (file missing).

- [ ] **Step 3: Create the schema**

`plugins/podium/schema/team.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "podium/team.schema.json",
  "title": "Podium team binding",
  "description": "Binds podium role slots to project agents. Place at <repo>/.claude/team.json.",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "version": { "const": 1 },
    "slots": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "planner": { "type": "string", "description": "Agent that brainstorms, writes spec and skeleton plan. Default podium:composer." },
        "critic": { "type": "string", "description": "Agent that reviews plans and final diffs in a fresh context. Default podium:critic." },
        "builder": { "type": "string", "description": "Agent that implements one plan task at a time. Default podium:performer." },
        "scout": { "type": "string", "description": "Agent for single-step lookups and light edits. Default podium:scout." }
      }
    },
    "workspace": { "type": ["string", "null"], "description": "Workspace root. null = $HOME/.agent-work. Relative paths resolve from the repo root." },
    "fallbackModel": { "type": ["string", "null"], "description": "Model ID used only when a pinned model is unavailable; the conductor reports the switch." }
  },
  "required": ["version"]
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/static/test-schema.sh`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/podium/schema tests/static/test-schema.sh
git commit -m "feat(podium): add team.json schema"
```

---

### Task 3: Team resolution library

**Files:**
- Create: `plugins/podium/hooks/lib/team.sh`
- Create fixtures under `tests/hook/fixtures/`
- Test: `tests/hook/test-team-lib.sh`

**Interfaces:**
- Consumes: agent filenames from Task 7 are not required — tests use fixture agents and a fixture plugin root.
- Produces (all in `lib/team.sh`, sourced, no side effects on load):
  - `PODIUM_SLOTS="planner critic builder scout"`
  - `podium_default_agent <slot>` → prints default agent, returns 1 for unknown slot
  - `podium_json_string <file> <key>` → prints first string value for `"key": "value"`, or nothing
  - `podium_json_valid <file>` → returns 0 valid, 1 invalid, 2 cannot check (no working jq/python3)
  - `podium_agent_exists <name> <project_dir> <plugin_root> <home>` → returns 0/1
  - `podium_workspace <team_file> <project_dir> <home>` → prints absolute workspace root
  - `podium_json_escape <string>` → prints JSON-escaped string (no surrounding quotes)
  - `podium_build_context <project_dir> <plugin_root> <home>` → prints the `<podium>…</podium>` block

- [ ] **Step 1: Create fixtures**

```bash
F=tests/hook/fixtures
mkdir -p $F/plugin/agents $F/home/.claude/agents \
  $F/proj-none \
  $F/proj-valid/.claude/agents \
  $F/proj-minified/.claude/agents \
  $F/proj-missing/.claude \
  $F/proj-invalid/.claude \
  $F/proj-workspace/.claude
for a in composer critic performer scout; do printf -- '---\nname: %s\n---\n' "$a" > $F/plugin/agents/$a.md; done
printf -- '---\nname: user-helper\n---\n' > $F/home/.claude/agents/helper.md
printf -- '---\nname: agora-ta\ndescription: x\n---\n' > $F/proj-valid/.claude/agents/ta.md
printf -- '---\nname: agora-ta\n---\n' > $F/proj-minified/.claude/agents/agora-ta.md
```

`tests/hook/fixtures/proj-valid/.claude/team.json`:
```json
{
  "version": 1,
  "slots": {
    "planner": "agora-ta",
    "scout": "user-helper"
  },
  "workspace": null
}
```

`tests/hook/fixtures/proj-minified/.claude/team.json`:
```json
{"version":1,"slots":{"planner":"agora-ta","critic":"podium:critic"},"fallbackModel":"claude-sonnet-5-5"}
```

`tests/hook/fixtures/proj-missing/.claude/team.json`:
```json
{ "version": 1, "slots": { "builder": "ghost-dev" } }
```

`tests/hook/fixtures/proj-invalid/.claude/team.json`:
```
{ "version": 1, "slots": { "planner": "agora-ta", }
```

`tests/hook/fixtures/proj-workspace/.claude/team.json`:
```json
{ "version": 1, "workspace": ".agent-work" }
```

- [ ] **Step 2: Write the failing tests**

`tests/hook/test-team-lib.sh`:
```bash
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
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash tests/hook/test-team-lib.sh`
Expected: FAIL — `team.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/team.sh`**

`plugins/podium/hooks/lib/team.sh`:
```bash
# Team resolution for the podium SessionStart hook.
# Pure bash + sed/grep; jq or python3 are used only to syntax-check team.json when present.

PODIUM_SLOTS="planner critic builder scout"

podium_default_agent() {
  case "$1" in
    planner) echo "podium:composer" ;;
    critic) echo "podium:critic" ;;
    builder) echo "podium:performer" ;;
    scout) echo "podium:scout" ;;
    *) return 1 ;;
  esac
}

# Prints the first string value of "key": "value" in file. Keys in team.json are unique,
# so flat extraction is enough; null and absent keys print nothing.
podium_json_string() {
  [ -f "$1" ] || return 0
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

# 0 = valid, 1 = invalid, 2 = no working checker.
podium_json_valid() {
  if command -v jq >/dev/null 2>&1; then
    jq empty "$1" >/dev/null 2>&1 && return 0 || return 1
  fi
  # On Windows python3 may be a Store stub that exits non-zero; probe before trusting it.
  if command -v python3 >/dev/null 2>&1 && python3 -c 'pass' >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1 && return 0 || return 1
  fi
  return 2
}

podium_agent_exists() {
  local name="$1" project_dir="$2" plugin_root="$3" home="$4" dir f
  case "$name" in
    podium:*) [ -f "${plugin_root}/agents/${name#podium:}.md" ]; return $? ;;
    *:*) return 0 ;;  # another plugin's agent: cannot be checked cheaply, trust the binding
  esac
  for dir in "${project_dir}/.claude/agents" "${home}/.claude/agents"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      grep -q -E "^name:[[:space:]]*${name}[[:space:]]*$" "$f" && return 0
    done
  done
  return 1
}

podium_workspace() {
  local team_file="$1" project_dir="$2" home="$3" ws
  ws="$(podium_json_string "$team_file" workspace)"
  if [ -z "$ws" ]; then echo "${home}/.agent-work"; return 0; fi
  case "$ws" in
    "~"*) echo "${home}${ws#\~}" ;;
    /*|[A-Za-z]:*) echo "$ws" ;;
    *) echo "${project_dir}/${ws}" ;;
  esac
}

podium_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

podium_build_context() {
  local project_dir="$1" plugin_root="$2" home="$3"
  local team_file="${project_dir}/.claude/team.json"
  local source="podium defaults" use_team=0 warnings="" rows="" rc slot agent bound fallback
  if [ -f "$team_file" ]; then
    rc=0; podium_json_valid "$team_file" || rc=$?
    case "$rc" in
      0) use_team=1; source=".claude/team.json" ;;
      2) use_team=1; source=".claude/team.json (syntax not checked: no jq or python3)" ;;
      *) warnings="${warnings}- .claude/team.json is not valid JSON; using podium defaults for every slot."$'\n' ;;
    esac
  fi
  for slot in $PODIUM_SLOTS; do
    agent="$(podium_default_agent "$slot")"
    if [ "$use_team" = 1 ]; then
      bound="$(podium_json_string "$team_file" "$slot")"
      if [ -n "$bound" ]; then
        if podium_agent_exists "$bound" "$project_dir" "$plugin_root" "$home"; then
          agent="$bound"
        else
          warnings="${warnings}- Slot '${slot}' binds missing agent '${bound}'; falling back to ${agent}."$'\n'
        fi
      fi
    fi
    rows="${rows}| ${slot} | ${agent} |"$'\n'
  done
  fallback=""
  [ "$use_team" = 1 ] && fallback="$(podium_json_string "$team_file" fallbackModel)"
  [ -n "$warnings" ] || warnings="none"$'\n'
  case "$warnings" in none*) warnings="Warnings: none" ;; *) warnings="Warnings:"$'\n'"${warnings%$'\n'}" ;; esac
  printf '%s\n' "<podium>
Podium is active and you are the CONDUCTOR. Before handling any user request, invoke the \`podium:conduct\` skill and follow it. It overrides superpowers' instruction to brainstorm or write plans in the main session: that work is delegated to the planner slot below.

Team source: ${source}
| slot | agent |
|---|---|
${rows%$'\n'}
Workspace root: $(podium_workspace "$team_file" "$project_dir" "$home")
Fallback model: ${fallback:-none}
${warnings}
</podium>"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash tests/hook/test-team-lib.sh`
Expected: `test-team-lib.sh: 36 passed, 0 failed` (count may differ by ±1 if you split an assertion; zero failures is the requirement).

- [ ] **Step 6: Commit**

```bash
git add plugins/podium/hooks/lib tests/hook
git commit -m "feat(podium): add team resolution library for SessionStart hook"
```

---

### Task 4: SessionStart hook entry point + Windows wrapper

**Files:**
- Create: `plugins/podium/hooks/session-start` (executable, extensionless)
- Create: `plugins/podium/hooks/run-hook.cmd` (executable)
- Create: `plugins/podium/hooks/hooks.json`
- Test: `tests/hook/test-session-start.sh`

**Interfaces:**
- Consumes: `podium_build_context`, `podium_json_escape` from Task 3.
- Produces: stdout JSON `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<podium block>"}}`; exit 0 always. Reads `CLAUDE_PROJECT_DIR` (fallback `$PWD`) and `HOME`.

- [ ] **Step 1: Write the failing test**

`tests/hook/test-session-start.sh`:
```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/hook/test-session-start.sh`
Expected: FAIL (hook files missing).

- [ ] **Step 3: Implement the hook files**

`plugins/podium/hooks/session-start`:
```bash
#!/usr/bin/env bash
# SessionStart hook for podium: resolves the active team and injects the <podium> block.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/team.sh
. "${SCRIPT_DIR}/lib/team.sh"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
context="$(podium_build_context "$project_dir" "$PLUGIN_ROOT" "$HOME")"
# printf instead of a heredoc: bash 5.3 heredoc hang (obra/superpowers#571).
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$(podium_json_escape "$context")"
exit 0
```

`plugins/podium/hooks/run-hook.cmd` — Windows/Unix polyglot, adapted from superpowers (MIT):
```
: << 'CMDBLOCK'
@echo off
REM Polyglot launcher: cmd.exe runs this batch part and finds bash; Unix shells skip it.
REM Hook scripts are extensionless so Claude Code's Windows ".sh -> bash" rewrite does not apply.
if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)
set "HOOK_DIR=%~dp0"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
REM No bash: exit quietly. Podium agents still load; only the <podium> block is missing.
exit /b 0
CMDBLOCK

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

`plugins/podium/hooks/hooks.json`:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

Then: `chmod +x plugins/podium/hooks/session-start plugins/podium/hooks/run-hook.cmd`

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/hook/test-session-start.sh && bash tests/run.sh`
Expected: `test-session-start.sh: 8 passed, 0 failed`; `tests/run.sh` exits 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/podium/hooks tests/hook/test-session-start.sh
git commit -m "feat(podium): add SessionStart hook with Windows launcher"
```

---

### Task 5: `skeleton-plan` skill

**Files:**
- Create: `plugins/podium/skills/skeleton-plan/SKILL.md`
- Test: covered by `tests/static/test-manifests.sh` (strict validation of skills) and smoke scenario S2 (Task 8)

**Interfaces:**
- Produces: skill `podium:skeleton-plan`, preloaded by `podium:composer` (Task 7). Defines the task template fields `Files`, `Consumes`, `Produces`, `Decisions`, `Test intent`, `Done when` that `podium:critic` checks.

- [ ] **Step 1: Write the skill**

`plugins/podium/skills/skeleton-plan/SKILL.md`:
````markdown
---
name: skeleton-plan
description: Use when writing an implementation plan as the podium planner - overrides superpowers:writing-plans so the plan pins every decision and interface but leaves function bodies and test code to the builder.
---

# Skeleton Plan

Run `superpowers:writing-plans` with the overrides below. Where this skill and writing-plans disagree, this skill wins.

## Overrides

| writing-plans element | Podium rule |
|---|---|
| Save location `docs/superpowers/plans/…` | Save to the podium task folder as `30-plan-vN.md` (the conductor gives the path) |
| Header "REQUIRED SUB-SKILL: subagent-driven-development / executing-plans" | Replace with: `> Executed by the podium builder slot, one task per dispatch.` |
| Goal, Architecture, Tech Stack, Spec, Global Constraints, Review Focus | Keep |
| File Structure, task right-sizing | Keep |
| `Interfaces: Consumes / Produces` | Keep — **mandatory on every task**, with exact signatures and types |
| Steps 1–5 with full test code and full implementation code | Drop. Use the task template below |
| "No Placeholders — code blocks required for code steps" | Replaced by the skeleton rule below. The other No-Placeholders items still apply |
| Self-Review | Keep, plus the skeleton checks below |
| Execution Handoff | Drop. Return to the conductor with the STATUS line |

## Skeleton rule

Allowed in the plan: signatures, types, interfaces, schemas, API contracts, file paths, command lines, config keys and values.
Forbidden in the plan: function bodies, test bodies, full file contents of source code.

**Boundary:** anything that is a *decision* belongs in the plan. Anything *mechanical* belongs to the builder. If a reasonable builder could implement it two materially different ways, it is a decision — pin it.

## Task template

```markdown
### Task N: <component>
Files: Create `path` · Modify `path` · Test `path`
Consumes: <exact signatures from earlier tasks, or "none">
Produces: <exact signatures later tasks rely on>
Decisions: <every choice the builder must not make alone; "none" only if truly none>
Test intent: <test name — behavior asserted> · <edge case — expected behavior> · …
Done when: <commands that must pass, e.g. "npm test -- payment passes, tsc --noEmit clean">
```

## Extra self-review checks

1. Every cross-task name in `Consumes` matches a `Produces` exactly (name, parameters, types).
2. Every behavior in the spec has at least one `Test intent` entry.
3. No task leaves an open decision the builder would have to guess.
4. No function or test bodies leaked in.
5. `Done when` is a runnable command, not "works correctly".
````

- [ ] **Step 2: Validate**

Run: `claude plugin validate --strict plugins/podium`
Expected: exit 0, no warnings for `skills/skeleton-plan`.

- [ ] **Step 3: Commit**

```bash
git add plugins/podium/skills/skeleton-plan
git commit -m "feat(podium): add skeleton-plan skill overriding writing-plans"
```

---

### Task 6: `conduct` skill

**Files:**
- Create: `plugins/podium/skills/conduct/SKILL.md`
- Test: `claude plugin validate --strict`; behavior in smoke scenarios S1–S3 (Task 8)

**Interfaces:**
- Consumes: the `<podium>` block format from Task 3 (`| slot | agent |` rows, `Workspace root:`, `Fallback model:`).
- Produces: the dispatch prompt template and the Contract text every agent (Task 7) obeys; workspace file names from spec §5.1.

- [ ] **Step 1: Write the skill**

`plugins/podium/skills/conduct/SKILL.md`:
````markdown
---
name: conduct
description: Use at the start of every session where podium is active and before handling any user request - defines how the main session triages requests, routes work to the podium team slots, relays questions verbatim, and tracks task state in the workspace.
---

# Conduct

You are the conductor. You receive the request, triage it, route it, relay questions and answers verbatim, and report results. For standard and complex work you do not plan, design, or write implementation code yourself — whatever model you run on.

## Overrides

| Instruction from elsewhere | Podium rule |
|---|---|
| superpowers `using-superpowers`: brainstorm before creative work | In the main session, do NOT run `brainstorming`, `writing-plans`, `executing-plans` or `subagent-driven-development`. Dispatch the planner slot; it runs them. |
| superpowers `brainstorming`: one question per message to the user | The planner writes question files; you relay them verbatim. |

Personal rules (confirm before commit, push, destructive commands) still apply.

## Slots

Dispatch the agent named for each slot in the `<podium>` block from session start, by `subagent_type`. If the block is missing: planner `podium:composer`, critic `podium:critic`, builder `podium:performer`, scout `podium:scout`, workspace root `~/.agent-work`.

Project agents bound to a slot do not know podium's contract, so **every dispatch prompt includes the Contract section verbatim**.

## Step 1 — Triage

Pick the highest level whose criteria match. Record the level and a one-line reason.

| Level | Any one of these | Route |
|---|---|---|
| trivial | question or lookup; single-file change with an unambiguous fix; no design choice | you, or scout; no workspace |
| standard | 2–5 files; no interface change; no open design choice | planner (standard-plan) → user approves → builder per task |
| complex | interface or contract change; several modules; open design choice; new subsystem; more than 5 files | full flow |

Escalation is one-way: when any agent returns `ESCALATE`, move up one level and continue from the planner using the files already written. Never downgrade.

## Step 2 — Workspace (standard and complex)

Folder: `<workspace root>/<project-slug>/<YYYY-MM-DD>-<task-slug>/`
- project-slug: repo root directory name, lowercase, spaces → `-`
- task-slug: 3–5 word kebab-case summary

Write `00-request.md`:
```markdown
# Request
<user message, verbatim>

## Triage
Level: <standard|complex> — <reason>

## Team
<the slot table from the <podium> block>
```

Write `status.md`, and rewrite it after every dispatch returns:
```markdown
# Status
Phase: <triage|questions|spec-review|planning|plan-review|plan-approval|building|final-review|done>
Active agent: <slot → agent, or none>
Next step: <one line>
Updated: <ISO 8601 timestamp>
```

File ownership — exactly one writer per file:

| File | Writer |
|---|---|
| `00-request.md`, `11-answers-N.md`, `status.md` | conductor |
| `10-questions-N.md`, `20-spec.md`, `30-plan-vN.md`, `32-response-vN.md` | planner |
| `31-review-vN.md`, `50-final-review.md` | critic |
| `40-task-K-report.md` | builder |

## Step 3 — Route

**Trivial:** answer directly, or dispatch scout with one single-step instruction. No workspace.

**Standard:**
1. Dispatch planner, mode `standard-plan` → `30-plan-v1.md`.
2. Give the user the plan path and a three-line summary. Wait for approval.
3. For each task K in order: dispatch builder, mode `implement`, task K → `40-task-K-report.md`.
4. Report results with the verification evidence from the task reports.

**Complex:**
1. Dispatch planner, mode `spec` → question rounds (see Relaying) → `20-spec.md`.
2. Ask the user to approve `20-spec.md`. Relay change requests to the planner (resume) until approved.
3. Resume planner with "spec approved", mode `plan` → `30-plan-v1.md`.
4. Dispatch a **fresh** critic, mode `plan-review`, on `30-plan-vN.md` → `31-review-vN.md`.
5. Resume planner, mode `revise` → `32-response-vN.md` + `30-plan-v(N+1).md`. If the review had any blocker, repeat steps 4–5 once more (max 2 critic rounds).
6. Give the user: final plan path, rejected findings with the planner's reasons, open disputes. Wait for approval.
7. Builder per task as in Standard step 3.
8. Dispatch a fresh critic, mode `final-review` → `50-final-review.md`. Report.

## Dispatch prompt template

```
Podium task folder: <absolute path>
Role: <planner|critic|builder|scout>
Mode: <spec|plan|standard-plan|revise|diagnose|plan-review|final-review|implement|lookup>
Task: <for implement: "Task K" from the plan; otherwise omit>
Inputs: <file names to read>
Output: <file name(s) to write>

<Contract, verbatim>
```

## Contract

```
- Read inputs from the task folder. Write only the output file(s) named above.
- End your reply with exactly one line:
  STATUS: <DONE|NEEDS_INPUT|BLOCKED|ESCALATE> <relative/path/to/output.md>
- NEEDS_INPUT: write numbered questions (with options where possible) to the next 10-questions-N.md and stop.
- ESCALATE: the work is harder than its triage level; explain why in your output file.
- BLOCKED: you cannot continue; explain why in your output file.
```

## Handling STATUS

| Result | Action |
|---|---|
| `DONE` | Update status.md; next step of the route |
| `NEEDS_INPUT` | Relay the questions file |
| `BLOCKED` | Read the output file; tell the user what is blocking and what you need |
| `ESCALATE` | Re-triage one level up; continue from the planner |
| missing or malformed STATUS line | Treat as `BLOCKED` |

## Relaying

- Show the questions file to the user **verbatim** — no paraphrase, no reordering, no added options.
- Write the user's reply **verbatim** to `11-answers-N.md`.
- Resume the same planner with `SendMessage`: "Answers are in 11-answers-N.md."
- If the planner cannot be resumed (new session), dispatch a fresh planner with every questions and answers file as inputs.

## Caps

- 5 question rounds; then tell the user the spec is not converging and ask how to proceed.
- 2 critic rounds per plan.
- 2 failed verifications for one builder task → dispatch planner, mode `diagnose`, with the task reports. If the planner returns BLOCKED, go to the user.

## Models

If a dispatch fails because its model is unavailable: tell the user. If the `<podium>` block names a fallback model, re-dispatch with that `model` override and say so. Never switch silently.

## Resuming

If the user refers to an earlier task, or a folder for this project has `status.md` with `Phase` other than `done`: read it, confirm with the user, and continue from `Next step` with fresh agents given the folder path.

## Finish

Set `Phase: done`. Tell the user what changed, the verification evidence, and the task folder path.
````

- [ ] **Step 2: Validate**

Run: `claude plugin validate --strict plugins/podium`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add plugins/podium/skills/conduct
git commit -m "feat(podium): add conduct skill for the conductor protocol"
```

---

### Task 7: Agents

**Files:**
- Create: `plugins/podium/agents/composer.md`, `critic.md`, `performer.md`, `scout.md`
- Test: `tests/static/test-agents.sh`

**Interfaces:**
- Consumes: Contract and modes from Task 6; skeleton template from Task 5.
- Produces: agents `podium:composer`, `podium:critic`, `podium:performer`, `podium:scout` with the Global Constraints model IDs.

- [ ] **Step 1: Write the failing test**

`tests/static/test-agents.sh`:
```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/static/test-agents.sh`
Expected: FAIL (`composer exists` etc.).

- [ ] **Step 3: Write the agents**

`plugins/podium/agents/composer.md`:
```markdown
---
name: composer
description: Podium planner slot. Use when the podium conductor dispatches planning work - brainstorming a spec through question files, writing a skeleton implementation plan, revising a plan after critique, or diagnosing a failed task. Writes only to the podium task folder.
model: claude-opus-5-5
skills:
  - superpowers:brainstorming
  - superpowers:writing-plans
  - superpowers:systematic-debugging
  - podium:skeleton-plan
---

You are the podium composer: the team's planner. The conductor dispatches you with a task folder, a mode, inputs and outputs, and the podium Contract. Follow the Contract exactly.

You never talk to the user directly. Every question goes into a questions file and you stop with `STATUS: NEEDS_INPUT`. The conductor relays the user's answers verbatim and resumes you.

## Modes

**spec** — Run `superpowers:brainstorming` for `00-request.md`, with these changes:
- Questions go to `10-questions-N.md` (N = next round number). Batch every question that does not depend on another question's answer; number them; offer options and mark your recommendation.
- Spec goes to `20-spec.md` in the task folder, not `docs/superpowers/specs/`. Do not commit it.
- After writing the spec, stop with `STATUS: DONE 20-spec.md`. Do not invoke writing-plans until the conductor resumes you with "spec approved".

**plan** — Run `superpowers:writing-plans` on `20-spec.md` under `podium:skeleton-plan`. Output `30-plan-v1.md`.

**standard-plan** — No spec. Write a short skeleton plan straight from `00-request.md` (and any answers files) under `podium:skeleton-plan`. Output `30-plan-v1.md`. If you find an interface change, an open design choice, or more than 5 files, stop with `STATUS: ESCALATE`.

**revise** — Read `31-review-vN.md`. Write `32-response-vN.md` with one line per finding: `<id> ACCEPT|REJECT — <reason>`. Write `30-plan-v(N+1).md` with accepted findings applied. Reject only with a concrete reason.

**diagnose** — Run `superpowers:systematic-debugging` on the failing task using its `40-task-K-report.md` files. Write the root cause and a corrected task to `30-plan-v(N+1).md`. If you cannot find the root cause, stop with `STATUS: BLOCKED`.

## Rules

- For file lookups, dispatch the scout slot named in `00-request.md` with one single-step instruction rather than reading widely yourself.
- Never write product code or edit files outside the task folder.
- Respect project rules in `CLAUDE.md` and `.claude/rules/`.

End every reply with the STATUS line.
```

`plugins/podium/agents/critic.md`:
```markdown
---
name: critic
description: Podium critic slot. Use when the podium conductor needs an independent fresh-context review of a skeleton plan or of the final diff. Reads the repo, writes only its review file in the podium task folder.
model: claude-opus-5-5
tools: Read, Grep, Glob, Bash, Write
---

You are the podium critic. You have no history with the plan you review; judge it only against its spec, the request and the repo. Follow the podium Contract in your dispatch prompt.

Use Bash only for read-only commands (git diff, git log, test runs). Write only your review file.

## Findings format

```
## <ID> [blocker|major|minor] <one-line title>
Where: <file / plan task / line>
Problem: <what is wrong, with evidence>
Fix: <the concrete change you expect>
```
IDs: `P1, P2…` for plan reviews, `F1, F2…` for final reviews. End the file with `Verdict: APPROVE` (no blockers or majors) or `Verdict: REVISE`.

- blocker: the plan cannot be executed correctly as written.
- major: it can be executed but will likely produce a wrong or incomplete result.
- minor: clarity or style.

## Mode plan-review → `31-review-vN.md`

Check:
1. Every cross-task interface has an exact signature, and each `Consumes` matches a `Produces`.
2. Every behavior in `20-spec.md` (or `00-request.md` for standard work) has a `Test intent` entry.
3. No open decision is left for the builder to guess.
4. No function or test bodies leaked into the plan.
5. Project rules (`CLAUDE.md`, `.claude/rules/`) are respected.
6. No placeholders, no contradictions, `Done when` is runnable.

## Mode final-review → `50-final-review.md`

Review the diff of the work (`git diff` against the base named in your dispatch, or the uncommitted diff):
1. Each plan task is implemented as specified; nothing out of scope.
2. Tests exist for each `Test intent` and the task reports show them passing.
3. Bugs, security issues, or project-rule violations in the changed code.

End every reply with the STATUS line: `STATUS: DONE <review file>`, or `STATUS: BLOCKED <review file>` if you could not review.
```

`plugins/podium/agents/performer.md`:
```markdown
---
name: performer
description: Podium builder slot. Use when the podium conductor dispatches one task of a skeleton plan for implementation - writes tests and code with TDD and reports evidence to the podium task folder.
model: claude-sonnet-5-5
skills:
  - superpowers:test-driven-development
  - superpowers:verification-before-completion
---

You are the podium performer: the team's builder. You implement exactly one plan task per dispatch. Follow the podium Contract in your dispatch prompt.

1. Read the plan file and your task. Read `Consumes`, `Produces`, `Decisions`, `Test intent`, `Done when`.
2. Implement with `superpowers:test-driven-development`: one failing test per `Test intent` entry, then the code that passes it.
3. Run every `Done when` command and capture its result.
4. Write `40-task-K-report.md`:
   ```
   # Task K report
   Changed: <file list>
   Tests: <test names>
   Verification: <each Done-when command → result, pasted>
   Deviations: <none | what differs from the plan and why>
   Open issues: <none | list>
   ```

Rules:
- If the plan leaves a design choice open, do not guess: write the question to the next `10-questions-N.md` and stop with `STATUS: NEEDS_INPUT`.
- If the task is bigger than the plan says (new interface, extra modules), stop with `STATUS: ESCALATE`.
- Implement `Produces` signatures exactly; do not rename.
- Do not commit unless the dispatch prompt says commits are approved. Never push.

End every reply with the STATUS line.
```

`plugins/podium/agents/scout.md`:
```markdown
---
name: scout
description: Podium scout slot. Use for single-step lookups - find files, grep for symbols, read a knowledge-base file and quote the relevant part, or make one small mechanical edit. Not for multi-step work.
model: claude-haiku-5-5
tools: Read, Grep, Glob, Bash, Edit, Write
---

You are the podium scout. Do one thing and report it. Follow the podium Contract in your dispatch prompt.

- Lookups: return paths with line numbers and short quotes. Do not summarize beyond what was asked.
- Edits: only the single mechanical edit requested. No refactoring.
- If the request needs more than a few steps or any judgment call, stop with `STATUS: ESCALATE` and say why.
- For a lookup with no output file, end with `STATUS: DONE -`.

End every reply with the STATUS line.
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/static/test-agents.sh && claude plugin validate --strict plugins/podium`
Expected: `test-agents.sh: 23 passed, 0 failed`; validate exits 0. If validate rejects the `skills:` list format, use the format it names and re-run `test-agents.sh`.

- [ ] **Step 5: Verify agents load with pinned models**

Run: `claude --plugin-dir plugins/podium agents 2>&1 | grep -i podium`
Expected: four `podium:` agents listed. If `claude agents` ignores `--plugin-dir`, run it after Task 9's local install instead and note that here.

- [ ] **Step 6: Commit**

```bash
git add plugins/podium/agents tests/static/test-agents.sh
git commit -m "feat(podium): add composer, critic, performer and scout agents"
```

---

### Task 8: Headless smoke scenarios (opt-in)

**Files:**
- Create: `tests/smoke/run-smoke.sh`
- Modify: `docs/superpowers/specs/2026-10-11-podium-design.md` (§2 unverified list: record U5 outcome)

**Interfaces:**
- Consumes: the whole plugin via `--plugin-dir`; `team.json` `workspace` override (relative path) so smoke runs never write to the real `~/.agent-work`.
- Produces: `PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh` → exit 0 when S1–S3 pass. Not named `test-*.sh`, so `tests/run.sh` never spends model tokens.

- [ ] **Step 1: Write the smoke script**

`tests/smoke/run-smoke.sh`:
```bash
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

ask() { (cd "$SB" && claude -p --plugin-dir "$REPO/plugins/podium" --permission-mode acceptEdits --output-format json "$1"); }
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
```

- [ ] **Step 2: Run it**

Run: `PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh`
Expected: `run-smoke.sh: 10 passed, 0 failed`.
If a scenario fails, use `superpowers:systematic-debugging`: read the JSON transcript in `$out` and the files in `.sandbox/.agent-work`, find which instruction the conductor or agent ignored, fix the wording in the skill/agent that owns it, re-run. Record each wording change in the commit message.

- [ ] **Step 3: Evaluate `claude plugin eval` (U5)**

Run: `claude plugin eval --help`
Decide whether S1–S3 should move to an eval suite (`evals/`). Record the decision and one-line reason under U5 in spec §2, replacing "must be tested" for U5 with the outcome.

- [ ] **Step 4: Commit**

```bash
git add tests/smoke/run-smoke.sh docs/superpowers/specs/2026-10-11-podium-design.md
git commit -m "test(podium): add opt-in headless smoke scenarios"
```

---

### Task 9: Local install + project-precedence checks (U1)

**Files:**
- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-10-11-podium-design.md` (§2: record U1 outcome)

**Interfaces:**
- Consumes: marketplace from Task 1.
- Produces: `podium@claude-setup` installed at user scope on this machine; README documents install and `team.json`.

- [ ] **Step 1: Install from the local marketplace**

```bash
claude plugin marketplace add ~/Workspace/claude-setup
claude plugin install podium@claude-setup
claude plugin list | grep podium
```
Expected: `podium@claude-setup` listed as enabled.

- [ ] **Step 2: Check U1 — can a project disable a user-enabled plugin?**

```bash
T="$(mktemp -d)"; mkdir -p "$T/.claude"
printf '{ "enabledPlugins": { "podium@claude-setup": false } }\n' > "$T/.claude/settings.json"
(cd "$T" && claude agents 2>&1 | grep -c 'podium:')
(cd /tmp && claude agents 2>&1 | grep -c 'podium:')
rm -rf "$T"
```
Expected: first count `0` if project override works, second count `4`. Record the result under U1 in spec §2. If the first count is not 0, document `permissions.deny: ["Agent(podium:*)"]` as the supported opt-out instead and verify it the same way.

- [ ] **Step 3: Write README.md**

````markdown
# claude-setup

Personal Claude Code setup. Contains the **podium** plugin: a model-pinned agent team routed by a model-agnostic conductor.

## Install podium only

```bash
claude plugin marketplace add <path-or-git-url-of-this-repo>
claude plugin install podium@claude-setup
```

## Team

| Slot | Default agent | Model |
|---|---|---|
| planner | `podium:composer` | `claude-opus-5-5` |
| critic | `podium:critic` | `claude-opus-5-5` |
| builder | `podium:performer` | `claude-sonnet-5-5` |
| scout | `podium:scout` | `claude-haiku-5-5` |

## Bind project agents

Create `<repo>/.claude/team.json` (schema: `plugins/podium/schema/team.schema.json`):

```json
{
  "version": 1,
  "slots": { "planner": "my-architect", "builder": "my-senior-dev" },
  "workspace": null,
  "fallbackModel": null
}
```

Unbound slots use the defaults. The SessionStart hook warns about bindings to agents that do not exist.

## Workspace

Task files live in `~/.agent-work/<project>/<date-task>/` unless `workspace` is set.

## Tests

```bash
bash tests/run.sh                              # unit + static
PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh   # headless, costs tokens
```

## Requirements

bash (Git Bash on Windows) for the SessionStart hook. `jq` for running the tests.
````

Add the U1 outcome as one line under "Bind project agents" (how to turn podium off for a project).

- [ ] **Step 4: Run all tests**

Run: `bash tests/run.sh`
Expected: exit 0, every file reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-11-podium-design.md
git commit -m "docs: add README and record project opt-out behavior"
```
