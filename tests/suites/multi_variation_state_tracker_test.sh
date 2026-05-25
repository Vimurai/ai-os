#!/usr/bin/env bash
# multi_variation_state_tracker_test.sh — Tests for E-88.
#
# Verifies the Multi-Variation-State-Tracker (SEO Topic Cluster Engine)
# bolted onto task-synchronizer-mcp per
# .ai/blueprints/seo-keyword-multiplier.md §Components 3 + §Data Model + §API:
#
#   - Two tables (topic_seeds, cluster_pages) with FK + CHECKs
#   - Four MCP tools: add_topic_seed, add_cluster_page,
#     report_performance, get_topic_cluster
#   - Input validation: term charset/length, target_volume range,
#     intent_type ∈ canonical set, FK enforcement
#   - Cannibalization guard ((seed_id, intent_type) uniqueness) + lifted
#     cluster-page cap (MAX_CLUSTER_PAGES_PER_SEED)
#   - JSON merge-patch semantics on report_performance
#   - Idempotent schema bootstrap (no errors on repeat open)
#   - In-place migration of the legacy keyword_seeds / content_variations
#     schema (approach_type → intent_type) preserving rows
#   - No regression of existing tables (tasks/stamps/deltas/patches)
#   - SEO_ALL_INTENTS single-source-of-truth cross-references
#     src/gemini/agents/seo_manager.md exactly (E-87 contract)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_MCP="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
STATE_DB="${REPO_ROOT}/src/mcp/shared/state-db.js"
INTENT_MOD="${REPO_ROOT}/src/shared/seo-cluster-intents.mjs"
MANAGER="${REPO_ROOT}/src/gemini/agents/seo_manager.md"

echo "===== multi_variation_state_tracker_test.sh ====="

# ── T-MVS-S01: Source contract — module + handlers + helpers ────────────────
echo ""
echo "  [T-MVS-S01] state-db.js has the new tables + id helpers"

assert_status 0 "topic_seeds CREATE present"           grep -q 'CREATE TABLE IF NOT EXISTS topic_seeds' "$STATE_DB"
assert_status 0 "cluster_pages CREATE present"          grep -q 'CREATE TABLE IF NOT EXISTS cluster_pages' "$STATE_DB"
assert_status 0 "FK constraint declared"                grep -q 'FOREIGN KEY (seed_id) REFERENCES topic_seeds' "$STATE_DB"
assert_status 0 "status CHECK constraint declared"      grep -q "status IN ('OPEN','IN_PROGRESS','COMPLETED','ARCHIVED')" "$STATE_DB"
assert_status 0 "target_volume CHECK ≤ 10"             grep -q "target_volume <= 10" "$STATE_DB"
assert_status 0 "idx_cluster_pages_seed index"          grep -q 'idx_cluster_pages_seed' "$STATE_DB"
assert_status 0 "intent_type column declared"           grep -q 'intent_type' "$STATE_DB"
assert_status 0 "nextTopicSeedId exported"              grep -q 'export function nextTopicSeedId' "$STATE_DB"
assert_status 0 "nextClusterPageId exported"            grep -q 'export function nextClusterPageId' "$STATE_DB"
assert_status 0 "_migrateSeoSchema present"             grep -q '_migrateSeoSchema' "$STATE_DB"

echo ""
echo "  [T-MVS-S01b] task-synchronizer-mcp wires the new tools + handlers"

assert_status 0 "MCP imports SEO_ALL_INTENTS"           grep -q 'SEO_ALL_INTENTS' "$SYNC_MCP"
assert_status 0 "MCP imports MAX_CLUSTER_PAGES_PER_SEED" grep -q 'MAX_CLUSTER_PAGES_PER_SEED' "$SYNC_MCP"
assert_status 0 "add_topic_seed case present"           grep -q 'case "add_topic_seed":' "$SYNC_MCP"
assert_status 0 "add_cluster_page case present"         grep -q 'case "add_cluster_page":' "$SYNC_MCP"
assert_status 0 "report_performance case present"       grep -q 'case "report_performance":' "$SYNC_MCP"
assert_status 0 "get_topic_cluster case present"        grep -q 'case "get_topic_cluster":' "$SYNC_MCP"

