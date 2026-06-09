#!/usr/bin/env bash
# task_velocity_aggregator_test.sh — E-155 (telemetry-hardening.md §Components 3)
# Verifies the task_velocity aggregator records reliably at task completion:
#   - telemetry.mjs exports recordTaskVelocityForTask
#   - task-synchronizer-mcp wires it into the DONE transition
#   - it aggregates per-task token usage and ALWAYS writes a row (0/0 when none)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TELEMETRY="${REPO_ROOT}/src/shared/telemetry.mjs"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: task_velocity_aggregator ──────────────────────────────────"

# ── Static wiring ─────────────────────────────────────────────────────────────
assert_contains "telemetry.mjs exports recordTaskVelocityForTask" \
  "export function recordTaskVelocityForTask" "$(cat "$TELEMETRY")"
sync_body="$(cat "$SYNC_MCP")"
assert_contains "task-synchronizer imports recordTaskVelocityForTask" \
  "recordTaskVelocityForTask" "$sync_body"
assert_contains "task-synchronizer calls aggregator in DONE path" \
  "recordTaskVelocityForTask({ task_id: args.id })" "$sync_body"

# ── Functional: aggregation + reliable write ──────────────────────────────────
out=$(node --input-type=module -e '
import { DatabaseSync } from "node:sqlite";
import { recordTaskVelocityForTask } from "'"${TELEMETRY}"'";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "e155t-"));
const usage = join(dir, "usage.sqlite");
const tele  = join(dir, "telemetry.sqlite");

const u = new DatabaseSync(usage);
u.exec("CREATE TABLE usage (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, model TEXT, tokens INTEGER NOT NULL DEFAULT 0, usd REAL, recorded_at TEXT)");
u.prepare("INSERT INTO usage(task_id,tokens) VALUES (?,?)").run("E-AGG", 120);
u.prepare("INSERT INTO usage(task_id,tokens) VALUES (?,?)").run("E-AGG", 380);
u.close();

recordTaskVelocityForTask({ task_id: "E-AGG" },  { usage_db_path: usage, db_path: tele, sync: true });
recordTaskVelocityForTask({ task_id: "E-ZERO" }, { usage_db_path: usage, db_path: tele, sync: true });

const t = new DatabaseSync(tele, { readOnly: true });
const a = t.prepare("SELECT turn_count, tokens_consumed FROM task_velocity WHERE task_id=?").get("E-AGG");
const z = t.prepare("SELECT turn_count, tokens_consumed FROM task_velocity WHERE task_id=?").get("E-ZERO");
t.close();
console.log("AGG=" + (a ? a.turn_count + "/" + a.tokens_consumed : "none"));
console.log("ZERO=" + (z ? z.turn_count + "/" + z.tokens_consumed : "none"));
' 2>&1)

assert_contains "aggregates turns + tokens for a task with usage" "AGG=2/500" "$out"
assert_contains "writes a row even with no usage (reliable at completion)" "ZERO=0/0" "$out"

assert_summary
