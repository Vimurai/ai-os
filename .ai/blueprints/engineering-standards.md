# Domain Blueprint: Engineering Standards

> [!IMPORTANT]
> Proactive architectural enforcement of clean code, reusability, and maintainability in the AI-OS codebase.

## Goal & Architecture
Establish an automated quality-control layer that prevents "architectural drift" and sub-standard code, ensuring all engineering work follows strict reuse and cleanliness principles.

## Core Concept
- **Architectural Friction**: Introducing automated gates in the commit pipeline (CI/pre-commit) that demand structural compliance before code is accepted.
- **Delegated Architecture**: Mandatory reuse of `src/shared/` components for common logic.

## Components
1. **Standards-Checker**: CLI tool (`node scripts/standards.mjs`) that parses `standards.json` and validates staged changes.
2. **Critic-Clean-Code**: An agent persona specialized in heuristic-based code structure analysis (heavier than linter, lighter than manual review).
3. **Standards-Registry**: `src/shared/standards.json` defining the formal rules (complexity thresholds, naming patterns, file-size limits).

## Data Model
- `StandardRule`: `{ rule_id, severity, threshold, description, auto_fix_available }`.
- `ComplianceReport`: `{ file_path, status, violated_rules: [] }`.

## API / Interface Contracts
- `validateStandards(diff_path: string) -> ComplianceReport`: Invoked by pre-commit hook.
- `reportDrift(report: ComplianceReport)`: Emits structured warnings to `ai-review` synthesizers.

## Security
- **Trust Boundaries**: The `standards-checker` only introspects code structure; it MUST NOT evaluate business logic or secrets.
- **Integrity**: `standards.json` is immutable without a Tier 3 Architect ruling.

## Execution Constraints
- **Performance**: Standard validation must complete in < 200ms per commit.
- **Concurrency**: Standards checker runs in parallel with existing linting/test gates.

## Rollback Plan
- Disable the pre-commit hook via `hooks/pre-commit.sh` (flag `AI_OS_SKIP_STANDARDS=1`).
- Revert the `registry.json` change that registers the new `critic_clean_code` agent.

## E-## Task Breakdown
- E-83: Create `src/shared/standards.json` and implement the `standards-checker` CLI utility.
- E-84: Develop the `critic_clean_code` persona and integrate it into the `ai-review` flow.
- E-85: Update `hooks/pre-commit.sh` to enforce the new standards gate.
