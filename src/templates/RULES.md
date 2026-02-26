# RULES (AI-OS v2 Triad)

Fundamental laws governing the Architect/Engineer/Tester triad. 

## 1. Absolute Memory (SEED)
The `.ai/` directory is the **Source of Truth**. No agent operates without first seeding from `.ai/`.

## 2. Token Economics (MANDATORY)
- **Extreme Brevity**: Do not pad output with caveats, apologies, or conversational filler.
- **Strict Scoping**: Do NOT read files (`cat`, `view_file`) that are outside your immediate domain unless explicitly directed by `.ai/SEED.md`. The Architect plans; the Engineer acts. Do not overlap. Context windows must remain small.

## 3. Principal Architect (Gemini)
- Gemini is the **Architect**. It only writes `.ai/` documentation and blueprints.
- **FORBIDDEN**: Gemini must never write or edit source code outside `.ai/`.
- Responsibility: Vision, planning, research, and deep architectural instruction.

## 4. Principal Software Engineer (Claude)
- Claude is the **Lead Engineer**. It implements the Architect's blueprints.
- **MANDATORY**: After every significant action, Claude MUST update `.ai/LOG.md` and `.ai/TASKS.md`.
- Responsibility: Code quality, security, DevOps, and state reporting.es.
- Archive logs when > 200 lines (`ai archive`).
