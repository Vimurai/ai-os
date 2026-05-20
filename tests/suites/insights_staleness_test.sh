#!/usr/bin/env bash
# insights_staleness_test.sh — Tests for E-86 insights-staleness.mjs probe
# and the ai-preflight Step 7 wiring per .ai/blueprints/meta-cognition.md
# §Components 4.
#
#   • Helper source contract: pure node:* imports, no shell-out, fail-open.
#   • Behavioural envelope: DISABLED / EMPTY / FRESH / STALE / UNAVAILABLE.
#   • Threshold of 200 new rows (DEFAULT_THRESHOLD) is the staleness trigger.
#   • AI_TELEMETRY_DISABLE=1 AND AI_INSIGHTS_STALENESS_DISABLE=1 both short-
#     circuit to status:DISABLED.
#   • ai-preflight SKILL.md Step 7 documents the locator chain, the verbatim
#     [INSIGHTS_STALE] block, and the rollback flag.
#   • Mirrors byte-identical to ~/.ai-os.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROBE="${REPO_ROOT}/src/shared/insights-staleness.mjs"
TELEMETRY="${REPO_ROOT}/src/shared/telemetry.mjs"
SKILL_SRC="${REPO_ROOT}/src/shared/skills/ai-preflight/SKILL.md"

echo "===== insights_staleness_test.sh ====="

# ── T-INS-S01: source contract ────────────────────────────────────────────────
echo ""
echo "  [T-INS-S01] insights-staleness.mjs source contract"

assert_status 0 "probe file exists"                  test -f "$PROBE"
assert_status 0 "exports checkInsightsStaleness"     \
  grep -qE 'export async function checkInsightsStaleness' "$PROBE"
assert_status 0 "exports DEFAULT_INSIGHTS_PATH"      \
  grep -qE 'export const DEFAULT_INSIGHTS_PATH'  "$PROBE"
assert_status 0 "exports DEFAULT_TELEMETRY_PATH"     \
  grep -qE 'export const DEFAULT_TELEMETRY_PATH' "$PROBE"
assert_status 0 "DEFAULT_THRESHOLD = 200"            \
  grep -qE 'DEFAULT_THRESHOLD = 200' "$PROBE"

# Both rollback flags must be recognised.
assert_status 0 "recognises AI_TELEMETRY_DISABLE"           grep -qE 'AI_TELEMETRY_DISABLE'           "$PROBE"
assert_status 0 "recognises AI_INSIGHTS_STALENESS_DISABLE"  grep -qE 'AI_INSIGHTS_STALENESS_DISABLE'  "$PROBE"

# Pure node:* — no shell-out.
assert_status 1 "no child_process / spawn / exec" \
  grep -qE 'child_process|spawnSync|spawn\(|execSync' "$PROBE"

# Locator chain mirrors E-58 / E-65 pattern.
assert_status 0 "locator chain references in-repo helper" \
  grep -qE 'telemetry\.mjs' "$PROBE"

# Five expected status values.
for st in FRESH STALE EMPTY DISABLED UNAVAILABLE; do
  assert_status 0 "status enum includes ${st}" \
    grep -qE "status: \"${st}\"" "$PROBE"
done

# Helper must never throw; CLI always exits 0.
assert_status 0 "CLI exits 0 unconditionally"        grep -qE 'process\.exit\(0\)' "$PROBE"

# ── T-INS-S02: AI_INSIGHTS_STALENESS_DISABLE=1 → DISABLED ─────────────────────
echo ""
echo "  [T-INS-S02] rollback flag short-circuits to DISABLED"

OUT="$(AI_INSIGHTS_STALENESS_DISABLE=1 node "$PROBE")"
assert_contains "AI_INSIGHTS_STALENESS_DISABLE→DISABLED" "\"status\":\"DISABLED\"" "$OUT"

OUT2="$(AI_TELEMETRY_DISABLE=1 node "$PROBE")"
assert_contains "AI_TELEMETRY_DISABLE→DISABLED"          "\"status\":\"DISABLED\"" "$OUT2"

# ── T-INS-S03: telemetry DB absent → EMPTY ────────────────────────────────────
echo ""
echo "  [T-INS-S03] telemetry absent → EMPTY"

SBOX="$(mktemp -d)"
OUT_EMPTY="$(node -e "
import('${PROBE}').then(async (m) => {
  const r = await m.checkInsightsStaleness({
    insights_path:  '${SBOX}/INSIGHTS.md',
    telemetry_path: '${SBOX}/telemetry.sqlite',
  });
  process.stdout.write(JSON.stringify(r));
});
")"
assert_contains "telemetry absent → EMPTY" "\"status\":\"EMPTY\"" "$OUT_EMPTY"

# ── T-INS-S04: telemetry present but < threshold → FRESH ──────────────────────
echo ""
echo "  [T-INS-S04] telemetry present, no INSIGHTS.md, < threshold → FRESH"

