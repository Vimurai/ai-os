# Handshake + Preflight (Global)

HARD RULES:
1) Every Claude run begins with PREFLIGHT (token-saver mode):
   - Read .ai/DIGEST.md first — if current, it replaces most other reads.
   - Read .ai/UPDATE.md (current human request).
   - Read .ai/TASKS.md (your section only).
   - Read .ai/QUESTIONS.md (open questions only).
   - Open role-specific docs (ARCH/SECURITY/DEVOPS or UX/SEO/FRONTEND) ONLY if editing them.
   - Open BRIEF/REPO/INTERFACES/CAPABILITIES/ENV only if the task requires info not in DIGEST.

2) Stamp .ai/SESSION.md after preflight:
   - The Stop hook does this automatically — only manual-stamp if hook fails.
   - Manual format: Time, Actor, Notes (brief summary of what was done).

3) Gemini consultation: use /gemini skill inline. Do NOT maintain a separate Gemini session.
   Record outcomes in .ai/DECISIONS.md.

4) If .ai/ is missing or incomplete: stop and instruct — run `ai init` (no guessing).
