#!/usr/bin/env bash
# seo_manager_test.sh — Tests for E-87 SEO-Topic-Cluster-Manager agent.
#
# Verifies src/gemini/agents/seo_manager.md against the contract in
# .ai/blueprints/seo-keyword-multiplier.md (SEO Topic Cluster Engine):
#
#   - §Components 1 (SEO-Topic-Cluster-Manager) — orchestration only
#   - §API generateTopicCluster(term) -> task_ids[]
#   - §Execution Constraints (1 Pillar + ≤10 Cluster pages, concurrency 3, <120s)
#   - §Rollback Plan (page-by-prefix lookup)
#   - §Core Concept cannibalization guard (distinct intents)
#   - The agent enumerates 1 Pillar + the canonical Cluster intents
#   - Anti-drift forbids content generation and state tracking
#   - YAML frontmatter parses cleanly (description quoted to prevent the
#     unquoted-colon class — same regression mode as E-49 / E-65)
#   - Mirrored byte-identical to .gemini/ + ~/.ai-os/gemini/

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGENT_SRC="${REPO_ROOT}/src/gemini/agents/seo_manager.md"
AGENT_GEM="${REPO_ROOT}/.gemini/agents/seo_manager.md"
AGENT_MIRROR="${HOME}/.ai-os/gemini/agents/seo_manager.md"
BLUEPRINT="${REPO_ROOT}/.ai/blueprints/seo-keyword-multiplier.md"

echo "===== seo_manager_test.sh ====="

# ── T-SEO-S01: File presence + frontmatter ───────────────────────────────────
echo ""
echo "  [T-SEO-S01] Agent file exists with parseable YAML frontmatter"

assert_status 0 "src/ agent file exists"             test -f "$AGENT_SRC"
assert_status 0 ".gemini/ mirror exists"             test -f "$AGENT_GEM"
assert_status 0 "frontmatter opens on line 1"        bash -c "head -1 '$AGENT_SRC' | grep -q '^---$'"
assert_status 0 "name: seo_manager"                  grep -q '^name: seo_manager$' "$AGENT_SRC"
assert_status 0 "description present"                grep -q '^description: ' "$AGENT_SRC"
assert_status 0 "description is double-quoted (no colon-parse trap)" \
  bash -c "head -10 '$AGENT_SRC' | grep -q '^description: \"'"
assert_status 0 "blueprint reference present"        grep -q "seo-keyword-multiplier.md" "$AGENT_SRC"
assert_status 0 "frontmatter has a closing --- delimiter" \
  bash -c "awk 'NR>1 && /^---$/{print NR; exit}' '$AGENT_SRC' | grep -qE '^[2-9]$|^[12][0-9]$|^30$'"
assert_status 0 "description value is properly quoted (no colon-parse trap)" \
  python3 -c "
import re, sys
with open('$AGENT_SRC') as f:
    head = ''.join(f.readlines()[:20])
m = re.search(r'^description:\s*(.+?)\$', head, flags=re.M)
if not m:
    sys.exit(1)
val = m.group(1).strip()
sys.exit(0 if (val.startswith('\"') and val.endswith('\"')) or val.startswith('>') or val.startswith('|') else 2)
"

# ── T-SEO-S02: Blueprint contract sections ───────────────────────────────────
echo ""
echo "  [T-SEO-S02] Agent body references every blueprint contract section"

assert_status 0 "ROLE declaration"                   grep -q '^ROLE: SEO_MANAGER' "$AGENT_SRC"
assert_status 0 "Forbidden section"                  grep -q '^## Forbidden' "$AGENT_SRC"
assert_status 0 "Preflight section"                  grep -q '^## Preflight' "$AGENT_SRC"
assert_status 0 "API contract section"               grep -q 'generateTopicCluster(term: string)' "$AGENT_SRC"
assert_status 0 "Execution Constraints section"      grep -q '^## Execution Constraints' "$AGENT_SRC"
assert_status 0 "Rollback section"                   grep -q '^## Rollback' "$AGENT_SRC"
assert_status 0 "What this agent is NOT (anti-drift)" grep -q '^## What this agent is NOT' "$AGENT_SRC"

# ── T-SEO-S03: Pillar + canonical Cluster intents ────────────────────────────
echo ""
echo "  [T-SEO-S03] The agent enumerates 1 Pillar + 10 distinct Cluster intents"

# Count numbered rows in the cluster-intent table (0 = Pillar, 1..10 = Cluster).
count="$(awk '/^## The Canonical Cluster Intents/,/^## Step 1/' "$AGENT_SRC" \
  | grep -cE '^\| *[0-9]+ *\|')"
assert_status 0 "exactly 11 rows in the intent table (pillar + 10)" bash -c "[[ $count -eq 11 ]]"

# Pillar + a few intents the blueprint calls out (§Goal: pillar, cost, comparison, process).
for slug in pillar-overview cost comparison process; do
  assert_status 0 "intent table includes \`${slug}\`" \
    grep -qE "\`${slug}\`" "$AGENT_SRC"
done

# Distinctness — every intent slug in the table is unique.
uniq_count="$(awk '/^## The Canonical Cluster Intents/,/^## Step 1/' "$AGENT_SRC" \
  | grep -oE '`[a-z][a-z0-9-]+`' \
  | sort -u | wc -l | tr -d ' ')"
