# Robustness Phase 7: Resilience & observability (2026-04-13)

## 1. Non-Destructive Preflight (High)

### The Problem
`orchestrator-mcp` currently marks implementation deltas as `read = 1` immediately upon returning them in `run_preflight`. If the Architect (Gemini) crashes or the session is interrupted before the Architect can process these deltas, the information is lost from future preflights.

### The Solution: Explicit Delta Acknowledgment
Implementation deltas should remain `unread` until the Architect explicitly acknowledges them.
- **Logic**: Remove the `UPDATE deltas SET read = 1` from `run_preflight`.
- **Tooling**: Add a new tool `mark_deltas_read(task_ids[])` to `task-synchronizer-mcp` (or `orchestrator-mcp`).
- **Workflow**: The Architect must call this tool after incorporating deltas into the blueprint.

## 2. Multi-Route Vibe Fault Tolerance (High)

### The Problem
In `vibe-check-mcp`, the `run_vibe_audit` loop lacks an inner `try...catch`. If a single route fails to load (e.g., 404 or timeout), the entire audit crashes, and no report is generated for the successful routes.

### The Solution: Per-Route Isolation
Wrap the navigation and evaluation logic for each route in a `try...catch`.
- **Logic**: If a route fails, record a `FAULT` status for that route and continue to the next.
- **Reporting**: Include the error message in the final VIBE_REPORT.

## 3. Token Spend Observability (Medium)

### The Problem
`token-budget-mcp` provides infrastructure for cost tracking, but nothing in the framework actually calls `report_cost`. Token usage remains untracked.

### The Solution: Hook Integration
Add a basic estimation or reporting mechanism.
- **Logic**: Update `stop-hook.sh` to optionally accept token counts from the CLI (if supported) or add a directive to agent personas to call `report_cost` at the end of Tier 2/3 tasks using the usage data provided by the LLM response.

## 4. Command Obfuscation Resistance (Medium)

### The Problem
`safe-exec-mcp` secret detection is bypassed by simple obfuscation (e.g., `token="sec""ret"`).

### The Solution: Normalized Secret Scanning
Implement a basic normalization step before regex matching.
- **Logic**: Strip quotes and basic escape characters from the command string before running the `SECRET_IN_COMMAND` check.

---

## Strategic Tasks (P-##)

- [ ] **P-38: Implement explicit delta acknowledgment in `orchestrator-mcp`.**
  - Stop marking deltas as read automatically during preflight.
  - Add `mark_deltas_read` tool to transition delta status.
- [ ] **P-39: Harden `run_vibe_audit` loop against single-route failures.**
  - Add inner `try...catch` to ensure one down route doesn't kill the whole audit.
- [ ] **P-40: Integrate `report_cost` into the Triad workflow.**
  - Add instructions to `security_engineer` and `devops_engineer` to report usage.
- [ ] **P-41: Add normalization to `safe-exec-mcp` for obfuscation resistance.**
  - Pre-process command strings to strip common obfuscation characters.
- [ ] **P-42: Fix `mkdirSync` race in `token-budget-mcp`.**
  - Add `recursive: true` and handle potential `EEXIST` or `ENOENT` during concurrent startup.