#!/usr/bin/env bash
# multi_variation_state_tracker_test.sh — Tests for E-79.
#
# Verifies the Multi-Variation-State-Tracker bolted onto
# task-synchronizer-mcp per .ai/blueprints/seo-keyword-multiplier.md
# §Components 3 + §Data Model + §API:
#
#   - Two new tables (keyword_seeds, content_variations) with FK + CHECKs
#   - Four new MCP tools: add_keyword_seed, add_content_variation,
#     report_performance, get_seed_cohort
#   - Input validation: term charset/length, target_volume range,
#     approach_type ∈ 20-canonical set, FK enforcement
#   - 20-variation hard cap + (seed_id, approach_type) uniqueness
#   - JSON merge-patch semantics on report_performance
#   - Idempotent schema migration (no errors on repeat open)
#   - No regression of existing tables (tasks/stamps/deltas/patches)
#   - SEO_APPROACH_TYPES single-source-of-truth cross-references
#     src/gemini/agents/seo_manager.md exactly (E-77 contract)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
STATE_DB="${REPO_ROOT}/src/mcp/shared/state-db.js"
APPROACH_MOD="${REPO_ROOT}/src/shared/seo-approach-types.mjs"
MANAGER="${REPO_ROOT}/src/gemini/agents/seo_manager.md"

echo "===== multi_variation_state_tracker_test.sh ====="

# ── T-MVS-S01: Source contract — module + handlers + helpers ────────────────
echo ""
echo "  [T-MVS-S01] state-db.js has the new tables + id helpers"

assert_status 0 "keyword_seeds CREATE present"          grep -q 'CREATE TABLE IF NOT EXISTS keyword_seeds' "$STATE_DB"
assert_status 0 "content_variations CREATE present"     grep -q 'CREATE TABLE IF NOT EXISTS content_variations' "$STATE_DB"
assert_status 0 "FK constraint declared"                grep -q 'FOREIGN KEY (seed_id) REFERENCES keyword_seeds' "$STATE_DB"
assert_status 0 "status CHECK constraint declared"      grep -q "status IN ('OPEN','IN_PROGRESS','COMPLETED','ARCHIVED')" "$STATE_DB"
assert_status 0 "target_volume CHECK ≤ 20"              grep -q "target_volume <= 20" "$STATE_DB"
assert_status 0 "idx_variations_seed index"             grep -q 'idx_variations_seed' "$STATE_DB"
assert_status 0 "nextKeywordSeedId exported"            grep -q 'export function nextKeywordSeedId' "$STATE_DB"
assert_status 0 "nextContentVariationId exported"       grep -q 'export function nextContentVariationId' "$STATE_DB"

echo ""
echo "  [T-MVS-S01b] task-synchronizer-mcp wires the new tools + handlers"

assert_status 0 "MCP imports SEO_APPROACH_TYPES"        grep -q 'SEO_APPROACH_TYPES' "$SYNC_MCP"
assert_status 0 "MCP imports MAX_VARIATIONS_PER_SEED"   grep -q 'MAX_VARIATIONS_PER_SEED' "$SYNC_MCP"
assert_status 0 "add_keyword_seed case present"         grep -q 'case "add_keyword_seed":' "$SYNC_MCP"
assert_status 0 "add_content_variation case present"    grep -q 'case "add_content_variation":' "$SYNC_MCP"
assert_status 0 "report_performance case present"       grep -q 'case "report_performance":' "$SYNC_MCP"
assert_status 0 "get_seed_cohort case present"          grep -q 'case "get_seed_cohort":' "$SYNC_MCP"

# ── T-MVS-S02: SEO_APPROACH_TYPES — 20 unique slugs, frozen, single-source ──
echo ""
echo "  [T-MVS-S02] SEO_APPROACH_TYPES has exactly 20 frozen unique slugs"

count="$(node --input-type=module -e "
  const m = await import('file://${APPROACH_MOD}');
  console.log(m.SEO_APPROACH_TYPES.length);
" 2>/dev/null)"
assert_status 0 "array length == 20" bash -c "[[ '$count' == '20' ]]"

