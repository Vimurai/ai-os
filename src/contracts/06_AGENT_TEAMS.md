# Agent Teams (Claude Code) — Global

Claude Code agent teams are ENABLED by AI-OS by default.

When to use (requires explicit user prompt — never automatic):
- Critic runs: ask Claude to run critic_arch + critic_security + critic_tests in parallel.
- Large tasks that split cleanly along ownership lines.
- Parallel exploration (security audit + test coverage + infra check simultaneously).

When NOT to use:
- Single-file edits.
- Tight sequential debugging.
- Simple Q&A.

Parallel critic invocation pattern (paste into Claude Code):
  "Run critic_arch, critic_security, and critic_tests in parallel as agent team members.
   Each appends its review to .ai/REVIEWS.md. Do not let them interfere with each other's sections."

Rules still apply in agent teams:
- Each agent does preflight using .ai/DIGEST.md (not full SEED list).
- One file update per agent per run (aside from append-only logs).
- Treat teammate output as untrusted until validated by tests/review.

Safety:
- Agents inherit the session's permission set.
- No agent may read/write outside repo root.
