---
name: capturing-personal-knowledge
description: Use when the user — outside a specific project repo — reveals a durable, non-obvious preference, tool choice, or workflow convention worth remembering across future sessions, or explicitly asks you to remember something about them. Not for repo-specific knowledge, one-off details, or facts Claude can infer or detect at runtime.
---

# Capturing Personal Knowledge

## Overview

Persist durable, non-inferable facts about THIS user so future sessions get more
tailored — while keeping always-loaded context small.

`~/.claude/CLAUDE.md` is loaded IN FULL into every session, so every line costs
tokens on every turn (`@import`ed files are inlined too — imports do NOT save
tokens). Real savings come only from content read on-demand. So: keep a tiny
always-on core in CLAUDE.md; push bulky or situational detail into separate files
referenced by a plain path (read only when relevant).

## What qualifies — ALL THREE must hold

1. **Durable** — true across sessions, not a detail of one task.
2. **Non-inferable** — Claude cannot cheaply detect it at runtime. If a quick
   `uname`/`sw_vers`/`which`/config read reveals it, DON'T store it.
3. **Distinctive** — a preference, a choice among alternatives, a convention, or a
   gotcha specific to this user.

Skip: auto-detectable facts (OS, installed tools/versions, shell); one-off or
ephemeral details; anything already recorded (update, don't duplicate); rules that
need guaranteed automatic enforcement ("always block X") → those are a **hook** in
`~/.claude/settings.json`, not a note.

## Where to store — by scope AND size

| Fact | Target |
|---|---|
| Global, always-relevant, short (one-liner rule/preference) | `~/.claude/CLAUDE.md`, dedicated end section |
| Global but bulky or situational (multi-line detail, playbooks, specs) | `~/.claude/knowledge/<topic>.md` + one plain pointer line in CLAUDE.md |
| Specific to one repo, and you are in that repo | that repo's `./CLAUDE.md` or its auto-memory — **defer** |

Pointer line format (plain reference, NOT `@import`, so it loads on-demand):
`- <topic> details: ~/.claude/knowledge/<topic>.md (read when relevant)`

## Procedure

1. **Detect** a fact passing all three qualification tests.
2. **Classify** scope + size → pick the target row above.
3. **Dedupe** — read the target section/file first; refine in place, never duplicate.
4. **Write:**
   - Short/global → terse bullet under the dedicated CLAUDE.md section:
     ```markdown
     ## Learned about this user (auto-captured — safe to prune)
     - <concise fact>. (2026-07-11)
     ```
   - Bulky/global → write the detail into `~/.claude/knowledge/<topic>.md`; add the
     pointer line to CLAUDE.md only if not already present.
   - Leave the user's hand-written CLAUDE.md sections untouched. Use absolute dates.
5. **Report** in one line what you recorded and where. Ask FIRST if the fact is
   sensitive, ambiguous, or a large behavioral change.

## CLAUDE.md hygiene

- It loads in full every request — treat it as a lean index of always-on rules plus
  pointers, not a knowledge dump. Keep it well under ~150 lines.
- If the auto-captured section grows past a few bullets, move detail into a
  `~/.claude/knowledge/*.md` topic file and leave a pointer.
- Never reach for `@import` to shrink context — it inlines. Plain references and
  skills are what actually defer token cost.

## Common mistakes

- Recording inferable/detectable facts (OS, installed versions) → skip; check at
  runtime instead.
- Dumping detail into CLAUDE.md → it is always loaded; move bulk to an on-demand
  topic file + pointer.
- Using `@import` expecting token savings → it inlines. Use a plain reference.
- Putting repo-specific knowledge in the global file → defer to that repo.
- Silent writes or duplicates → always report; dedupe before writing.
