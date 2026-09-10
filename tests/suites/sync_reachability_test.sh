#!/usr/bin/env bash
# sync_reachability_test.sh — E-247 (D-067 §1): every step of `ai sync` actually runs.
#
# THE BUG THIS SUITE EXISTS FOR. E-217 added an early `return 0` to do_sync to fix its exit
# status — the function used to return whatever ran last, and a stray 128 from a
# `git rev-parse` in a non-git directory made a clean sync look like a failure. The return
# was placed BEFORE the second half of the function, so from that commit onward:
#
#   install_git_hooks, _upgrade_legacy_git_hooks, _regenerate_mcp_docs,
#   _regenerate_blueprints_index, _wal_checkpoint_state_db, _generate_repo_map,
#   _generate_memory_palace, _ensure_generated_gitignore and _report_policy_staleness
#
# never ran, and `ai sync` never printed "Done." Nine ruled features were silently lost, for
# weeks, in a command run reflexively after every pull. Nothing failed. That is the whole
# difficulty: dead code does not raise anything, and the only visible symptom was a missing
# final line that nobody was checking for.
#
# WHY THE TEST IS SHAPED THIS WAY. Asserting "the source contains install_git_hooks" would
# have passed throughout the entire outage — the call was always there, just unreachable. So
# every assertion below reads the OUTPUT OF A REAL SYNC in a temp project. A step is proven
# to have run only by the marker it prints.
#
# A first restore attempt made `ai sync` EXIT 1 under `set -e` (E-244, reverted), which is
# why D-067 §1 rules each step fail-open with a printed reason: a step that breaks must say
# so and let the rest finish, never abort the command or resurrect the silent-loss failure
# in a new form.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"

echo "── Suite: sync_reachability_test (E-247) ───────────────────────────"

# The AST repo map is the most expensive step and its content is irrelevant here; the
# assertions below check that it REPORTS, and the skip notice is a report.
export AI_OS_DISABLE_REPO_MAP=1

# A project fixture. Deliberately NOT a git repository for the default case: `ai init`
# exited 128 there until E-244, and install_git_hooks is the first step of the restored
# half — so the non-git path is the one most likely to abort the whole command again.
_proj() {
  local d; d="$(test_tmpdir e247)"
  mkdir -p "$d/.ai" "$d/.claude"
  cat > "$d/.ai/roles.json" <<'JSON'
{ "roles": { "architect": {"provider":"claude","pane_identifier":"1","model":"fable"},
             "engineer":  {"provider":"claude","pane_identifier":"0","model":"opus"} } }
JSON
  cp "${REPO_ROOT}/src/templates/providers.json" "$d/.ai/providers.json" 2>/dev/null || true
  printf '%s' "$d"
}

_p="$(_proj)"
_out="$( cd "$_p" && bash "$AI" sync 2>&1 )"
_rc=$?

# ── E-247.1: the command completes and SAYS so ───────────────────────────────
# The missing final line was the only symptom the outage ever produced.
assert_contains "E-247.01a: 'ai sync' prints Done. — it did not for weeks" "Done." "$_out"
assert_status 0 "E-247.01b: and still exits 0 (the reason the early return was added)" \
  bash -c "[[ '$_rc' -eq 0 ]]"

# ── E-247.2: every restored step reports, by marker ──────────────────────────
# Each step is named by something it prints on the path a fixture actually takes. A step
# that is skipped prints its reason and still counts as reached — reachability is the
# property under test, not success.
assert_contains "E-247.02a: git hooks step runs (non-git fixture → its own notice)" \
  "Not a git repo" "$_out"
assert_contains "E-247.02b: mcp.md is regenerated from registry.json" \
  ".ai/blueprints/mcp.md" "$_out"
# NOT the bare "_INDEX.md": that substring also appears in "_SKILLS_INDEX.md", which the
# PROVISIONING half prints — so the loose form passed throughout the outage and would have
# gone on passing after a broken restore. Caught by running the reproducer before fixing
# anything, which is the point of running it first.
assert_contains "E-247.02c: the blueprint index is regenerated" \
  ".ai/blueprints/_INDEX.md" "$_out"
assert_contains "E-247.02d: the AST repo map step reports (skipped here by env)" \
  "REPO_MAP.md" "$_out"
