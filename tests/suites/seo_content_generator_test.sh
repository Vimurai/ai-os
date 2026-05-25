#!/usr/bin/env bash
# seo_content_generator_test.sh — Tests for the SEO-Content-Generator agent.
#
# Verifies src/gemini/agents/seo_content_generator.md against the contract
# in .ai/blueprints/seo-keyword-multiplier.md §Components 2 + §API:
#
#   - generateClusterContent(seed_id, intent_type) → content_blob
#   - Honors §Execution Constraints (120s, concurrency 3, cluster cap)
#   - Honors §Security (duplicate-content, identity_guardian, critic_security)
#   - Anti-drift: NOT the orchestrator (E-87), NOT the state tracker
#   - Intent taxonomy is single-sourced from seo-cluster-intents.mjs /
#     the seo_manager cluster-intent table
#   - Frontmatter description double-quoted (colon-parse guard)
#   - Mirrored byte-identical to .gemini/ + ~/.ai-os/gemini/

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGENT_SRC="${REPO_ROOT}/src/gemini/agents/seo_content_generator.md"
AGENT_GEM="${REPO_ROOT}/.gemini/agents/seo_content_generator.md"
AGENT_MIRROR="${HOME}/.ai-os/gemini/agents/seo_content_generator.md"
MANAGER_SRC="${REPO_ROOT}/src/gemini/agents/seo_manager.md"
BLUEPRINT="${REPO_ROOT}/.ai/blueprints/seo-keyword-multiplier.md"

echo "===== seo_content_generator_test.sh ====="

# ── T-SCG-S01: Presence + frontmatter integrity ──────────────────────────────
echo ""
echo "  [T-SCG-S01] Agent file exists with parseable frontmatter"

assert_status 0 "src/ agent file exists"             test -f "$AGENT_SRC"
assert_status 0 ".gemini/ mirror exists"             test -f "$AGENT_GEM"
assert_status 0 "frontmatter opens on line 1"        bash -c "head -1 '$AGENT_SRC' | grep -q '^---$'"
assert_status 0 "name: seo_content_generator"        grep -q '^name: seo_content_generator$' "$AGENT_SRC"
assert_status 0 "description present"                grep -q '^description: ' "$AGENT_SRC"
assert_status 0 "description is double-quoted"       \
  bash -c "head -10 '$AGENT_SRC' | grep -q '^description: \"'"
assert_status 0 "blueprint reference in description" grep -q "seo-keyword-multiplier.md" "$AGENT_SRC"
assert_status 0 "frontmatter has closing delimiter within first 30 lines" \
  bash -c "awk 'NR>1 && /^---$/{print NR; exit}' '$AGENT_SRC' | grep -qE '^[2-9]$|^[12][0-9]$|^30$'"
assert_status 0 "description value uses safe quoting (no colon-parse trap)" \
  python3 -c "
import re, sys
with open('$AGENT_SRC') as f:
    head = ''.join(f.readlines()[:20])
m = re.search(r'^description:\s*(.+?)\$', head, flags=re.M)
if not m: sys.exit(1)
val = m.group(1).strip()
sys.exit(0 if (val.startswith('\"') and val.endswith('\"')) or val.startswith('>') or val.startswith('|') else 2)
"

# ── T-SCG-S02: Required §-sections from the blueprint ───────────────────────
echo ""
echo "  [T-SCG-S02] Agent body covers every required blueprint section"

assert_status 0 "ROLE declaration"                   grep -q '^ROLE: SEO_CONTENT_GENERATOR' "$AGENT_SRC"
assert_status 0 "Forbidden section"                  grep -q '^## Forbidden' "$AGENT_SRC"
assert_status 0 "Preflight section"                  grep -q '^## Preflight' "$AGENT_SRC"
assert_status 0 "API contract section"               grep -q 'generateClusterContent(seed_id: string, intent_type: string)' "$AGENT_SRC"
assert_status 0 "Execution Constraints section"      grep -q '^## Execution Constraints' "$AGENT_SRC"
assert_status 0 "Rollback section"                   grep -q '^## Rollback' "$AGENT_SRC"
assert_status 0 "What this agent is NOT (anti-drift)" grep -q '^## What this agent is NOT' "$AGENT_SRC"

