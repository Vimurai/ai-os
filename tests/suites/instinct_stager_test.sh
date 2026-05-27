#!/usr/bin/env bash
# instinct_stager_test.sh — Tests for E-93 instinct staging (ecc-integrations.md
# §Components 1 & 2): src/shared/instinct-stager.mjs + the meta_analyst
# Instinct-Extraction prompt.
#
# Deterministic: imports the real stager module and stages a mixed batch into a
# temp proposed/ dir. Covers confidence gating, malformed/dangerous rejection,
# path-traversal neutralisation, inert frontmatter, and provenance headers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAGER="${REPO_ROOT}/src/shared/instinct-stager.mjs"
META="${REPO_ROOT}/src/gemini/agents/meta_analyst.md"

echo "── Suite: instinct_stager_test (E-93) ──────────────────────────────"

PDIR="$(mktemp -d)/proposed"

# Mixed batch: 1 valid, 1 low-conf, 1 malformed, 2 dangerous, 1 traversal, 1 empty-slug.
export PDIR
export INSTINCTS='[
  {"pattern_id":"INST-01","confidence_score":0.85,"trigger_condition":"When resolving a failing test","proposed_skill_content":"# Test-Fix Instinct\n\nRun the failing test, form a hypothesis, fix, re-run."},
  {"pattern_id":"INST-02","confidence_score":0.5,"trigger_condition":"low confidence","proposed_skill_content":"# Low\n\nbody"},
  {"pattern_id":"INST-03","confidence_score":0.9,"trigger_condition":"missing content"},
  {"pattern_id":"INST-04","confidence_score":0.95,"trigger_condition":"danger","proposed_skill_content":"# Danger\n\nrm -rf /tmp/x"},
  {"pattern_id":"INST-05","confidence_score":0.95,"trigger_condition":"secret","proposed_skill_content":"# Sec\n\nAKIAABCDEFGHIJKLMNOP here"},
  {"pattern_id":"../../etc/passwd","confidence_score":0.99,"trigger_condition":"traversal","proposed_skill_content":"# Trav\n\nharmless body"},
  {"pattern_id":"!!!","confidence_score":0.99,"trigger_condition":"empty slug","proposed_skill_content":"# Empty\n\nbody"}
]'

MANIFEST=$(node --input-type=module -e "
import { stageInstincts } from '${STAGER}';
const res = stageInstincts(JSON.parse(process.env.INSTINCTS), { proposedDir: process.env.PDIR });
console.log(JSON.stringify(res));
")

# helper: query manifest with a python expression over the parsed dict `d`
mq() { python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print($1)" <<<"$MANIFEST"; }

# ── T-93.01: valid high-confidence instinct is staged ────────────────────────
assert_contains "T-93.01: 2 staged (INST-01 + traversal-slug)" "2" "$(mq 'len(d["staged"])')"
assert_contains "T-93.01: INST-01 staged" "INST-01" "$(mq '[s["pattern_id"] for s in d["staged"]]')"
assert_exists "${PDIR}/inst-01/SKILL.md"

# ── T-93.02: low-confidence is skipped with reason ───────────────────────────
assert_contains "T-93.02: INST-02 below-confidence" "below-confidence" "$(mq '[s["reason"] for s in d["skipped"] if s["pattern_id"]=="INST-02"]')"

# ── T-93.03: malformed (no content) is skipped ───────────────────────────────
assert_contains "T-93.03: INST-03 missing content" "missing-proposed_skill_content" "$(mq '[s["reason"] for s in d["skipped"] if s["pattern_id"]=="INST-03"]')"

# ── T-93.04: dangerous shell content is skipped (security) ───────────────────
assert_contains "T-93.04: INST-04 rm -rf rejected" "dangerous-content:destructive-rm" "$(mq '[s["reason"] for s in d["skipped"] if s["pattern_id"]=="INST-04"]')"

# ── T-93.05: secret pattern is skipped (security) ────────────────────────────
assert_contains "T-93.05: INST-05 aws-key rejected" "dangerous-content:aws-key" "$(mq '[s["reason"] for s in d["skipped"] if s["pattern_id"]=="INST-05"]')"

# ── T-93.06: empty-slug pattern_id is skipped ────────────────────────────────
assert_contains "T-93.06: '!!!' unsafe-pattern_id" "unsafe-pattern_id" "$(mq '[s["reason"] for s in d["skipped"]]')"

# ── T-93.07: path-traversal pattern_id is neutralised, stays inside proposedDir
trav_path=$(mq '[s["path"] for s in d["staged"] if s["pattern_id"]=="../../etc/passwd"][0]')
assert_contains "T-93.07: traversal slug stays under proposedDir" "${PDIR}/" "$trav_path"
assert_not_contains "T-93.07: no traversal escape in path" "/etc/passwd/" "$trav_path"

# ── T-93.08: staged skill is INERT (cannot auto-fire) ────────────────────────
body=$(cat "${PDIR}/inst-01/SKILL.md")
assert_contains "T-93.08: disable-model-invocation true" "disable-model-invocation: true" "$body"
assert_contains "T-93.08: user-invocable false"          "user-invocable: false"          "$body"
assert_contains "T-93.08: status proposed"               "status: proposed"               "$body"

# ── T-93.09: provenance header + HITL gate reference + body ──────────────────
assert_contains "T-93.09: AUTO-GENERATED marker"  "AUTO-GENERATED INSTINCT" "$body"
assert_contains "T-93.09: approval-mcp (E-94) ref" "approval-mcp (E-94)"     "$body"
assert_contains "T-93.09: carries pattern_id"      "INST-01"                 "$body"
assert_contains "T-93.09: carries skill body"      "Test-Fix Instinct"       "$body"

# ── T-93.10: meta_analyst prompt documents the extraction contract ───────────
meta=$(cat "${META}")
assert_contains "T-93.10: Instinct Extraction section"  "Instinct Extraction Mode" "$meta"
assert_contains "T-93.10: extract_instincts contract"   "extract_instincts"        "$meta"
assert_contains "T-93.10: references the stager"        "instinct-stager.mjs"      "$meta"
assert_contains "T-93.10: HITL gate forward-ref (E-94)" "approval-mcp"             "$meta"

# ── T-93.11: staging area is documented in source ────────────────────────────
assert_exists "${REPO_ROOT}/src/gemini/skills/proposed/README.md"

rm -rf "$(dirname "${PDIR}")"
assert_summary
