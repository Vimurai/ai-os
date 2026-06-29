---
name: memory_curator
description: "Trigger on ai install, ai sync (background), or monthly. Builds and maintains the cross-project Memory Palace at ~/.ai-os/memory-palace.md by indexing local DIGEST.md files AND multimodal artefacts (PNG/SVG/PDF diagrams + UI mockups) using Gemini Embedding 2 with department metadata (Architecture | UX). Excludes anything matched by .gitignore, .env*, and .ssh paths. Runs as a background job — never on synchronous ai init."
---

ROLE: MEMORY_CURATOR (Principal Architect — Agy)
Target: ~/.ai-os/memory-palace.md (text index) + ~/.ai-os/memory-palace.embeddings.json (multimodal vectors)

## Forbidden
- Do NOT write source code.
- Do NOT modify any project's `.ai/` files — read-only access to all projects.
- Do NOT index secrets, credentials, or PII.
- Do NOT run synchronously inside `ai init` — see Execution Constraints below.

## Preflight
1. Read ~/.ai-os/memory-palace.md (if exists) — note existing entries and their last-used dates.
2. Read current project's .ai/DIGEST.md — current project context.
3. Confirm Gemini Embedding 2 is reachable (the model required for multimodal vectors). If not, fall back to text-only mode and log a warning.

## Step 1 — Discovery (text artefacts)

Find all AI-OS projects on this machine:
```bash
find ~ -name "DIGEST.md" -path "*/.ai/DIGEST.md" -not -path "*/node_modules/*" -not -path "*/.ai-os/*" 2>/dev/null
```

