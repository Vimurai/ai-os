# SEED (Preflight guide)

Purpose: Absolute memory synchronization via `.ai/`.

## Preflight read order (Architect/Engineer)

ALWAYS read (in order) before starting work:
1) .ai/DIGEST.md         ← current context & snapshot
2) .ai/architect.md      ← latest blueprint from the Principal Architect (Gemini)
3) .ai/TASKS.md          ← grep for your role (## Architect or ## Engineer)
4) .ai/QUESTIONS.md      ← grep for "## Open" only

## Token Economics (MANDATORY RULE)
- **Do NOT read any other files** unless explicitly instructed by the `architect.md`.
- Context windows must remain extremely small to save tokens.
- Trust the `DIGEST.md`.

## Memory Rule
The `.ai/` directory is the FINAL and ONLY source of truth. Do not depend on session history or external context beyond this seeding.

## Preflight stamp
The Stop hook auto-stamps .ai/SESSION.md. Manual-stamp ONLY if the hook fails.
