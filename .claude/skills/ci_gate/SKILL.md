---
name: ci_gate
description: Gate required before changing any CI/CD pipeline or deployment config. Documents the change, security implications, and rollback plan in .ai/DEVOPS.md before any edits are made.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Edit, Write
context: default
agent: default
---

# CI Gate (Required Before Changing Deployment Pipeline or CI Config)

Before altering CI/deploy config, document in `.ai/DEVOPS.md`:
- What is changing and why
- Security implications: new secrets needed? new network access? new permissions?
- Rollback plan: how to revert if the pipeline breaks
- Test the change on a branch first — never modify main CI blindly

## Pipeline Order (Always Enforce)
1. `lint` (fast, catches style/basic errors)
2. `typecheck` (if typed language)
3. `test` (unit + integration)
4. `build` (only if tests pass)
5. `deploy` (only if build passes, and only on protected branches)

Never merge if CI is red. Never skip CI with `--no-verify` or equivalent.

## Dynamic Context Injection
Current CI config files: !find . -name "*.yml" -path "*/.github/workflows/*" -o -name "*.yaml" -path "*/.github/workflows/*" 2>/dev/null | head -10
