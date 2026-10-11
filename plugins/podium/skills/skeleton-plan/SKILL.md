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
