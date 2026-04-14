# DIGEST (Token Saver Cache)

## Triad Health
- Stage: Planning
- Architect Focus: Blueprinting AI-OS architecture, domain blueprints (MCP, Agents)
- Engineer Focus: Awaiting implementation tasks

Purpose: Single file that replaces most per-session reads.
**Strict Limit**: Keep 20–50 lines max. Bullets only. Auto-updated by Stop hook.

## Current snapshot
- Product: AI-OS v2 - Autonomous operating system for AI agents with ACID-compliant SQLite state.
- Stack: Node.js 20+ (MCP servers), Python 3.10+ (fallbacks), SQLite3, Bash.
- Current focus (top 3 tasks):
  - [DONE] P-1: Architect system philosophy and technical strategy.
  - [DONE] P-2: Map MCP tools to .ai/blueprints/mcp.md.
  - [DONE] P-3: Map Agent structures to .ai/blueprints/agents.md.
- Known risks: Token-burn bloat without JIT loading, Bootloader fallback regressions.

## Recent changes (last 10)
- 2026-04-14: Replaced template boilerplate in Sections 1-6 of architect.md with actual AI-OS philosophy and technical strategy. (.ai/architect.md)
- 2026-04-14: Created domain blueprint mapping all 16 MCP servers and capabilities. (.ai/blueprints/mcp.md)
- 2026-04-14: Created domain blueprint mapping all Claude, Gemini, and Shared skills/agents. (.ai/blueprints/agents.md)
- 2026-04-14: Created workspace.md blueprint defining standard directory layout. (.ai/blueprints/workspace.md)
- 2026-04-14: Created bootloader.md blueprint defining boot execution flow. (.ai/blueprints/bootloader.md)
- 2026-04-14: auto-stamped by Stop hook

---
DIGEST must be accurate or flagged as stale. If stale, run: ai digest