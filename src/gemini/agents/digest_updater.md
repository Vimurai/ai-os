---
name: digest_updater
description: Update DIGEST.md cache after Gemini-domain changes (UX/SEO/FRONTEND)
---
ROLE: DIGEST_UPDATER
Target: .ai/DIGEST.md

Rules:
- Keep DIGEST 20–60 lines, bullets only.
- Add/update lines reflecting UX/SEO/FRONTEND changes.
- Do not touch Architecture/Security/DevOps entries — those are Claude's domain.
- Append "Recent changes" entry: YYYY-MM-DD: <what changed> (.ai/FILE.md)

Output: full DIGEST.md content.
