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
P9=""; P10=""; P11=""   # E-204 auto-handoff fixtures (created in T-09)
trap 'rm -rf "$PROJ" "$P9" "$P10" "$P11"' EXIT
mkdir -p "${PROJ}/.ai"
cp "$TEMPLATE" "${PROJ}/.ai/state.json"

# Run the helper from inside the project (it resolves .ai via cwd walk-up).
# Usage: run_add <ROLE> <args...>  → echoes stdout (the created id); stderr suppressed.
# AI_OS_NO_AUTO_HANDOFF=1 isolates T-01..T-08 from the E-204 auto-handoff side effect
# (exercised explicitly in T-09) so they never touch signal.json.
run_add() {
  local role="$1"; shift
  ( cd "$PROJ" && AI_OS_CALLER_ROLE="$role" AI_OS_NO_AUTO_HANDOFF=1 node "$HELPER" "$@" 2>/dev/null )
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

# ── T-09: E-204 auto-handoff on cross-role task creation ─────────────────────
echo ""; echo "  [T-09] E-204 auto-handoff"

# Unit: autoHandoffTarget() pure logic — target from prefix, gated on creator role.
aht() { # <prefix> <callerRole> → target role or 'null'
  node --input-type=module -e "
import { autoHandoffTarget } from '${HELPER}';
process.stdout.write(String(autoHandoffTarget({ prefix: process.argv[1], callerRole: process.argv[2] }) ?? 'null'));
" "$1" "$2" 2>/dev/null
}
t="$(aht E architect)"; assert_status 0 "T-09.01: architect + E → engineer"        test "engineer"  = "$t"
t="$(aht E engineer)";  assert_status 0 "T-09.02: engineer + E → null (own work)"   test "null"      = "$t"
t="$(aht P engineer)";  assert_status 0 "T-09.03: engineer + P → architect"         test "architect" = "$t"
t="$(aht P architect)"; assert_status 0 "T-09.04: architect + P → null (own work)"  test "null"      = "$t"
t="$(aht X architect)"; assert_status 0 "T-09.05: unknown prefix → null"            test "null"      = "$t"

# Count UNDELIVERED handoffs for a target in a project's signal.json (0 if absent).
undelivered() { # <projdir> <target>
  node --input-type=module -e "
import { readFileSync, existsSync } from 'node:fs';
const p = process.argv[1] + '/.ai/signal.json';
if (!existsSync(p)) { process.stdout.write('0'); }
else { const raw = JSON.parse(readFileSync(p,'utf8')); const q = Array.isArray(raw) ? raw : [raw];
  process.stdout.write(String(q.filter(e => e && e.target === process.argv[2] && e.delivered !== true).length)); }
" "$1" "$2" 2>/dev/null
}
seed_proj() { local d; d="$(mktemp -d)"; mkdir -p "${d}/.ai"; cp "$TEMPLATE" "${d}/.ai/state.json"; printf '%s' "$d"; }

# Behavioral: architect creating an E-## auto-wakes the engineer (one undelivered signal).
P9="$(seed_proj)"
( cd "$P9" && AI_OS_CALLER_ROLE=architect node "$HELPER" "Cross-role task 1" >/dev/null 2>&1 )
c="$(undelivered "$P9" engineer)"; assert_status 0 "T-09.06: architect+E emits 1 engineer handoff" test "1" = "$c"

# Dedup: a second cross-role create coalesces into the still-pending signal (stays 1).
( cd "$P9" && AI_OS_CALLER_ROLE=architect node "$HELPER" "Cross-role task 2" >/dev/null 2>&1 )
c="$(undelivered "$P9" engineer)"; assert_status 0 "T-09.07: second create deduped (still 1)" test "1" = "$c"

# Opt-out: AI_OS_NO_AUTO_HANDOFF=1 suppresses the handoff entirely.
P10="$(seed_proj)"
( cd "$P10" && AI_OS_CALLER_ROLE=architect AI_OS_NO_AUTO_HANDOFF=1 node "$HELPER" "Disabled task" >/dev/null 2>&1 )
c="$(undelivered "$P10" engineer)"; assert_status 0 "T-09.08: AI_OS_NO_AUTO_HANDOFF=1 emits nothing" test "0" = "$c"

# Same-role: engineer queuing its own E-## does NOT self-handoff.
P11="$(seed_proj)"
( cd "$P11" && AI_OS_CALLER_ROLE=engineer node "$HELPER" "Own task" >/dev/null 2>&1 )
c="$(undelivered "$P11" engineer)"; assert_status 0 "T-09.09: engineer+E (own work) emits nothing" test "0" = "$c"

assert_summary
