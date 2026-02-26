# DevOps (Global)

- Reproducible builds — any dev should get the same result.
- Tests run in CI before merge.
- No secrets committed — use .env.example with all keys present, values empty.
- Deterministic, idempotent scripts.
- Health checks and smoke tests for every main flow.

Prefer:
- Small CI: lint → typecheck → test → build (in that order).
- Minimal dependencies — each new dep requires a DECISION record.
- Structured logs: JSON or key=value, no PII, no secrets, actionable errors only.
- Observability: logs + at least one metric for critical paths.