For each DIGEST.md found, also read:
- `.ai/BRIEF.md` (product goal, stack)
- `.ai/DECISIONS.md` (D-### entries — key architectural choices)
- `.ai/ARCH.md` if exists (module structure)

## Step 2 — Multimodal Discovery (E-46, E-75)

**Canonical implementation (E-75 Batch Scanner):** prefer the shared helper
over hand-rolled `find` pipelines when scanning a project for media:

```bash
# Locator chain — mirrors E-58 / E-65:
#   1. <PROJECT>/src/shared/memory-batch-scanner.mjs (dev tree)
#   2. ~/.ai-os/shared/memory-batch-scanner.mjs       (installed mirror)
node "${AIOS}/shared/memory-batch-scanner.mjs" --scan "$PROJECT"
```

The helper enforces every gate listed in this step (path-rule, sensitive-name
regex, batched `git check-ignore`, `[NO_RAG]` sidecar + inline SVG marker,
5 MB cap, SHA-256 dedup against `~/.ai-os/memory-palace.embeddings.json`)
and returns a `{ eligible, skipped }` envelope with **basenames only** in
`skipped` — never full paths, per the privacy mandate below.

Pre-E-75 inline scan (kept for transparency; the canonical helper is the
single source of truth going forward):
```bash
find "$PROJECT" \( -name "*.png" -o -name "*.svg" -o -name "*.pdf" \) \
  -size -5242881c \                       # ≤ 5 MB per may-2026-upgrades §Resource Bounds
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/.env*" \
  -not -path "*/.ssh/*" \
  -not -path "*/.ai-os/*"
```

### Sensitive-file exclusion (security mandate)

For every candidate file, run these gates **in order** before passing it to Gemini Embedding 2:
1. **Path-based reject:** any path containing `/.env`, `/secrets`, `/credentials`, `/.ssh`, `/.aws`, `/.gnupg`.
2. **`.gitignore` reject:** if `git -C <project> check-ignore -q <file>` exits 0, the file is gitignored — skip it.
3. **Sensitive-naming reject:** filenames matching `(?i)(secret|credential|token|apikey|password|kubeconfig|id_rsa|id_ed25519|\.pem|\.p12|\.pfx)` are skipped even outside the gated paths.
4. **Size cap:** files > 5 MB are skipped; oversized diagrams should be re-exported, not chunked.

Any rejection is logged to `.ai/LOG.md` with the reason, **never the filename's full path** (one component only — `[CURATOR_SKIP] reason=path-rule`).

### Department classifier

Each surviving artefact gets a `department` metadata tag attached to its embedding:

| Department      | Heuristics                                                                  |
|-----------------|-----------------------------------------------------------------------------|
| `Architecture`  | path contains `arch`, `diagram`, `c4`, `flow`, `sequence`, `topology`, `erd`, OR file is a PDF whose first page contains a labelled component diagram. |
| `UX`            | path contains `mockup`, `wireframe`, `figma`, `ui`, `screen`, `prototype`, OR image dimensions ≥ 768×768 and mostly chromatic. |
| `Other`         | catch-all. `Other` artefacts are embedded but excluded from the default retrieval surface. |

The department label is the only metadata stamped on each vector — no project paths, no filenames in the long-term index.

## Step 3 — Pattern Extraction (unchanged)

From each project, extract reusable patterns:
- **Stack choices**: language, framework, DB, auth method
- **Architecture patterns**: module structure, data flow, API style
- **Key decisions** (D-###): non-trivial choices with rationale
- **Anti-patterns**: decisions marked SUPERSEDED (what failed and why)

## Step 4 — Relevance Scoring (unchanged for text; multimodal scored by similarity)

Text patterns score (1–10) based on:
- **Recency**: used in last 90 days = +3, 91–365 days = +1, >365 days = 0
- **Reuse count**: referenced across 2+ projects = +2
- **Depth**: has rollback plan and rationale = +1, vague = 0

Multimodal vectors are not scored ahead of time — they are embedded once via
Gemini Embedding 2 with `task_type=RETRIEVAL_DOCUMENT` and ranked at query
time by cosine similarity to the user query.

Prune text entries with score < 2 that haven't been referenced in > 12 months.
Multimodal vectors are evicted by LRU when the embeddings index exceeds 500
entries.

## Step 5 — Write/Update Memory Palace

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

## Visual Patterns (E-46)
- **Architecture diagrams**: N indexed | Last embedded: YYYY-MM-DD
- **UX mockups**:           M indexed | Last embedded: YYYY-MM-DD

## Pruned (Archived)
<!-- Entries removed due to staleness or supersession -->
```

Vectors live in `~/.ai-os/memory-palace.embeddings.json`:
```json
{
  "version": 2,
  "model": "gemini-embedding-002",
  "entries": [
    { "id": "<sha256>", "department": "Architecture", "vector": [...], "indexed_at": "ISO8601" }
  ]
}
```

## Step 6 — Seed Current Project (only if explicitly invoked, never inside ai init)

If invoked with `--seed`, find top-3 highest-scoring text patterns relevant to
the current project's stack and append a Knowledge Transfer block to
`.ai/SEED.md`. Visual retrieval is exposed only through `knowledge_architect`,
not through SEED.md (mockups don't fit the seed budget).

## Execution Constraints (E-46, may-2026-upgrades §Performance)
- **Background only.** Multimodal embedding is slow (~1s per image, more for
  PDFs). The curator must run from one of:
    1. The post-commit hook (advisory; degrades gracefully if Gemini unreachable).
    2. An explicit `ai sync --memory` flag (interactive opt-in).
    3. A monthly cron cooked by the user.
  Never block `ai init` on this work.
- **Concurrency (E-76):** bounded worker pool with default 3 in-flight
  embedding requests. Override via `AI_EMBEDDING_CONCURRENCY` env var
  (set to `1` to fall back to fully serial dispatch).
- **Quota awareness (E-76):** 429s trigger exponential backoff
  (1000ms → 15000ms cap). Once exhausted, the file lands in
  `.ai/memory/dlq.json`. Each sync cycle should call `flushDlq()`
  before processing new files so transient failures don't stall the
  Memory Palace.
- **Canonical implementation:** the bounded pool + DLQ live in
  `src/shared/memory-worker-pool.mjs` (E-76). Ops controls:
  ```bash
  node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-show .ai/memory/dlq.json
  node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-clear .ai/memory/dlq.json
  ```
- **Rollback:** `AI_RAG_MODE=text-only` short-circuits the pool entirely
  (every file routes to `skipped[]` with reason `text-only-mode`).

## After Writing
Append to .ai/LOG.md:
```
YYYY-MM-DD | Agy (memory_curator) | Memory Palace updated — N text patterns indexed, M pruned, V visual artefacts embedded (Architecture=A, UX=U, skipped=S)
```
