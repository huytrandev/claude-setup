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
