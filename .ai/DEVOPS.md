# DEVOPS (Append-only — CI/CD and pipeline change log)

---

## DEVOPS-001 — Bootloader Fallback CI Validation (E-2)

**Date**: 2026-04-14
**Task**: E-2
**Status**: PENDING IMPLEMENTATION

### What is changing and why
A new test suite `tests/suites/resilience_test.sh` will be created to validate the Bootloader's three-layer degradation mechanism (per `.ai/blueprints/bootloader.md` §3):

1. **Simulated Node Failure test** — Temporarily renames/chmods `src/mcp/orchestrator-mcp/index.js` to simulate a crash, then asserts the system falls back to the `ai-exec` CLI layer reading `.ai/state.json`.
2. **Fallback Verification test** — Asserts JIT read requests successfully return data via the secondary fallback path (Python/Bash parsing of `state.json`).
3. **State Integrity test** — After simulated crash + recovery, runs `PRAGMA integrity_check;` against `.ai/state.sqlite` and diffs against `state.json` to assert zero corruption.

No existing CI workflow files are being created or modified at this time. The test suite is a standalone shell script; wiring into a GitHub Actions workflow is a separate future task.

### Security implications
- **No new secrets required.** Tests operate on local filesystem only; no network access.
- **No new permissions.** The `chmod` in the simulated-failure test is scoped to a non-sensitive test fixture and must be reverted by the test teardown.
- **SQLite access is read-only** in the fallback path per the blueprint constraint (§2): fallback scripts MUST only execute read-only queries unless using `BEGIN EXCLUSIVE TRANSACTION` with `PRAGMA synchronous = FULL`.
- **No CI secrets exposure.** Test output must be scrubbed of any file paths that could leak internal directory structure before being logged to CI artifacts.

### Pipeline order enforced
The resilience test suite will be positioned after `lint` and `typecheck` but before `build`:
1. `lint`
2. `typecheck` (if applicable)
3. `test` (unit + **resilience**)
4. `build`
5. `deploy` (protected branches only)

### Rollback plan
- Delete `tests/suites/resilience_test.sh`. No other files are modified by E-2.
- If the test is later wired into CI, remove the workflow step referencing it. The test is additive-only and has no side effects on production code.

### Branch strategy
- Implement and validate on the current branch (`master`) before merging. Run `bash tests/suites/resilience_test.sh` locally to confirm PASS before any commit.

---

## DEVOPS-002 — Install framework in CI before tests

**Date**: 2026-05-27
**Status**: IN PROGRESS

### What is changing and why
`.github/workflows/test.yml` runs `bash tests/run.sh` against a bare checkout
with **no framework install**, so `~/.ai-os/` never exists in CI. ~12 assertions
across 5 suites (telemetry, insights_staleness, meta_analyst,
multi_variation_state_tracker, standards_checker) assert byte-identity via
`diff -q "$SRC" "${HOME}/.ai-os/..."` and fail with exit 2 (file missing). A
further ~16 assertions (managed_agents_sync_hook, state_projector_sync,
installer_node_check) depend on the installed/dev environment. CI has been
chronically red on every push as a result. **All 28 failures pass locally**
where `~/.ai-os/` is present.

**Fix:** add an `Install AI-OS framework` step that runs `bash install-ai-os.sh`
**before** `Run tests`, populating `~/.ai-os/` from `src/` so the mirror +
install-dependent suites have their expected environment. The installer is a
non-interactive thin copier; `install_global()`'s failure-prone parts
(`gh copilot`, `do_mcp_setup`) are guarded with `|| true`/`|| echo`, so it does
not abort under `set -e`.

### Security implications
- **No new secrets.** Installer is local file copy + npm install (deps already
  installed by the existing CI step). No network beyond npm (already present).
- **No new permissions.** Runs as the unprivileged GitHub runner user; writes
  only under `$HOME` (ephemeral runner).
- **No CI secrets exposure.** Installer output is build log only; no tokens.