# ── T-MVS-S02: SEO cluster intents — frozen, distinct, single-source ────────
echo ""
echo "  [T-MVS-S02] SEO_CLUSTER_INTENTS + SEO_ALL_INTENTS shape + pillar"

cluster_count="$(node --input-type=module -e "
  const m = await import('file://${INTENT_MOD}');
  console.log(m.SEO_CLUSTER_INTENTS.length);
" 2>/dev/null)"
assert_status 0 "cluster intents length == 10" bash -c "[[ '$cluster_count' == '10' ]]"

all_count="$(node --input-type=module -e "
  const m = await import('file://${INTENT_MOD}');
  console.log(m.SEO_ALL_INTENTS.length);
" 2>/dev/null)"
assert_status 0 "all intents length == 11 (pillar + 10 clusters)" bash -c "[[ '$all_count' == '11' ]]"

pillar="$(node --input-type=module -e "
  const m = await import('file://${INTENT_MOD}');
  console.log(m.SEO_PILLAR_INTENT);
" 2>/dev/null)"
assert_status 0 "pillar intent is pillar-overview" bash -c "[[ '$pillar' == 'pillar-overview' ]]"

frozen="$(node --input-type=module -e "
  const m = await import('file://${INTENT_MOD}');
  console.log(Object.isFrozen(m.SEO_CLUSTER_INTENTS) && Object.isFrozen(m.SEO_ALL_INTENTS));
" 2>/dev/null)"
assert_status 0 "intent arrays are frozen" bash -c "[[ '$frozen' == 'true' ]]"

# Cross-reference: every intent in SEO_ALL_INTENTS must appear in the
# seo_manager.md cluster-intent table.
missing="$(python3 -c "
import re, json, subprocess
slugs = subprocess.check_output(['node','--input-type=module','-e',
  \"const m = await import('file://${INTENT_MOD}'); console.log(JSON.stringify([...m.SEO_ALL_INTENTS]));\"
], text=True).strip()
slugs = json.loads(slugs)
mgr = open('${MANAGER}').read()
mgr_slugs = set(re.findall(r'\`([a-z][a-z0-9-]+)\`', mgr))
missing = [s for s in slugs if s not in mgr_slugs]
print(','.join(missing) if missing else 'OK')
")"
assert_status 0 "every SEO_ALL_INTENTS slug exists in seo_manager.md" \
  bash -c "[[ '$missing' == 'OK' ]]"

# ── Set up an isolated sandbox + drive the MCP via stdio JSON-RPC ───────────
SBOX="$(mktemp -d -t e88-XXXXXX)"
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
assert_status 0 "topic_seeds table created on first open" \
  bash -c "echo '$TABLES' | grep -q 'topic_seeds'"
assert_status 0 "cluster_pages table created on first open" \
  bash -c "echo '$TABLES' | grep -q 'cluster_pages'"
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
echo "  [T-MVS-S03] tools/list advertises the four E-88 tools"

for tool in add_topic_seed add_cluster_page report_performance get_topic_cluster; do
  ( cd "${SBOX}/proj" && mcp_assert_tool_listed "$SYNC_MCP" "$tool" )
  assert_status 0 "tools/list includes ${tool}" bash -c "[[ $? -eq 0 ]]"
done

# ── T-MVS-S04: add_topic_seed happy path ────────────────────────────────────
echo ""
echo "  [T-MVS-S04] add_topic_seed creates TS-1 and returns the row"

resp="$(_call add_topic_seed '{"term":"ai testing","target_volume":10}')"
text="$(echo "$resp" | _text)"
assert_status 0 "response confirms TS-1 created"        bash -c "echo '$text' | grep -q 'TopicSeed TS-1'"
assert_status 0 "response includes term"                bash -c "echo '$text' | grep -q '\"term\": \"ai testing\"'"
assert_status 0 "response includes target_volume=10"    bash -c "echo '$text' | grep -q '\"target_volume\": 10'"

# ── T-MVS-S05: add_topic_seed input validation ──────────────────────────────
echo ""
echo "  [T-MVS-S05] add_topic_seed rejects bad inputs"

