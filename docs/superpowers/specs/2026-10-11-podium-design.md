# Podium — Multi-Agent Team & Portable Claude Code Setup

- **Date:** 2026-10-11
- **Status:** Draft — awaiting user review
- **Repo:** `~/Workspace/claude-setup`

## 1. Goals

1. **Portable setup.** On any machine (macOS, Linux, Windows), cloning one repo and running one install script reproduces the same Claude Code configuration.
2. **Model-pinned agent team.** Thinking, reviewing, implementing and scouting are done by dedicated subagents pinned to explicit model IDs (`claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`), independent of whichever model the user runs as the main session.
3. **Conductor is model-agnostic.** The main session only receives input, triages, routes, relays and summarizes. It does not do the planning itself, so the system behaves the same whether the conductor runs Opus, Sonnet or another model.
4. **Right-sized effort.** Requests are triaged; trivial work never spins up the full team.
5. **Project config wins.** A repo that defines its own agent team (e.g. Agora) can bind its agents to Podium's role slots; project settings take precedence over global ones.
6. **superpowers stays the process engine.** Podium reuses superpowers skills (brainstorming, writing-plans, test-driven-development, systematic-debugging, verification-before-completion) inside the agents instead of re-implementing them.

### Non-goals

- Re-implementing superpowers' subagent-driven-development.
- Syncing session data (`history.jsonl`, `projects/`, `sessions/`, `security/`) between machines.
- A UI or dashboard for `~/.agent-work`.
- Automatic cleanup of old workspaces (can be added later).

## 2. Verified platform facts

Checked on Claude Code 2.1.296 against code.claude.com docs (sub-agents, model-config, skills, memory, settings, permissions) and by direct test:

