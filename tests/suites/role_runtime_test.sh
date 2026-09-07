#!/usr/bin/env bash
# role_runtime_test.sh — E-215 (architect-provider-parity.md §Components 5-6):
# ARCHITECT.md runtime ladder + the `ai doctor` per-role provisioning report.
#
# ARCHITECT.md named `activate_skill` as THE way to invoke a skill. That is an MCP tool
# a Claude-hosted Architect may not have, while the Skill tool does not exist on agy —
# so the rulefile was wrong for whichever runtime it was not written for. The ladder
# makes it correct on both.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ARCH_TPL="${REPO_ROOT}/src/templates/ARCHITECT.md"
ENG_TPL="${REPO_ROOT}/src/templates/ENGINEER.md"
AI_BIN="${REPO_ROOT}/src/bin/ai"
MANIFEST="${REPO_ROOT}/src/shared/role-manifest.mjs"

echo "── Suite: role_runtime_test (E-215) ─────────────────────────────────"

# ── E-215.1: Session Start ladder mirrors ENGINEER.md ───────────────────────
assert_status 0 "E-215.01a: ARCHITECT.md step 1 is the Skill tool" \
  grep -q 'skill: "ai-preflight"' "$ARCH_TPL"
assert_status 0 "E-215.01b: step 2 falls back to run_preflight" \
  grep -q 'mcp__orchestrator-mcp__run_preflight()' "$ARCH_TPL"
assert_status 0 "E-215.01c: step 3 is activate_skill as last resort" \
  grep -q 'activate_skill({ skill_name: "ai-preflight" })' "$ARCH_TPL"
# The manual read order must survive as the floor when every layer fails.
assert_status 0 "E-215.01d: the DIGEST-first manual read order is retained" \
  grep -q 'DIGEST.md → .ai/architect.md → .ai/TASKS.md' "$ARCH_TPL"
# Both rulefiles must offer the same three steps — that is what "mirror" means here.
for _step in 'skill: "ai-preflight"' 'mcp__orchestrator-mcp__run_preflight()' 'activate_skill({ skill_name: "ai-preflight" })'; do
  assert_status 0 "E-215.01e: ENGINEER.md also offers [$_step]" grep -qF "$_step" "$ENG_TPL"
done

# ── E-215.2: Skill Invocation is runtime-aware ─────────────────────────────
assert_status 0 "E-215.02a: 'use the Skill tool when present' is stated" \
  grep -qi 'Use the Skill tool when present' "$ARCH_TPL"
assert_status 0 "E-215.02b: the MCP invoker remains documented for agy" \
  grep -q 'activate_skill({ skill_name: "", list_skills: true })' "$ARCH_TPL"
assert_status 0 "E-215.02c: the compact pattern offers both runtimes" \
  grep -q 'skill: "ai-compact"' "$ARCH_TPL"

# ── E-215.3: Gemini Model Mandate moved under Provider notes ───────────────
assert_status 0 "E-215.03a: a Provider notes heading exists" \
  grep -qE '^## Provider notes$' "$ARCH_TPL"
assert_status 1 "E-215.03b: Model Mandate is no longer a top-level heading" \
  grep -qE '^## Model Mandate' "$ARCH_TPL"
assert_status 0 "E-215.03c: it survives as a gemini-scoped subsection" \
  grep -qE '^### Gemini provider — Model Mandate' "$ARCH_TPL"
# The content itself must not be lost — this is a re-home, not a deletion.
assert_status 0 "E-215.03d: the pinned model is still named" \
  grep -q 'gemini-3.1-pro' "$ARCH_TPL"
assert_status 0 "E-215.03e: the rollback path is still documented" \
  grep -q 'GEMINI_MODEL=gemini-2.5-pro' "$ARCH_TPL"

# ── E-215.4: sovereign text untouched ──────────────────────────────────────
assert_status 0 "E-215.04a: the Forbidden Zone section is intact" \
  grep -qE '^## The Forbidden Zone$' "$ARCH_TPL"
assert_status 0 "E-215.04b: the §35 ANTI-DRIFT section is intact" \
  grep -qE '^## ANTI-DRIFT PROTOCOL' "$ARCH_TPL"
assert_status 0 "E-215.04c: the Role Resolution clause (E-208) is intact" \
  grep -q 'Role Resolution (D-054' "$ARCH_TPL"
# The shims are load-bearing (D-051) and must not have been touched.
assert_status 0 "E-215.04d: GEMINI.md is still a pure @import shim" \
  grep -q '@ARCHITECT.md' "${REPO_ROOT}/src/templates/GEMINI.md"
assert_status 0 "E-215.04e: CLAUDE.md is still a pure @import shim" \
  grep -q '@ENGINEER.md' "${REPO_ROOT}/src/templates/CLAUDE.md"

