# Token Discipline (Global)

- **Gemini-First Planning:** Every non-trivial task MUST start with a `/gemini` planning session to generate a `PLAN.md`.
- **Model Auto-Switching:** Use the lowest capable model for the task.
  - *Preflight/Maintenance:* Haiku/Flash.
  - *Implementation:* Sonnet.
  - *Deep Reasoning:* Opus/Extended Thinking.
- Output only what is needed. Prefer bullets/tables over prose.
- One run = update ONE target file (except append-only logs).
- Use /gemini skill for Planning/UX/Frontend/SEO; do not burn Claude tokens on these.
- Use /copilot skill for CLI/shell command lookups.
- Read budget: max 6 files per session. Use Gemini's summaries to stay under budget.
- Never re-output file content you already read this session in full.
