# Domain Blueprint: MCP Nervous System

> [!IMPORTANT]
> This document maps all AI-OS Model Context Protocol (MCP) servers according to §34 Architectural Fragmentation.

The AI-OS MCP Nervous System is a robust suite of custom servers that grants intelligence agents specific, safe, and audited access to project state, system commands, and code manipulation.

## Core State & Coordination
- **`task-synchronizer-mcp`**: AI-OS Exclusive State Mutator — SQLite-backed state with `TASKS.md`/`REVIEWS.md` markdown views. Coordinates tasks, logging, and stamp verification securely.
- **`orchestrator-mcp`**: AI-OS Orchestrator: Deterministic workflow execution for preflight, review, and handover operations.

## Security & Compliance
- **`safe-exec-mcp`**: AI-OS UACS: AST-analyzes shell commands for destructive patterns before execution.
- **`context-guardian-mcp`**: AI-OS UACS: Guards `ai archive` and `git commit` by checking for unresolved TODO/FIXME/Pending markers.
- **`verification-mcp`**: AI-OS §32: Programmatic compliance auditing — verifies agent YAML frontmatter against `registry.json` and MCP tool exports.
- **`blueprint-aligner-mcp`**: AI-OS UACS: Compares git diff output against `architect.md` rules to detect deviations, preventing plan drift.

## Context & Memory
- **`context-invoker-mcp`**: AI-OS UACS: Gives Claude dynamic access to skills and agents by name (JIT Metadata Loading).
- **`archive-manager-mcp`**: AI-OS Auto-Pilot: Monitors `.ai/` context health and orchestrates autonomous archive operations to prevent context bloat.
- **`memory-manager-mcp`**: AI-OS §31: Global cross-project memory palace — stores and queries project architectural signatures.
- **`token-budget-mcp`**: AI-OS Token Budget & Cost Governance (§27) — real-time LLM spend tracking with SQLite persistence.

## Execution & Git Operations
- **`patch-mcp`**: AI-OS Staleness-Aware File Patching (§25) — MD5-verified atomic file updates.
- **`propose-patch-mcp`**: AI-OS Human-in-the-Loop Safe Diff Flow (§30) — `propose_patch` with TUI preview and explicit confirm/reject.
- **`github-bridge-mcp`**: AI-OS GitHub Bridge (§28) — fetch assigned issues via `gh` CLI and surface them for Architect review cycles.

## Quality & Intelligence
- **`risk-analyzer-mcp`**: AI-OS TSRT: Classifies intent and git changes as Tier 1/2/3 to enable gate skipping and token savings.
- **`vibe-check-mcp`**: AI-OS MCP server: Visual audit, chaos testing, and performance metrics via Headless Playwright.
- **`lsp-mcp`**: AI-OS Code Intelligence Layer (§23) — TypeScript compiler API wrapper for symbol/type awareness.