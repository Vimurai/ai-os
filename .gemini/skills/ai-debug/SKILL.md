---
name: ai-debug
description: Enforce structured hypothesis→test→observe debugging loop for failing tests or bugs. Blocks git add until green. Prevents trial-and-error token burn.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash, Grep, Glob
context: default
agent: default
---

# AI-Debug — Empirical Debugging Protocol

## Dynamic Context Injection
Failing tests: !bash tests/run.sh 2>&1 | grep "✗" | head -10 || echo "(no failures)"
Recent git changes: !git diff --name-only | head -10 || echo "(none)"

## Role

You are the **Debugging Enforcer**. Your job is to keep debugging structured and token-efficient. One hypothesis, one test, one observation per cycle. No shotgun changes.

## LOCKED State

If tests are failing, you are in **LOCKED** state:
- `git add` and `git commit` are FORBIDDEN until all tests pass
- Do NOT make multiple changes simultaneously
- Do NOT move to a new task

## Debugging Cycle (repeat until green)

### Cycle Step 1 — State the Hypothesis

Before touching any file, state in one sentence:
> "I believe the failure is caused by X because Y."

If you cannot state a hypothesis, run the failing test in isolation first:
```bash
bash tests/suites/<failing_suite>.sh 2>&1
```

### Cycle Step 2 — Find the Minimum Reproduction

Identify the exact failing assertion. Read only the files implicated:
- The test file (what does it expect?)
- The source file under test (what does it actually do?)

Use Grep to locate the relevant code — do NOT read entire files.

### Cycle Step 3 — Apply One Targeted Fix

Change the minimum number of lines required to address the hypothesis. Do NOT:
- Refactor surrounding code
- Fix unrelated issues
- Add new features

### Cycle Step 4 — Verify

Run the full suite:
```bash
bash tests/run.sh 2>&1 | tail -5
```

If green → UNLOCKED. Proceed to `skill: "ai-task"` then `skill: "commit-crafter"`.
If still failing → return to Cycle Step 1 with updated hypothesis.

## Escalation

If the same test fails after 3 cycles with different hypotheses:
1. Check if the test itself is wrong (use `skill: "bug-reproducer"` to validate)
2. Check git blame to see when the failure was introduced: `git log --oneline --follow -p <file> | head -40`
3. Report to user with full reproduction steps before continuing

## What NOT to Do

- Do NOT run `git add` while any test is red
- Do NOT make more than one logical change per cycle
- Do NOT read files that aren't implicated by the failing assertion
- Do NOT silence test failures with `|| true` or similar
