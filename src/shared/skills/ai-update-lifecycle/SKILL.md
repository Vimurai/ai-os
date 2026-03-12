---
name: ai-update-lifecycle
description: Manages the UPDATE.md lifecycle — archives the processed intent after Gate 1 completes, reinitializes a fresh template, and warns when UPDATE.md is overloaded (>500 lines). Prevents stale intent accumulation.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Write, Bash
context: default
agent: default
---

# AI-OS Update Lifecycle

Manages `.ai/UPDATE.md` after Gate 1 (prd_writer) has processed it.

## Dynamic Context Injection
UPDATE.md line count: !wc -l .ai/UPDATE.md 2>/dev/null | awk '{print $1}' || echo "0"
Last modified: !stat -f "%Sm" .ai/UPDATE.md 2>/dev/null || stat -c "%y" .ai/UPDATE.md 2>/dev/null || echo "unknown"

## Step 1 — Guard Check

Before archiving, verify Gate 1 has processed the current UPDATE.md:
- Check `.ai/LOG.md` for a `prd_writer` entry dated today or matching the current session.
- If NO prd_writer entry found: **STOP — do not archive unprocessed intent.**

## Step 2 — Warn on Overload

If UPDATE.md exceeds 500 lines:
```
⚠️  UPDATE.md is overloaded (>500 lines). This usually means:
- Multiple unprocessed sessions were stacked without archiving.
- Gate 1 was bypassed.
Action: Review UPDATE.md, extract distinct intents, run ai-update for each.
```

## Step 3 — Archive Processed UPDATE.md

```bash
ARCHIVE_DIR=".ai/archive/$(date +%Y-%m)"
mkdir -p "$ARCHIVE_DIR"
STAMP=$(date +%Y%m%d_%H%M)
cp .ai/UPDATE.md "$ARCHIVE_DIR/UPDATE.${STAMP}.md"
```

Verify the copy succeeded before proceeding.

## Step 4 — Reinitialize Fresh Template

Overwrite `.ai/UPDATE.md` with the standard empty template:
```
# UPDATE.md — Session Intent

<!-- Write your intent below. Be specific: target component, outcome, constraints. -->
<!-- Minimum 8 words with an action verb. Example: "Add rate limiting to /api/auth endpoints using Redis." -->

```

## Step 5 — Log

Append to `.ai/LOG.md`:
```
YYYY-MM-DD | <actor> | UPDATE.md archived to .ai/archive/YYYY-MM/UPDATE.YYYYMMDD_HHMM.md — template reinitialized
```

## Rules
- Never archive if prd_writer has not processed the current UPDATE.md.
- Never delete archive files.
- Trigger automatically after prd_writer completes, or when `ai archive` is run.
