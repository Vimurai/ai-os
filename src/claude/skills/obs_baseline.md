SKILL: Observability Baseline (apply when implementing features or setting up DevOps)

Logging:
- Use structured format: JSON or key=value pairs.
- Required fields: timestamp, level, service/module, message, trace_id (if distributed).
- NEVER log: passwords, tokens, API keys, PII (emails, names, IDs that map to real people).
- Errors must be actionable: include context (what failed, where, relevant input shape — not the value).

Metrics (instrument at least):
- Request/operation latency (p50, p95, p99).
- Error rate by type.
- Critical resource utilization if applicable (queue depth, DB connections).

Tracing (if distributed):
- Propagate trace context across service boundaries.
- Instrument at trust boundaries (external API calls, DB queries, queue publishes).

Health checks:
- CLI: exit 0 on healthy, exit 1 with reason on unhealthy.
- Server: GET /health → 200 {"status":"ok"} or 503 with reason.

CI visibility:
- Test results in machine-readable format (JUnit XML or equivalent).
- Build artifacts published with version + commit SHA.
