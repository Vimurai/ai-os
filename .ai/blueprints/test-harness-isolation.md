# Test Harness Isolation Blueprint

## Goal & Architecture
Ensures that the E2E test harness (`tests/run.sh`) no longer pollutes the git working tree by leaving `.mcp.json` modified. This isolates test configuration from production configuration.

## Core Concept
Use a dedicated configuration file (`.mcp.test.json`) for the test harness and point the tests to it, completely ignoring the production `.mcp.json`.

## Components
1. **Test Config Generator**: A script or setup step in `run.sh` that dynamically generates `.mcp.test.json` based on the current `.mcp.json` but with sandbox paths.
2. **Environment Overrides**: Modifying the test invocation environment to use `MCP_CONFIG_PATH=.mcp.test.json`.
3. **Cleanup Trap**: A bash trap that ensures the temporary test config is deleted and any temporary directories are removed upon test exit.

## Data Model
`mcp_config.json` schema remains identical, just saved to a separate ephemeral path during testing.

## API / Interface Contracts
- Environment variable `MCP_CONFIG_PATH` is respected by all MCP loaders.

## Security
No security impact. Test isolation prevents accidental production mutations.

## Execution Constraints
The teardown trap must execute regardless of whether the test exits successfully, fails, or is interrupted (SIGINT/SIGTERM).

## Rollback Plan
Revert the test harness changes to point back to the hardcoded `.mcp.json` modification logic if dynamic test config fails.

## E-## Task Breakdown
- **E-156**: Implement `.mcp.test.json` generation and isolated config loading in `tests/run.sh`.
- **E-157**: Add robust bash trap cleanup logic to remove test artifacts.

## Environment Dependence (D-061 §4, 2026-09-09)
Three tests in the D-059/D-060 sprint passed on a developer Mac and failed on CI: a mirror byte-identity check, an unpruned `node_modules` corpus scan, and an assertion that assumed an ambient tmux server. Rule: every assertion must state what it requires of the machine, and a requirement that is genuinely optional is expressed with `skip_unless_cmd` / `skip_unless_env` (a recorded SKIP, never a fabricated PASS or FAIL). The `ai-review` skill and the `critic_tests` agent ask the standing question "does this assertion depend on what the running machine happens to have?" on every test diff. → E-236.

## Performance Budgets Are Host-Relative (D-062 §2, 2026-09-09)
Absolute wall-clock budgets ("under 200ms") are true only on the reference machine: a bare `node` spawn alone costs ~197ms on some developer hosts while CI passes. Rule: every performance assertion names a same-host baseline measured in the same run; the absolute budget is enforced only when `CI=true`; elsewhere the assertion is `elapsed ≤ k × baseline + slack` (defaults k=2, slack=50ms, declared beside the budget); baseline and elapsed are printed every run so a failure carries its evidence; an absolute budget without a baseline is a `critic_tests` finding. This is the environment-dependence rule (§ above) extended from "what the machine has" to "how fast it is". Rollback `AI_OS_PERF_ABSOLUTE=1`.

## Leaked External State — the Third Environment Dependence (D-063 §2, 2026-09-09)
Three varieties now stand together: **what the machine has** (E-236: supply or skip), **how fast it is** (E-239: host-relative budgets whose baseline includes the assertion's own instrument — D-063 §1), and **what a previous run left behind** (this section). The `ai start` suites leaked 50 tmux servers on one machine because the socket name used `$$` and a FAILING assertion skipped the cleanup line — leaks happened only when something was already wrong. Rules: (1) register cleanup in an `EXIT` trap BEFORE creating external state; names from `mktemp` entropy, never `$$`; (2) `tests/run.sh` snapshots and diffs the known external-state kinds (test-prefixed tmux servers, sandbox-named processes, `.ai/` lock dirs, harness temp dirs), reports `LEAKED n <kind>` per suite, fails the run on CI, offers `--sweep` locally; it matches only by test prefix or sandbox name, never by age or count; (3) standing review question #3 in `critic_tests`/`ai-review`: "what does this test leave behind when an assertion fails halfway?". → E-240. Rollback `AI_OS_TEST_NO_SWEEP=1`.
