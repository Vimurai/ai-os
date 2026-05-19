---
name: ai-preflight
description: Use activate_skill with this name at the start of every session in an AI-OS project. Executes the DIGEST-first read order (DIGEST → TASKS.md → architect.md if needed) and stamps SESSION.md.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Glob, Bash, mcp__task-synchronizer-mcp__verify_markdown_sync
context: default
agent: default
---

# AI-OS Preflight — Session Bootstrap

## Dynamic Context Injection
Project root: !pwd
AI-OS project: !test -d .ai && echo "YES — .ai/ found" || echo "NO — run: ai init"
DIGEST freshness: !head -2 .ai/DIGEST.md 2>/dev/null || echo "(DIGEST.md missing — run skill: ai-digest)"
Open tasks: !grep "^- \[ \]" .ai/TASKS.md 2>/dev/null | head -5 || echo "(none)"
Incident status: !for c in src/shared/incident-aggregate.mjs "${HOME}/.ai-os/shared/incident-aggregate.mjs"; do [ -f "$c" ] && node "$c" 2>/dev/null | head -1 && break; done 2>/dev/null || echo "(aggregator unavailable)"

## Preflight Read Order (DIGEST-First)

Execute in strict order — stop reading a file if it contains everything needed:

### 1. Read `.ai/DIGEST.md` ← PRIMARY
The current project snapshot. If DIGEST is current (≤ 3 days old), it replaces most other reads.
Contains: product summary, stack, Triad health, current focus, known risks, recent changes.

### 2. architect.md ← BLUEPRINT (SKIPPED)
**DO NOT read `.ai/architect.md` during preflight.** It is skipped to save tokens.
Only use `filesystem.read` on `.ai/architect.md` *after* preflight, and ONLY IF your specific assigned task explicitly requires architectural details.

### 3. Read `.ai/TASKS.md` ← YOUR ASSIGNMENTS
Assigned tasks (E-## for Claude, P-## for Gemini). Always read.

### 4. Verify markdown ↔ state sync ← FAILSAFE (E-60, blueprint state-sync-validation)

Before trusting TASKS.md, verify the file actually agrees with state.sqlite:

```
mcp__task-synchronizer-mcp__verify_markdown_sync()
```

- `[SYNC_PASS]` — proceed normally.
- `[SYNC_FAIL]` — read the listed anomalies. The most common failure is a
  task you completed last session that you forgot to mark `DONE`. If you
  see `E-N is [x] in TASKS.md but OPEN in state`, that's almost certainly
  the case — fix it via `update_task_status({id: "E-N", status: "DONE"})`
  before claiming any work is "done" in the new session.
- The MCP auto-regenerates the markdown when rows are missing from one
  side, so you usually need to act only on `is [x] but OPEN` /
  `is [ ] but DONE` anomalies.

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

### 6. Run the Incident Aggregator ← AUTO-IMPROVEMENT (E-66/E-67, blueprint incident-tracker)

After the sync check, run the JIT aggregator to surface recurring
unpredictable events captured by the `ai-incident` skill (E-65). The
aggregator reads `~/.ai-os/incidents.ndjson`, groups records by
`stack_signature`, and reports counts. Budget: <50ms — the helper does a
single linear pass.

**Locator chain** (mirrors E-58 / E-65 fail-open patterns):
1. `src/shared/incident-aggregate.mjs` (in-repo dev tree)
2. `${HOME}/.ai-os/shared/incident-aggregate.mjs` (installed mirror)

**Invocation** (run silently, parse the JSON):
```bash
node "${AGGREGATOR}" 2>/dev/null || echo '{"status":"AGGREGATOR_UNAVAILABLE"}'
```

**Output handling** — branch on the `status` field:

- `OK` / `NO_INCIDENTS` / `DISABLED` / `AGGREGATOR_UNAVAILABLE` — silent.
  No-op; continue to the next step.
- `THRESHOLD_REACHED` — emit an inline context block to the agent. Use
  the format below verbatim so the Architect (Gemini) can recognise the
  signal in the next handoff:

  ```
  [INCIDENT_THRESHOLD_REACHED] N distinct signature(s) at or above the
  threshold (>=3 occurrences). Recurring failures the framework should
  address — please draft a P-## blueprint per .ai/blueprints/incident-tracker.md
  before continuing implementation work.

  Top recurring signatures:
    - <stack_signature> (count=N, agents=[...], types=[...])
      sample: "<sanitised one-line message>"
    - …

  Suggested next step: switch to Gemini and ask for a blueprint that
  resolves the highest-count signature first.
  ```

  This is **prompting**, not **doing** — the Engineer must not draft
  P-## tasks (anti-drift §35). The block is the explicit handoff cue
  for the Architect.

**Rollback**: set `AI_INCIDENT_TRACKER_DISABLE=1` to short-circuit the
aggregator (it returns `status: "DISABLED"`). Manual deletion of
`~/.ai-os/incidents.ndjson` is safe and stateless.

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
- Files read: DIGEST, architect.md, TASKS.md
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

**Step 3 — Read open tasks**
```bash
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