SBOX2="$(mktemp -d)"
DB="${SBOX2}/telemetry.sqlite"
# Write 5 rows — well under the 200 threshold.
node -e "
import('${TELEMETRY}').then(async (m) => {
  for (let i = 0; i < 5; i++) {
    m.recordToolExecution({
      project_root: '/p',
      session_id: 's-' + i,
      tool_name: 'srv.tool',
      execution_time_ms: 1,
      status: 'SUCCESS',
    }, { sync: true, db_path: '${DB}' });
  }
  m.resetTelemetryCache();
});
"

OUT_FRESH="$(node -e "
import('${PROBE}').then(async (m) => {
  const r = await m.checkInsightsStaleness({
    insights_path:  '${SBOX2}/INSIGHTS.md',
    telemetry_path: '${DB}',
  });
  process.stdout.write(JSON.stringify(r));
});
")"
assert_contains "< threshold → FRESH"            "\"status\":\"FRESH\""  "$OUT_FRESH"
assert_contains "total_rows reflects 5 writes"  "\"total_rows\":5"      "$OUT_FRESH"

# ── T-INS-S05: telemetry ≥ threshold + no INSIGHTS.md → STALE ─────────────────
echo ""
echo "  [T-INS-S05] telemetry ≥ threshold, no INSIGHTS.md → STALE"

SBOX3="$(mktemp -d)"
DB3="${SBOX3}/telemetry.sqlite"
# Lower threshold to 5 so we don't need 200 rows for the test.
OUT_STALE="$(node -e "
import('${TELEMETRY}').then(async (m) => {
  for (let i = 0; i < 6; i++) {
    m.recordToolExecution({
      project_root: '/p',
      session_id: 's-' + i,
      tool_name: 'srv.tool',
      execution_time_ms: 1,
      status: 'SUCCESS',
    }, { sync: true, db_path: '${DB3}' });
  }
  m.resetTelemetryCache();
}).then(async () => {
  const m = await import('${PROBE}');
  const r = await m.checkInsightsStaleness({
    insights_path:  '${SBOX3}/INSIGHTS.md',
    telemetry_path: '${DB3}',
    threshold: 5,
  });
  process.stdout.write(JSON.stringify(r));
});
")"
assert_contains "≥ threshold + no INSIGHTS → STALE" "\"status\":\"STALE\"" "$OUT_STALE"
assert_contains "reason names threshold"           "(>= 5)"               "$OUT_STALE"

# ── T-INS-S06: INSIGHTS.md exists, no new rows since mtime → FRESH ───────────
echo ""
echo "  [T-INS-S06] INSIGHTS.md fresher than telemetry → FRESH"

SBOX4="$(mktemp -d)"
DB4="${SBOX4}/telemetry.sqlite"
INSIGHTS4="${SBOX4}/INSIGHTS.md"
# Write rows, then create INSIGHTS.md and bump its mtime to "now" so no rows
# are newer than it.
OUT_AFTER="$(node -e "
import('${TELEMETRY}').then(async (m) => {
  for (let i = 0; i < 10; i++) {
    m.recordToolExecution({
      project_root: '/p',
      session_id: 's-' + i,
      tool_name: 'srv.tool',
      execution_time_ms: 1,
      status: 'SUCCESS',
    }, { sync: true, db_path: '${DB4}' });
  }
  m.resetTelemetryCache();
}).then(async () => {
  const fs = await import('node:fs');
  fs.writeFileSync('${INSIGHTS4}', '# INSIGHTS.md\\n');
  // Forward-date mtime by 1 hour so all telemetry rows pre-date it.
  const future = new Date(Date.now() + 3600 * 1000);
  fs.utimesSync('${INSIGHTS4}', future, future);
}).then(async () => {
  const m = await import('${PROBE}');
  const r = await m.checkInsightsStaleness({
    insights_path:  '${INSIGHTS4}',
    telemetry_path: '${DB4}',
    threshold: 1,
  });
  process.stdout.write(JSON.stringify(r));
});
")"
assert_contains "no new rows since INSIGHTS.md → FRESH" "\"status\":\"FRESH\""             "$OUT_AFTER"
assert_contains "new_rows_since_insights = 0"           "\"new_rows_since_insights\":0"    "$OUT_AFTER"

# ── T-INS-S07: INSIGHTS.md exists + rows added after mtime → STALE ────────────
echo ""
echo "  [T-INS-S07] INSIGHTS.md older than telemetry growth → STALE"

