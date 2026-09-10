#!/usr/bin/env bash
# provider_workspace_test.sh — E-244 (D-066 §4): workspaces follow the role binding.
#
# `ai sync` provisioned .claude/, .gemini/ AND .agents/ on every project, unconditionally,
# regardless of what .ai/roles.json said. Under the all-Claude default that leaves two
# fully-populated workspaces — ~40 skill directories — for CLIs nothing will ever launch.
#
# THE DANGEROUS HALF IS THE PRUNE, and it is weighted accordingly below. "Delete the
# directory of a provider nobody uses" is one careless `rm -rf` away from deleting a
# user's own skill, so the prune reuses E-220's evidence rules with an EMPTY source set:
# sync wrote it, nobody edited it, nothing upstream provides it. Everything else is
# reported and kept, and the directory survives if anything is left in it.
#
# .claude/ IS NEVER STALE even when roles.json does not name claude — the git hooks,
# settings.json and the SessionStart role stamp live there. A corrupt roles.json must not
# take the hook wiring with it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PW="${REPO_ROOT}/src/shared/provider-workspace.mjs"
# The AST repo map is irrelevant to provider workspaces and is the most expensive thing
# a sync does; every `ai sync` below runs the full pipeline otherwise.
export AI_OS_DISABLE_REPO_MAP=1
AI="${REPO_ROOT}/src/bin/ai"

echo "── Suite: provider_workspace_test (E-244) ──────────────────────────"

# A project fixture: <architect-provider> <engineer-provider>, with the workspace dirs
# that exist named after them.
_proj() {  # <arch> <eng> [dirs-to-create...]
  local arch="$1" eng="$2"; shift 2
  local d; d="$(test_tmpdir e244)"
  mkdir -p "$d/.ai"
  cat > "$d/.ai/roles.json" <<JSON
{ "roles": { "architect": {"provider":"${arch}","pane_identifier":"1"},
             "engineer":  {"provider":"${eng}","pane_identifier":"0"} } }
JSON
  cp "${REPO_ROOT}/src/templates/providers.json" "$d/.ai/providers.json"
  local x; for x in "$@"; do mkdir -p "$d/$x"; done
  printf '%s' "$d"
}

_classify() { ( cd "$1" && node "$PW" list .ai . 2>/dev/null ); }
_stale()    { ( cd "$1" && node "$PW" stale .ai . 2>/dev/null ); }

# ── E-244.1: classification follows .ai/roles.json ────────────────────────────
_all_claude="$(_proj claude claude .claude .gemini .agents)"
_c="$(_classify "$_all_claude")"
assert_contains "E-244.01a: claude is 'always' (hooks + settings live there)" \
  $'claude\t.claude\talways' "$_c"
assert_contains "E-244.01b: an unbound gemini workspace is STALE" \
  $'gemini\t.gemini\tstale' "$_c"
assert_contains "E-244.01c: an unbound agy workspace is STALE" \
  $'agy\t.agents\tstale' "$_c"

# A SPLIT Triad must classify exactly the other way, or the rule is just "delete .gemini".
_split="$(_proj agy claude .claude .gemini .agents)"
_s="$(_classify "$_split")"
assert_contains "E-244.01d: with the Architect on agy, .agents/ is MAPPED, not stale" \
  $'agy\t.agents\tmapped' "$_s"
assert_status 1 "E-244.01e: and agy does not appear in the stale list" \
  bash -c "_o=\$(cd '$_split' && node '$PW' stale .ai . 2>/dev/null); printf '%s' \"\$_o\" | grep -q '^agy'"

# A directory that does not exist is not stale — there is nothing to clean up.
_none="$(_proj claude claude .claude)"
assert_status 1 "E-244.01f: an ABSENT workspace is never reported as stale" \
  bash -c "cd '$_none' && node '$PW' stale .ai . >/dev/null 2>&1"

