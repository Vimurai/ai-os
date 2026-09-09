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
