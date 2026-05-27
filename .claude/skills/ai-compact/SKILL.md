---
name: ai-compact
description: Use activate_skill with this name when SESSION.md exceeds ~2000 tokens, before a long task, or when asked to compact/distill context. Distills conversation history into "Active Context", archives the raw SESSION.md log, and resets it to a minimal header. Equivalent to running /compact.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Bash, Write, Edit
context: default
agent: default
---

# AI-OS Context Compaction (§24 — ai-compact)

## Dynamic Context Injection
SESSION.md line count: !wc -l < .ai/SESSION.md 2>/dev/null || echo "0"
Archive dir exists: !test -d .ai/archive && echo "YES" || echo "NO (will be created)"
Today's date: !date '+%Y-%m-%d'

## Purpose

When `SESSION.md` grows large (> ~2000 tokens / ~150 lines), raw history becomes
a liability — it wastes tokens without adding context value. This skill:

1. **Distills** the session into a compact "Active Context" summary (≤ 30 lines).
2. **Archives** the raw `SESSION.md` to `.ai/archive/YYYY-MM/SESSION.<timestamp>.md`.
3. **Resets** `SESSION.md` to a minimal header + the distilled Active Context.
4. **Clears** `digest_stale` flag if DIGEST was regenerated this session.

## Step 1 — Read SESSION.md

```
Read .ai/SESSION.md
```

If SESSION.md has fewer than 80 lines, compaction is not needed. Inform the user
and exit: _"SESSION.md is compact (N lines). No compaction needed."_

## Step 2 — Distill Active Context

Analyze SESSION.md and produce a structured summary in this format:

```markdown
## Active Context (compacted: YYYY-MM-DD)

### Completed this session
- E-##: <one-line summary>
- E-##: <one-line summary>

### Current focus
<One-sentence description of what was being worked on at session end>

### Open decisions / blockers
- <any unresolved questions or blockers, one per line>

### Files modified (key changes)
- path/to/file — reason
```

**Rules for distillation:**
- Maximum 30 lines total.
- Focus on E-## tasks completed, current focus, and open blockers.
- Do NOT include raw tool output, debug noise, or intermediate steps.
- Do NOT include secrets, PII, or internal API responses.

## Step 3 — Archive raw SESSION.md

Determine the archive path:
```bash
ARCHIVE_DIR=".ai/archive/$(date '+%Y-%m')"
TIMESTAMP=$(date '+%Y%m%d_%H%M')
ARCHIVE_PATH="${ARCHIVE_DIR}/SESSION.${TIMESTAMP}.md"
mkdir -p "$ARCHIVE_DIR"
```

Move the current SESSION.md content to the archive:
```
Read .ai/SESSION.md → Write to ${ARCHIVE_PATH}
```

## Step 4 — Reset SESSION.md

Write a fresh SESSION.md with only the distilled Active Context:

```markdown
# SESSION.md (reset: YYYY-MM-DD HH:MM)
<!-- Compacted by ai-compact. Raw log archived to .ai/archive/YYYY-MM/SESSION.<ts>.md -->

<Active Context from Step 2>

---
```

## Step 5 — Update state.json (optional)

If `.ai/state.json` exists and `digest_stale` is `false` (DIGEST was already
regenerated this session), skip. Otherwise, leave `digest_stale` unchanged —
compaction does not update DIGEST.md.

Append a compact stamp to `.ai/LOG.md`:
```
<TODAY> | Claude | ai-compact | SESSION.md compacted → .ai/archive/YYYY-MM/SESSION.<ts>.md
```

## Completion

Report to the user:
```
✓ Context compacted successfully.
  Archive: .ai/archive/YYYY-MM/SESSION.<timestamp>.md
  SESSION.md reset to <N> lines (Active Context).
  Tokens saved: ~<estimate based on line count reduction>.
```
