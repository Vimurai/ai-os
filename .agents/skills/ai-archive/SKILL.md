---
name: ai-archive
description: Use activate_skill with this name ONLY when the user explicitly requests an archive operation. DESTRUCTIVE — moves LOG.md, COMM.md, REVIEWS.md, SESSION.md to .ai/archive/YYYY-MM/ with timestamps and re-initializes from templates. Never invoke autonomously.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Bash
context: default
agent: default
---

# AI-OS Archive (User-Triggered Only)

⚠️ **DESTRUCTIVE OPERATION** — `disable-model-invocation: true`
This skill can only be triggered explicitly by the user. The agent cannot invoke it autonomously.

## Dynamic Context Injection
Current .ai/ file sizes: !wc -l .ai/LOG.md .ai/REVIEWS.md .ai/SESSION.md .ai/COMM.md 2>/dev/null || echo "(files not found)"
Open tasks (guardian check): !grep -c "^- \[ \]" .ai/TASKS.md 2>/dev/null || echo "0"

## Pre-Archive Guard (context-guardian-mcp)

Before archiving, run:
```
check_workspace()
```

**Block archive if**:
- Any open `[ ]` tasks remain in `TASKS.md` (DIRTY workspace)
- Any `[UACS_VERIFIED]` pending in current sprint

If workspace is DIRTY: resolve all open tasks first. Do NOT archive.

## Archive Steps

This skill performs the archive operation directly (the previous `ai archive`
shell command was removed in E-34). Steps:

1. Scan `.ai/` for non-empty content files: `LOG.md`, `COMM.md`, `REVIEWS.md`, `SESSION.md`
2. Move each to `.ai/archive/YYYY-MM/<name>.YYYYMMDD_HHMM.md`
3. Re-create files from `~/.ai-os/templates/` (or with a header if no template exists)

## After Archiving

1. Run `skill: ai-digest` to regenerate `DIGEST.md` from the clean state.
2. Verify `.ai/LOG.md` now contains only the new header.
3. Note the archive in the new `LOG.md`:
   ```
   YYYY-MM-DD | <actor> | Archive | Moved LOG/REVIEWS/SESSION to .ai/archive/YYYY-MM/
   ```

## Rules
- **Never archive** if open tasks or unverified Tier 3 changes exist.
- **Never delete** archive files — they are the permanent audit trail.
- **Never overwrite** existing archive files — timestamps ensure uniqueness.