assert_status 0 "all intent slugs are distinct (≥ 11 unique)" \
  bash -c "[[ $uniq_count -ge 11 ]]"

# ── T-SEO-S04: Anti-drift mandates (Forbidden + What this agent is NOT) ──────
echo ""
echo "  [T-SEO-S04] Agent forbids content generation and state tracking"

assert_status 0 "Forbidden: no content generation" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qi 'generate article content'"
assert_status 0 "Forbidden: no state tracking" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qi 'page performance'"
assert_status 0 "Forbidden: cap on MAX_CLUSTER_PAGES_PER_SEED" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -q 'MAX_CLUSTER_PAGES_PER_SEED'"
assert_status 0 "References the SEO-Content-Generator downstream owner" \
  grep -q 'SEO-Content-Generator' "$AGENT_SRC"
assert_status 0 "References the Multi-Variation-State-Tracker owner" \
  grep -q 'Multi-Variation-State-Tracker' "$AGENT_SRC"
assert_status 0 "References the SEO-Engineer persona (E-90)" \
  grep -q 'SEO-Engineer' "$AGENT_SRC"

# ── T-SEO-S05: Execution Constraints carry the blueprint's exact numbers ─────
echo ""
echo "  [T-SEO-S05] Concurrency 3 / cluster cap / 120s budget surfaced verbatim"

assert_status 0 "concurrency=3 referenced" \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -qE 'batches of 3|concurrency.*3'"
assert_status 0 "cluster-page cap referenced" \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -qE '10 Cluster pages|11th Cluster'"
assert_status 0 "120-second performance budget referenced" \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -q '120s'"

# ── T-SEO-S06: API contract — add_task example references the right tool ─────
echo ""
echo "  [T-SEO-S06] Step 3 wires task-synchronizer-mcp::add_task"

assert_status 0 "Step 3 names add_task tool" \
  grep -q 'mcp__task-synchronizer-mcp__add_task' "$AGENT_SRC"
assert_status 0 "Step 2 persists the seed via add_topic_seed" \
  grep -q 'mcp__task-synchronizer-mcp__add_topic_seed' "$AGENT_SRC"
assert_status 0 "Step 3 specifies tier:2 (per blueprint)" \
  bash -c "awk '/^## Step 3/,/^## Step 4/' '$AGENT_SRC' | grep -q 'tier: *2'"
assert_status 0 "Step 3 uses canonical description prefix" \
  bash -c "awk '/^## Step 3/,/^## Step 4/' '$AGENT_SRC' | grep -q 'SEO cluster page:'"
assert_status 0 "Step 5 returns task_ids[] per blueprint API" \
  bash -c "awk '/^## Step 5/,/^## Step 6/' '$AGENT_SRC' | grep -q 'task_ids'"

# ── T-SEO-S07: Input validation (security — untrusted keyword term) ──────────
echo ""
echo "  [T-SEO-S07] Untrusted keyword input handled per blueprint §Security"

assert_status 0 "Preflight asserts length cap on term" \
  bash -c "awk '/^## Preflight/,/^## API/' '$AGENT_SRC' | grep -qE '256 chars|256 character'"
assert_status 0 "Preflight rejects shell metacharacters" \
  bash -c "awk '/^## Preflight/,/^## API/' '$AGENT_SRC' | grep -q 'shell metacharacters'"
assert_status 0 "INVALID_TOPIC_TERM error tag documented" \
  grep -q 'INVALID_TOPIC_TERM' "$AGENT_SRC"

# ── T-SEO-S08: Rollback section maps to blueprint §Rollback Plan ─────────────
echo ""
echo "  [T-SEO-S08] Rollback section is actionable"

assert_status 0 "Rollback names update_task_status as the unwind tool" \
  bash -c "awk '/^## Rollback/,/^## What this agent is NOT/' '$AGENT_SRC' | grep -q 'update_task_status'"
assert_status 0 "Rollback acknowledges content-file purge is out-of-scope" \
  bash -c "awk '/^## Rollback/,/^## What this agent is NOT/' '$AGENT_SRC' | grep -qE 'git restore|content files'"

# ── T-SEO-S09: Mirror byte-identity ──────────────────────────────────────────
echo ""
echo "  [T-SEO-S09] .gemini/ + ~/.ai-os/gemini/ mirrors match src/"

assert_status 0 ".gemini/ mirror byte-identical to src/" \
  diff -q "$AGENT_SRC" "$AGENT_GEM"
if [[ -f "$AGENT_MIRROR" ]]; then
  assert_status 0 "~/.ai-os mirror byte-identical to src/" \
    diff -q "$AGENT_SRC" "$AGENT_MIRROR"
else
  echo "    ⚠  ~/.ai-os mirror absent — skipping"
fi

# ── T-SEO-S10: Blueprint file presence + bidirectional reference ─────────────
echo ""
echo "  [T-SEO-S10] Blueprint file referenced in agent and vice versa"

assert_status 0 "blueprint file exists"               test -f "$BLUEPRINT"
assert_status 0 "blueprint names E-87 + seo_manager.md target" \
  grep -q "E-87.*seo_manager.md" "$BLUEPRINT"
assert_status 0 "agent description references the blueprint path" \
  grep -q "seo-keyword-multiplier.md" "$AGENT_SRC"

echo ""
assert_summary
echo "===== seo_manager_test.sh PASS ====="