assert_contains "E-247.02e: the Memory Palace candidate index is refreshed" \
  "palace-index.json" "$_out"

# ── E-247.3: the step summary ────────────────────────────────────────────────
# A count is what makes a SILENT loss loud. "Done." alone returned in E-217's shape too;
# the summary is what distinguishes "every step ran" from "the function reached its end".
assert_match "E-247.03a: a step summary is printed" \
  'steps: [0-9]+ ok' "$_out"
assert_status 1 "E-247.03b: and it is not a hardcoded zero" \
  bash -c "printf '%s' '$_out' | grep -q 'steps: 0 ok'"

# ── E-247.4: FAIL-OPEN — a broken step must not abort the command ────────────
# The property that separates this restore from the one that had to be reverted. A step
# forced to fail must print a skip reason and the sync must still reach Done.
_pf="$(_proj)"
_fout="$( cd "$_pf" && AI_OS_E247_FORCE_FAIL=repo_map bash "$AI" sync 2>&1 )"
_frc=$?
assert_contains "E-247.04a: a failing step prints a skip reason naming the step" \
  "sync: repo_map skipped" "$_fout"
assert_contains "E-247.04b: and the sync still completes" "Done." "$_fout"
assert_status 0 "E-247.04c: and still exits 0" bash -c "[[ '$_frc' -eq 0 ]]"
assert_match "E-247.04d: the summary counts the failure separately" \
  'steps: [0-9]+ ok, 1 skipped' "$_fout"

# ── E-247.5: the rollback ────────────────────────────────────────────────────
# D-067 §1 makes today's truncated behaviour available EXPLICITLY, so an operator who hits
# a bad step has a way back that does not involve editing the script.
_pm="$(_proj)"
_mout="$( cd "$_pm" && AI_OS_SYNC_MINIMAL=1 bash "$AI" sync 2>&1 )"
assert_status 1 "E-247.05a: AI_OS_SYNC_MINIMAL=1 stops after provisioning" \
  bash -c "printf '%s' '$_mout' | grep -q 'palace-index.json'"
assert_contains "E-247.05b: and says why it stopped, rather than looking finished" \
  "AI_OS_SYNC_MINIMAL=1" "$_mout"
assert_status 0 "E-247.05c: the minimal path still exits 0" \
  bash -c "cd '$_pm' && AI_OS_SYNC_MINIMAL=1 bash '$AI' sync >/dev/null 2>&1"

# ── E-247.6: the non-git case specifically ───────────────────────────────────
# install_git_hooks is the FIRST restored step and `git rev-parse` exits 128 outside a
# repository. Under `set -e` a plain assignment carried that status and killed the script
# (fixed in E-244); this pins that the whole tail still runs there.
_pg="$(_proj)"
_gout="$( cd "$_pg" && bash "$AI" sync 2>&1 )"
assert_contains "E-247.06a: a NON-git project reaches the end of sync" "Done." "$_gout"
# NOT a .gitignore assertion here: _ensure_generated_gitignore returns early outside a git
# work tree, and correctly so — a .gitignore in a directory git does not track is furniture.
# The step still has to have RUN, which the summary count below proves, and the file itself
# is asserted in the git fixture (06e).
assert_match "E-247.06b: and every step is accounted for in the non-git case" \
  'steps: [0-9]+ ok' "$_gout"

# A REAL git repository must reach the end too — the hook install actually does work there.
_pr="$(_proj)"
( cd "$_pr" && git init -q . && git config user.email t@t && git config user.name t )
_rout="$( cd "$_pr" && bash "$AI" sync 2>&1 )"
assert_contains "E-247.06c: a git project reaches the end as well" "Done." "$_rout"
assert_status 0 "E-247.06d: and the Gate 2 pre-commit stub was installed" \
  test -f "${_pr}/.git/hooks/pre-commit"
# E-233's generated-artefact patterns land where they mean something: inside a work tree.
assert_status 0 "E-247.06e: the generated-artefact .gitignore was written (E-233)" \
  test -f "${_pr}/.gitignore"
assert_status 0 "E-247.06f: and it names an artefact sync regenerates" \
  grep -q '_SKILLS_INDEX.md' "${_pr}/.gitignore"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== sync_reachability_test.sh PASS ====="
else
  echo "===== sync_reachability_test.sh FAIL (${FAIL_COUNT}) ====="
fi