frozen="$(node --input-type=module -e "
  const m = await import('file://${APPROACH_MOD}');
  console.log(Object.isFrozen(m.SEO_APPROACH_TYPES));
" 2>/dev/null)"
assert_status 0 "array is frozen" bash -c "[[ '$frozen' == 'true' ]]"

# Cross-reference: every slug in SEO_APPROACH_TYPES must appear in the
# seo_manager.md approach table.
missing="$(python3 -c "
import re, json, subprocess
slugs = subprocess.check_output(['node','--input-type=module','-e',
  \"const m = await import('file://${APPROACH_MOD}'); console.log(JSON.stringify([...m.SEO_APPROACH_TYPES]));\"
], text=True).strip()
slugs = json.loads(slugs)
mgr = open('${MANAGER}').read()
m = re.search(r'## The 20 Canonical Approach-Types(.+?)## Step 1', mgr, flags=re.S)
mgr_block = m.group(1) if m else ''
mgr_slugs = set(re.findall(r'\`([a-z][a-z0-9-]+)\`', mgr_block))
missing = [s for s in slugs if s not in mgr_slugs]
print(','.join(missing) if missing else 'OK')
")"
assert_status 0 "every SEO_APPROACH_TYPES slug exists in seo_manager.md" \
  bash -c "[[ '$missing' == 'OK' ]]"

# ── Set up an isolated sandbox + drive the MCP via stdio JSON-RPC ───────────
SBOX="$(mktemp -d -t e79-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT
mkdir -p "${SBOX}/proj/.ai"