### Pipeline order enforced
1. deps (`npm ci` + per-MCP `npm install`)
2. **install (`bash install-ai-os.sh`)** ← new, before tests
3. `test` (`bash tests/run.sh`)
4. secret-gitignore check (unchanged)

### Rollback plan
- Revert the single added step in `.github/workflows/test.yml` (delete the
  `Install AI-OS framework` step or `git revert` the commit). The change is
  additive and isolated to the workflow file — no source or test changes.
- If the installer step itself breaks CI, removing the step returns the suite
  to its prior (red mirror) baseline with no other regression.

### Branch strategy
- Validate on branch `ci/install-framework-before-tests` first (never modify
  master CI blindly). Push, watch the Actions run on the branch, iterate on any
  residual failures (notably the `bash --posix` installer re-exec assertion,
  which may be a separate ubuntu-bash portability issue), then merge to master.

---

## DEVOPS-003 — Bump GitHub Actions to v5

**Date**: 2026-05-27
**Status**: IN PROGRESS

### What is changing and why
`actions/checkout@v4` and `actions/setup-node@v4` run on Node.js 20, which
GitHub flagged as deprecated. The runner will force Node.js 24 by default
from **2026-06-02**, after which the v4 actions emit warnings (and risk
forward-compat issues). v5 of both actions ships native Node 24 support
and is a drop-in replacement — same inputs, same behaviour. Bump to:

- `actions/checkout@v4` → `actions/checkout@v5`
- `actions/setup-node@v4` → `actions/setup-node@v5`

### Security implications
- **No new secrets.** No new permissions. Both actions are first-party
  (`actions/*`) and pinned by major version, consistent with the existing
  pinning style.
- Both v5 releases are official GitHub Actions releases; no supply-chain
  posture change vs the prior v4 pin.

### Pipeline order enforced
Unchanged — only the action versions are bumped:
1. deps (`npm ci` + per-MCP `npm install`)
2. install (`bash install-ai-os.sh`)
3. test (`bash tests/run.sh`)
4. secret-gitignore check

### Rollback plan
- One-line revert of the two `uses:` pins back to `@v4`, or `git revert`
  the commit. Additive-equivalent change; no other files touched.

### Branch strategy
- Validate on branch `ci/bump-actions-v5`; merge only after the branch's
  PR run is fully green.

---

## DEVOPS-004 — Universal Telemetry Hook Wiring (E-105)

**Date**: 2026-06-02
**Task**: E-105
**Status**: IN PROGRESS

### What is changing and why
`hooks/post-tool-use.sh` currently does AQG-only (re-runs `tests/run.sh`
when Write/Edit touches `src/**`). Per `.ai/blueprints/universal-telemetry.md`
§Components 2, it must also record every tool execution into
`~/.ai-os/telemetry.sqlite` via the new `telemetry.mjs --record-tool` CLI
shipped in E-104. Today telemetry sees ~1% of tool activity because only
`mcp-router::proxy_call` is instrumented (incident logged 2026-06-01,
signature `src/mcp/mcp-router/index.js:proxy_call_only_instrumentation`).

**Change**: append a backgrounded telemetry block to `post-tool-use.sh`.
The block translates Claude Code's PostToolUse JSON (`tool_name` + nested
`tool_response.isError` / `tool_response.duration_ms`) into the
blueprint's flat CLI schema and pipes it to
`telemetry.mjs --record-tool`. Spawned with `&` + `disown` + stderr/stdout
redirected to `/dev/null` so the hook returns within budget even when
telemetry is slow.

### Security implications
- **No new secrets.** No new network access. Helper writes only to
  `~/.ai-os/telemetry.sqlite` (already in scope per E-84).
- **No new permissions.** `node` invocation only; locator chain mirrors
  E-58 (`src/shared/telemetry.mjs` → `${HOME}/.ai-os/shared/telemetry.mjs`).
- **PII**: `telemetry.mjs` already hashes `project_root` (sha256, 12 hex)
  and the hook never forwards `tool_input`/`tool_response` payload bodies
  — only the three blueprint fields (`tool_name`, `execution_time_ms`,
  `status`).