# The project root copies are what an agent actually loads — keep them in step.
assert_status 0 "E-215.04f: root ARCHITECT.md matches its template" \
  diff -q "$ARCH_TPL" "${REPO_ROOT}/ARCHITECT.md"

# ── E-215.5: role-manifest CLI vs import (the _isMain trap) ────────────────
# argv[1] IS the module path when the module is imported dynamically, so a filename
# suffix test wrongly concluded "I am the CLI" and printed usage + exit 2 into the
# importing caller. `ai doctor` aborted mid-report because of it.
assert_status 0 "E-215.05a: the CLI path still prints source dirs" \
  bash -c "node --no-warnings '$MANIFEST' '${REPO_ROOT}/.ai' '${REPO_ROOT}/src/config/registry.json' claude | grep -q 'shared/skills'"
# A tiny probe script keeps the quoting readable — the point is that IMPORTING the
# module must print only the returned value, with no CLI usage banner leaking in.
# .cjs extension: node needs it to pick a module format for a temp file.
_PROBE="$(mktemp).cjs"
cat > "$_PROBE" <<'PROBE'
const { pathToFileURL } = require("node:url");
// slice(2): argv[0] is node, argv[1] is THIS probe script.
const [mod, registry, role] = process.argv.slice(2);
import(pathToFileURL(mod).href).then((m) => {
  process.stdout.write(m.rulefileForRole(registry, role) || "(empty)");
});
PROBE
_rulefile() {  # <role> → resolved rulefile, plus anything the import leaked
  node --no-warnings "$_PROBE" "$MANIFEST" "${REPO_ROOT}/src/config/registry.json" "$1" 2>&1
}
assert_contains "E-215.05b: importing resolves the architect rulefile" "ARCHITECT.md" "$(_rulefile architect)"
assert_not_contains "E-215.05c: importing leaks no CLI usage banner" "usage: role-manifest.mjs" "$(_rulefile architect)"
assert_contains "E-215.05d: importing resolves the engineer rulefile" "ENGINEER.md" "$(_rulefile engineer)"
assert_contains "E-215.05e: an unknown role resolves to empty, not a crash" "(empty)" "$(_rulefile nosuchrole)"
rm -f "$_PROBE"

# ── E-215.6: the doctor per-role report ────────────────────────────────────
_DOC="$(cd "$REPO_ROOT" && bash "$AI_BIN" doctor 2>&1)"
assert_contains "E-215.06a: doctor prints a per-role section" "Per-role provisioning" "$_DOC"
assert_contains "E-215.06b: it reports the architect's provider" "architect →" "$_DOC"
assert_contains "E-215.06c: it reports the engineer's provider" "engineer →" "$_DOC"
assert_contains "E-215.06d: it reports skills" "skills" "$_DOC"
assert_contains "E-215.06e: it reports agents" "agents" "$_DOC"
assert_contains "E-215.06f: it reports the settings overlay" "overlay" "$_DOC"
assert_contains "E-215.06g: it reports the rulefile" "rulefile" "$_DOC"
# The report must reach the END of both roles — it previously aborted after the
# overlay line because a failing node lookup tripped `set -e`.
assert_contains "E-215.06h: the report completes through the engineer's rulefile" "ENGINEER.md" "$_DOC"
assert_contains "E-215.06i: and the architect's rulefile" "ARCHITECT.md" "$_DOC"
assert_contains "E-215.06j: doctor continues past the report" "Project-Scoped" "$_DOC"

# It is diagnostic only — it must never change the tree.
_BEFORE="$(cd "$REPO_ROOT" && git status --porcelain | md5 -q)"
( cd "$REPO_ROOT" && bash "$AI_BIN" doctor >/dev/null 2>&1 )
_AFTER="$(cd "$REPO_ROOT" && git status --porcelain | md5 -q)"
assert_status 0 "E-215.06k: doctor is read-only (working tree unchanged)" \
  bash -c "[[ '$_BEFORE' == '$_AFTER' ]]"

# A project with a role bound to a non-claude provider must report n/a, not a failure.
_AGY="$(mktemp -d)"; mkdir -p "$_AGY/.ai"
cat > "$_AGY/.ai/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "agy", "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON
_DOC_AGY="$( cd "$_AGY" && bash "$AI_BIN" doctor 2>&1 )"
assert_contains "E-215.06l: an agy-bound architect is reported as such" "architect → agy" "$_DOC_AGY"
assert_contains "E-215.06m: agy agents are reported n/a (they ship as a plugin)" \
  "n/a for agy" "$_DOC_AGY"
assert_contains "E-215.06n: the overlay is n/a for a non-claude provider" \
  "n/a for provider" "$_DOC_AGY"
rm -rf "$_AGY"

assert_summary
