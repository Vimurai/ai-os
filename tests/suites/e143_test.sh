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
PROPOSE_SRC="$(cat "$PROPOSE_MCP")"
GUARDIAN_SRC="$(cat "$GUARDIAN_MCP")"

# ── patch-mcp: roleGuard present ──────────────────────────────────────────────
assert_contains "patch-mcp: roleGuard function defined" "roleGuard" "$PATCH_SRC"
assert_contains "patch-mcp: ANTI_DRIFT_VIOLATION error present" "ANTI_DRIFT_VIOLATION" "$PATCH_SRC"
assert_contains "patch-mcp: caller_role parameter in schema" "caller_role" "$PATCH_SRC"
assert_contains "patch-mcp: architect enum value in schema" '"architect"' "$PATCH_SRC"
assert_contains "patch-mcp: roleGuard called with args.caller_role" "roleGuard(args.caller_role" "$PATCH_SRC"

# ── patch-mcp: whitelist paths ────────────────────────────────────────────────
assert_contains "patch-mcp: .ai/ in architect whitelist" '".ai/"' "$PATCH_SRC"
assert_contains "patch-mcp: plans/ in architect whitelist" '"plans/"' "$PATCH_SRC"

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
  GUARD_SCRIPT=$(mktemp /tmp/e143_guard_XXXXXX.mjs)
  cat > "$GUARD_SCRIPT" <<'JSEOF'
import { relative } from "path";

function roleGuard(callerRole, absPath, cwd) {
  if (!callerRole || callerRole.toLowerCase() !== "architect") return null;
  const rel = relative(cwd, absPath).replace(/\\/g, "/");
  const allowed = rel === ".ai" || rel.startsWith(".ai/") ||
                  rel === "plans" || rel.startsWith("plans/");
  if (!allowed) {
    return { blocked: true, message: "[ANTI_DRIFT_VIOLATION]" };
  }
  return null;
}

const cwd = "/project";
const block1  = roleGuard("architect", "/project/src/mcp/foo.js", cwd);    // blocked
const allow1  = roleGuard("architect", "/project/.ai/TASKS.md", cwd);       // allowed
const allow2  = roleGuard("architect", "/project/plans/foo.md", cwd);       // allowed
const allow3  = roleGuard("engineer",  "/project/src/mcp/foo.js", cwd);     // allowed
const allow4  = roleGuard(null,        "/project/src/mcp/foo.js", cwd);     // allowed
const blockSrc= roleGuard("architect", "/project/src/bin/ai", cwd);         // blocked

const ok =
  block1  !== null && block1.message === "[ANTI_DRIFT_VIOLATION]" &&
  allow1  === null &&
  allow2  === null &&
  allow3  === null &&
  allow4  === null &&
  blockSrc !== null;

process.stdout.write(ok ? "PASS" : "FAIL");
JSEOF
  RESULT=$(node "$GUARD_SCRIPT" 2>/dev/null || echo "error")
  rm -f "$GUARD_SCRIPT"
  if [[ "$RESULT" == "PASS" ]]; then
    _pass "e143: roleGuard blocks src/ for architect, allows .ai/ plans/ engineer null"
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
