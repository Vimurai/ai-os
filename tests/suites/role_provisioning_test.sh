#!/usr/bin/env bash
# role_provisioning_test.sh — E-212 (architect-provider-parity.md §Components 1-2):
# role-aware provisioning. `do_sync` used to provision by PROVIDER DIRECTORY, which
# silently equated provider with role — fine while each vendor served one role, wrong
# under D-054 where one provider can serve both. These assertions pin the join:
# registry.json `roles` (which dirs serve which role) x .ai/roles.json (which provider
# holds which role). E-254 (D-069): both roles are served from src/claude/*, so the
# join is now visible in the SERVED-ROLES output rather than in distinct directories.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
MANIFEST="${REPO_ROOT}/src/shared/role-manifest.mjs"
REGISTRY="${REPO_ROOT}/src/config/registry.json"

echo "── Suite: role_provisioning_test (E-212) ────────────────────────────"

# ── E-212.1: the manifest exists and names the one source adapter (D-069) ────
assert_status 0 "E-212.01a: registry.json declares a roles manifest" \
  bash -c "python3 -c \"import json;d=json.load(open('$REGISTRY'));assert 'roles' in d\""
assert_status 0 "E-212.01b: architect maps to claude/skills" \
  bash -c "python3 -c \"import json;d=json.load(open('$REGISTRY'));assert d['roles']['architect']['skill_dirs']==['claude/skills']\""
assert_status 0 "E-212.01c: engineer maps to claude/*" \
  bash -c "python3 -c \"import json;d=json.load(open('$REGISTRY'));assert d['roles']['engineer']['agent_dirs']==['claude/agents']\""
assert_status 0 "E-212.01d: each role names its rulefile" \
  bash -c "python3 -c \"import json;d=json.load(open('$REGISTRY'));assert d['roles']['architect']['rulefile']=='ARCHITECT.md' and d['roles']['engineer']['rulefile']=='ENGINEER.md'\""

# ── E-212.2: the join — provider -> source dirs ──────────────────────────────
_dual="$(mktemp -d)"; mkdir -p "$_dual"
cat > "$_dual/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "claude", "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON
# A role bound to a provider OTHER than claude. `acme` is a neutral declared name; the
# manifest must still join on it, whatever the provider is called.
_split="$(mktemp -d)"; mkdir -p "$_split"
cat > "$_split/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "acme",   "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON

_src() { node --no-warnings "$MANIFEST" "$1" "$REGISTRY" "$2" "${3:-}" 2>/dev/null | tr '\n' ' '; }

# All-Claude: one provider serves BOTH roles, so it receives the union.
assert_contains "E-212.02a: dual-claude — claude gets the role skill dir" "claude/skills" "$(_src "$_dual" claude)"
assert_contains "E-212.02c: dual-claude — shared is always included" "shared/skills" "$(_src "$_dual" claude)"
assert_contains "E-212.02e: dual-claude — claude gets the role agent dir" "claude/agents" "$(_src "$_dual" claude --agents)"
assert_contains "E-212.02f: dual-claude — both roles reported as served" "architect engineer" "$(_src "$_dual" claude --roles)"
# UNION, deduped: both roles name claude/skills, and a doubled entry would sync it twice
# (the second pass through the no-clobber path, reporting every skill as a collision).
assert_status 0 "E-254.02g: the union is deduped — claude/skills listed exactly once" \
  bash -c "[ \"\$(node --no-warnings '$MANIFEST' '$_dual' '$REGISTRY' claude | grep -cx 'claude/skills')\" -eq 1 ]"

# Split: the provider holding ONE role must be reported as serving only that role.
assert_contains "E-212.03a: split — claude serves the Engineer" "engineer" "$(_src "$_split" claude --roles)"
assert_not_contains "E-212.03b: split — claude does NOT serve the Architect" "architect" "$(_src "$_split" claude --roles)"
assert_contains "E-212.03c: split — the Architect's provider gets the role skill dir" "claude/skills" "$(_src "$_split" acme)"
assert_contains "E-212.03d: split — and still gets shared" "shared/skills" "$(_src "$_split" acme)"

# A provider bound to no role gets shared only — a normal state, not an error.
assert_contains "E-212.04a: an unserved provider still receives shared" "shared/skills" "$(_src "$_split" nosuchprovider)"
assert_not_contains "E-212.04b: an unserved provider receives no role dirs" "claude/skills" "$(_src "$_split" nosuchprovider)"
assert_status 0 "E-212.04c: an unserved provider is not an error" \
  bash -c "node --no-warnings '$MANIFEST' '$_split' '$REGISTRY' nosuchprovider >/dev/null 2>&1"

