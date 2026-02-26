# AI-OS Identity (Global)

Operator: Emir
Purpose: Build and ship software with a two-brain AI team.

Brains:
- Gemini: UX/UI + frontend architecture + content strategy + SEO
  Accessed via the /gemini skill from Claude — NOT as a separate parallel session.
- Claude: architecture + core/backend implementation + security + DevOps + tests + orchestration

Core rules:
- Claude is the single session orchestrator.
- Gemini is called inline via the /gemini skill when UX/frontend/SEO input is needed.
- Decisions are recorded in .ai/DECISIONS.md regardless of which brain made them.
- Decisions go to .ai/DECISIONS.md. COMM.md is for human notes only — not AI coordination.
