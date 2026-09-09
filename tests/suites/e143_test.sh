#!/usr/bin/env bash
# e143_test.sh — Role-Aware RBAC interceptors (E-143, §35 ANTI-DRIFT)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."

echo "── Suite: e143_test ─────────────────────────────────────────────────"

PATCH_MCP="${REPO_ROOT}/src/mcp/patch-mcp/index.js"
PROPOSE_MCP="${REPO_ROOT}/src/mcp/propose-patch-mcp/index.js"
GUARDIAN_MCP="${REPO_ROOT}/src/mcp/context-guardian-mcp/index.js"

assert_exists "$PATCH_MCP"
assert_exists "$PROPOSE_MCP"
assert_exists "$GUARDIAN_MCP"

PATCH_SRC="$(cat "$PATCH_MCP")"
# E-219 (D-056 R1): role derivation and the .ai//plans/ scope moved OUT of each server into one shared module, so the scope assertions follow it.
CALLER_ROLE_SRC="${REPO_ROOT}/src/mcp/shared/caller-role.mjs"
PROPOSE_SRC="$(cat "$PROPOSE_MCP")"
GUARDIAN_SRC="$(cat "$GUARDIAN_MCP")"

# ── patch-mcp: roleGuard present ──────────────────────────────────────────────
assert_contains "patch-mcp: roleGuard function defined" "roleGuard" "$PATCH_SRC"
assert_contains "patch-mcp: ANTI_DRIFT_VIOLATION error present" "ANTI_DRIFT_VIOLATION" "$PATCH_SRC"
assert_contains "patch-mcp: caller_role parameter in schema" "caller_role" "$PATCH_SRC"
assert_contains "patch-mcp: architect enum value in schema" '"architect"' "$PATCH_SRC"
assert_contains "patch-mcp: roleGuard called with args.caller_role" "roleGuard(args.caller_role" "$PATCH_SRC"

# ── patch-mcp: whitelist paths ────────────────────────────────────────────────
# E-219: there is no longer a quoted whitelist STRING to grep for — the scope is one
# regex in architect-writes.mjs, and caller-role delegates to the predicate built on it.
# Asserting the delegation is stronger than asserting a literal: a second hand-rolled
# prefix test would satisfy the old grep while reintroducing the symlink hole E-216 closed.
ARCH_WRITES_SRC="${REPO_ROOT}/src/mcp/safe-exec-mcp/architect-writes.mjs"
assert_status 0 "patch-mcp: .ai//plans/ scope defined once, as a regex" \
  grep -qE 'SAFE_ARCHITECT_PATH = /.*\.ai\|plans' "$ARCH_WRITES_SRC"
assert_status 0 "patch-mcp: the shared guard DELEGATES to that predicate (no second copy)" \
  grep -q 'architectPathVerdict(absPath, findProjectRootFrom(cwd))' "$CALLER_ROLE_SRC"

# ── propose-patch-mcp: roleGuard present ─────────────────────────────────────
assert_contains "propose-patch-mcp: roleGuard function defined" "roleGuard" "$PROPOSE_SRC"
assert_contains "propose-patch-mcp: ANTI_DRIFT_VIOLATION error present" "ANTI_DRIFT_VIOLATION" "$PROPOSE_SRC"
assert_contains "propose-patch-mcp: caller_role parameter in schema" "caller_role" "$PROPOSE_SRC"
assert_contains "propose-patch-mcp: roleGuard called at propose time" "roleGuard(args.caller_role" "$PROPOSE_SRC"
assert_contains "propose-patch-mcp: roleGuard called at confirm time (defense in depth)" "roleGuard(patch.caller_role" "$PROPOSE_SRC"
assert_contains "propose-patch-mcp: caller_role stored in patch object" "caller_role: args.caller_role" "$PROPOSE_SRC"