# ── E-244.2: FAIL-SAFE — an unreadable roles.json prunes nothing ──────────────
# Deleting a live workspace because a config failed to parse is the one outcome this
# feature must never produce.
_corrupt="$(_proj claude claude .claude .gemini .agents)"
printf '{ "roles": { ' > "${_corrupt}/.ai/roles.json"
assert_status 1 "E-244.02a: a CORRUPT roles.json yields no stale workspaces" \
  bash -c "cd '$_corrupt' && node '$PW' stale .ai . >/dev/null 2>&1"
_missing="$(_proj claude claude .claude .gemini .agents)"
rm -f "${_missing}/.ai/roles.json"
assert_status 1 "E-244.02b: a MISSING roles.json yields no stale workspaces either" \
  bash -c "cd '$_missing' && node '$PW' stale .ai . >/dev/null 2>&1"
# And claude survives even when roles.json names nobody at all.
_empty="$(_proj claude claude .claude .gemini)"
printf '{ "roles": {} }' > "${_empty}/.ai/roles.json"
assert_contains "E-244.02c: .claude/ is never stale, even with an EMPTY roles map" \
  $'claude\t.claude\talways' "$(_classify "$_empty")"
assert_status 1 "E-244.02d: and .claude is absent from the stale list" \
  bash -c "_o=\$(cd '$_empty' && node '$PW' stale .ai . 2>/dev/null); printf '%s' \"\$_o\" | grep -q '^claude'"

# ── E-244.3: THE PRUNE — evidence, not absence ───────────────────────────────
# The whole feature turns on this block. A sync-written, unmodified skill goes; a
# user-authored one beside it stays and is reported.
_pp="$(_proj claude claude .claude)"
mkdir -p "${_pp}/.agents/skills/synced-skill" "${_pp}/.agents/skills/my-own-skill"
printf '# synced\n' > "${_pp}/.agents/skills/synced-skill/SKILL.md"
printf '# mine\n'   > "${_pp}/.agents/skills/my-own-skill/SKILL.md"
# Record ONLY the synced one, the way a real sync would.
( cd "$_pp" && node "${REPO_ROOT}/src/shared/sync-manifest.mjs" record .agents/skills >/dev/null 2>&1 )
# Then make the user's skill un-recorded by rewriting the manifest without it.
python3 - "${_pp}/.agents/skills/_SYNC_MANIFEST.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["entries"].pop("my-own-skill", None)
json.dump(m, open(p, "w"), indent=2)
PY
_pout="$( cd "$_pp" && bash "$AI" sync --prune-providers 2>&1 )"

assert_status 1 "E-244.03a: the sync-written skill is GONE" \
  test -d "${_pp}/.agents/skills/synced-skill"
# THE ASSERTION THIS FEATURE EXISTS TO SATISFY.
assert_status 0 "E-244.03b: the USER'S skill survives the prune" \
  test -f "${_pp}/.agents/skills/my-own-skill/SKILL.md"
assert_contains "E-244.03c: and the surviving directory is REPORTED, not silently left" \
  ".agents/ kept" "$_pout"
assert_contains "E-244.03d: the prune names the provider and the reason" \
  "no role is bound to 'agy'" "$_pout"

# With nothing left un-prunable, the directory itself goes.
_pq="$(_proj claude claude .claude)"
mkdir -p "${_pq}/.agents/skills/only-synced"
printf '# s\n' > "${_pq}/.agents/skills/only-synced/SKILL.md"
( cd "$_pq" && node "${REPO_ROOT}/src/shared/sync-manifest.mjs" record .agents/skills >/dev/null 2>&1 )
_qout="$( cd "$_pq" && bash "$AI" sync --prune-providers 2>&1 )"
assert_status 1 "E-244.03e: a fully-prunable workspace directory is removed" \
  test -d "${_pq}/.agents"
assert_contains "E-244.03f: and the removal is announced" ".agents/ removed" "$_qout"

