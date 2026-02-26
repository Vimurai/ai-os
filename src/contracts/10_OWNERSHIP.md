# Ownership (Global)

Single Writer Principle: one file = one owner. If you don't own it, you do NOT modify it.

Claude WRITES:
- .ai/ARCH.md
- .ai/SECURITY.md
- .ai/THREAT_MODEL.md
- .ai/DEVOPS.md

Claude EDITS (controlled sections only):
- .ai/BRIEF.md — Architecture Notes + Security/DevOps Notes sections only
- .ai/TASKS.md — "## Claude" section (C-## tasks) only

Gemini (via /gemini skill) PRODUCES content for:
- .ai/UX.md, .ai/SEO.md, .ai/FRONTEND.md
- .ai/BRIEF.md — UX Notes, SEO/Content Notes, Frontend Notes sections only
- .ai/TASKS.md — "## Gemini" section (G-## tasks) only
Note: Claude pastes Gemini output into these files after review.

Both APPEND:
- .ai/DIGEST.md (short cache notes — auto-updated by Stop hook)
- .ai/REVIEWS.md (critic reviews — append-only)
- .ai/DECISIONS.md (proposals + final decisions)
- .ai/QUESTIONS.md (questions with safe defaults)
- .ai/SESSION.md (auto-stamped by Stop hook)
- .ai/LOG.md (auto-appended by PostToolUse hook)
- .ai/CHANGELOG.md (user-visible notes)
- .ai/COMM.md (retained for human notes; no longer the primary AI comm bus)

Templates (human fills in):
- .ai/REPO.md, .ai/ENV.md, .ai/QUALITY.md, .ai/INTERFACES.md,
  .ai/CAPABILITIES.md, .ai/PROMPTS.md, .ai/SEED.md, .ai/READMAP.md,
  .ai/CRITICS.md, .ai/BRIEF.md, .ai/RULES.md, .ai/UPDATE.md

No one rewrites files they don't own. No "rewrite whole document" behavior.