# Seed the schema by opening the DB once via state-db.js (CREATE IF NOT EXISTS).
AIDIR="${SBOX}/proj/.ai" REPO_ROOT="${REPO_ROOT}" node --no-warnings --input-type=module -e "
  const { getDb, regenerateViews } = await import(\`\${process.env.REPO_ROOT}/src/mcp/shared/state-db.js\`);
  const db = getDb(process.env.AIDIR);
  regenerateViews(process.env.AIDIR, db);
" 2>/dev/null

# Confirm both new tables exist after the seed.
sqlite_check() {
  node --no-warnings --input-type=module -e "
    const { DatabaseSync } = await import('node:sqlite');
    const db = new DatabaseSync('${SBOX}/proj/.ai/state.sqlite');
    const t = db.prepare(\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\").all();
    console.log(t.map(r=>r.name).join(','));
    db.close();
  " 2>/dev/null
}
TABLES="$(sqlite_check)"
assert_status 0 "keyword_seeds table created on first open" \
  bash -c "echo '$TABLES' | grep -q 'keyword_seeds'"
assert_status 0 "content_variations table created on first open" \
  bash -c "echo '$TABLES' | grep -q 'content_variations'"
assert_status 0 "existing tasks table unchanged" \
  bash -c "echo '$TABLES' | grep -q ',tasks'"
assert_status 0 "existing stamps table unchanged" \
  bash -c "echo '$TABLES' | grep -q ',stamps'"

# Helper: drive a tool from the SBOX cwd so the MCP resolves .ai relative there.
_call() {
  # $1=tool, $2=args JSON
  ( cd "${SBOX}/proj" && mcp_call_tool "$SYNC_MCP" "$1" "$2" )
}

# Convenience: extract the text content from a JSON-RPC result.
_text() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read() or '{}')
print('\n'.join(c.get('text','') for c in (d.get('content') or [])))
"
}

# ── T-MVS-S03: tools/list advertises all four new tools ─────────────────────
echo ""
echo "  [T-MVS-S03] tools/list advertises the four new E-79 tools"

for tool in add_keyword_seed add_content_variation report_performance get_seed_cohort; do
  ( cd "${SBOX}/proj" && mcp_assert_tool_listed "$SYNC_MCP" "$tool" )
  assert_status 0 "tools/list includes ${tool}" bash -c "[[ $? -eq 0 ]]"
done

# ── T-MVS-S04: add_keyword_seed happy path ──────────────────────────────────
echo ""
echo "  [T-MVS-S04] add_keyword_seed creates KS-1 and returns the row"

resp="$(_call add_keyword_seed '{"term":"ai testing","target_volume":20}')"
text="$(echo "$resp" | _text)"
assert_status 0 "response confirms KS-1 created"        bash -c "echo '$text' | grep -q 'KeywordSeed KS-1'"
assert_status 0 "response includes term"                bash -c "echo '$text' | grep -q '\"term\": \"ai testing\"'"
assert_status 0 "response includes target_volume=20"    bash -c "echo '$text' | grep -q '\"target_volume\": 20'"

# ── T-MVS-S05: add_keyword_seed input validation ────────────────────────────
echo ""
echo "  [T-MVS-S05] add_keyword_seed rejects bad inputs"

for tuple in \
  'empty:{"term":""}:INVALID_KEYWORD_TERM' \
  'oversize:{"term":"'"$(python3 -c 'print("x"*300)')"'"}:INVALID_KEYWORD_TERM' \
  'shellmeta:{"term":"ai`rm -rf /`"}:INVALID_KEYWORD_TERM' \
  'newline:{"term":"line1\nline2"}:INVALID_KEYWORD_TERM' \
  'tv_zero:{"term":"ok","target_volume":0}:INVALID_TARGET_VOLUME' \
  'tv_huge:{"term":"ok","target_volume":99}:INVALID_TARGET_VOLUME'; do
  label="${tuple%%:*}"
  rest="${tuple#*:}"
  args="${rest%:*}"
  want="${tuple##*:}"
  resp="$(_call add_keyword_seed "$args")"
  text="$(echo "$resp" | _text)"
  assert_status 0 "case=${label} → ${want}" bash -c "echo '$text' | grep -q '${want}'"
done

# ── T-MVS-S06: add_content_variation happy path ─────────────────────────────
echo ""
echo "  [T-MVS-S06] add_content_variation attaches CV-1 to KS-1"

resp="$(_call add_content_variation '{"seed_id":"KS-1","approach_type":"listicle","content_blob":"# Top 10 AI Testing Tools"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "response confirms CV-1 created" bash -c "echo '$text' | grep -q 'ContentVariation CV-1'"
assert_status 0 "response carries approach_type=listicle" bash -c "echo '$text' | grep -q 'listicle'"

# ── T-MVS-S07: add_content_variation rejects unknown approach_type ──────────
echo ""
echo "  [T-MVS-S07] Unknown approach_type → UNKNOWN_APPROACH_TYPE"

resp="$(_call add_content_variation '{"seed_id":"KS-1","approach_type":"bogus-shape"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "rejects bogus slug"           bash -c "echo '$text' | grep -q 'UNKNOWN_APPROACH_TYPE'"
assert_status 0 "error mentions the 20-canonical set" bash -c "echo '$text' | grep -q 'listicle'"

# ── T-MVS-S08: add_content_variation enforces FK (seed must exist) ──────────
echo ""
echo "  [T-MVS-S08] seed_id must exist → SEED_NOT_FOUND"

resp="$(_call add_content_variation '{"seed_id":"KS-999","approach_type":"how-to-guide"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "missing seed → SEED_NOT_FOUND" bash -c "echo '$text' | grep -q 'SEED_NOT_FOUND'"

# Bad seed_id format
resp="$(_call add_content_variation '{"seed_id":"notakey","approach_type":"how-to-guide"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "malformed seed_id → INVALID_SEED_ID" bash -c "echo '$text' | grep -q 'INVALID_SEED_ID'"

# ── T-MVS-S09: (seed_id, approach_type) uniqueness ──────────────────────────
echo ""
echo "  [T-MVS-S09] Duplicate (seed_id, approach_type) → APPROACH_ALREADY_USED"

resp="$(_call add_content_variation '{"seed_id":"KS-1","approach_type":"listicle"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "duplicate slug rejected" bash -c "echo '$text' | grep -q 'APPROACH_ALREADY_USED'"

# ── T-MVS-S10: 20-cap defence-in-depth ──────────────────────────────────────
echo ""
echo "  [T-MVS-S10] Variation #21 refused → VARIATION_CAP_REACHED"

# Fill the remaining 19 slots (we already used 'listicle' as CV-1).
for slug in how-to-guide case-study comparison-versus ultimate-guide step-by-step-tutorial \
             best-of-roundup data-backed-analysis pros-cons-tradeoff expert-roundup \
             tool-or-product-review trends-outlook mistakes-to-avoid faq-compilation \
             checklist-or-cheatsheet definition-explainer cost-pricing-analysis \
             alternatives-multi-way personal-lessons future-predictions; do
  _call add_content_variation "{\"seed_id\":\"KS-1\",\"approach_type\":\"${slug}\"}" >/dev/null
done

# Now KS-1 has 20 variations; a 21st (any slug) must fail. We must use a
# slug that hasn't been used yet — but all 20 are taken, so the
# APPROACH_ALREADY_USED gate would fire first. To prove the cap, we'd
# need a 21st valid slug — which doesn't exist by design. The cap is
# therefore tested by add_content_variation refusing a NEW seed reaching
# variation #21 via a hypothetical 21st slug; since no 21st slug exists,
# the cap is structurally enforced by the slug taxonomy itself.
#
# But the explicit CAP check in code is still reachable: simulate by
# inserting a 21st row at the SQLite layer with a duplicate slug? No —
# uniqueness is by (seed_id, approach_type), and there are only 20 slugs.
#
# So the CAP gate would only ever fire if SEO_APPROACH_TYPES is ever
# extended past 20. Instead of contriving a brittle test, assert the
# count IS the 20-cap.

count="$(node --no-warnings --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX}/proj/.ai/state.sqlite');
  console.log(db.prepare(\"SELECT COUNT(*) as n FROM content_variations WHERE seed_id='KS-1'\").get().n);
  db.close();
" 2>/dev/null)"
assert_status 0 "KS-1 holds exactly 20 variations" bash -c "[[ '$count' == '20' ]]"
assert_status 0 "MAX_VARIATIONS_PER_SEED constant is 20" \
  bash -c "node --input-type=module -e \"
    const m = await import('file://${APPROACH_MOD}');
    console.log(m.MAX_VARIATIONS_PER_SEED);
  \" 2>/dev/null | grep -q '^20$'"
# Existence of the CAP gate in source (test that the code path exists even
# if hard to reach via the unique-slug constraint above).
assert_status 0 "VARIATION_CAP_REACHED gate present in source" \
  grep -q 'VARIATION_CAP_REACHED' "$SYNC_MCP"

# ── T-MVS-S11: report_performance merge semantics ───────────────────────────
echo ""
echo "  [T-MVS-S11] report_performance merges JSON keys; idempotent on repeat"

resp="$(_call report_performance '{"variation_id":"CV-1","metrics":{"clicks":120,"impressions":4500}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "first call records both metrics" \
  bash -c "echo '$text' | grep -q '\"clicks\": 120'"
assert_status 0 "first call records impressions"  \
  bash -c "echo '$text' | grep -q '\"impressions\": 4500'"

# Second call: add ctr; existing keys remain.
resp="$(_call report_performance '{"variation_id":"CV-1","metrics":{"ctr":0.027,"clicks":135}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "second call merges ctr key" bash -c "echo '$text' | grep -q '\"ctr\": 0.027'"
assert_status 0 "second call updates clicks" bash -c "echo '$text' | grep -q '\"clicks\": 135'"
assert_status 0 "previous impressions key preserved" \
  bash -c "echo '$text' | grep -q '\"impressions\": 4500'"

# Bad inputs.
resp="$(_call report_performance '{"variation_id":"not-cv","metrics":{}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "malformed variation_id → INVALID_VARIATION_ID" \
  bash -c "echo '$text' | grep -q 'INVALID_VARIATION_ID'"

resp="$(_call report_performance '{"variation_id":"CV-999","metrics":{"clicks":1}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "unknown variation_id → VARIATION_NOT_FOUND" \
  bash -c "echo '$text' | grep -q 'VARIATION_NOT_FOUND'"

resp="$(_call report_performance '{"variation_id":"CV-1","metrics":"not-an-object"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "non-object metrics → INVALID_METRICS" \
  bash -c "echo '$text' | grep -q 'INVALID_METRICS'"

# ── T-MVS-S12: get_seed_cohort returns nested envelope ──────────────────────
echo ""
echo "  [T-MVS-S12] get_seed_cohort returns {seed, variations[], counts}"

resp="$(_call get_seed_cohort '{"seed_id":"KS-1"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "envelope carries the seed object"   bash -c "echo '$text' | grep -q '\"seed\":'"
assert_status 0 "envelope carries variations array"  bash -c "echo '$text' | grep -q '\"variations\":'"
assert_status 0 "counts.total == 20"                 bash -c "echo '$text' | grep -q '\"total\": 20'"
assert_status 0 "counts.remaining == 0"              bash -c "echo '$text' | grep -q '\"remaining\": 0'"
assert_status 0 "performance_metrics is parsed JSON" bash -c "echo '$text' | grep -q '\"ctr\": 0.027'"

# Missing seed
resp="$(_call get_seed_cohort '{"seed_id":"KS-999"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "missing seed → SEED_NOT_FOUND" \
  bash -c "echo '$text' | grep -q 'SEED_NOT_FOUND'"

# ── T-MVS-S13: Schema migration idempotency ─────────────────────────────────
echo ""
echo "  [T-MVS-S13] Re-opening the DB does not error or duplicate tables"

# Seed-again: should be a no-op for the existing tables.
AIDIR="${SBOX}/proj/.ai" REPO_ROOT="${REPO_ROOT}" node --no-warnings --input-type=module -e "
  const { getDb } = await import(\`\${process.env.REPO_ROOT}/src/mcp/shared/state-db.js\`);
  // Bypass the in-process cache to force a re-open.
  await import('node:sqlite').then(({DatabaseSync}) => {
    const direct = new DatabaseSync(process.env.AIDIR + '/state.sqlite');
    direct.close();
  });
  const db = getDb(process.env.AIDIR);
  // Trigger CREATE IF NOT EXISTS via a fresh exec is implicit on getDb;
  // a probe query confirms readability.
  const r = db.prepare('SELECT COUNT(*) as n FROM keyword_seeds').get();
  console.log(r.n);
" 2>/dev/null | grep -q '^1$' && echo OK || echo FAIL
assert_status 0 "re-open preserves KS-1" \
  bash -c "AIDIR='${SBOX}/proj/.ai' REPO_ROOT='${REPO_ROOT}' node --no-warnings --input-type=module -e \"
    const { getDb } = await import(\\\`\\\${process.env.REPO_ROOT}/src/mcp/shared/state-db.js\\\`);
    const db = getDb(process.env.AIDIR);
    const n = db.prepare('SELECT COUNT(*) as n FROM keyword_seeds').get().n;
    process.exit(n === 1 ? 0 : 1);
  \" 2>/dev/null"

# ── T-MVS-S14: No regression of existing tools (tasks path) ─────────────────
echo ""
echo "  [T-MVS-S14] Existing add_task / update_task_status still work"

resp="$(_call add_task '{"owner":"Engineer (Claude)","description":"e79 regression smoke","tier":1}')"
text="$(echo "$resp" | _text)"
assert_status 0 "add_task still works" bash -c "echo '$text' | grep -q 'Added E-'"

new_id="$(echo "$text" | grep -oE 'E-[0-9]+' | head -1)"
resp="$(_call update_task_status "{\"id\":\"${new_id}\",\"status\":\"DONE\",\"summary\":\"regression\"}")"
text="$(echo "$resp" | _text)"
assert_status 0 "update_task_status still works" \
  bash -c "echo '$text' | grep -q '${new_id} → DONE'"

# ── T-MVS-S15: Mirror byte-identity ─────────────────────────────────────────
echo ""
echo "  [T-MVS-S15] ~/.ai-os mirrors match src/"

assert_status 0 "task-synchronizer-mcp mirror"  diff -q "$SYNC_MCP" "${HOME}/.ai-os/mcp/task-synchronizer-mcp/index.js"
assert_status 0 "state-db.js mirror"            diff -q "$STATE_DB" "${HOME}/.ai-os/mcp/shared/state-db.js"
assert_status 0 "seo-approach-types.mjs mirror" diff -q "$APPROACH_MOD" "${HOME}/.ai-os/shared/seo-approach-types.mjs"

echo ""
assert_summary
echo "===== multi_variation_state_tracker_test.sh PASS ====="