# NO MANIFEST = NO EVIDENCE. A workspace sync has never recorded must survive whole.
_pr="$(_proj claude claude .claude)"
mkdir -p "${_pr}/.agents/skills/unrecorded"
printf '# u\n' > "${_pr}/.agents/skills/unrecorded/SKILL.md"
( cd "$_pr" && bash "$AI" sync --prune-providers >/dev/null 2>&1 )
assert_status 0 "E-244.03g: with NO manifest, nothing is pruned (first run has no evidence)" \
  test -f "${_pr}/.agents/skills/unrecorded/SKILL.md"

# A MAPPED provider's workspace is never touched BY THIS COMMAND. The skill here is
# deliberately USER-AUTHORED (never recorded), because a recorded skill that is no longer
# in the source set is prunable by ORDINARY sync (E-220) whether or not the provider is
# mapped — asserting on one would test E-220's rule, not this one, and would fail for a
# reason that has nothing to do with provider workspaces.
_pm="$(_proj agy claude .claude)"
mkdir -p "${_pm}/.agents/skills/live-skill"
printf '# live\n' > "${_pm}/.agents/skills/live-skill/SKILL.md"
( cd "$_pm" && bash "$AI" sync --prune-providers >/dev/null 2>&1 )
assert_status 0 "E-244.03h: a MAPPED provider's workspace is untouched by the prune" \
  test -f "${_pm}/.agents/skills/live-skill/SKILL.md"
assert_status 1 "E-244.03i: and agy is not even listed as stale while it holds a role" \
  bash -c "_o=\$(cd '$_pm' && node '$PW' stale .ai . 2>/dev/null); printf '%s' \"\$_o\" | grep -q '^agy'"

# ── E-244.4: the prune is EXPLICIT — a plain sync never deletes ───────────────
# A cleanup that happens on a command people run reflexively is an incident waiting.
_ps="$(_proj claude claude .claude)"
mkdir -p "${_ps}/.agents/skills/only-synced"
printf '# s\n' > "${_ps}/.agents/skills/only-synced/SKILL.md"
( cd "$_ps" && node "${REPO_ROOT}/src/shared/sync-manifest.mjs" record .agents/skills >/dev/null 2>&1 )
_plain="$( cd "$_ps" && bash "$AI" sync 2>&1 )"
assert_status 0 "E-244.04a: a PLAIN 'ai sync' deletes nothing" \
  test -f "${_ps}/.agents/skills/only-synced/SKILL.md"
assert_contains "E-244.04b: but it does SAY the workspace is stale" \
  "stale provider workspace: .agents/" "$_plain"
assert_contains "E-244.04c: and names the command that would remove it" \
  "ai sync --prune-providers" "$_plain"

# ── E-244.5: provisioning follows the binding ────────────────────────────────
_pv="$(_proj claude claude .claude)"
_vout="$( cd "$_pv" && bash "$AI" sync 2>&1 )"
assert_status 1 "E-244.05a: an all-Claude project does not get a .gemini/" \
  test -d "${_pv}/.gemini"
assert_status 1 "E-244.05b: nor an .agents/" test -d "${_pv}/.agents"
assert_status 0 "E-244.05c: .claude/ is still provisioned" test -d "${_pv}/.claude/skills"
# Silence would be worse than the directory: a reader expecting .gemini/ must learn why.
assert_contains "E-244.05d: the skip is ANNOUNCED, not silent" \
  ".gemini/ skipped (no role bound to 'gemini'" "$_vout"
assert_contains "E-244.05e: and so is the agy skip" \
  ".agents/ skipped (no role bound to 'agy'" "$_vout"

# NON-VACUITY: bind a role to gemini and the directory comes back. Without this, 05a-b
# would pass on a build that had simply deleted the gemini provisioning code.
_pg="$(_proj gemini claude .claude)"
( cd "$_pg" && bash "$AI" sync >/dev/null 2>&1 )
assert_status 0 "E-244.05f: binding the Architect to gemini provisions .gemini/ again" \
  test -d "${_pg}/.gemini/agents"