# ── context-guardian-mcp: check_role_access tool ─────────────────────────────
assert_contains "context-guardian-mcp: check_role_access tool registered" "check_role_access" "$GUARDIAN_SRC"
assert_contains "context-guardian-mcp: ANTI_DRIFT_VIOLATION in response" "ANTI_DRIFT_VIOLATION" "$GUARDIAN_SRC"
assert_contains "context-guardian-mcp: ALLOWED response for permitted paths" "ALLOWED" "$GUARDIAN_SRC"
assert_contains "context-guardian-mcp: engineer enum value" '"engineer"' "$GUARDIAN_SRC"
assert_contains "context-guardian-mcp: Pre-flight RBAC description" "Pre-flight RBAC check" "$GUARDIAN_SRC"

# ── functional: roleGuard logic ───────────────────────────────────────────────
if command -v node &>/dev/null; then
  # E-219: this previously embedded its own COPY of roleGuard and asserted that a
  # caller supplying NO role was allowed to write anywhere — so the suite certified the
  # exact default-open behaviour E-219 exists to remove, and it passed because it was
  # testing a copy rather than the shipped code. It now imports the real module.
# `mktemp <tmpl>` only substitutes X's at the END of the template on BSD/macOS, so a
# suffixed template like `/tmp/name_XXXXXX.mjs` is a FIXED, PREDICTABLE path — it does not
# randomise at all. Two concurrent runs collide (`mkstemp failed: File exists`) and the
# suite dies before its summary. A temp DIRECTORY plus a named file inside randomises on
# both BSD and GNU and keeps the extension, which node needs to pick the ESM loader.
  GUARD_DIR=$(mktemp -d); GUARD_SCRIPT="$GUARD_DIR/guard.mjs"
  cat > "$GUARD_SCRIPT" <<JSEOF
import { architectScopeGuard, _resetCallerRoleCache } from "file://${REPO_ROOT}/src/mcp/shared/caller-role.mjs";

const cwd = process.cwd();
const g = (role, p) => {
  _resetCallerRoleCache();
  return architectScopeGuard(role, p, cwd) === null ? "allow" : "block";
};

// With AI_OS_CALLER_ROLE=architect in the environment (set by the runner below), the
// derived role is architect regardless of what the caller volunteers.
const results = {
  srcBlocked:      g(undefined, cwd + "/src/mcp/foo.js"),
  aiAllowed:       g(undefined, cwd + "/.ai/TASKS.md"),
  plansAllowed:    g(undefined, cwd + "/plans/foo.md"),
  // THE REGRESSION: omitting the role no longer buys unrestricted access.
  omittedBlocked:  g(undefined, cwd + "/src/bin/ai"),
  // A volunteered engineer cannot lift the derived architect restriction.
  claimedEngineer: g("engineer", cwd + "/src/bin/ai"),
};

const ok =
  results.srcBlocked === "block" &&
  results.aiAllowed === "allow" &&
  results.plansAllowed === "allow" &&
  results.omittedBlocked === "block" &&
  results.claimedEngineer === "block";

process.stdout.write(ok ? "PASS" : "FAIL " + JSON.stringify(results));
JSEOF
  RESULT=$(AI_OS_CALLER_ROLE=architect CLAUDE_CODE_SESSION_ID= node "$GUARD_SCRIPT" 2>/dev/null || echo "error")
  rm -rf "$GUARD_DIR"
  if [[ "$RESULT" == "PASS" ]]; then
    _pass "e143: shipped guard blocks src/ for architect, allows .ai//plans/, and an OMITTED role no longer allows (E-219)"
  else
    _fail "e143: roleGuard logic incorrect (got: $RESULT)"
  fi
else
  _pass "e143: roleGuard functional test skipped (node unavailable)"
fi

# ── syntax checks ─────────────────────────────────────────────────────────────
assert_status 0 "patch-mcp: syntax OK after E-143 changes" \
  node --check "$PATCH_MCP"

assert_status 0 "propose-patch-mcp: syntax OK after E-143 changes" \
  node --check "$PROPOSE_MCP"

assert_status 0 "context-guardian-mcp: syntax OK after E-143 changes" \
  node --check "$GUARDIAN_MCP"

assert_summary