for tuple in \
  'empty:{"term":""}:INVALID_TOPIC_TERM' \
  'oversize:{"term":"'"$(python3 -c 'print("x"*300)')"'"}:INVALID_TOPIC_TERM' \
  'shellmeta:{"term":"ai`rm -rf /`"}:INVALID_TOPIC_TERM' \
  'newline:{"term":"line1\nline2"}:INVALID_TOPIC_TERM' \
  'tv_zero:{"term":"ok","target_volume":0}:INVALID_TARGET_VOLUME' \
  'tv_huge:{"term":"ok","target_volume":99}:INVALID_TARGET_VOLUME'; do
  label="${tuple%%:*}"
  rest="${tuple#*:}"
  args="${rest%:*}"
  want="${tuple##*:}"
  resp="$(_call add_topic_seed "$args")"
  text="$(echo "$resp" | _text)"
  assert_status 0 "case=${label} → ${want}" bash -c "echo '$text' | grep -q '${want}'"
done

# ── T-MVS-S06: add_cluster_page happy path (Pillar) ─────────────────────────
echo ""
echo "  [T-MVS-S06] add_cluster_page attaches CP-1 (pillar-overview) to TS-1"

resp="$(_call add_cluster_page '{"seed_id":"TS-1","intent_type":"pillar-overview","content_blob":"# AI Testing: The Complete Guide"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "response confirms CP-1 created" bash -c "echo '$text' | grep -q 'ClusterPage CP-1'"
assert_status 0 "response carries intent_type=pillar-overview" bash -c "echo '$text' | grep -q 'pillar-overview'"

# ── T-MVS-S07: add_cluster_page rejects unknown intent_type ─────────────────
echo ""
echo "  [T-MVS-S07] Unknown intent_type → UNKNOWN_INTENT_TYPE"

resp="$(_call add_cluster_page '{"seed_id":"TS-1","intent_type":"bogus-shape"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "rejects bogus slug"           bash -c "echo '$text' | grep -q 'UNKNOWN_INTENT_TYPE'"
assert_status 0 "error mentions canonical set" bash -c "echo '$text' | grep -q 'cost'"

# ── T-MVS-S08: add_cluster_page enforces FK (seed must exist) ───────────────
echo ""
echo "  [T-MVS-S08] seed_id must exist → SEED_NOT_FOUND"

resp="$(_call add_cluster_page '{"seed_id":"TS-999","intent_type":"how-to"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "missing seed → SEED_NOT_FOUND" bash -c "echo '$text' | grep -q 'SEED_NOT_FOUND'"

# Bad seed_id format
resp="$(_call add_cluster_page '{"seed_id":"notakey","intent_type":"how-to"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "malformed seed_id → INVALID_SEED_ID" bash -c "echo '$text' | grep -q 'INVALID_SEED_ID'"

# ── T-MVS-S09: cannibalization guard ((seed_id, intent_type) uniqueness) ─────
echo ""
echo "  [T-MVS-S09] Duplicate (seed_id, intent_type) → INTENT_ALREADY_USED"

resp="$(_call add_cluster_page '{"seed_id":"TS-1","intent_type":"pillar-overview"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "duplicate intent rejected" bash -c "echo '$text' | grep -q 'INTENT_ALREADY_USED'"

# ── T-MVS-S10: lifted cluster-page cap ──────────────────────────────────────
echo ""
echo "  [T-MVS-S10] 1 Pillar + 10 Cluster pages; cap gate present"

# Fill all 10 distinct cluster intents (CP-1 is the pillar already).
for slug in cost comparison how-to process alternatives best-for-use-case \
             benefits requirements mistakes faq; do
  _call add_cluster_page "{\"seed_id\":\"TS-1\",\"intent_type\":\"${slug}\"}" >/dev/null
done

