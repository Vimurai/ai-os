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

### Absolute performance budgets without a baseline (E-239, D-062 §2) — **P1**

A bare millisecond budget (`elapsed < 200`) measures the MACHINE, not the code. Flag any
perf assertion that declares an absolute limit without a same-host baseline.

`incident_aggregator` asserted "under 200ms" and measured **381ms** on a developer laptop
while passing on CI — `node -e ''` alone cost ~197ms there. The same assertion then passed
on that laptop once 54 leaked tmux servers and a wedged download were cleared. It had been
tracking machine load the entire time.

Required shape: `assert_perf <label> <elapsed> <absolute> <baseline>` — absolute enforced
on CI where the hardware is known, `elapsed <= k*baseline + slack` elsewhere, and **both
numbers printed every run**. A perf assertion that prints only a verdict cannot distinguish
"the code got slower" from "the machine is busy", which is the whole question.

### Leaked external state (review question #3 — E-240, D-063 §2) — **P1**

> **What does this test leave behind when an assertion fails HALFWAY?**

Not when it passes — when it aborts. Cleanup written as the last line of a block never runs
on the path that matters, so a suite leaks precisely when something is already wrong.

The E-227/E-228 suites leaked **50 tmux servers** that way. Their socket names used `$$`,
which recycles, so a later run attached to a leftover server still holding windows and read
`windows=3` where it expected none. The leak was found by hand, days later.

Look for external state created without a matching `register_cleanup` **registered before
the state exists**: tmux servers, background processes, temp dirs outside the sandbox,
`.ai/` lock dirs, `~/.ai-os` writes, `.ai/signal.json` entries.

Required shape: `register_cleanup "…"` FIRST, then create; names from `mktemp` entropy,
**never `$$`**. `tests/run.sh` reports `LEAKED n <kind>` per suite and fails the run on CI.

This is the third variety of environment dependence, alongside "what the machine has"
(E-236) and "how fast it is" (E-239).

### State that must outlive a subshell (review question #4 — E-241, D-064 §2) — **P1**

> **Is this helper ever called inside a command substitution, a pipeline, or a
> `while read` loop — and does it set state that must outlive that call?**

`$(helper …)`, `helper | …` and `… | while read` all run in a SUBSHELL. Anything the helper
assigns to a variable, appends to an array, or installs as a trap **dies when that subshell
exits**, which is immediately. The call still returns the right string, so it looks correct.

This has bitten three times in two sprints, each time silently:

| Helper | What evaporated |
|---|---|
| `perf_baseline_node` (E-239) | the cache variable — every call re-measured with 5 node spawns |
| `register_cleanup` (E-240) | the handler array AND its trap — nothing was ever cleaned |
| `_self_stamp` (E-229) | captured output, via a different subshell mechanism |

Each was caught by an assertion written for another reason. That is the system working, but
the recurrence is the point.

**The rule (D-064 §2):** a helper returns DATA on stdout **or** sets STATE in the caller's
shell — never both. If it must do both, persist the state somewhere that survives the
subshell (a file) and say so in a comment, or split it into two functions.

### The scan that never ran (review question #5 — E-251, D-067 §5) — **P1**

> **Can this scan return an EMPTY set and still pass?**

A suite that forms a corpus and then asserts something about its contents is asserting
nothing when the corpus is empty — and "no violations found" is exactly what an empty
corpus reports. The failure is silent, permanent, and looks like health.

Three rule-scanning suites built their corpus with `find src .claude .agents .gemini`.
E-244 made provisioning role-aware, so `.agents/` and `.gemini/` stopped existing under the
all-Claude default; `find` exited non-zero, `execSync` threw, and the corpus came back
EMPTY. All three would have gone on printing "no findings" indefinitely. The only thing
that caught it was a file-count assertion each suite happened to carry, added when this
shape bit before.

Note the attempted fix that made it worse: filtering the root list for existence. That
turns a loud failure into a quiet shrink — the scan still runs, over less and less.

**The rule (D-067 §5):** build the corpus with `corpus_or_fail <min> <root>… [-- <find
predicate>…]`. It fails when a root is MISSING (named, not filtered out) or when the count
is below the floor, and it prints the count on every run, pass or fail. Then assert that
the scanner read that same corpus — the size of the list and the number of files the
scanner reports must agree, or an empty read is still reporting "clean" one layer in.

Look for: any `find`, `glob`, `readdir`, `git ls-files` or `execSync("find …")` whose result
feeds a "nothing found" assertion, with no assertion on how much was scanned.

This is the fifth variety of the harness measuring something else, alongside what the
machine HAS (E-236), how fast it IS (E-239), what a previous run LEFT (E-240) and a cleanup
that never RAN (E-241).

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
