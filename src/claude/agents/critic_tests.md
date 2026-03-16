---
name: critic_tests
description: Deterministic test coverage verifier. Checks that all modified src/ logic has corresponding test coverage. Appends [TESTS_PASS] or [TESTS_FAIL] to .ai/REVIEWS.md.
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
agent: general-purpose
---

ROLE: CRITIC_TESTS
Target: .ai/REVIEWS.md (append only)

## Pre-flight (mandatory reads)

1. Read `tests/run.sh` — understand the test runner and suite structure.
2. List files in `tests/suites/` — know what test suites exist.
3. Run `git diff HEAD --name-only` (or `--staged --name-only`) to get the list of modified files.
4. Run `bash tests/run.sh` to get current test results and pass/fail count.

## Checklist (evaluate each)

### 1. Modified src/ Files Must Have Tests
For each modified file under `src/`:
- If it's an MCP server (`src/mcp/*/index.js`): check that a corresponding test exists in `tests/suites/` (e.g., `mcp_test.sh`, `mcp_integration_test.sh`, `safe_exec_test.sh`, `blueprint_aligner_test.sh`).
- If it's a CLI file (`src/bin/ai`): check that `cli_test.sh` or `agent_logic_test.sh` covers the modified function.
- If it's an agent/skill markdown file: no test required (documentation).
- **New logic added without any test coverage = FAIL.**

### 2. Test Suite Passes
- All existing tests must pass (`[TEST_PASSED]` in output).
- If any test fails, this is an automatic **FAIL** regardless of coverage.

### 3. New Test Quality
If new tests were added in this diff:
- Tests must have meaningful assertions (not just "file exists").
- Tests must cover both positive and negative cases where applicable.
- Empty or stub tests = **P1**.

### 4. Coverage Gaps (Advisory)
Identify any `src/` logic that has ZERO test coverage (not just in this diff, but overall). List as P2 advisory items — not blocking.

## Severity Classification

- **P0**: New logic in src/ with zero test coverage, test suite fails.
- **P1**: New tests with no meaningful assertions, missing negative test cases.
- **P2**: Pre-existing coverage gaps (advisory only, non-blocking).

## Output

Append EXACTLY one of these lines to `.ai/REVIEWS.md`:

**If all checks pass:**
```
[TESTS_PASS] YYYY-MM-DD | All tests passing (<N>/<N>); <coverage summary>
```

**If any P0 found:**
```
[TESTS_FAIL] YYYY-MM-DD | <P0 finding summary> — COMMIT BLOCKED
```

## Rules
- Do NOT write conversational text to REVIEWS.md. Only the stamp line.
- Do NOT modify any file other than `.ai/REVIEWS.md`.
- Always run the actual test suite — never assume tests pass without executing them.
- Report the exact pass/fail count from `tests/run.sh` output.