# ── T-SCG-S03: Cluster-intent taxonomy is single-sourced ────────────────────
echo ""
echo "  [T-SCG-S03] Generator's template table covers the canonical intents"

# Extract intent slugs from the generator's template table.
gen_count="$(awk '/^## Step 2/,/^## Step 3/' "$AGENT_SRC" \
  | grep -oE '`[a-z][a-z0-9-]+`' | sort -u | wc -l | tr -d ' ')"
assert_status 0 "generator enumerates ≥ 11 distinct intent slugs (pillar + 10)" \
  bash -c "[[ $gen_count -ge 11 ]]"

# Cross-reference: every slug in the generator MUST also exist in the manager.
missing="$(python3 -c "
import re
with open('$AGENT_SRC') as f:
    gen_text = f.read()
with open('$MANAGER_SRC') as f:
    mgr_text = f.read()
# Pull slugs from generator's Step 2 table.
m_block = re.search(r'## Step 2(.+?)## Step 3', gen_text, flags=re.S)
gen_slugs = set(re.findall(r'\`([a-z][a-z0-9-]+)\`', m_block.group(1) if m_block else ''))
# Pull slugs from manager's cluster-intent table.
mgr_block = re.search(r'## The Canonical Cluster Intents(.+?)## Step 1', mgr_text, flags=re.S)
mgr_slugs = set(re.findall(r'\`([a-z][a-z0-9-]+)\`', mgr_block.group(1) if mgr_block else ''))
missing = gen_slugs - mgr_slugs
print(','.join(sorted(missing)) if missing else 'OK')
")"
assert_status 0 "every generator intent exists in the manager taxonomy" \
  bash -c "[[ '$missing' == 'OK' ]]"

# ── T-SCG-S04: Anti-drift mandates ───────────────────────────────────────────
echo ""
echo "  [T-SCG-S04] Generator forbids orchestration + state tracking"

assert_status 0 "Forbidden: NO orchestration (E-87)" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qE 'orchestrate|SEO-Topic-Cluster-Manager'"
assert_status 0 "Forbidden: NO state tracking" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qE 'state|Multi-Variation-State-Tracker'"
assert_status 0 "Forbidden: NO publish / deploy" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qiE 'publish|deploy'"
assert_status 0 "What-this-is-NOT references E-87 by id"  grep -q 'E-87' "$AGENT_SRC"
assert_status 0 "References the Multi-Variation-State-Tracker"  grep -q 'Multi-Variation-State-Tracker' "$AGENT_SRC"

# ── T-SCG-S05: Blueprint Execution Constraints surfaced verbatim ────────────
echo ""
echo "  [T-SCG-S05] 120s budget + concurrency 3 + 1000ms→15000ms backoff"

assert_status 0 "120-second wall-clock budget" \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -q '120 seconds\\|120-second'"
assert_status 0 "concurrency cap of 3"         \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -qE '3 in-flight|concurrency.*3'"
assert_status 0 "exponential backoff 1000→15000ms" \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -qE '1000ms.*15000ms|1000ms → 15000ms'"
assert_status 0 "cluster cap / cannibalization defence-in-depth"      \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -qE 'cannibalization|cluster-page cap'"

# ── T-SCG-S06: Security gates (duplicate-content + identity + critic) ───────
echo ""
echo "  [T-SCG-S06] Three security gates referenced per blueprint §Security"

assert_status 0 "Step 4 duplicate-content check (SHA-256 + Jaccard)" \
  grep -q 'SHA-256\|sha256' "$AGENT_SRC"
