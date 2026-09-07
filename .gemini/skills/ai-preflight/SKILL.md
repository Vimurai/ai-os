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
Incident status: !for c in src/shared/incident-aggregate.mjs "${HOME}/.ai-os/shared/incident-aggregate.mjs"; do [ -f "$c" ] && node "$c" 2>/dev/null | grep -m1 '"status"' | sed -E 's/.*"status": *"([^"]+)".*/\1/' && break; done 2>/dev/null || echo "(aggregator unavailable)"

## Preflight Read Order (DIGEST-First)

Execute in strict order — stop reading a file if it contains everything needed:

### 1. Read `.ai/DIGEST.md` ← PRIMARY
The current project snapshot. If DIGEST is current (≤ 3 days old), it replaces most other reads.
Contains: product summary, stack, Triad health, current focus, known risks, recent changes.

### 2. architect.md ← BLUEPRINT (SKIPPED)
**DO NOT read `.ai/architect.md` during preflight.** It is skipped to save tokens.
Only use `filesystem.read` on `.ai/architect.md` *after* preflight, and ONLY IF your specific assigned task explicitly requires architectural details.

### 3. Read `.ai/TASKS.md` ← YOUR ASSIGNMENTS
Assigned tasks (E-## for Claude, P-## for Agy). Always read.

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
  the format below verbatim so the Architect (Agy) can recognise the
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

  Suggested next step: switch to Agy and ask for a blueprint that
  resolves the highest-count signature first.
  ```

  This is **prompting**, not **doing** — the Engineer must not draft
  P-## tasks (anti-drift §35). The block is the explicit handoff cue
  for the Architect.

**Rollback**: set `AI_INCIDENT_TRACKER_DISABLE=1` to short-circuit the
aggregator (it returns `status: "DISABLED"`). Manual deletion of
`~/.ai-os/incidents.ndjson` is safe and stateless.

### 7. INSIGHTS.md Staleness Check ← META-COGNITION (E-86, blueprint meta-cognition)

After the incident aggregator, run the staleness probe for the
cross-project meta-cognition report (E-85). The helper compares
`~/.ai-os/INSIGHTS.md` mtime against telemetry rows accumulated in
`~/.ai-os/telemetry.sqlite` (E-84). Budget: <50ms — one stat + one
SQLite COUNT() with optional `since_iso` clause.

**Locator chain** (mirrors E-58 / E-65 / E-75 / E-83):
1. `src/shared/insights-staleness.mjs` (in-repo dev tree)
2. `${HOME}/.ai-os/shared/insights-staleness.mjs` (installed mirror)

**Invocation** (run silently, parse the JSON envelope):
```bash
for c in src/shared/insights-staleness.mjs "${HOME}/.ai-os/shared/insights-staleness.mjs"; do
  if [ -f "$c" ]; then PROBE="$c"; break; fi
done
node "${PROBE}" 2>/dev/null || echo '{"status":"UNAVAILABLE"}'
```

**Output handling** — branch on the `status` field:

- `FRESH` / `EMPTY` / `DISABLED` / `UNAVAILABLE` — silent. No-op;
  continue to the open-on-demand reads below.
- `STALE` — emit an inline context block to the agent. Use the format
  below verbatim so the user can convert it to a `skill: ai-insights`
  invocation:

  ```
  [INSIGHTS_STALE] N new telemetry rows since INSIGHTS.md last
  refreshed (threshold: 200). The cross-project meta-cognition
  report is out of date — recurring tool errors, latency outliers,
  and CLI-automation candidates may have shifted.

  Telemetry: <total_rows> total, <new_rows_since_insights> new since
            <insights_mtime or "(never generated)">.

  Suggested next step: run `skill: ai-insights` to regenerate
  ~/.ai-os/INSIGHTS.md before the next planning loop. The skill is
  on-demand and bounded — no telemetry write side-effects.
  ```

  Like the incident-aggregator hand-off (Step 6), this is **prompting**,
  not **doing** — the staleness probe never invokes the meta_analyst
  itself. The agent surfaces the block; the user decides whether to
  trigger `ai-insights`.

**Rollback**: set `AI_INSIGHTS_STALENESS_DISABLE=1` to short-circuit
the probe (it returns `status: "DISABLED"`). The wider
`AI_TELEMETRY_DISABLE=1` (E-84) also disables this check by extension.
Manual deletion of `~/.ai-os/INSIGHTS.md` is safe — the next probe
re-evaluates from the telemetry DB.

### 8. Load REPO_MAP.md ← ARCHITECTURE CONTEXT (E-98, blueprint ast-repository-map)

After the staleness checks, load the AST Repository Map **if it exists**:

```bash
test -f .ai/REPO_MAP.md && cat .ai/REPO_MAP.md || echo "(no REPO_MAP.md — run: ai sync)"
```

`.ai/REPO_MAP.md` is a token-compressed skeleton of the codebase —
the most central files (PageRank over the import graph) with their
exports, class/method **signatures** (bodies elided with `⋮`), and
imports. It is regenerated by `ai sync` via `ast-parser-mcp generate_map`
(E-95/E-96/E-97) within a strict token budget (default 2048).

- **If present**: read it for immediate architectural orientation —
  prefer it over blind `grep`/full-file reads when locating where a
  symbol lives. It is a *map*, not the source of truth; open the real
  file before editing.
- **If absent**: it has not been generated yet (fresh clone, or
  `AI_OS_DISABLE_REPO_MAP=1`). Run `ai sync` to build it, or fall back
  to `grep`/`list_directory`.

**Rollback**: `AI_OS_DISABLE_REPO_MAP=1` stops regeneration; deleting
`.ai/REPO_MAP.md` is safe — the next `ai sync` rebuilds it.

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
If Layer 2 also fails (python3/bash unavailable), escalate to **Layer 3**: read the "Emergency Recovery" section in `ENGINEER.md` (the canonical Engineer rulefile; `CLAUDE.md` is a shim that imports it).

## Token Economics Hard Rules
- Do NOT read files outside your domain unless the task explicitly requires it.
- Do NOT read `src/**` unless your task involves a specific file.
- If DIGEST is current, skip files it already summarizes.
- SESSION.md is auto-stamped by the Stop hook — manual stamp only if hook fails.
