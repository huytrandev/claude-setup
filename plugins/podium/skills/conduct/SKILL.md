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

Dispatch the agent named for each slot in the `<podium>` block from session start, by `subagent_type`. If the block is missing: planner `podium:composer`, critic `podium:critic`, builder `podium:performer`, scout `podium:scout`, workspace root `$HOME/.agent-work` expanded to an absolute path.

Project agents bound to a slot do not know podium's contract, so **every dispatch prompt includes the Contract section verbatim**.

## Step 1 — Triage

Decide in this order and record the level with a one-line reason:

1. **complex** if any of: interface or contract change; several modules; open design choice; new subsystem; more than 5 files.
2. **trivial** if all of: a question or lookup, or a single-file change with an unambiguous fix; no design choice.
3. Otherwise **standard** (typically 2–5 files that need a short written plan).

| Level | Route |
|---|---|
| trivial | you, or scout in `lookup` mode; no workspace |
| standard | planner (`standard-plan`) → user approves → builder per task |
| complex | full flow |

Escalation is one-way. When any agent returns `ESCALATE`:
- from trivial: create the workspace (Step 2) and continue as standard with planner mode `standard-plan`;
- from standard: continue as complex with planner mode `spec`, passing every file already written as inputs;
- from complex: there is no higher level — treat it as `BLOCKED`.

Never downgrade.

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
Phase: <questions|spec-approval|planning|plan-review|plan-approval|building|diagnosing|final-review|blocked|done>
Active agent: <slot → agent, or none>
Next step: <one line>
Updated: <ISO 8601 timestamp>
```

File ownership — exactly one writer per file:

| File | Writer |
|---|---|
| `00-request.md`, `11-answers-N.md`, `status.md` | conductor |
| `10-questions-N.md` | whichever agent returned `NEEDS_INPUT` for round N |
| `20-spec.md`, `30-plan-vN.md`, `32-response-vN.md` | planner |
| `31-review-vN.md`, `50-final-review.md` | critic |
| `40-task-K-report.md` | builder |

Round numbers N are global per task folder: before every dispatch or resume, the next questions file is `10-questions-<highest existing N + 1>.md`.

## Step 3 — Route

**Trivial:** answer directly, or dispatch scout with one single-step instruction. No workspace.

**Standard:**
1. Dispatch planner, mode `standard-plan` → `30-plan-v1.md`.
2. Give the user the plan path and a three-line summary. Wait for approval.
3. For each task K in order: dispatch builder, mode `implement`, task K, input: the latest `30-plan-vN.md` → `40-task-K-report.md`.
4. Report results with the verification evidence from the task reports.

**Complex:**
1. Dispatch planner, mode `spec` → question rounds (see Relaying) → `20-spec.md`.
2. Ask the user to approve `20-spec.md`. Write any change request verbatim to the next `11-answers-N.md` and resume the planner (mode `spec`) until approved.
3. Resume planner, mode `plan`, with "spec approved" → `30-plan-v1.md`.
4. Dispatch a **fresh** critic, mode `plan-review`, on `30-plan-vN.md` → `31-review-vN.md`.
5. Resume planner, mode `revise` → `32-response-vN.md` + `30-plan-v(N+1).md`. If the review had any blocker, repeat steps 4–5 once more (max 2 critic rounds).
6. Give the user: final plan path, rejected findings with the planner's reasons, open disputes, and any blocker still open after round 2. Wait for approval.
7. Builder per task as in Standard step 3.
8. Dispatch a fresh critic, mode `final-review` → `50-final-review.md`. If it lists blockers or majors, give them to the user with the review path and ask whether to dispatch the builder to fix them. Report.

## Dispatch prompt template

Use these fields for every dispatch **and every resume** (`SendMessage`):

```
Podium task folder: <absolute path, or "none" for a trivial lookup>
Role: <planner|critic|builder|scout>
Mode: <mode>
Task: <for implement: "Task K"; otherwise omit>
Inputs: <file names to read>
Output: <file name(s) to write>
Questions file: <next 10-questions-N.md, or "none" for a trivial lookup>

<Contract, verbatim>
```

Output per mode:

| Role / mode | Output |
|---|---|
| planner `spec` | `20-spec.md` (or the questions file) |
| planner `plan`, `standard-plan` | `30-plan-v1.md` |
| planner `revise` | `32-response-vN.md`, `30-plan-v(N+1).md` |
| planner `diagnose` | `30-plan-v(N+1).md` |
| critic `plan-review` | `31-review-vN.md` |
| critic `final-review` | `50-final-review.md` |
| builder `implement` | `40-task-K-report.md` |
| scout `lookup` | none — reply inline |

## Contract

```
- Read inputs from the task folder. Write only the output file(s) named above, plus the questions file if you return NEEDS_INPUT.
- End your reply with exactly one line:
  STATUS: <DONE|NEEDS_INPUT|BLOCKED|ESCALATE> <relative/path/to/output.md>
  With no task folder or no output file, use "-" as the path.
- NEEDS_INPUT: write numbered questions (with options where possible) to the questions file named above and stop.
- ESCALATE: the work is harder than its triage level; explain why in your output file (or inline when there is none).
- BLOCKED: you cannot continue; explain why in your output file (or inline when there is none).
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
- Write the user's reply **verbatim** to the matching `11-answers-N.md`.
- Resume **the agent that asked** with `SendMessage`, using the dispatch fields (same Mode, Inputs plus `11-answers-N.md`, same Output).
- If that agent cannot be resumed (new session), dispatch a fresh agent of the same slot with every questions and answers file as inputs.

## Caps

- 5 question rounds; then tell the user the spec is not converging and ask how to proceed.
- 2 critic rounds per plan.
- A builder task fails verification when its report's `Verification` shows a failing `Done when` command, or the builder returns `BLOCKED`. After 2 failures for one task: dispatch planner, mode `diagnose`, with that task's reports → `30-plan-v(N+1).md`; then dispatch a fresh builder for the corrected task. If the planner returns `BLOCKED`, go to the user.

## Models

If a dispatch fails because its model is unavailable: tell the user. If the `<podium>` block names a fallback model, re-dispatch with that `model` override and say so. Never switch silently.

## Resuming

If the user refers to an earlier task, or a folder for this project has `status.md` with `Phase` other than `done`: read it, confirm with the user, and continue from `Next step` with fresh agents given the folder path.

## Finish

Set `Phase: done`. Tell the user what changed, the verification evidence, and the task folder path.
