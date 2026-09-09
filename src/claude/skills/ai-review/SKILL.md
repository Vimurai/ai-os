---
name: ai-review
description: Run a tier-aware critic review before committing. Tier 1 skips review. Tier 2 runs blueprint-aligner only. Tier 3 runs full parallel critics (arch + security + tests) plus security_engineer and UACS verification. Replaces the removed `ai review claude` shell command (E-34).
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
context: fork
agent: default
---

# AI-OS Review (Tier-Aware Parallel Critics)

## Dynamic Context Injection
Current tier signals: !git diff --staged --name-only 2>/dev/null | head -10 || echo "(no staged changes)"
Recent CRITIC_STAMP: !grep -m1 "\[CRITIC_STAMP\]" .ai/REVIEWS.md 2>/dev/null || echo "(none — review required)"
Recent distributed stamps: !grep -E "\[(ARCH|SEC|TESTS|ALIGN)_(PASS|FAIL)\]" .ai/REVIEWS.md 2>/dev/null | tail -4 || echo "(none)"
Recent UACS_VERIFIED: !grep -m1 "\[UACS_VERIFIED\]" .ai/LOG.md 2>/dev/null || echo "(none)"

## Step 1 — Detect Tier

Classify the current changes using `risk-analyzer-mcp`:
```
classify_risk()   ← reads staged diff automatically
```

Or classify manually:
- **Tier 1**: Only `.css`, `.md`, `.txt`, docs, formatting → skip review.
- **Tier 2**: `src/**` logic changes, tests, refactors → blueprint_aligner only.
- **Tier 3**: auth, secrets, new dependencies, breaking changes → full Triad.

---

## Tier 1 — Skip Review

CSS/docs/typos only. No critic agents needed.

```bash
npx prettier --check .
npx eslint . --max-warnings 0
```

Commit: `git commit -m "[TIER_1] <description>"`
No `[CRITIC_STAMP]` required for Tier 1.

---

## Tier 2 — Blueprint Aligner + Clean-Code (parallel)

Spawn both critics in parallel — they review independent surfaces (blueprint
alignment vs. code shape) and stamp their own verdicts. `review_synthesizer`
or the human operator weighs both before committing.

```
Agent("Run blueprint-aligner-mcp align_diff(). Use mcp__task-synchronizer-mcp__add_stamp with type ALIGN_PASS or ALIGN_FAIL to record the result.")
Agent("Run the critic_clean_code agent (E-81). Use mcp__task-synchronizer-mcp__add_stamp with type CLEAN_PASS, CLEAN_WARN, or CLEAN_FAIL to record the result.")
```

Expected stamps after both complete:
- `[ALIGN_PASS/FAIL]` — from `blueprint-aligner-mcp`
- `[CLEAN_PASS/WARN/FAIL]` — from `critic_clean_code.md` (E-81 — invokes E-80 standards-checker)

Pass gate (all required for [CRITIC_STAMP]):
- ALIGN must be `PASS`
- CLEAN must NOT be `FAIL` (a `CLEAN_WARN` is acceptable for Tier 2)

If both clear, record the synthesis stamp:
```
mcp__task-synchronizer-mcp__add_stamp({
  type: "CRITIC_STAMP",
  agent: "ai-review-tier2",
  summary: "[TIER_2] Blueprint aligned + clean-code gate clear — <N warnings ignored>"
})
```

If either fails, the failing critic's stamp is the COMMIT BLOCKED signal —
do not write a passing CRITIC_STAMP.

Commit (only after PASS): `git commit -m "[TIER_2] <description>"`

---

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


## Tier 3 — Full Parallel Critics (Distributed Stamping)

Spawn all critics in parallel using the `Agent` tool. Each critic is a **materialized agent file** — load its instructions via `activate_agent` and follow them exactly.

```
Agent("Run the critic_arch agent. Use mcp__task-synchronizer-mcp__add_stamp with type ARCH_PASS or ARCH_FAIL to record the result.")
Agent("Run the critic_security agent. Use mcp__task-synchronizer-mcp__add_stamp with type SEC_PASS or SEC_FAIL to record the result.")
Agent("Run the critic_tests agent. Use mcp__task-synchronizer-mcp__add_stamp with type TESTS_PASS or TESTS_FAIL to record the result.")
Agent("Run the critic_clean_code agent (E-81). Use mcp__task-synchronizer-mcp__add_stamp with type CLEAN_PASS, CLEAN_WARN, or CLEAN_FAIL to record the result.")
Agent("Run blueprint-aligner-mcp align_diff(). Use mcp__task-synchronizer-mcp__add_stamp with type ALIGN_PASS or ALIGN_FAIL to record the result.")
Agent("Run the security_engineer agent. Use mcp__task-synchronizer-mcp__add_stamp with type SEC_CLEARED to record the result.")
```

Expected stamps after all complete:
- `[ARCH_PASS/FAIL]` — from `critic_arch.md`
- `[SEC_PASS/FAIL]` — from `critic_security.md`
- `[TESTS_PASS/FAIL]` — from `critic_tests.md`
- `[CLEAN_PASS/WARN/FAIL]` — from `critic_clean_code.md` (E-81 — runs E-80 standards-checker)
- `[ALIGN_PASS/FAIL]` — from `blueprint-aligner-mcp`
- `[SEC_CLEARED]` — from `security_engineer.md`

### After All Critics Complete → Trigger review_synthesizer

Do NOT write `[CRITIC_STAMP]` manually. Instead, invoke `review_synthesizer`:
```
activate_skill("review_synthesizer")
```

`review_synthesizer` reads all distributed stamps (`[ARCH_PASS]`, `[SEC_PASS]`, `[TESTS_PASS]`,
`[ALIGN_PASS]`), aggregates findings, and writes the final `[CRITIC_STAMP]` + release verdict.

If all gates clear, `review_synthesizer` also appends to `.ai/LOG.md`:
```
[UACS_VERIFIED] YYYY-MM-DD | Tier 3 review complete — all gates passed
```

Then run: `skill: ai-test` with --vibe (mandatory for Tier 3 before commit).

Commit: `git commit -m "[TIER_3] <description>"`
