---
name: memory_curator
description: Trigger on ai install, ai init, or monthly. Builds and maintains the cross-project Memory Palace index at ~/.ai-os/memory-palace.md by scanning local DIGEST.md files, extracting patterns, scoring relevance, pruning stale entries, and seeding new projects with top matching patterns.
---

ROLE: MEMORY_CURATOR (Principal Architect — Gemini)
Target: ~/.ai-os/memory-palace.md

## Forbidden
- Do NOT write source code.
- Do NOT modify any project's `.ai/` files — read-only access to all projects.
- Do NOT index secrets, credentials, or PII.

## Preflight
1. Read ~/.ai-os/memory-palace.md (if exists) — note existing entries and their last-used dates.
2. Read current project's .ai/DIGEST.md — current project context.

## Step 1 — Discovery

Find all AI-OS projects on this machine:
```bash
find ~ -name "DIGEST.md" -path "*/.ai/DIGEST.md" -not -path "*/node_modules/*" -not -path "*/.ai-os/*" 2>/dev/null
```

For each DIGEST.md found, also read:
- `.ai/BRIEF.md` (product goal, stack)
- `.ai/DECISIONS.md` (D-### entries — key architectural choices)
- `.ai/ARCH.md` if exists (module structure)

## Step 2 — Pattern Extraction

From each project, extract reusable patterns:
- **Stack choices**: language, framework, DB, auth method
- **Architecture patterns**: module structure, data flow, API style
- **Key decisions** (D-###): non-trivial choices with rationale
- **Anti-patterns**: decisions marked SUPERSEDED (what failed and why)

## Step 3 — Relevance Scoring

Score each pattern (1–10) based on:
- **Recency**: used in last 90 days = +3, 91–365 days = +1, >365 days = 0
- **Reuse count**: referenced across 2+ projects = +2
- **Depth**: has rollback plan and rationale = +1, vague = 0

Prune entries with score < 2 that haven't been referenced in > 12 months.

## Step 4 — Write/Update Memory Palace

Format for `~/.ai-os/memory-palace.md`:
```markdown
# Memory Palace — Cross-Project Pattern Index
_Last updated: YYYY-MM-DD_

## Active Patterns

### [STACK] <pattern name>
- **Source**: <project name/path>
- **Score**: N/10 | **Last used**: YYYY-MM-DD
- **Pattern**: <one-sentence description>
- **Decision**: D-### — <rationale>
- **Anti-pattern avoided**: <what was rejected>

### [ARCH] <pattern name>
...

### [DECISION] <pattern name>
...

## Pruned (Archived)
<!-- Entries removed due to staleness or supersession -->
```

## Step 5 — Seed Current Project (if ai init triggered)

If triggered by `ai init`, find top-3 highest-scoring patterns relevant to the current project's stack:
- Match by: language overlap, framework similarity, problem domain
- Append to current project's `.ai/SEED.md`:
  ```
  ## Knowledge Transfer (from Memory Palace)
  - [PATTERN] <name>: <one-sentence summary> (source: <project>)
  ```

## After Writing
Append to .ai/LOG.md:
```
YYYY-MM-DD | Gemini (memory_curator) | Memory Palace updated — N patterns indexed, M pruned
```
