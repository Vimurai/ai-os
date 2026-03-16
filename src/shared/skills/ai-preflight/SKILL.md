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

### 5. Check Implementation Deltas ← FEEDBACK LOOP (P-42 §29)
If `.ai/state.json` exists, check for unread implementation deltas:
```
Read .ai/state.json → look for entries in "deltas" array where "read" is false
```
If unread deltas exist, display them prominently:
```
## Unread Implementation Deltas
- E-78: Created state.json schema | Files: src/templates/state.json, src/bin/ai
- E-79: task-synchronizer-mcp v2.0 | Files: src/mcp/task-synchronizer-mcp/index.js
```
After reading, mark them as read (set `"read": true`) so they don't repeat.
**Architect**: If a delta shows divergence from your blueprint, update `architect.md` to reflect reality.

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

## Layer 2 Fallback — Bash/jq Context Retrieval (§30 Bootloader Resilience)

Use this section when `orchestrator-mcp::run_preflight` is unavailable (MCP server down, node error, cold start). This is Layer 2 of the 3-layer resilience chain.

### Trigger Condition
`run_preflight()` returns an error OR `orchestrator-mcp` is not listed in active MCP servers.

### Fallback Execution

**Step 1 — Read DIGEST (primary context)**
```bash
cat .ai/DIGEST.md
```

**Step 2 — Extract structured state from state.json (Bash/jq)**
```bash
# Task counts
python3 -c "
import json
s = json.load(open('.ai/state.json'))
counts = {}
for t in s['tasks']:
    counts[t['status']] = counts.get(t['status'], 0) + 1
print('Tasks:', counts)
print('Focus:', s['project'].get('focus', '(none)'))
" 2>/dev/null || grep "^- \[ \]" .ai/TASKS.md | head -10

# Last 3 stamps
python3 -c "
import json
s = json.load(open('.ai/state.json'))
for st in s['stamps'][-3:]:
    print(f\"[{st['type']}] {st['timestamp'][:10]} | {st.get('summary','')}\")
" 2>/dev/null || tail -3 .ai/REVIEWS.md
```

**Step 3 — Read UPDATE.md and open tasks**
```bash
cat .ai/UPDATE.md
grep "^- \[ \]" .ai/TASKS.md | head -10
```

**Step 4 — Stamp SESSION.md manually**
```bash
echo "---" >> .ai/SESSION.md
echo "- Time: $(date -u +%Y-%m-%d\ %H:%M) UTC (Layer 2 fallback)" >> .ai/SESSION.md
echo "- Actor: Claude (ai-preflight skill)" >> .ai/SESSION.md
echo "---" >> .ai/SESSION.md
```

### Escalation
If Layer 2 also fails (python3/bash unavailable), escalate to **Layer 3**: read the "Emergency Recovery" section in `CLAUDE.md`.

## Token Economics Hard Rules
- Do NOT read files outside your domain unless the task explicitly requires it.
- Do NOT read `src/**` unless your task involves a specific file.
- If DIGEST is current, skip files it already summarizes.
- SESSION.md is auto-stamped by the Stop hook — manual stamp only if hook fails.
