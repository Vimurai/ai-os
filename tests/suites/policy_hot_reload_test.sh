#!/usr/bin/env bash
# policy_hot_reload_test.sh — E-237 (D-061 §5): a long-running server must not serve a
# stale policy.
#
# An MCP server is spawned once and lives for the whole session, and ESM caches a module by
# URL forever — so a policy refreshed by `ai sync` never reached the running process.
# Throughout the 2026-09-09 sprint `run_review` reported a P0 PATH_TRAVERSAL on
# `source "${SCRIPT_DIR}/../lib/assert.sh"` while the on-disk traversal-policy.mjs graded
# that exact line P1/anchor=self_dir. Every review had to be adjudicated by hand.
#
# A gate that cries wolf is worse than one that is merely wrong: people learn to wave it
# through, and the next finding — a real one — gets waved through with it.
#
# The assertions are weighted toward two things the naive fix gets wrong: that a reload
# actually happens when the file changes, and that it does NOT happen when it has not,
# because busting the cache per call re-parses the module every request and leaks an ESM
# record each time (nothing can be evicted from the module registry).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOADER="${REPO_ROOT}/src/mcp/shared/load-policy.mjs"

echo "── Suite: policy_hot_reload_test (E-237) ───────────────────────────"

assert_status 0 "E-237.01a: the loader exists" test -f "$LOADER"
assert_status 0 "E-237.01b: it exports loadPolicy"      grep -q "export async function loadPolicy" "$LOADER"
assert_status 0 "E-237.01c: and a staleness reporter"   grep -q "export function policyStaleness" "$LOADER"
assert_status 0 "E-237.01d: rollback env is honoured"   grep -q "AI_OS_POLICY_HOT_RELOAD" "$LOADER"

# ── E-237.2: a rewritten policy is picked up, and an unchanged one is not ──
# Both halves matter. The first is the bug; the second is the leak the fix must not cause.
_reload_probe() {  # <mode> → observed values, space separated
  MODE="$1" node --input-type=module -e '
    const { writeFileSync, mkdtempSync } = await import("fs");
    const { tmpdir } = await import("os");
    const { join } = await import("path");
    const { pathToFileURL } = await import("url");

    // A throwaway policy module of our own, so the real ones are never touched.
    const dir = mkdtempSync(join(tmpdir(), "e237-"));
    const file = join(dir, "policy.mjs");
    const write = (v) => writeFileSync(file, `export const verdict = ${JSON.stringify(v)};\n`);

    const { loadPolicy, POLICY_PATHS, policyLoadCounts } =
      await import(pathToFileURL(process.env.LOADER).href);
    POLICY_PATHS["e237-probe"] = file;

    write("P0");
    const first = (await loadPolicy("e237-probe")).verdict;

    // Unchanged: must NOT re-import.
    const again = (await loadPolicy("e237-probe")).verdict;
    const countAfterSame = policyLoadCounts()["e237-probe"];

    // Rewritten — the `ai sync` event. mtimeMs is sub-millisecond, but bump the clock a
    // little so the test does not depend on filesystem timestamp granularity: a
    // whole-second stamp is exactly what made the E-229 re-exec inert.
    await new Promise((r) => setTimeout(r, 20));
    write("P1");
    const third = (await loadPolicy("e237-probe")).verdict;
    const countAfterChange = policyLoadCounts()["e237-probe"];

    console.log([first, again, third, countAfterSame, countAfterChange].join(" "));
  ' 2>/dev/null
}
export LOADER

_out="$(_reload_probe hot)"
read -r _first _again _third _cSame _cChange <<< "$_out"
assert_contains "E-237.02a: the first load returns the policy on disk"        "P0" "${_first:-}"
assert_contains "E-237.02b: an unchanged file returns the same policy"        "P0" "${_again:-}"
assert_contains "E-237.02c: a REWRITTEN file is picked up (the actual bug)"   "P1" "${_third:-}"
# The leak guard: one import for the first load, and still one after a no-change call.
assert_contains "E-237.02d: an unchanged file is NOT re-imported (no leak)"   "1"  "${_cSame:-}"
assert_contains "E-237.02e: a changed file is imported exactly once more"     "2"  "${_cChange:-}"

# ── E-237.3: the rollback pins the first load ─────────────────────────────
_pinned="$(AI_OS_POLICY_HOT_RELOAD=0 _reload_probe pinned)"
read -r _p1 _p2 _p3 _pc1 _pc2 <<< "$_pinned"
assert_contains "E-237.03a: pinned, the first load still works"              "P0" "${_p1:-}"
assert_contains "E-237.03b: pinned, a rewrite is IGNORED (pre-E-237 behaviour)" "P0" "${_p3:-}"
assert_contains "E-237.03c: pinned, the module is imported exactly once"     "1"  "${_pc2:-}"

# ── E-237.4: the real consumers ask per request ───────────────────────────
assert_status 0 "E-237.04a: orchestrator loads the traversal policy per request" \
  grep -q 'await loadPolicy("traversal-policy")' "${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"
assert_status 1 "E-237.04b: and no longer statically imports it" \
  grep -q 'import { classifyDiffTraversal } from' "${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"
assert_status 0 "E-237.04c: patch-mcp refreshes at the top of the handler" \
  grep -q 'await refreshPolicies();' "${REPO_ROOT}/src/mcp/patch-mcp/index.js"
assert_status 0 "E-237.04d: propose-patch-mcp does too" \
  grep -q 'await refreshPolicies();' "${REPO_ROOT}/src/mcp/propose-patch-mcp/index.js"
# FAIL-SAFE: a reload that throws must leave the PREVIOUS policy deciding, never an
# undefined guard. A gate that disappears is far worse than one a version behind.
assert_status 0 "E-237.04e: patch-mcp keeps the last good policy on a failed reload" \
  grep -q 'keep the last good policy' "${REPO_ROOT}/src/mcp/patch-mcp/index.js"
assert_status 0 "E-237.04f: and starts from the static import, never undefined" \
  grep -q '_staticScopeGuard' "${REPO_ROOT}/src/mcp/patch-mcp/index.js"

# ── E-237.5: `ai sync` reports a running server on an older policy ────────
assert_status 0 "E-237.05a: ai sync has the staleness notice" \
  grep -q '_report_policy_staleness' "${REPO_ROOT}/src/bin/ai"

# ── E-237.6: mirrors ─────────────────────────────────────────────────────
if [[ -f "${HOME}/.ai-os/mcp/shared/load-policy.mjs" ]]; then
  assert_status 0 "E-237.06a: ~/.ai-os mirror of the loader matches src" \
    diff -q "$LOADER" "${HOME}/.ai-os/mcp/shared/load-policy.mjs"
else
  echo "    ⚠  ~/.ai-os mirror absent — skipping"
  _pass "E-237.06a: mirror check skipped (not installed)"
fi

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== policy_hot_reload_test.sh PASS ====="
else
  echo "===== policy_hot_reload_test.sh FAIL (${FAIL_COUNT}) ====="
fi
