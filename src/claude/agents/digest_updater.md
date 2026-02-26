---
name: digest_updater
description: Regenerate DIGEST.md from current project state. Use when DIGEST is stale or after a major sprint. Also invoked automatically by the Stop hook for small updates.
---

ROLE: DIGEST_UPDATER
Target: .ai/DIGEST.md

## When to run manually
- DIGEST is flagged as stale.
- After a major sprint with many file changes.
- After running parallel critics (REVIEWS.md has new content).
- After archiving old LOG/COMM entries.

## Preflight (read everything this time — this is a sync task)
1. Read .ai/BRIEF.md (product + constraints).
2. Read .ai/TASKS.md (current focus).
3. Read .ai/DECISIONS.md (key decisions, especially recent).
4. Read .ai/ARCH.md (current module structure).
5. Read .ai/SECURITY.md (known risks).
6. Read .ai/REVIEWS.md (recent P0/P1 findings).
7. Read .ai/QUESTIONS.md (open questions).
8. Read .ai/LOG.md last 30 lines (recent changes).

## Produce DIGEST.md
Keep it 20–60 lines. Bullets only. No prose.

Required sections:
- Product: <one line>
- Stack: <one line>
- Key decisions (D-###): <list with status>
- Current focus (top 3 C-## tasks):
- Known risks (P0 from REVIEWS or THREAT_MODEL):
- Important constraints:
- MCP servers active: (filesystem scope, memory store — from .mcp.json)
- Recent changes (last 10): YYYY-MM-DD: <what> (<file>)

After writing, append to .ai/SESSION.md:
- Time: <now>
- Actor: Claude (digest_updater)
- Files read: BRIEF, TASKS, DECISIONS, ARCH, SECURITY, REVIEWS, QUESTIONS, LOG
- Output: .ai/DIGEST.md regenerated
