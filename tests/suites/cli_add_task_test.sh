#!/usr/bin/env bash
# cli_add_task_test.sh — Unit + behavioral tests for the shell-native `ai add-task`
# (E-198, Architect Ruling A / pending D-053). Verifies the CLI persists tasks through
# the SAME shared state-db::addTask as task-synchronizer-mcp::add_task (single source of
# truth), stamps caller_role → owner, and that rows survive verify_markdown_sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${REPO_ROOT}/src/shared/cli-add-task.mjs"
STATE_DB="${REPO_ROOT}/src/mcp/shared/state-db.js"
BIN_AI="${REPO_ROOT}/src/bin/ai"
TEMPLATE="${REPO_ROOT}/src/templates/state.json"

echo "── Suite: cli_add_task (E-198) ────────────────────────────────────"

# Fresh temp project with a state.json seed (getDb builds state.sqlite from it).
PROJ="$(mktemp -d)"
trap 'rm -rf "$PROJ"' EXIT
mkdir -p "${PROJ}/.ai"
cp "$TEMPLATE" "${PROJ}/.ai/state.json"

# Run the helper from inside the project (it resolves .ai via cwd walk-up).
# Usage: run_add <ROLE> <args...>  → echoes stdout (the created id); stderr suppressed.
run_add() {
  local role="$1"; shift
  ( cd "$PROJ" && AI_OS_CALLER_ROLE="$role" node "$HELPER" "$@" 2>/dev/null )
}
task_field() { # <id> <col>
  node --input-type=module -e "
import { getDb } from '${STATE_DB}';
const r = getDb('${PROJ}/.ai').prepare('SELECT * FROM tasks WHERE id = ?').get(process.argv[1]);
process.stdout.write(r ? String(r[process.argv[2]] ?? '') : '__MISSING__');
" "$1" "$2" 2>/dev/null
}

# ── T-01: file structure + syntax ────────────────────────────────────────────
echo ""; echo "  [T-01] Structure"
assert_status 0 "cli-add-task.mjs exists" test -f "$HELPER"
assert_status 0 "helper parses as ESM" node -e "import('file://${HELPER}').catch(e=>{if(e instanceof SyntaxError)process.exit(1)})"

# ── T-02: wired into bin/ai dispatch ─────────────────────────────────────────
echo ""; echo "  [T-02] CLI wiring"
assert_status 0 "bin/ai has add-task dispatch case" grep -qE '^\s*add-task\)\s+do_add_task' "$BIN_AI"
assert_status 0 "bin/ai defines do_add_task" grep -q 'do_add_task()' "$BIN_AI"

# ── T-03: single-source write path (no divergence from the MCP) ──────────────
echo ""; echo "  [T-03] Shared addTask (DRY with MCP)"
assert_status 0 "state-db.js exports addTask" grep -qE '^export function addTask' "$STATE_DB"
assert_status 0 "task-synchronizer-mcp imports the shared addTask" \
  grep -q 'addTask as _addTask' "${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
assert_status 0 "helper routes through the shared addTask" \
  grep -q "import { getDb, addTask } from" "$HELPER"

# ── T-04: functional create + caller_role stamping ───────────────────────────
echo ""; echo "  [T-04] Create + caller_role → owner"
id_arch="$(run_add architect --tier 2 "Architect created task")"
assert_contains "T-04.01: returns an E-id on stdout" "E-" "$id_arch"
assert_contains "T-04.02: architect role → owner 'Architect (Agy)'" "Architect (Agy)" "$(task_field "$id_arch" owner)"
assert_contains "T-04.03: status OPEN (no deps)" "OPEN" "$(task_field "$id_arch" status)"
assert_contains "T-04.04: tier persisted" "2" "$(task_field "$id_arch" tier)"

id_eng="$(run_add engineer "Engineer created task")"
assert_contains "T-04.05: engineer role → owner 'Engineer (Claude)'" "Engineer (Claude)" "$(task_field "$id_eng" owner)"

# explicit --owner overrides the role mapping
id_own="$(run_add architect --owner "Tester (TestSprite)" "Explicit owner task")"
assert_contains "T-04.06: explicit --owner wins over role" "Tester (TestSprite)" "$(task_field "$id_own" owner)"

# ── T-05: survives verify_markdown_sync (row is in the regenerated view) ─────
echo ""; echo "  [T-05] Regenerated views"
assert_status 0 "T-05.01: TASKS.md regenerated with the new task" \
  grep -q "Architect created task" "${PROJ}/.ai/TASKS.md"
assert_status 0 "T-05.02: state.json view holds the new task" \
  grep -q "Engineer created task" "${PROJ}/.ai/state.json"

# ── T-06: DAG — depends_on unmet → BLOCKED ───────────────────────────────────
echo ""; echo "  [T-06] Dependencies"
id_dep="$(run_add engineer --depends-on "${id_arch}" "Blocked-by-dep task")"
assert_contains "T-06.01: unmet dependency → BLOCKED" "BLOCKED" "$(task_field "$id_dep" status)"

# ── T-07: prefix + input validation ──────────────────────────────────────────
echo ""; echo "  [T-07] Prefix + validation"
id_p="$(run_add architect --prefix P "Architect plan task")"
assert_contains "T-07.01: --prefix P → P-id" "P-" "$id_p"
assert_status 2 "T-07.02: empty description → usage exit 2" \
  bash -c "cd '$PROJ' && AI_OS_CALLER_ROLE=engineer node '$HELPER' --tier 1 2>/dev/null"

# ── T-08: stdout purity (only the id on stdout; noise → stderr) ──────────────
echo ""; echo "  [T-08] stdout purity"
out="$(run_add engineer "Purity check task")"
assert_status 0 "T-08.01: stdout is a single bare id line" \
  bash -c "printf '%s' '$out' | grep -qxE 'E-[0-9]+'"

assert_summary
