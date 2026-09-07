#!/usr/bin/env bash
# traversal_policy_test.sh — E-222 (D-057 §2): context-aware PATH_TRAVERSAL grading.
#
# `run_review`'s traversal check was one flat regex — any added line containing `../` was
# a P0 that BLOCKED the commit. That blocked E-220's fix for a real vulnerability, on an
# idiom (`"${_sd}/../shared/x.mjs"`) already present at four other sites in the same file
# that simply were not in that diff. A gate that fires on correct code teaches people to
# route around it, which costs more than the check earns.
#
# The fixtures run in BOTH directions on purpose. Loosening a security check is only safe
# if the cases it must still catch are enumerated beside the ones it must stop catching —
# otherwise "fixed the false positive" and "removed the check" look identical from here.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POLICY="${REPO_ROOT}/src/shared/traversal-policy.mjs"
ORCH="${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"
AI_BIN="${REPO_ROOT}/src/bin/ai"

echo "── Suite: traversal_policy_test (E-222) ─────────────────────────────"

# grade <line> [strict] → P0 | P1 | none
_grade() {
  node --input-type=module --no-warnings -e '
    import { classifyTraversal } from "'"$POLICY"'";
    const strict = process.argv[2] === "strict";
    const v = classifyTraversal(process.argv[1], { strict });
    process.stdout.write(v?.severity ?? "none");
  ' -- "$1" "${2:-}" 2>/dev/null
}

# ── E-222.1: MUST STILL BLOCK — runtime path handling ───────────────────────
# The whole point of the check. Every one of these is a `../` whose base comes from
# somewhere other than the script's own location.
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-222.01 P0: $label" "P0" "$(_grade "$line")"
done <<'CASES'
join with a request field|+  const target = join(req.query.path, "../", name);
concatenated user input|+  fs.readFileSync("../../" + userInput);
variable base|+  const p = userDir + "/../" + name;
template with a param|+  const f = `${base}/../${name}`;
bare traversal in prose|+  // see the note above ../ nothing
shell with an unknown var|+  cat "${INPUT_DIR}/../elsewhere"
absolute /etc/|+  const cfg = "/etc/hosts";
absolute /root/|+  open("/root/.config/thing")
/etc/ even when anchored|+  cp "${AIOS}/x" /etc/hosts
CASES

# ── E-222.2: MUST NOT BLOCK — script-relative resolution ────────────────────
# Every one of these is an anchor named in SCRIPT_RELATIVE_ANCHORS, in the shape it
# actually appears in this repo (quotes, parens and all — an earlier cut of the anchor
# patterns rejected `"$(dirname "${BASH_SOURCE[0]}")/../src"` because of the quoting).
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-222.02 P1: $label" "P1" "$(_grade "$line")"
done <<'CASES'
shell _sd idiom|+  for c in "${_sd}/../shared/sync-manifest.mjs" \
shell SELF_DIR idiom|+      "${SELF_DIR}/../shared/wal-flusher.mjs" \
inline BASH_SOURCE dirname|+          "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../src/shared/locate.sh"; do
node new URL idiom|+  const p = new URL("../safe-exec-mcp/index.js", import.meta.url);
node __dirname idiom|+  const s = join(__dirname, "../shared/state-db.js");
install mirror root|+  local m="${AIOS}/../mcp/x.js"
AI_OS_HOME root|+  c="${AI_OS_HOME:-$HOME/.ai-os}/../shared/y.mjs"
CASES

# ── E-222.3: lines with no traversal at all are silent ──────────────────────
assert_contains "E-222.03a: an ordinary line grades none" "none" "$(_grade '+  echo hello world')"
assert_contains "E-222.03b: a removed line is ignored"     "none" "$(_grade '-  fs.read("../../" + x)')"
assert_contains "E-222.03c: a diff header is ignored"      "none" "$(_grade '+++ b/src/x.js')"

# ── E-222.4: one unanchored occurrence keeps the whole line blocking ────────
# A line may carry both shapes; the dangerous one governs.
assert_contains "E-222.04a: anchored + unanchored on one line stays P0" "P0" \
  "$(_grade '+  a("${_sd}/../ok"); b(req.path + "/../" + n);')"

# ── E-222.5: the rollback flag restores the flat regex ──────────────────────
assert_contains "E-222.05a: strict mode blocks the anchored idiom too" "P0" \
  "$(_grade '+  for c in "${_sd}/../shared/x.mjs"' strict)"
assert_status 0 "E-222.05b: run_review reads AI_OS_REVIEW_STRICT_TRAVERSAL" \
  bash -c "grep -q 'AI_OS_REVIEW_STRICT_TRAVERSAL' '$ORCH'"

# ── E-222.6: the policy has exactly one definition ─────────────────────────
assert_status 0 "E-222.06a: the anchor list is exported from one module" \
  bash -c "grep -q 'export const SCRIPT_RELATIVE_ANCHORS' '$POLICY'"
assert_status 1 "E-222.06b: run_review keeps no second copy of the regex" \
  bash -c "grep -q 'traversalPattern' '$ORCH'"
assert_status 0 "E-222.06c: run_review delegates to the shared policy" \
  bash -c "grep -q 'classifyTraversal(diff' '$ORCH'"

# ── E-222.7: an advisory is REPORTED, never dropped ────────────────────────
# "Downgraded to P1" must not become "silently ignored" — a reviewer still sees it.
assert_status 0 "E-222.07a: a P1 traversal is emitted as a WARN row" \
  bash -c "grep -q 'status: traversal.severity === .P0. ? .FAIL. : .WARN.' '$ORCH'"
assert_status 0 "E-222.07b: the report names the anchor that excused it" \
  bash -c "grep -q 'anchored to ' '$ORCH'"

# ── E-222.8: the real diff that motivated this passes ───────────────────────
# The concrete regression: src/bin/ai's own locator bootstrap must not be a P0.
_real="$(grep -F 'shared/locate.sh' "$AI_BIN" | head -1)"
if [[ -n "$_real" ]]; then
  assert_not_contains "E-222.08a: src/bin/ai's own locator bootstrap is not P0" "P0" \
    "$(_grade "+${_real}")"
fi

assert_summary
