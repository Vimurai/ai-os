SKILL: Dependency Gate (required before adding any new major dependency)

Before adding: record in .ai/DECISIONS.md (Decision:TBD) with:
- Why needed: (what problem it solves — be specific)
- Alternatives considered: (including "implement it ourselves")
- Size/weight: (bundle size, install footprint)
- Security track record: (known CVEs? last audit?)
- Maintenance status: (actively maintained? last release?)
- License: (compatible with this project?)
- Rollback plan: (how to remove it if it causes problems)

Do NOT install the dependency until the human sets Decision: <chosen option>.
If the dependency is a dev/test-only dep with no security surface, a lightweight note in DECISIONS.md suffices.
