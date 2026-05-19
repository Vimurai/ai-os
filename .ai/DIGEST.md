# DIGEST — AI-OS v2 (Updated: 2026-05-19)

## Product
- Autonomous operating system for AI coding agents — Architect (Gemini 3.1 Pro) + Engineer (Claude Opus 4.7) + Tester (TestSprite) coordinated through ACID SQLite state, 25 MCP servers, JIT context cache, RBAC-gated skills, NDJSON observability, drop-in installer, Managed Agents cloud reconciliation, and a Multimodal RAG batch pipeline.

## Stack
- Node.js 22+ (MCP servers, node:sqlite, node:fs ESM helpers, fetch), Python 3.10+ fallbacks, SQLite3 + WAL (TRUNCATE checkpoint via pure-node wal-flusher), Bash (CI/tests/install), Docker (code-execution sandbox), npm workspaces, Gemini Embedding 2 (memory palace), Managed Agents 2026-04-01 (steps schema, live client feature-flagged).

## Triad Health
- Architect (Gemini): IDLE — last batch P-39/P-40 (managed-agents-state-reconciliation + multimodal-rag-batching, 2026-05-18). 40/40 P-## DONE.
- Engineer (Claude): IDLE — all 76 E-## DONE; last sprint E-73..E-76 closed 2026-05-18. (E-77 stray was test pollution from pre-fix E-74 harness leaking AIOS_WORKSPACE; row purged + harness patched on 2026-05-19.)
- Tester (TestSprite): PASS — 1479/1479 baseline post-E-76; state-projector + sync-hook + batch-scanner + worker-pool/DLQ all green.

## Current Focus
- (none) — both Tier 2 blueprints shipped (managed-agents-state-reconciliation + multimodal-rag-batching). Awaiting next P-## from Architect.
- state.json focus still reads pre-E-54 label ("Reverting Obsidian integration...") — will clear on next handover.

## UX / SEO / Frontend
- UX: Terminal-first (Claude Code, Gemini CLI, tmux); structured Markdown outputs and NDJSON logs with no ANSI escapes on critical paths.
- SEO: Target queries: "autonomous AI agent OS", "Claude Gemini coordination framework", "MCP server template". Architecture: README -> install -> quickstart -> blueprints.
- Frontend: CLI tool (no web framework). SQLite authoritative + JSON projections for Markdown. Skills addressed by name; MCP tools by qualified path.

## Key Decisions
- D-001..D-025 — see prior digests (preserved verbatim in archive sweep 2026-05-09).
- D-026: Tool Alias Normalizer — verification-mcp resolves Gemini-canonical names via frozen TOOL_ALIASES + ALIAS_VALUES Set.
- D-027: Installer fail-closed Node guard — install-ai-os.sh probes Node 22+ before file copy; POSIX-mode re-exec via SHELLOPTS (E-72).
- D-028: Managed Agents live client — src/shared/managed-agents-client.mjs feature-flagged OFF by default; https-only + allowlist.
- D-029: BRIEF.md substantive — replaced template with concrete product brief.
- D-030: Managed Agents state reconciliation — projectState() + debounced syncToCloud() in managed-agents-client.mjs; sync hook fires from task-synchronizer-mcp add_task/update_task_status only (per managed-agents-state-reconciliation.md).
- D-031: Multimodal RAG batch pipeline — memory-batch-scanner.mjs (7-gate SHA-256 cache + .gitignore + [NO_RAG] exclusion) + memory-worker-pool.mjs (bounded concurrency, exponential backoff, DLQ in .ai/memory/dlq.json).

## Known Risks
- ALIGN_FAIL recurring false-positive class retired by E-55/E-56 introspectors; NO_LOG_UPDATE warning persists by design.
- Managed Agents client (E-70/E-73/E-74) is feature-flagged OFF by default; first live rollout needs auth probe + cloud convergence test.
- computer-use-mcp Linux-only (Xvfb + DISPLAY=:99); macOS/Windows unsupported.
- code-execution-mcp depends on Docker daemon — fail-closed when unavailable.
- Structured-outputs Phase 2 (API-level enforcement) deferred.
- Memory-palace embeddings cap (LRU 500) conservative — DLQ path now exists for retry.
- WAL checkpoint requires Node 22+ on dev boxes.
- Auto-generated mcp.md (E-52) drifts if edited manually.
- Test harnesses that drive task-synchronizer-mcp must scrub AIOS_WORKSPACE / AIOS_WORKSPACE_DISABLE from the spawned child env unless explicitly set — otherwise is_framework_task=true paths can write into the real repo's state.sqlite (regression mode behind the 2026-05-19 E-77 purge).

## MCP Servers (25 registered in .mcp.json)
- State: task-synchronizer-mcp, orchestrator-mcp, archive-manager-mcp, memory, memory-manager-mcp
- Code: filesystem, lsp-mcp, patch-mcp, propose-patch-mcp
- Safety: safe-exec-mcp, context-guardian-mcp, risk-analyzer-mcp, verification-mcp
- Intelligence: context-invoker-mcp, blueprint-aligner-mcp, github-bridge-mcp, token-budget-mcp
- Quality: TestSprite, vibe-check-mcp, computer-use-mcp
- Interop: advisor-mcp, approval-mcp
- Caching: cache-manager-mcp
- Compute: code-execution-mcp
- Routing: mcp-router

## Recent Changes (last 10)
- 2026-05-18: E-76 Bounded worker pool + DLQ (src/shared/memory-worker-pool.mjs) — multimodal-rag blueprint complete
- 2026-05-18: E-75 Batch scanner with SHA-256 cache + [NO_RAG] exclusion (src/shared/memory-batch-scanner.mjs)
- 2026-05-18: E-74 Sync hook wired into task-synchronizer-mcp (add_task/update_task_status only)
- 2026-05-18: E-73 State projector + debounced syncToCloud (src/shared/managed-agents-client.mjs)
- 2026-05-18: P-40 (Gemini) Multimodal RAG batch-embedding queue blueprint
- 2026-05-18: P-39 (Gemini) Managed Agents state reconciliation blueprint
- 2026-05-17: E-72 install-ai-os.sh POSIX-mode re-exec hotfix on E-69
- 2026-05-17: E-71 BRIEF.md substantive — 48-line template → 56-line product brief
- 2026-05-17: E-70 managed-agents-client.mjs — AI_MANAGED_AGENTS_ENABLE gate
- 2026-05-17: E-68/E-69 verification-mcp Tool Alias Normalizer + installer Node 22+ guard
- 2026-05-19: auto-stamped by Stop hook