assert_status 0 "Step 4 references Jaccard shingles for fuzzy match" \
  grep -q 'Jaccard' "$AGENT_SRC"
assert_status 0 "DUPLICATE_REJECTED status documented" \
  grep -q 'DUPLICATE_REJECTED' "$AGENT_SRC"
assert_status 0 "Step 5 invokes identity_guardian" \
  grep -q 'identity_guardian' "$AGENT_SRC"
assert_status 0 "Step 5 invokes critic_security" \
  grep -q 'critic_security' "$AGENT_SRC"
assert_status 0 "REVIEW_BLOCKED status documented" \
  grep -q 'REVIEW_BLOCKED' "$AGENT_SRC"

# ── T-SCG-S07: Backoff / budget envelope statuses ───────────────────────────
echo ""
echo "  [T-SCG-S07] Structured status envelope on every failure path"

for status in OFFLINE UNKNOWN_INTENT_TYPE INVALID_SEED_ID RATE_LIMITED_EXHAUSTED BUDGET_EXCEEDED DUPLICATE_REJECTED REVIEW_BLOCKED; do
  assert_status 0 "status code referenced: ${status}" \
    grep -q "${status}" "$AGENT_SRC"
done

# ── T-SCG-S08: QA + persistence wiring ──────────────────────────────────────
echo ""
echo "  [T-SCG-S08] QA via seo_content_checklist + stamp via add_stamp"

assert_status 0 "Step 6 activates seo_content_checklist skill" \
  grep -q 'seo_content_checklist' "$AGENT_SRC"
assert_status 0 "Step 7 calls task-synchronizer-mcp::add_stamp" \
  grep -q 'task-synchronizer-mcp::add_stamp' "$AGENT_SRC"
assert_status 0 "Stamp type = SEO_VARIATION_GENERATED" \
  grep -q 'SEO_VARIATION_GENERATED' "$AGENT_SRC"
assert_status 0 "Stamp summary carries content_sha256 marker" \
  grep -q 'sha256=' "$AGENT_SRC"

# ── T-SCG-S09: Rollback section is actionable ───────────────────────────────
echo ""
echo "  [T-SCG-S09] Rollback maps to blueprint §Rollback Plan"

assert_status 0 "Rollback names stamp deletion" \
  bash -c "awk '/^## Rollback/,/^## What this agent is NOT/' '$AGENT_SRC' | grep -qE 'stamp|SEO_VARIATION_GENERATED'"
assert_status 0 "Rollback references git restore for staged content" \
  bash -c "awk '/^## Rollback/,/^## What this agent is NOT/' '$AGENT_SRC' | grep -q 'git restore'"

# ── T-SCG-S10: Mirror byte-identity ─────────────────────────────────────────
echo ""
echo "  [T-SCG-S10] .gemini/ + ~/.ai-os/gemini/ mirrors match src/"

assert_status 0 ".gemini/ mirror byte-identical to src/" \
  diff -q "$AGENT_SRC" "$AGENT_GEM"
if [[ -f "$AGENT_MIRROR" ]]; then
  assert_status 0 "~/.ai-os mirror byte-identical to src/" \
    diff -q "$AGENT_SRC" "$AGENT_MIRROR"
else
  echo "    ⚠  ~/.ai-os mirror absent — skipping"
fi

# ── T-SCG-S11: Blueprint reference ──────────────────────────────────────────
echo ""
echo "  [T-SCG-S11] Blueprint names the SEO-Content-Generator + agent references it back"

assert_status 0 "blueprint file exists"               test -f "$BLUEPRINT"
assert_status 0 "blueprint names the SEO-Content-Generator (Component 2)" \
  grep -q "SEO-Content-Generator" "$BLUEPRINT"
assert_status 0 "agent description names blueprint path" \
  grep -q "seo-keyword-multiplier.md" "$AGENT_SRC"

echo ""
assert_summary
echo "===== seo_content_generator_test.sh PASS ====="
