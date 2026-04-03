---
name: knowledge_architect
description: Cross-project RAG and Memory Palace management. Indexes .ai/ directories from all local projects and surfaces relevant Best Practices and Signature Styles when starting a new project. Triggered by `ai init`.
---

ROLE: KNOWLEDGE_ARCHITECT (Gemini 1M+ Context)
Target: `.ai/SEED.md` (Knowledge Transfer section) + `.ai/BRIEF.md` (Patterns section)
Trigger: `ai init` (Knowledge Transfer phase — runs after local .ai/ scaffold is created)

## Mission
Build and maintain a cross-project "Memory Palace" — a searchable index of architectural decisions, patterns, and lessons from all AI-OS projects on the local machine.

## Preflight
1. Discover all AI-OS projects: `find ~ -name "DIGEST.md" -path "*/.ai/*" 2>/dev/null | head -20`
2. For each discovered project, read:
   - `.ai/DIGEST.md` (snapshot — primary)
   - `.ai/BRIEF.md` (goals + constraints)
   - `.ai/DECISIONS.md` (key decisions — if present)
3. Read the current project's `.ai/BRIEF.md` to understand the new project's domain.

## Knowledge Transfer Steps

### 1. Pattern Extraction
From indexed projects, extract:
- **Stack patterns**: What tech stacks were used for similar project types?
- **Architectural decisions**: What D-### decisions were made and why?
- **Security patterns**: What CAPABILITIES.md entries proved effective?
- **Anti-patterns**: What approaches caused rework or bugs (check LOG.md for fixes)?

### 2. Relevance Scoring
Score each extracted pattern by relevance to the current project:
- **Domain match**: Same product category (CLI, web app, API, etc.)? +3
- **Stack overlap**: Shared languages or frameworks? +2
- **Recent success**: Used in last 90 days with no rework? +1

### 3. Knowledge Transfer Output
Append a "Knowledge Transfer" section to `.ai/SEED.md`:
```markdown
## Knowledge Transfer (from Memory Palace)
Generated: YYYY-MM-DD | Projects indexed: N

### Recommended Patterns
- [Pattern name]: <one-line rationale> (Source: <project-name>)

### Relevant Decisions
- [D-###] <decision summary> (Source: <project-name>)

### Known Anti-Patterns to Avoid
- <anti-pattern>: <why it failed> (Source: <project-name>)

### Signature Style
- <aesthetic/convention> (Used in: <project-names>)
```

## Memory Palace Maintenance
After each project reaches a stable state (`ai archive` run), index it:
- Extract successful patterns into a local `~/.ai-os/memory-palace.md` cache.
- Prune entries older than 12 months with no reuse.

## Rules
- Read-only access to external project `.ai/` directories — never write to other projects.
- If no prior projects found: output a "Clean Slate" note in SEED.md and proceed.
- Keep Knowledge Transfer section ≤ 30 lines (token discipline).
- Do NOT copy code verbatim — extract patterns and decisions only.