SBOX5="$(mktemp -d)"
DB5="${SBOX5}/telemetry.sqlite"
INSIGHTS5="${SBOX5}/INSIGHTS.md"
OUT_OLDER="$(node -e "
async function main() {
  const fs = await import('node:fs');
  // Step 1: pre-date INSIGHTS.md to 1 hour ago.
  fs.writeFileSync('${INSIGHTS5}', '# INSIGHTS.md (pre-existing)\\n');
  const past = new Date(Date.now() - 3600 * 1000);
  fs.utimesSync('${INSIGHTS5}', past, past);
  // Step 2: now record telemetry rows — they all post-date INSIGHTS.md.
  const t = await import('${TELEMETRY}');
  for (let i = 0; i < 8; i++) {
    t.recordToolExecution({
      project_root: '/p',
      session_id: 's-' + i,
      tool_name: 'srv.tool',
      execution_time_ms: 1,
      status: 'SUCCESS',
    }, { sync: true, db_path: '${DB5}' });
  }
  t.resetTelemetryCache();
  // Step 3: probe with threshold=5 so 8 new rows → STALE.
  const m = await import('${PROBE}');
  const r = await m.checkInsightsStaleness({
    insights_path:  '${INSIGHTS5}',
    telemetry_path: '${DB5}',
    threshold: 5,
  });
  process.stdout.write(JSON.stringify(r));
}
main();
")"
assert_contains "rows newer than mtime → STALE"      "\"status\":\"STALE\"" "$OUT_OLDER"
assert_contains "new_rows_since_insights >= 5"      "\"new_rows_since_insights\":8" "$OUT_OLDER"

# ── T-INS-S08: CLI emits envelope to stdout + exits 0 ─────────────────────────
echo ""
echo "  [T-INS-S08] CLI emits envelope to stdout + exits 0"

assert_status 0 "CLI exits 0 even with no telemetry" \
  bash -c "AI_INSIGHTS_STALENESS_DISABLE=1 node '$PROBE' >/dev/null"

OUT_CLI="$(node "$PROBE" 2>/dev/null)"
assert_contains "CLI emits JSON envelope" "\"status\":" "$OUT_CLI"

# --quiet suppresses stdout but still exits 0.
QUIET_OUT="$(node "$PROBE" --quiet 2>/dev/null)"
assert_status 0 "--quiet still exits 0" \
  bash -c "node '$PROBE' --quiet >/dev/null"
assert_status 0 "--quiet produces no stdout" \
  bash -c "[[ -z '$QUIET_OUT' ]]"

# ── T-INS-S09: ai-preflight Step 7 wiring ─────────────────────────────────────
echo ""
echo "  [T-INS-S09] ai-preflight Step 7 documents the staleness check"

assert_status 0 "Step 7 heading present"               \
  grep -qE '^### 7\. INSIGHTS\.md Staleness Check' "$SKILL_SRC"
assert_status 0 "Step 7 names E-86"                    grep -q  'E-86' "$SKILL_SRC"
assert_status 0 "Step 7 references blueprint"          \
  grep -qE 'meta-cognition' "$SKILL_SRC"
assert_status 0 "Step 7 names locator chain (in-repo)" \
  grep -qE 'src/shared/insights-staleness\.mjs' "$SKILL_SRC"
assert_status 0 "Step 7 names locator chain (installed)" \
  grep -qE '\.ai-os/shared/insights-staleness\.mjs' "$SKILL_SRC"
assert_status 0 "Step 7 documents AI_INSIGHTS_STALENESS_DISABLE" \
  grep -qE 'AI_INSIGHTS_STALENESS_DISABLE' "$SKILL_SRC"
assert_status 0 "Step 7 emits [INSIGHTS_STALE] block"  \
  grep -qE '\[INSIGHTS_STALE\]' "$SKILL_SRC"
assert_status 0 "Step 7 prompts skill: ai-insights"    \
  grep -qE 'skill: \`?ai-insights\`?' "$SKILL_SRC"
assert_status 0 "Step 7 acknowledges other-status silence" \
  grep -qE 'FRESH.*EMPTY.*DISABLED.*UNAVAILABLE' "$SKILL_SRC"

# ── T-INS-S10: mirrors byte-identical ─────────────────────────────────────────
echo ""
echo "  [T-INS-S10] ~/.ai-os mirrors byte-identical"

assert_status 0 "insights-staleness.mjs mirror"   diff -q "$PROBE"   "${HOME}/.ai-os/shared/insights-staleness.mjs"
assert_status 0 "ai-preflight SKILL.md mirror"    diff -q "$SKILL_SRC" "${HOME}/.ai-os/shared/skills/ai-preflight/SKILL.md"
assert_status 0 "ai-preflight .claude mirror"     diff -q "$SKILL_SRC" "${REPO_ROOT}/.claude/skills/ai-preflight/SKILL.md"
assert_status 0 "ai-preflight .gemini mirror"     diff -q "$SKILL_SRC" "${REPO_ROOT}/.gemini/skills/ai-preflight/SKILL.md"

echo ""
assert_summary
echo "===== insights_staleness_test.sh PASS ====="