# TS-1 now holds 1 pillar + 10 cluster pages = 11 total; cluster pages == 10
# (the cap). An 11th cluster page would require an 11th cluster intent, which
# does not exist by design — UNKNOWN_INTENT_TYPE fires first — so the cap is
# structurally bounded by the intent taxonomy. We assert the counts + the
# constant + the source gate.
total="$(node --no-warnings --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX}/proj/.ai/state.sqlite');
  console.log(db.prepare(\"SELECT COUNT(*) as n FROM cluster_pages WHERE seed_id='TS-1'\").get().n);
  db.close();
" 2>/dev/null)"
assert_status 0 "TS-1 holds exactly 11 pages (1 pillar + 10 cluster)" bash -c "[[ '$total' == '11' ]]"

cluster="$(node --no-warnings --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${SBOX}/proj/.ai/state.sqlite');
  console.log(db.prepare(\"SELECT COUNT(*) as n FROM cluster_pages WHERE seed_id='TS-1' AND intent_type != 'pillar-overview'\").get().n);
  db.close();
" 2>/dev/null)"
assert_status 0 "TS-1 holds exactly 10 cluster pages (at cap)" bash -c "[[ '$cluster' == '10' ]]"

assert_status 0 "MAX_CLUSTER_PAGES_PER_SEED constant is 10" \
  bash -c "node --input-type=module -e \"
    const m = await import('file://${INTENT_MOD}');
    console.log(m.MAX_CLUSTER_PAGES_PER_SEED);
  \" 2>/dev/null | grep -q '^10$'"
assert_status 0 "CLUSTER_CAP_REACHED gate present in source" \
  grep -q 'CLUSTER_CAP_REACHED' "$SYNC_MCP"

# ── T-MVS-S11: report_performance merge semantics ───────────────────────────
echo ""
echo "  [T-MVS-S11] report_performance merges JSON keys; idempotent on repeat"

resp="$(_call report_performance '{"page_id":"CP-1","metrics":{"clicks":120,"impressions":4500}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "first call records both metrics" \
  bash -c "echo '$text' | grep -q '\"clicks\": 120'"
assert_status 0 "first call records impressions"  \
  bash -c "echo '$text' | grep -q '\"impressions\": 4500'"

# Second call: add ctr; existing keys remain.
resp="$(_call report_performance '{"page_id":"CP-1","metrics":{"ctr":0.027,"clicks":135}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "second call merges ctr key" bash -c "echo '$text' | grep -q '\"ctr\": 0.027'"
assert_status 0 "second call updates clicks" bash -c "echo '$text' | grep -q '\"clicks\": 135'"
assert_status 0 "previous impressions key preserved" \
  bash -c "echo '$text' | grep -q '\"impressions\": 4500'"

# Bad inputs.
resp="$(_call report_performance '{"page_id":"not-cp","metrics":{}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "malformed page_id → INVALID_PAGE_ID" \
  bash -c "echo '$text' | grep -q 'INVALID_PAGE_ID'"

resp="$(_call report_performance '{"page_id":"CP-999","metrics":{"clicks":1}}')"
text="$(echo "$resp" | _text)"
assert_status 0 "unknown page_id → PAGE_NOT_FOUND" \
  bash -c "echo '$text' | grep -q 'PAGE_NOT_FOUND'"

resp="$(_call report_performance '{"page_id":"CP-1","metrics":"not-an-object"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "non-object metrics → INVALID_METRICS" \
  bash -c "echo '$text' | grep -q 'INVALID_METRICS'"

# ── T-MVS-S12: get_topic_cluster returns nested envelope ────────────────────
echo ""
echo "  [T-MVS-S12] get_topic_cluster returns {seed, pages[], counts}"

resp="$(_call get_topic_cluster '{"seed_id":"TS-1"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "envelope carries the seed object"   bash -c "echo '$text' | grep -q '\"seed\":'"
assert_status 0 "envelope carries pages array"       bash -c "echo '$text' | grep -q '\"pages\":'"
assert_status 0 "counts.total == 11"                 bash -c "echo '$text' | grep -q '\"total\": 11'"
assert_status 0 "counts.pillar == 1"                 bash -c "echo '$text' | grep -q '\"pillar\": 1'"
assert_status 0 "counts.cluster == 10"               bash -c "echo '$text' | grep -q '\"cluster\": 10'"
assert_status 0 "counts.remaining == 0"              bash -c "echo '$text' | grep -q '\"remaining\": 0'"
assert_status 0 "performance_metrics is parsed JSON" bash -c "echo '$text' | grep -q '\"ctr\": 0.027'"

# Missing seed
resp="$(_call get_topic_cluster '{"seed_id":"TS-999"}')"
text="$(echo "$resp" | _text)"
assert_status 0 "missing seed → SEED_NOT_FOUND" \
  bash -c "echo '$text' | grep -q 'SEED_NOT_FOUND'"

# ── T-MVS-S13: Legacy-schema migration preserves rows ───────────────────────
echo ""
echo "  [T-MVS-S13] keyword_seeds/content_variations migrate to topic_seeds/cluster_pages"

MBOX="$(mktemp -d -t e88mig-XXXXXX)"
mkdir -p "${MBOX}/.ai"
# Build a legacy-schema DB with one seed + one variation (approach_type).
node --no-warnings --input-type=module -e "
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync('${MBOX}/.ai/state.sqlite');
  db.exec(\`
    CREATE TABLE keyword_seeds(id TEXT PRIMARY KEY, term TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'OPEN', target_volume INTEGER NOT NULL DEFAULT 20 CHECK(target_volume>0 AND target_volume<=20), created_at TEXT NOT NULL, completed_at TEXT);
    CREATE TABLE content_variations(id TEXT PRIMARY KEY, seed_id TEXT NOT NULL, approach_type TEXT NOT NULL, content_blob TEXT, performance_metrics TEXT, published_at TEXT, created_at TEXT NOT NULL, FOREIGN KEY(seed_id) REFERENCES keyword_seeds(id) ON DELETE CASCADE);
    CREATE INDEX idx_variations_seed ON content_variations(seed_id);
    CREATE INDEX idx_variations_approach ON content_variations(seed_id, approach_type);
  \`);
  db.prepare('INSERT INTO keyword_seeds(id,term,status,target_volume,created_at) VALUES (?,?,?,?,?)').run('KS-1','legacy seed','OPEN',20,new Date().toISOString());
  db.prepare('INSERT INTO content_variations(id,seed_id,approach_type,created_at) VALUES (?,?,?,?)').run('CV-1','KS-1','listicle',new Date().toISOString());
  db.close();
" 2>/dev/null

# Open via state-db.js getDb — runs the in-place migration.
MIG="$(AIDIR="${MBOX}/.ai" REPO_ROOT="${REPO_ROOT}" node --no-warnings --input-type=module -e "
  const { getDb } = await import(\`\${process.env.REPO_ROOT}/src/mcp/shared/state-db.js\`);
  const db = getDb(process.env.AIDIR);
  const tables = db.prepare(\"SELECT name FROM sqlite_master WHERE type='table'\").all().map(r=>r.name);
  const cols = db.prepare('PRAGMA table_info(cluster_pages)').all().map(c=>c.name);
  const seedTerm = db.prepare('SELECT term FROM topic_seeds WHERE id=?').get('KS-1')?.term;
  const pageIntent = db.prepare('SELECT intent_type FROM cluster_pages WHERE id=?').get('CV-1')?.intent_type;
  console.log(JSON.stringify({
    renamed: tables.includes('topic_seeds') && tables.includes('cluster_pages') && !tables.includes('keyword_seeds') && !tables.includes('content_variations'),
    intentCol: cols.includes('intent_type') && !cols.includes('approach_type'),
    seedTerm, pageIntent,
  }));
" 2>/dev/null)"
assert_status 0 "legacy tables renamed (topic_seeds + cluster_pages)" \
  bash -c "echo '$MIG' | grep -q '\"renamed\":true'"
assert_status 0 "approach_type column renamed to intent_type" \
  bash -c "echo '$MIG' | grep -q '\"intentCol\":true'"
assert_status 0 "legacy seed row preserved" \
  bash -c "echo '$MIG' | grep -q '\"seedTerm\":\"legacy seed\"'"
assert_status 0 "legacy variation row preserved as cluster page" \
  bash -c "echo '$MIG' | grep -q '\"pageIntent\":\"listicle\"'"
rm -rf "$MBOX"

# ── T-MVS-S14: No regression of existing tools (tasks path) ─────────────────
echo ""
echo "  [T-MVS-S14] Existing add_task / update_task_status still work"

resp="$(_call add_task '{"owner":"Engineer (Claude)","description":"e88 regression smoke","tier":1}')"
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

assert_status 0 "task-synchronizer-mcp mirror"   diff -q "$SYNC_MCP" "${HOME}/.ai-os/mcp/task-synchronizer-mcp/index.js"
assert_status 0 "state-db.js mirror"             diff -q "$STATE_DB" "${HOME}/.ai-os/mcp/shared/state-db.js"
assert_status 0 "seo-cluster-intents.mjs mirror" diff -q "$INTENT_MOD" "${HOME}/.ai-os/shared/seo-cluster-intents.mjs"

echo ""
assert_summary
echo "===== multi_variation_state_tracker_test.sh PASS ====="
