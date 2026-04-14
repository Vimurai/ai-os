# Handshake + Preflight (Global)

HARD RULES:
1) Every session begins with PREFLIGHT via the skill:
   ```
   skill: "ai-preflight"
   ```
   This calls orchestrator-mcp::run_preflight() — reads DIGEST.md + TASKS.md,
   queries state.sqlite for task counts, focus, and unread deltas.
   Do NOT manually read .ai/ files before running preflight.

2) Session stamp (.ai/SESSION.md):
   - The Stop hook auto-stamps after every session — only manual-stamp if hook fails.

3) Gemini ↔ Claude handoff:
   - Architect (Gemini) creates P-## tasks via add_task MCP tool.
   - Engineer (Claude) picks up open E-## tasks from TASKS.md.
   - After completing: run_handover({ task_id: "E-##", summary: "..." })
   - Record architectural decisions in .ai/DECISIONS.md.

4) If .ai/ is missing or incomplete: stop and run `ai init` — do not guess.