# Corrupt / missing config degrades to shared rather than throwing.
_bad="$(mktemp -d)"; echo 'not json{' > "$_bad/roles.json"
assert_contains "E-212.05a: corrupt roles.json degrades to shared, never throws" "shared/skills" "$(_src "$_bad" claude)"
assert_contains "E-212.05b: absent roles.json degrades to shared" "shared/skills" "$(_src "$(mktemp -d)" claude)"

# ── E-212.6: bash 3.2 — empty arrays under `set -u` ──────────────────────────
# macOS ships bash 3.2.57, where expanding an EMPTY array as "${arr[@]}" raises
# "unbound variable" (safe only from 4.4). An unserved provider produces exactly that
# empty list, so this is the common path. Caught live: sync aborted mid-run and left
# workspaces unprovisioned.
assert_status 0 "E-212.06a: src/bin/ai parses under bash 3.2" /bin/bash -n "$AI_BIN"
assert_status 0 "E-212.06b: array expansions are count-guarded, not bare" \
  grep -q 'NOTE ON BASH 3.2' "$AI_BIN"
assert_status 0 "E-212.06c: agent_dirs expansion is count-guarded" \
  grep -q 'agent_dirs\[@\]}" -gt 0' "$AI_BIN"
assert_status 0 "E-212.06d: skill_dirs expansion is count-guarded" \
  grep -q 'skill_dirs\[@\]}" -gt 0' "$AI_BIN"

# BEHAVIOURAL: a real sync in a project where claude serves only ONE role. This is the
# shape of the original abort — a source-text assertion alone would not catch it,
# because the expansion is still present, just guarded.
_e212_ws="$(mktemp -d)"
mkdir -p "$_e212_ws/.ai"
cat > "$_e212_ws/.ai/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "acme", "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON
# E-244: run the WORKING TREE's ai, not ${HOME}/.ai-os/bin/ai. These are assertions about
# how the code BEHAVES, and the installed mirror is whatever version was last installed —
# so on a developer machine they silently tested the previous release. That is not
# hypothetical: with the mirror one release behind, a case here passed locally and failed
# on CI, where `ai install` runs from HEAD. An environment-dependent assertion (E-236) in
# the suite that exists to prove provisioning works.
_e212_out="$(cd "$_e212_ws" && /bin/bash "$AI_BIN" sync 2>&1)"; _e212_rc=$?
assert_not_contains "E-212.06e: sync completes with no unbound-variable abort (bash 3.2)" \
  "unbound variable" "$_e212_out"
assert_status 0 "E-212.06e2: and exits 0" test "$_e212_rc" -eq 0
assert_status 0 "E-212.06g: the Engineer's workspace is still provisioned" \
  test -f "$_e212_ws/.claude/skills/ai-task/SKILL.md"
assert_contains "E-212.06h: and it reports serving the Engineer role" \
  ".claude/ serves role(s): engineer" "$_e212_out"

# ── E-212.7: the 7 Architect agents meet the Claude frontmatter contract ─────
for a in ux_reviewer docs-architect knowledge_architect meta_analyst memory_curator seo_manager seo_content_generator; do
  f="${REPO_ROOT}/src/claude/agents/${a}.md"
  assert_status 0 "E-212.07 [$a]: declares allowed-tools" grep -qE '^allowed-tools:' "$f"
  assert_status 0 "E-212.07 [$a]: declares context: fork" grep -qE '^context: fork$' "$f"
  assert_status 0 "E-212.07 [$a]: declares agent: general-purpose" grep -qE '^agent: general-purpose$' "$f"
  # NOT widened: these are advisory Architect personas (Forbidden Zone), so the contract
  # must not hand them Bash/Write/Edit.
  assert_status 1 "E-212.07 [$a]: allowed-tools does not add Bash" \
    bash -c "grep -E '^allowed-tools:' '$f' | grep -q 'Bash'"
  assert_status 1 "E-212.07 [$a]: allowed-tools does not add Write/Edit" \
    bash -c "grep -E '^allowed-tools:' '$f' | grep -qE '\\bWrite\\b|\\bEdit\\b'"
done