_pa="$(_proj agy claude .claude)"
( cd "$_pa" && bash "$AI" sync >/dev/null 2>&1 )
assert_status 0 "E-244.05g: and binding it to agy provisions .agents/" \
  test -d "${_pa}/.agents/skills"

# ── E-244.6: the adapters stay (D-052) ───────────────────────────────────────
# This task removes PROJECT workspaces, not provider support. Deleting the source
# adapters would make the 05f/05g re-provisioning impossible and is out of scope.
assert_status 0 "E-244.06a: src/agents/skills survives (D-052)" \
  test -d "${REPO_ROOT}/src/agents/skills"
assert_status 0 "E-244.06b: src/gemini/agents survives (D-052)" \
  test -d "${REPO_ROOT}/src/gemini/agents"

# ── E-244.7: doctor reports it, and repairs nothing ──────────────────────────
_pd="$(_proj claude claude .claude .agents)"
_dout="$( cd "$_pd" && bash "$AI" doctor 2>&1 )"
assert_contains "E-244.07a: doctor reports the stale workspace" \
  "stale provider workspace: .agents/" "$_dout"
assert_status 0 "E-244.07b: and doctor does NOT remove it (diagnose ≠ repair)" \
  test -d "${_pd}/.agents"
_pdc="$(_proj claude claude .claude)"
_dcout="$( cd "$_pdc" && bash "$AI" doctor 2>&1 )"
assert_contains "E-244.07c: a clean project says so explicitly" \
  "every provider workspace present serves a bound role" "$_dcout"

# ── E-244.8: `git rev-parse` no longer aborts the script outside a repo ──────
# `GIT_HOOKS_DIR="$(git rev-parse --git-dir 2>/dev/null)/hooks"` is a PLAIN assignment,
# so under `set -euo pipefail` it carried git's exit 128 and killed the whole script —
# three lines above the "not a git repo" branch that was written to handle exactly this.
# That is the long-standing `ai init` exit-128 in a fresh directory.
_pn="$(test_tmpdir e244ng)"   # deliberately NOT a git repository
assert_status 0 "E-244.08a: 'ai init' completes in a NON-git directory (was exit 128)" \
  bash -c "cd '$_pn' && bash '$AI' init >/dev/null 2>&1"
assert_status 0 "E-244.08b: and it scaffolded .ai/ rather than dying first" \
  test -f "${_pn}/.ai/roles.json"
assert_status 0 "E-244.08c: the guard is the empty-string one, not a swallowed 128" \
  bash -c "sed -n '/^install_git_hooks() {/,/^}/p' '$AI' | grep -q 'git rev-parse --git-dir 2>/dev/null || true'"

# ── E-244.9: two defects this task FOUND and did not fix ────────────────────
# Recorded as assertions so they cannot be quietly "tidied" without a decision.
#
# (1) The second half of do_sync is unreachable — both branches of its `if` return or
#     exit first. Hooks, doc regeneration, the WAL checkpoint, REPO_MAP, the Memory
#     Palace index and the E-237 policy report have not run on `ai sync` since E-217.
#     A trial restore made `ai sync` exit 1 under `set -e`, so it is its own task.
assert_status 0 "E-244.09a: the dead-code finding is recorded at the return that causes it" \
  bash -c "grep -q 'DELIBERATELY NOT FIXED HERE' '$AI'"
assert_status 0 "E-244.09b: and again at the dead tail itself" \
  bash -c "grep -q 'is DEAD CODE' '$AI'"
# (2) E-237's staleness note word-split its own output. Fixed here because it is one
#     line and carries no behaviour, unlike the tail above.
assert_status 1 "E-244.09c: the policy note no longer word-splits (unquoted \$stale is gone)" \
  bash -c "grep -q \"printf '  %s..n' .stale\" '$AI'"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== provider_workspace_test.sh PASS ====="
else
  echo "===== provider_workspace_test.sh FAIL (${FAIL_COUNT}) ====="
fi
