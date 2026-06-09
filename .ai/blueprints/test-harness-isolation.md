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
