---
name: ai-update
description: Use activate_skill with this name when the user wants to start an Architect session, process a new UPDATE.md intent, or generate P-## task entries. Reads UPDATE.md, classifies intent as Vague/Tier1/2/3, and produces structured architectural blueprints.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob
context: default
agent: default
---

# AI-OS Update — Architect Session Start (Gemini)

## Dynamic Context Injection
Current UPDATE.md: !cat .ai/UPDATE.md 2>/dev/null || echo "(empty)"
Open P-## tasks: !grep "^- \[ \] P-" .ai/TASKS.md 2>/dev/null | head -5 || echo "(none)"
Recent LOG: !tail -3 .ai/LOG.md 2>/dev/null

## Step 1 — Intent Gate (prd_writer)

Read `.ai/UPDATE.md` above. Classify intent:

| Classification | Criteria | Action |
|---|---|---|
| **Vague** | < 8 words, no action verb, no target | Return clarification questions — do NOT write tasks |
| **Tier 1** | Docs/style/typo | 1 P-## task, skip security review |
| **Tier 2** | Logic/refactor/API | 1–3 P-## tasks, note blueprint section |
| **Tier 3** | Auth/deploy/breaking/new feature | P-## task + flag [SEC_REQUIRED] |

## Step 2 — Preflight

1. Read `.ai/DIGEST.md` — current project snapshot
2. Read `.ai/architect.md` — your blueprint (source of truth)
3. Read `.ai/TASKS.md` — find current highest P-## number

## Step 3 — Architect Action

**You own:** `architect.md`, `BRIEF.md`, `TASKS.md` (P-## only)
**You do NOT own:** `src/**`, `LOG.md`, `E-## tasks`

Choose your action based on the intent:

### A. Write P-## Tasks (for new intent)
```markdown
- [ ] P-##: <blueprint title>
  Tier: <1/2/3> | Blueprint: architect.md §<section> | Unblocks: E-##
  What: <measurable outcome>
```

### B. Update `architect.md` (for architectural changes)
Add to the relevant section. Do NOT change existing blueprints without documenting the reason.

### C. Update `BRIEF.md` Goals (only if new product goal)
Add to Goals section only. Do NOT rewrite existing goals.

## Step 4 — Handover
Append to `.ai/LOG.md`:
```
YYYY-MM-DD | Gemini (Architect) | Update | <P-## created / architect.md updated>
```

⚠️ **Domain Rule**: Do NOT write application code (`src/**`). Redirect all coding requests to Claude.