- **Fail-open**: `AI_TELEMETRY_DISABLE=1` short-circuits the helper.
  Hook continues even if `node` is absent or the helper is missing.

### Pipeline order enforced
Hook-level change; CI pipeline order unchanged.
1. deps (`npm ci`)
2. install (`bash install-ai-os.sh`)
3. test (`bash tests/run.sh`)  ← telemetry_test.sh extended with hook-integration assertions
4. secret-gitignore check

### Execution constraints
- Hook overhead budget: **<50ms** (blueprint §Execution Constraints).
  Achieved by background detach — telemetry write happens off the hot path.
- AQG behavior preserved verbatim: telemetry block is appended AFTER the
  existing AQG logic, never replacing or short-circuiting it.

### Rollback plan
- **Per blueprint §Rollback**: revert `~/.ai-os/hooks/post-tool-use.sh` to
  the AQG-only version (`git checkout HEAD~1 -- hooks/post-tool-use.sh`
  then re-install).
- Set `AI_TELEMETRY_DISABLE=1` system-wide to pause data collection
  without touching the hook.
- The change is additive — the AQG block is byte-identical to its
  pre-E-105 form. Hook-level removal of the telemetry block restores the
  prior behavior.

### Branch strategy
- Local validation on `master`: run extended `tests/suites/telemetry_test.sh`
  + `tests/run.sh` to verify (a) hook-integration assertions pass and (b)
  AQG still locks on test failures unchanged. Hook overhead measured via
  `time` wrapper around a sample invocation.

---

---

## DEVOPS-005 — Make master green again + node:test job (E-230, D-060 §1)

**Date**: 2026-09-09
**Task**: E-230
**Status**: IN PROGRESS (validated on branch `engineer/e230-ci-green` via PR before master)

### Correction to the record

E-230's task text says "this repo has NO CI configuration". That is **false**, and so was
my own earlier statement to the same effect (repeated three times, including in commit
`1257fa6`). `.github/workflows/test.yml` has existed and run since at least 2026-08-04.
D-060 corrected me. Root cause of my error: `ls .github/workflows/` failed because `ls` is
aliased to `eza`, which rejected the trailing slash, and my `|| echo "(no …)"` fallback
printed the negative — I read a **tool error** as a **negative result**. The lesson is
recorded here because it caused three sprints to "verify on CI" against a CI nobody looked
at, while master was red.

### What is changing and why

