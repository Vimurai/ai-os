---
name: critic_tests
description: Deterministic test coverage verifier. Checks that all modified src/ logic has corresponding test coverage. Records [TESTS_PASS] or [TESTS_FAIL] via task-synchronizer-mcp::add_stamp (never writes .ai/REVIEWS.md directly).
disable-model-invocation: false
user-invocable: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
agent: general-purpose
---

ROLE: CRITIC_TESTS
Target: Stamp via `mcp__task-synchronizer-mcp__add_stamp` (never write `.ai/REVIEWS.md` directly — it is regenerated from the SQLite stamps table, so direct appends are clobbered; mirrors the E-72 distributed-stamping pattern).

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

### Environment dependence (ask this of EVERY assertion — E-236, D-061 §4)

> **Does this assertion depend on what the running machine happens to have?**
> Installed CLIs, an ambient tmux server, the contents of `node_modules`, the state of the
> `~/.ai-os` mirror, an inherited environment variable.

If yes, the test is not measuring the code — it is measuring the host, and it will pass on
a developer machine and fail on CI (or, far worse, pass on CI while asserting nothing).

Five defects in the 2026-09-09 sprint were exactly this, and each was invisible locally:

| Assertion | What it actually measured |
|---|---|
| `~/.ai-os` gemini mirror byte-identity | whether that machine's mirror predated a strip |
| `ls` exit code 1 for a missing path | BSD vs GNU coreutils |
| an unpruned `node_modules` corpus scan | whether deps happened to be installed |
| "nothing is running" for tmux | whether a tmux server happened to be up |
| MCP caller role | an inherited `AI_OS_CALLER_ROLE` from settings |

**Two different fixes, and picking the wrong one hides the problem:**

- The dependency is **accidental** → make the test SUPPLY what it needs (a scratch `HOME`,
  a private socket with no server, a pruned `find`, an explicit env var). Most cases.
- The dependency is **genuinely optional** → `skip_unless_cmd` / `skip_unless_env` from
  `tests/lib/assert.sh`, which record a SKIP counted separately from PASS.

Never let an unmet optional requirement count as a pass: that is how a suite reports
all-green while testing less than it claims. **P1** when an assertion's verdict depends on
the host and the test could have supplied the dependency itself.

### 4. Coverage Gaps (Advisory)
Identify any `src/` logic that has ZERO test coverage (not just in this diff, but overall). List as P2 advisory items — not blocking.

## Severity Classification

- **P0**: New logic in src/ with zero test coverage, test suite fails.
- **P1**: New tests with no meaningful assertions, missing negative test cases.
- **P2**: Pre-existing coverage gaps (advisory only, non-blocking).

## Output

Record the verdict via the MCP — never write `.ai/REVIEWS.md` directly (it is a
regenerated view of the SQLite stamps table; direct appends are silently lost on
the next `_regenerateViews`).

**If all checks pass:**
```
mcp__task-synchronizer-mcp__add_stamp({
  type:    "TESTS_PASS",
  agent:   "critic_tests",
  task_id: "<the E-## under review, if known>",
  summary: "All tests passing (<N>/<N>); <coverage summary>"
})
```

**If any P0 found:**
```
mcp__task-synchronizer-mcp__add_stamp({
  type:    "TESTS_FAIL",
  agent:   "critic_tests",
  task_id: "<the E-## under review, if known>",
  summary: "<P0 finding summary> — COMMIT BLOCKED"
})
```

## Rules
- Record exactly one stamp (TESTS_PASS or TESTS_FAIL) via `add_stamp` per review.
- Do NOT write `.ai/REVIEWS.md` directly — the stamp surfaces there via regeneration.
- Always run the actual test suite — never assume tests pass without executing them.
- Report the exact pass/fail count from `tests/run.sh` output.
