#!/usr/bin/env bash
# skill_promoter_test.sh — Tests for E-94 approval-gated skill promotion
# (ecc-integrations.md §Components 2 & §Security): src/shared/skill-promoter.mjs.
#
# Deterministic: imports the real promoter (+ instinct-stager for staging) and
# exercises the approval-mcp decision gate. Covers APPROVED promotion +
# frontmatter activation, fail-closed REJECTED/NON_TTY/missing decisions,
# no-clobber of active skills, dangerous-content re-scan, and unsafe slugs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROMOTER="${REPO_ROOT}/src/shared/skill-promoter.mjs"
STAGER="${REPO_ROOT}/src/shared/instinct-stager.mjs"
META="${REPO_ROOT}/src/gemini/agents/meta_analyst.md"

echo "── Suite: skill_promoter_test (E-94) ───────────────────────────────"

INSTINCT='[{"pattern_id":"INST-01","confidence_score":0.9,"trigger_condition":"after green tests","proposed_skill_content":"# Commit Instinct\n\nStage, write a Conventional Commit, push."}]'

# stage_and_promote <decisionJSON|""> → JSON { res, proposedExists, activeExists, activeContent, proposedList }
stage_and_promote() {
  local decision="$1"
  local root; root="$(mktemp -d)"
  PDIR="${root}/proposed" ADIR="${root}/active" DEC="$decision" INST="$INSTINCT" \
  node --input-type=module -e "
import { stageInstincts } from '${STAGER}';
import { promoteSkill, listProposedSkills } from '${PROMOTER}';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
const PDIR=process.env.PDIR, ADIR=process.env.ADIR;
stageInstincts(JSON.parse(process.env.INST), { proposedDir: PDIR });
const proposedList = listProposedSkills(PDIR).map(s=>s.slug);
const decision = process.env.DEC ? JSON.parse(process.env.DEC) : undefined;
const res = promoteSkill('inst-01', { proposedDir: PDIR, activeDir: ADIR, decision });
const ap = resolve(ADIR,'inst-01','SKILL.md');
console.log(JSON.stringify({ res, proposedList,
  proposedExists: existsSync(resolve(PDIR,'inst-01','SKILL.md')),
  activeExists: existsSync(ap),
  activeContent: existsSync(ap) ? readFileSync(ap,'utf8') : '' }));
"
  rm -rf "$root"
}
jq_get() { python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print($1)"; }

# ── T-94.01: listProposedSkills enumerates staged proposals ──────────────────
out=$(stage_and_promote '{"status":"APPROVED","id":7}')
assert_contains "T-94.01: proposal listed before promote" "inst-01" "$(echo "$out" | jq_get 'd["proposedList"]')"

# ── T-94.02: APPROVED decision promotes + activates frontmatter ──────────────
assert_contains "T-94.02: promoted=true"               "True"  "$(echo "$out" | jq_get 'd["res"]["promoted"]')"
assert_contains "T-94.02: active SKILL.md written"      "True"  "$(echo "$out" | jq_get 'd["activeExists"]')"
assert_contains "T-94.02: model-invocation enabled"    "disable-model-invocation: false" "$(echo "$out" | jq_get 'd["activeContent"]')"
assert_contains "T-94.02: user-invocable enabled"      "user-invocable: true"            "$(echo "$out" | jq_get 'd["activeContent"]')"
assert_contains "T-94.02: status active"               "status: active"                  "$(echo "$out" | jq_get 'd["activeContent"]')"
assert_contains "T-94.02: promotion provenance stamp"  "PROMOTED to active via approval-mcp HITL gate (E-94)" "$(echo "$out" | jq_get 'd["activeContent"]')"
assert_contains "T-94.02: proposal removed from staging" "False" "$(echo "$out" | jq_get 'd["proposedExists"]')"
assert_not_contains "T-94.02: stale PROPOSED provenance stripped" "PROPOSED, NOT ACTIVE" "$(echo "$out" | jq_get 'd["activeContent"]')"

# ── T-94.03: REJECTED decision is fail-closed ────────────────────────────────
out=$(stage_and_promote '{"status":"REJECTED"}')
assert_contains "T-94.03: not promoted"          "False"               "$(echo "$out" | jq_get 'd["res"]["promoted"]')"
assert_contains "T-94.03: reason not-approved"   "not-approved:REJECTED" "$(echo "$out" | jq_get 'd["res"]["reason"]')"
assert_contains "T-94.03: no active skill"       "False"               "$(echo "$out" | jq_get 'd["activeExists"]')"
assert_contains "T-94.03: proposal preserved"    "True"                "$(echo "$out" | jq_get 'd["proposedExists"]')"

# ── T-94.04: NON_TTY decision is fail-closed ─────────────────────────────────
out=$(stage_and_promote '{"status":"NON_TTY"}')
assert_contains "T-94.04: NON_TTY refused" "not-approved:NON_TTY" "$(echo "$out" | jq_get 'd["res"]["reason"]')"

# ── T-94.05: missing decision is fail-closed ─────────────────────────────────
out=$(stage_and_promote '')
assert_contains "T-94.05: no-decision refused" "not-approved:no-decision" "$(echo "$out" | jq_get 'd["res"]["reason"]')"

# ── T-94.06: no-clobber of an existing active skill ──────────────────────────
root="$(mktemp -d)"
out=$(PDIR="${root}/proposed" ADIR="${root}/active" INST="$INSTINCT" node --input-type=module -e "
import { stageInstincts } from '${STAGER}';
import { promoteSkill } from '${PROMOTER}';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
const PDIR=process.env.PDIR, ADIR=process.env.ADIR;
stageInstincts(JSON.parse(process.env.INST), { proposedDir: PDIR });
mkdirSync(resolve(ADIR,'inst-01'),{recursive:true});
writeFileSync(resolve(ADIR,'inst-01','SKILL.md'),'# REAL ACTIVE SKILL\\n','utf8');
const res = promoteSkill('inst-01',{ proposedDir:PDIR, activeDir:ADIR, decision:{status:'APPROVED'} });
const kept = readFileSync(resolve(ADIR,'inst-01','SKILL.md'),'utf8');
console.log(JSON.stringify({ res, kept }));
")
rm -rf "$root"
assert_contains "T-94.06: refuses to clobber active" "active-skill-exists" "$(echo "$out" | jq_get 'd["res"]["reason"]')"
assert_contains "T-94.06: existing active untouched"  "REAL ACTIVE SKILL"  "$(echo "$out" | jq_get 'd["kept"]')"

# ── T-94.07: dangerous content re-scan blocks promotion (defence in depth) ───
root="$(mktemp -d)"
mkdir -p "${root}/proposed/danger"
cat > "${root}/proposed/danger/SKILL.md" <<'SKILL'
---
name: danger
disable-model-invocation: true
user-invocable: false
status: proposed
---
# Danger
rm -rf /tmp/x
SKILL
out=$(PDIR="${root}/proposed" ADIR="${root}/active" node --input-type=module -e "
import { promoteSkill } from '${PROMOTER}';
const res = promoteSkill('danger',{ proposedDir:process.env.PDIR, activeDir:process.env.ADIR, decision:{status:'APPROVED'} });
console.log(JSON.stringify({ res }));
")
rm -rf "$root"
assert_contains "T-94.07: dangerous content blocked even if approved" "dangerous-content" "$(echo "$out" | jq_get 'd["res"]["reason"]')"

# ── T-94.08: unsafe slug is rejected ─────────────────────────────────────────
out=$(node --input-type=module -e "
import { promoteSkill } from '${PROMOTER}';
console.log(JSON.stringify({ res: promoteSkill('../escape',{ proposedDir:'/tmp/p', activeDir:'/tmp/a', decision:{status:'APPROVED'} }) }));
")
assert_contains "T-94.08: unsafe slug refused" "unsafe-slug" "$(echo "$out" | jq_get 'd["res"]["reason"]')"

# ── T-94.09: meta_analyst documents the approval-gated promotion flow ────────
meta=$(cat "${META}")
assert_contains "T-94.09: promotion section present"   "Promotion to active (E-94" "$meta"
assert_contains "T-94.09: uses request_approval"       "request_approval"          "$meta"
assert_contains "T-94.09: references skill-promoter"   "skill-promoter.mjs"        "$meta"
assert_contains "T-94.09: notes fail-closed NON_TTY"   "NON_TTY"                   "$meta"

assert_summary
