---
name: ai-preflight
description: Use activate_skill with this name at the start of every session in an AI-OS project. Executes the DIGEST-first read order (DIGEST → architect.md → UPDATE.md → TASKS.md) and stamps SESSION.md.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Glob
context: default
agent: default
---

# AI-OS Preflight — Session Bootstrap

## Dynamic Context Injection
Project root: !pwd
AI-OS project: !test -d .ai && echo "YES — .ai/ found" || echo "NO — run: ai init"
DIGEST freshness: !head -2 .ai/DIGEST.md 2>/dev/null || echo "(DIGEST.md missing — run: ai digest)"
Open tasks: !grep "^- \[ \]" .ai/TASKS.md 2>/dev/null | head -5 || echo "(none)"

## Preflight Read Order (DIGEST-First)

Execute in strict order — stop reading a file if it contains everything needed:

### 1. Read `.ai/DIGEST.md` ← PRIMARY
The current project snapshot. If DIGEST is current (≤ 3 days old), it replaces most other reads.
Contains: product summary, stack, Triad health, current focus, known risks, recent changes.

### 2. Read `.ai/architect.md` ← BLUEPRINT
The Principal Architect's blueprint. Read only if DIGEST references open architectural questions or your task touches architecture.

### 3. Read `.ai/UPDATE.md` ← CURRENT REQUEST
Human intent for this session. Always read.

### 4. Read `.ai/TASKS.md` ← YOUR ASSIGNMENTS
Assigned tasks (E-## for Claude, P-## for Gemini). Always read.

### Open Only When Task Touches That Domain
- `.ai/BRIEF.md` — Project rules & lore (read if onboarding or task touches product goals)
- `.ai/RULES.md` — Token economics & Triad contract
- `.ai/CAPABILITIES.md` — Allowed scope (always read for Tier 3 tasks)
- `.ai/REVIEWS.md` — Recent critic findings (read if preparing to commit)

## Session Stamp

After reading, append to `.ai/SESSION.md`:
```
---
- Time: YYYY-MM-DD HH:MM UTC
- Actor: <actor> (preflight)
- Files read: DIGEST, architect.md, UPDATE.md, TASKS.md
- Focus: <one-line summary of current task>
---
```

## Token Economics Hard Rules
- Do NOT read files outside your domain unless the task explicitly requires it.
- Do NOT read `src/**` unless your task involves a specific file.
- If DIGEST is current, skip files it already summarizes.
- SESSION.md is auto-stamped by the Stop hook — manual stamp only if hook fails.