# ── E-217 (D-055 R2): collision resolved by renaming; guard is now fatal ────
echo "  [E-217] skill-name collision resolution"

# The Architect's task/history skills are RENAMED, not deduplicated — they do a
# different job for a different role. Same reason arch-review is not ai-review (E-149).
assert_status 0 "E-217.01a: arch-task exists in the Architect set" \
  test -f "${REPO_ROOT}/src/claude/skills/arch-task/SKILL.md"
assert_status 0 "E-217.01b: arch-oracle exists in the Architect set" \
  test -f "${REPO_ROOT}/src/claude/skills/arch-oracle/SKILL.md"
assert_status 1 "E-217.01c: the Architect set no longer ships ai-task" \
  test -e "${REPO_ROOT}/src/claude/skills/ai-task"
assert_status 1 "E-217.01d: the Architect set no longer ships repo-oracle" \
  test -e "${REPO_ROOT}/src/claude/skills/repo-oracle"
# The ENGINEER keeps the original names — that is the point of the rename.
assert_status 0 "E-217.01e: the Engineer keeps ai-task" \
  test -f "${REPO_ROOT}/src/shared/skills/ai-task/SKILL.md"
assert_status 0 "E-217.01f: the Engineer keeps repo-oracle" \
  test -f "${REPO_ROOT}/src/shared/skills/repo-oracle/SKILL.md"
# Frontmatter name must match the directory, or the skill loads under the old name.
assert_status 0 "E-217.01g: arch-task frontmatter name matches" \
  grep -qE '^name: arch-task$' "${REPO_ROOT}/src/claude/skills/arch-task/SKILL.md"
assert_status 0 "E-217.01h: arch-oracle frontmatter name matches" \
  grep -qE '^name: arch-oracle$' "${REPO_ROOT}/src/claude/skills/arch-oracle/SKILL.md"

# References must follow the rename, and ARCHITECT.md must explain WHY the names
# differ so nobody "corrects" them back to match the Engineer's.
assert_status 0 "E-217.02a: ARCHITECT.md points at arch-task" \
  grep -q 'arch-task' "${REPO_ROOT}/src/templates/ARCHITECT.md"
assert_status 0 "E-217.02b: ARCHITECT.md records why the names differ" \
  grep -q 'must not collide' "${REPO_ROOT}/src/templates/ARCHITECT.md"
assert_status 0 "E-217.02c: task-planner hands back to arch-task" \
  grep -q 'skill: arch-task' "${REPO_ROOT}/src/claude/skills/task-planner/SKILL.md"
assert_status 0 "E-217.02d: root ARCHITECT.md matches its template" \
  diff -q "${REPO_ROOT}/src/templates/ARCHITECT.md" "${REPO_ROOT}/ARCHITECT.md"

# All 20 agents now satisfy the frontmatter contract (seo_engineer lacked `context:`
# since E-90 — the only one failing, deliberately left alone in E-212 and fixed here).
assert_status 0 "E-217.03a: seo_engineer declares context:" \
  grep -qE '^context: fork$' "${REPO_ROOT}/src/claude/agents/seo_engineer.md"
_E217_BAD=0
for _f in "${REPO_ROOT}"/src/claude/agents/*.md; do
  for _k in name description allowed-tools context agent; do
    grep -qE "^${_k}:" "$_f" || _E217_BAD=$((_E217_BAD + 1))
  done
done
assert_contains "E-217.03b: every agent satisfies the frontmatter contract" "0" "$_E217_BAD"

# The guard is FATAL in a multi-role workspace and inert in a single-role one.
assert_status 0 "E-217.04a: sync returns non-zero on an unresolved collision" \
  grep -q 'unresolved skill-name collision' "$AI_BIN"
assert_status 0 "E-217.04b: the error names the rename precedent" \
  grep -q 'arch-task, arch-oracle, arch-review' "$AI_BIN"
# A name already on DISK is not a collision — it may be a stale copy from an earlier
# sync. Only a name claimed by ANOTHER SOURCE in the same run counts; comparing against
# disk residue reported task-planner, which exists in exactly one source dir.
assert_status 0 "E-217.04c: collisions compare sources within a run, not disk residue" \
  grep -q '_SKILL_CLAIMS' "$AI_BIN"
assert_status 0 "E-217.04d: sync returns success explicitly (no stray git status)" \
  grep -q 'Explicit success: without it do_sync returns' "$AI_BIN"

assert_summary
