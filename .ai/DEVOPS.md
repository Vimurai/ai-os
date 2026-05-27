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
