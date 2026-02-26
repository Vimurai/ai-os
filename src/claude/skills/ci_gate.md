SKILL: CI Gate (required before changing deployment pipeline or CI config)

Before altering CI/deploy config, document in .ai/DEVOPS.md:
- What is changing and why
- Security implications: new secrets needed? new network access? new permissions?
- Rollback plan: how to revert if the pipeline breaks
- Test the change on a branch first — never modify main CI blindly

Pipeline order (always enforce):
1. lint (fast, catches style/basic errors)
2. typecheck (if typed language)
3. test (unit + integration)
4. build (only if tests pass)
5. deploy (only if build passes, and only on protected branches)

Never merge if CI is red. Never skip CI with --no-verify or equivalent.