Master has been RED since 2026-09-07 (first failure: the D-054 merge; last green:
2026-08-04, PR #35). Five suites failed. None of them was a product bug — all five were
defects in the tests or in test observability:

1. `meta_analyst`, `seo_manager`, `seo_content_generator` — asserted that
   `~/.ai-os/gemini/agents/*.md` is **byte-identical** to `src/`. It is not, by design:
   `strip_gemini_agent_fields` removes `disable-model-invocation`, `user-invocable` and
   `allowed-tools`, which Gemini CLI v0.37+ does not support. The assertion passed only on
   a developer machine whose `~/.ai-os` predated the strip. Replaced with
   "identical modulo the stripped keys" plus a check that the strip actually ran, so the
   weaker assertion cannot pass on an untransformed copy.
2. `pane_binding` E-208.08i — asserted `ls` exits **1** for a missing path. GNU coreutils
   exits **2**; BSD/macOS exits 1. The test encoded the mac value and had therefore never
   passed on Linux. Replaced with `compgen -G` (a bash builtin, same result everywhere)
   and the fixture was made hermetic: it previously globbed the shared system temp dir two
   levels up, where an unrelated suite's stray file could fail this **security** assertion
   or mask a real escape.
3. `propose_patch_apply` — failed with "0 passed, 1 failed" and **no output at all**, so it
   was undiagnosable from the CI log. Two masking defects: `tests/lib/mcp-client.sh` sent
   the MCP server's stderr to `DEVNULL`, and `extract_id`'s `grep` exited 1 under
   `set -euo pipefail`, killing the suite mid-assignment before any assertion could report
   the server's reply. Both fixed; the client now prints the server's stderr tail and the
   exit reason. The underlying Linux-only cause is not yet known and will be named by the
   next CI run rather than guessed at.

Additions per D-060 §1: a second job running the `node:test` unit layer with
`UNIT_COVERAGE=1`; `patch --version` printed in the log so the E-221 patch driver modes are
evidenced under GNU patch 2.7; the run log uploaded as an artifact; a README badge.

### Security implications

None. No new secrets, no new network access, no new permissions. The workflow keeps
`--ignore-scripts` on all installs. `actions/upload-artifact` publishes the test log, which
contains only test output — no credentials are echoed by the suite. Both jobs remain
read-only with respect to the repository and run under the default `GITHUB_TOKEN`.

### Rollback plan

Revert the workflow file to its previous revision; the second job is additive and can be
deleted independently of the fixes to the test suites. The test-suite corrections are
independent of the workflow and stand on their own. `git revert` of this branch's merge
restores the prior (red) state exactly.

### Branch-first validation

Per this gate, the change is NOT pushed to master directly. It goes to
`engineer/e230-ci-green` and is opened as a PR; `on: pull_request: branches: [master]`
runs the full workflow there. Master is only updated once that run is green.

---

## DEVOPS-006 — Playwright browsers out of the default install (E-235, D-061 §3)

**Date**: 2026-09-09
**Task**: E-235
**Status**: IN PROGRESS (validated on branch `engineer/e235-browsers-out-of-install` via PR)

### What is changing and why

`ai mcp-setup` ran `npx playwright install chromium` unconditionally, inside the path that
`install-ai-os.sh` — and therefore every user install and every CI run — depends on. It is
an unbounded ~150MB network fetch. On 2026-09-09 it ran for **over an hour** on a developer
machine without finishing.

The `|| true` that wrapped it gave no protection at all: the failure mode is **hanging**,
not erroring, and you cannot `|| true` your way out of a process that never returns. That
is the specific reason this needed a real change rather than better error handling.

Three parts:

1. The download leaves the default path. Opt in with `ai mcp-setup --browsers`, or
   `AI_OS_INSTALL_BROWSERS=1` to restore the old behaviour exactly.
2. When it does run, it is **bounded and visible** — a watchdog enforces
   `AI_OS_BROWSER_TIMEOUT` (default 600s) and progress is no longer swallowed by
   `tail -2`. `timeout(1)` is not present on macOS by default, so the limit is enforced
   with a watchdog rather than assumed: a timeout that silently is not applied is worse
   than none, because it is believed.
3. Missing browsers now fail FAST at first use with `[BROWSER_MISSING]` and the one command
   that fixes it, instead of Playwright's installation essay or a hang.

### CI

The workflow installs browsers in an **explicit, cached** step so the vibe suites still
run. Cached on the Playwright version from the lockfile, so it is a download once per
version rather than once per run. The step is `continue-on-error: false` — if browsers are
meant to be there, a failure to install them should be visible rather than surface later as
a puzzling suite failure.

### Security implications

None new. No new secrets, no new permissions. The change REDUCES what the default install
fetches from the network: the Playwright CDN is no longer contacted during `ai install`,
which is a strict reduction in install-time network surface and makes an air-gapped or
proxied install viable where it previously stalled.

### Rollback plan

`AI_OS_INSTALL_BROWSERS=1` restores the old install-time download. `ai mcp-setup
--browsers` performs it on demand. `AI_OS_SKIP_BROWSER_CHECK=1` bypasses the first-use
probe for an operator whose browser lives somewhere unusual. Reverting the workflow hunk
restores the previous CI behaviour independently of the CLI change.

### Branch-first validation

Per this gate, not pushed to master directly: the change goes up as a PR so
`on: pull_request` exercises the new cached browser step before master moves.