| Fact | Source |
|---|---|
| Subagents can spawn subagents, up to 3 levels below main by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`) | docs + live test (`NESTED_OK`) |
| Agent frontmatter `model:` accepts full IDs such as `claude-opus-5-5` | docs |
| Agent frontmatter `skills:` preloads skills (max 32) | docs |
| A finished subagent can be resumed with `SendMessage`, keeping its full history (not Explore/Plan) | docs |
| Agent precedence: managed > `--agents` > project `.claude/agents` > user `~/.claude/agents` > plugin | docs |
| Plugin agents/skills are namespaced `plugin:name` and never shadow bare names | docs |
| Skill precedence is **personal over project** | docs |
| User and project `CLAUDE.md` are concatenated; conflicts have **no** precedence | docs |
| Settings: project overrides user for scalar keys; list keys (e.g. `permissions.allow`) merge | docs |
| Plugin agents ignore frontmatter `hooks`, `mcpServers`, `permissionMode` | docs |
| superpowers `writing-plans` (6.4.1) requires full code in every code step ("No Placeholders") | read `SKILL.md` |

**Unverified — must be tested during implementation:**
- U1 (verified 2026-10-11, claude CLI on macOS): a project `.claude/settings.json` with `enabledPlugins: {"podium@claude-setup": false}` DOES override a user-scope enabled plugin. A headless session in that project listed no `podium:` subagents (NONE); a plain directory listed all four. `claude plugin list --json` from inside the project reports podium as `enabled: false`, `projectEnabled: false`. The `permissions.deny` fallback was not needed.
- U2 (verified 2026-10-11, claude CLI on macOS): user-level and project-level `PreToolUse` hooks both run. A project `.claude/settings.json` defining a `Bash` PreToolUse hook that touches a marker file was placed in a temp dir; a headless `claude -p` session there was asked to run a harmless echo of the guard's trigger string. The marker file was created (project hook ran) and the user-level guard still denied the command ("would wipe the whole filesystem"). So `hooks` merge across scopes rather than the project replacing the user's. `env` merge was not tested.
- U3 (resolved by design): not relied on; installer uses `claude plugin marketplace add` and `claude plugin install`. Verified in a clean ubuntu:24.04 container with the real CLI and no login: install.sh installed all marketplaces and plugins (Summary: 18 changed), and a second run reported `Summary: 0 changed` (`tests/install/fresh-machine.sh`, path with spaces included). Whether `enabledPlugins` alone auto-installs was not tested.
- U4 (partially verified): install.ps1 verified in a pwsh/Linux container (`tests/install/run-ps1-docker.sh`). Native Windows plus Git Bash hook execution is not yet verified. Manual check: run install.ps1 on Windows, start `claude`, confirm the `<podium>` block appears (ask: "what slots does podium list?").
- U5 (resolved): `claude plugin eval` runs `evals/**/case.yaml` (or prompt.md + graders/*.md) cases against a plugin with a no-plugin ablation arm and scored graders. Decision: keep S1-S3 as the bash smoke script for phase 1 because they assert on workspace files in a sandbox repo, which prompt graders do not cover as directly; revisit an eval suite for triage-quality regressions later.
- Weaker conductor (2026-10-11, `PODIUM_SMOKE_MODEL=<model> PODIUM_SMOKE=1 bash tests/smoke/run-smoke.sh`): conductor on default model 10/10, on `sonnet` 10/10 (S1 pass, S2 pass, S3 pass), on `haiku` 10/10 (S1 pass, S2 pass, S3 pass). One run per model; LLM behavior is nondeterministic, so this is a sample, not a guarantee.

## 3. Architecture

### 3.1 Role slots

| Slot | Default agent | Model | Responsibility |
|---|---|---|---|
| conductor | main session (any model) | — | Receive request, triage, route, relay questions/answers **verbatim**, update `status.md`, summarize results. Never plans or designs. |
| planner | `podium:composer` | `claude-opus-5-5` | Brainstorm, write spec and skeleton plan, revise after critique, diagnose escalated failures. May spawn `scout`. |
| critic | `podium:critic` | `claude-opus-5-5` | Review spec/plan in a fresh context against a rubric; final whole-diff review. Read-only. |
| builder | `podium:performer` | `claude-sonnet-5-5` | Implement one plan task at a time with TDD; write a task report. |
| scout | `podium:scout` | `claude-haiku-5-5` | Single-step lookups: find files, read KB, grep, very light edits. |

The critic is always a **new instance** with no planner history, so it does not defend the plan it is reviewing.

### 3.2 Configuration layers (highest priority first)

1. **Project `.claude/team.json`** — binds slots to project agents and may override the workspace path.
2. **Podium SessionStart hook** — reads `team.json`, validates it, injects the active team and the conductor protocol pointer into context.
3. **Podium plugin defaults** — `podium:*` agents and skills.
4. **Personal dotfiles** — `CLAUDE.md`, `settings.json`, guard hook, statusline. Contains **no** orchestration rules, avoiding the CLAUDE.md "no precedence" conflict with project instructions.

### 3.3 `team.json`

```json
{
  "version": 1,
  "slots": {
    "planner": "agora-ta",
    "critic": "plan-review",
    "builder": "agora-senior-dev",
    "scout": "podium:scout"
  },
  "workspace": null,
  "fallbackModel": null
}
```

- `version`: schema version, currently `1`; validated against `plugins/podium/schema/team.schema.json`.
- Every slot is optional; an unbound slot uses the Podium default.
- `workspace`: `null` → `~/.agent-work`; a string → that path (relative paths resolve from repo root).
- `fallbackModel`: `null` → no silent fallback; one of the Agent tool `model` aliases (`sonnet`, `opus`, `haiku`, `fable`) → used only when the pinned model is unavailable, and the conductor reports it. Agent frontmatter keeps full model IDs.
- A project that wants Podium fully off sets `"podium@<marketplace>": false` in `.claude/settings.json` (U1 verified), or denies `Agent(podium:*)`.

## 4. Triage

The conductor classifies every request with fixed criteria (cheap, works on weaker models):

| Level | Criteria (any one is enough to reach this level) | Flow |
|---|---|---|
| trivial | Question/lookup; single-file change with an unambiguous fix; no design choice | Conductor handles it or calls `scout`. No workspace folder. |
| standard | 2–5 files; no interface change; no open design choice | planner writes a short skeleton plan (no spec, no critic) → builder per task → verify. |
| complex | Interface/contract change; multiple modules; open design choice; new subsystem; >5 files | Full flow (§5). |

Escalation is one-way: any agent that finds the work harder than its level returns `ESCALATE`; the conductor re-triages upward. Nothing downgrades mid-task.

## 5. Data flow

### 5.1 Workspace layout

`<workspace>/<project-slug>/<YYYY-MM-DD-task-slug>/`, where `<workspace>` defaults to `~/.agent-work` (`$HOME` / `%USERPROFILE%`) and `<project-slug>` is the repo root directory name.

| File | Single writer | Content |
|---|---|---|
| `00-request.md` | conductor | User request verbatim, triage level with reason, active team mapping |
| `10-questions-N.md` | planner | Numbered questions for round N, with options where possible |
| `11-answers-N.md` | conductor | User answers verbatim |
| `20-spec.md` | planner | Spec (complex only) |
| `30-plan-vN.md` | planner | Skeleton plan version N |
| `31-review-vN.md` | critic | Findings tagged blocker / major / minor |
| `32-response-vN.md` | planner | Accept/reject per finding with reason |
| `40-task-K-report-aM.md` | builder | One report per attempt M (from 1): what changed, tests run and results, open issues |
| `50-final-review.md` | critic | Whole-diff review |
| `status.md` | conductor | Current phase, active agent, next step |

Agents receive the **folder path**, not pasted content. One writer per file prevents overwrites.

### 5.2 Return contract

Every agent ends its reply with exactly one line:

```
STATUS: <DONE|NEEDS_INPUT|BLOCKED|ESCALATE> <relative/path/to/output.md>
```

The conductor routes on this line alone, so it does not need to understand the content.

### 5.3 Complex flow

1. Conductor triages, writes `00-request.md`, dispatches planner with the folder path.
2. **Question loop:** planner writes `10-questions-N.md`, returns `NEEDS_INPUT`. Conductor shows the questions verbatim, writes `11-answers-N.md` verbatim, resumes planner via `SendMessage`. Planner batches independent questions to limit round-trips. Repeats until the spec is written.
3. Conductor asks the user to approve `20-spec.md`.
4. Planner writes `30-plan-v1.md`. Conductor dispatches a fresh critic → `31-review-v1.md`. Conductor resumes planner → `32-response-v1.md` + `30-plan-v2.md`. If blockers remain, one more round (max 2).
5. Conductor presents the final plan, rejected findings and open disputes for user approval.
6. Builder implements each task → `40-task-K-report-aM.md`. A task that fails verification is retried once with a fresh builder; after a second failure the planner diagnoses it (`superpowers:systematic-debugging`) and writes the full plan with the task replaced, and a fresh builder retries; a third failure goes to the user.
7. Fresh critic reviews the whole diff → `50-final-review.md`. Conductor summarizes.

Standard flow = steps 1, 4 (planner only, no critic), 6, verification; no spec.

## 6. Agent behavior

### 6.1 Conductor (`podium:conduct` skill)

- Injected by the SessionStart hook for every session.
- **Overrides superpowers in the main session:** the conductor does not run `brainstorming` or `writing-plans` itself; it delegates them to the planner slot and only relays their questions. (`using-superpowers` otherwise pushes the main session to brainstorm before acting.)
- Relays verbatim; never paraphrases questions or answers.
- Commit/push/destructive commands still require user confirmation (personal rules apply).

### 6.2 Planner (`podium:composer`)

- Frontmatter: `model: claude-opus-5-5`; `skills:` brainstorming, writing-plans, systematic-debugging, `podium:skeleton-plan`.
- Runs `superpowers:brainstorming`, but user dialogue goes through question files instead of direct chat.
- Runs `superpowers:writing-plans` under the skeleton override (§6.3).

### 6.3 Skeleton-plan override (`podium:skeleton-plan` skill)

| writing-plans element | Podium rule |
|---|---|
| Header, File Structure, task decomposition, Review Focus, Self-Review | Keep |
| `Consumes / Produces` with exact signatures | Keep — **mandatory** |
| Steps 1–5 with full test and implementation code | Drop. Replace with **Decisions**, **Test intent** (test names, behaviors asserted, edge cases), **Done when** |
| "No Placeholders — code blocks required" | Replace with the **skeleton rule**: signatures, types, interfaces, schemas and API contracts allowed; function bodies and test code forbidden |
| "REQUIRED SUB-SKILL: subagent-driven-development" | Replace: executed by the builder slot |

Boundary: anything that is a **decision** belongs in the plan; anything **mechanical** belongs to the builder.

Example task:

```markdown
### Task 3: Add retry to PaymentClient
Files: Modify `src/payment/client.ts` · Test `src/payment/client.test.ts`
Consumes: `RetryPolicy` (Task 1) — `{ maxAttempts: number; backoffMs: (n: number) => number }`
Produces: `PaymentClient.charge(req: ChargeRequest, policy?: RetryPolicy): Promise<ChargeResult>`
Decisions: retry only on 5xx/timeout, never on 4xx; idempotency key reused across attempts
Test intent: retries 5xx up to maxAttempts · no retry on 402 · same idempotency key on every attempt
Done when: 3 tests pass, typecheck clean
```

Trade-off accepted: superpowers requires full code because it assumes the executor lacks context and taste. Podium moves that work to Sonnet 5.5 and relies on the critic to ensure every decision is pinned in the plan.

### 6.4 Critic (`podium:critic`)

- `model: claude-opus-5-5`; tools: Read, Grep, Glob, Bash (read-only use).
- Plan rubric:
  - exact signatures on every cross-task interface;
  - test intent for every behavior in the spec;
  - no open decision the builder would have to guess;
  - no code bodies leaked into the plan;
  - project rules (`.claude/rules`, CLAUDE.md) respected;
  - placeholders and contradictions.
- Final review rubric: diff matches the plan, tests present and passing, no out-of-scope changes.

### 6.5 Builder (`podium:performer`)

- `model: claude-sonnet-5-5`; `skills:` test-driven-development, verification-before-completion.
- Implements exactly one task per dispatch. Returns `NEEDS_INPUT` for any undecided design choice instead of guessing. Never commits unless the plan says so and the user has approved.

### 6.6 Scout (`podium:scout`)

- `model: claude-haiku-5-5`; single-step tasks only (Haiku takes 2–3× more turns on multi-step work, which raises cost).

## 7. Packaging and install

### 7.1 Repo layout

```
claude-setup/
├── .claude-plugin/marketplace.json
├── plugins/podium/
│   ├── .claude-plugin/plugin.json
│   ├── agents/      composer.md · critic.md · performer.md · scout.md
│   ├── skills/      conduct/SKILL.md · skeleton-plan/SKILL.md
│   ├── hooks/       hooks.json · session-start.sh
│   └── schema/      team.schema.json
├── dotfiles/        CLAUDE.md · settings.json · hooks/guard-destructive.sh · statusline-command.sh
├── install.sh
├── install.ps1
├── tests/
└── docs/superpowers/specs/
```

### 7.2 Install script (`install.sh` / `install.ps1`)

1. Back up any existing target file to `~/.claude/backups/<timestamp>/`.
2. Link `dotfiles/*` into `~/.claude/` (symlink on macOS/Linux; copy on Windows).
3. `claude plugin marketplace add` for this repo and `claude-plugins-official`; `claude plugin install` for Podium and every plugin listed in `dotfiles/settings.json` `enabledPlugins`.
4. Create `~/.agent-work/`.
5. Idempotent: a second run makes no changes besides backups of files that differ.

Teammates who only want Podium run the two `claude plugin` commands; their personal config is untouched.

### 7.3 Model upgrades

Change `model:` in the four agent files, bump `plugin.json` version, run `claude plugin update`.

## 8. Error handling

| Situation | Behavior |
|---|---|
| Missing or malformed `STATUS:` line | Treat as `BLOCKED`; conductor reads the output file and reports to the user |
| Pinned model unavailable | Report clearly; use `fallbackModel` only if set; never silently switch |
| `team.json` invalid or binds a missing agent | SessionStart hook warns; affected slot falls back to the Podium default with a notice |
| Runaway loops | Caps: 5 question rounds, 2 critic rounds, 2 builder failures per task → planner; planner stuck → user |
| Session interrupted | Workspace files are the source of truth; a new session reads `status.md` and dispatches fresh agents with the folder path (`SendMessage` resume works only within one session) |
| Concurrent writes | Single-writer-per-file rule (§5.1) |

## 9. Testing

1. **Static:** frontmatter has required fields and valid model IDs; `team.json` fixtures validate against the schema.
2. **Hook:** `session-start.sh` against fixture dirs — no `team.json`, valid mapping, mapping to a missing agent, malformed JSON.
3. **Headless smoke:** `claude -p` in a sandbox repo with one trivial, one standard, one complex request; assert triage level, files created, `STATUS:` lines. Evaluate `claude plugin eval` (U5).
4. **Fresh machine:** run the installer under a second macOS user or a container; run it twice to confirm idempotency.
5. **Agora:** add `team.json` binding Agora agents; run one small ticket end to end.
6. **Unverified items U1–U4** each get an explicit test; results recorded in this spec.
