# Token Saver Mode — Global

Goal: minimize tokens without losing correctness by leveraging the Tripartite Engine (Gemini/Claude/TestSprite).

## 1. Tripartite Workflow Integration
1) **Plan with Gemini:** Use `/gemini` for all research, requirement gathering, and architectural planning.
   - Result: A concise `PLAN.md` (or update to `TASKS.md`) that Claude can follow.
   - Benefit: Gemini handles high-context ingestion; Claude only receives the plan.
2) **Build with Claude Code:** Use Claude for implementation based on the `PLAN.md`.
   - Rule: Claude must NOT re-research what Gemini already covered.
3) **Test with TestSprite:** Use TestSprite MCP/CLI to verify changes.
   - Rule: If tests fail, TestSprite output becomes the "Plan" for the next Claude iteration.

## 2. Reading & Ingestion
1) Read order: see .ai/SEED.md (canonical). Batch all 4 preflight reads in one parallel tool call.
2) Never re-read a file you already read this session.
3) Prefer grep/find + targeted excerpt over full-file ingestion for files > 100 lines.
4) **Gemini Ingestion:** Send large files/repo-maps to Gemini first. Use Gemini's summary as the context for Claude.

## 3. Maintenance
1) DIGEST as cache: after each run, the Stop hook auto-appends a short update.
2) Archive old LOG/COMM/REVIEWS entries when they exceed 200 lines (run `ai archive`).

## 4. Model selection (Auto-Switching)
- **Haiku (Flash):** Preflight, command execution, log updates, simple edits.
- **Sonnet (Pro):** Complex implementation, refactoring, tool-use loops.
- **Opus (Extended Thinking):** Critical architecture, multi-dependency debugging.
- CLI/shell command generation → delegate to /copilot (zero Claude tokens).

## 5. Skip-read signal
If DIGEST contains "stable since YYYY-MM-DD" and the current task does not touch those domains, skip REPO / INTERFACES / ENV / CAPABILITIES without reading.
