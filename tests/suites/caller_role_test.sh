#!/usr/bin/env bash
# caller_role_test.sh — E-219 (D-056 R1): server-side caller-role derivation.
#
# Closes THREAT_MODEL T-PATCHMCP-001. patch-mcp and propose-patch-mcp each carried a
# self-declared guard that returned ALLOW whenever the caller simply omitted
# `caller_role` — so an unidentified client could write anywhere, and that was the only
# barrier left in any session started without the settings overlay.
#
# Every case drives the REAL server over stdio JSON-RPC in a disposable project. A
# static grep cannot tell you whether the guard actually refuses a write.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRIVER="${REPO_ROOT}/tests/lib/patch-mcp-driver.mjs"
SAFE_EXEC="${REPO_ROOT}/src/mcp/safe-exec-mcp/index.js"

echo "── Suite: caller_role_test (E-219) ──────────────────────────────────"

_SID_E="e219s-eng-$RANDOM$RANDOM"
_SID_A="e219s-arch-$RANDOM$RANDOM"
node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" engineer  "$_SID_E" >/dev/null 2>&1
node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" architect "$_SID_A" >/dev/null 2>&1

_drive() {  # <target> <json-args-extra> <env assignments...> → allow | BLOCK | error
  local target="$1" extra="$2"; shift 2
  env "$@" node --no-warnings "$DRIVER" "$target" "$extra" 2>/dev/null
}

# ── E-219.1: the verified session record is authoritative ──────────────────
assert_contains "E-219.01a: verified ENGINEER record may write src/" "allow" \
  "$(_drive src '{}' CLAUDE_CODE_SESSION_ID="$_SID_E")"
assert_contains "E-219.01b: verified ARCHITECT record may NOT write src/" "BLOCK" \
  "$(_drive src '{}' CLAUDE_CODE_SESSION_ID="$_SID_A")"
assert_contains "E-219.01c: verified ARCHITECT record may write .ai/" "allow" \
  "$(_drive ai '{}' CLAUDE_CODE_SESSION_ID="$_SID_A")"

# ── E-219.2: the spawn-frozen launch env is the second source ──────────────
assert_contains "E-219.02a: env engineer (no record) may write src/" "allow" \
  "$(_drive src '{}' CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=engineer)"
assert_contains "E-219.02b: env architect (no record) may NOT write src/" "BLOCK" \
  "$(_drive src '{}' CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=architect)"

# ── E-219.3: NO evidence → architect (fail closed) ─────────────────────────
# THE REGRESSION THIS TASK EXISTS FOR: omitting caller_role used to mean "unrestricted".
assert_contains "E-219.03a: no record and no env → src/ is BLOCKED" "BLOCK" \
  "$(_drive src '{}' CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=)"
assert_contains "E-219.03b: no record and no env → .ai/ is still allowed" "allow" \
  "$(_drive ai '{}' CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=)"

# ── E-219.4: a volunteered role may RESTRICT, never LIFT ───────────────────
assert_contains "E-219.04a: claiming engineer against an ARCHITECT record is ignored" "BLOCK" \
  "$(_drive src '{"caller_role":"engineer"}' CLAUDE_CODE_SESSION_ID="$_SID_A")"
assert_contains "E-219.04b: claiming architect against an ENGINEER record self-restricts" "BLOCK" \
  "$(_drive src '{"caller_role":"architect"}' CLAUDE_CODE_SESSION_ID="$_SID_E")"
assert_contains "E-219.04c: claiming engineer with no evidence does not lift the default" "BLOCK" \
  "$(_drive src '{"caller_role":"engineer"}' CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=)"

# ── E-219.5: symlink / hardlink — the F1 regression ────────────────────────
# `.ai/link -> ../src/x` is a symlink the Architect may legitimately create INSIDE its
# own scope. A prefix test on the path allows a write straight through it, which is the
# normalise-only check E-216 spent seven rounds replacing. The guard must delegate to
# architectPathVerdict rather than hand-roll a second predicate.
assert_contains "E-219.05a: a symlink in .ai/ pointing at src/ is BLOCKED" "BLOCK" \
  "$(_drive symlink '{}' CLAUDE_CODE_SESSION_ID="$_SID_A")"
assert_contains "E-219.05b: a hardlink in .ai/ aliasing src/ is BLOCKED" "BLOCK" \
  "$(_drive hardlink '{}' CLAUDE_CODE_SESSION_ID="$_SID_A")"
assert_contains "E-219.05c: an ordinary .ai/ file is unaffected by those checks" "allow" \
  "$(_drive ai '{}' CLAUDE_CODE_SESSION_ID="$_SID_A")"
assert_contains "E-219.05d: the ENGINEER may still write through the same symlink" "allow" \
  "$(_drive symlink '{}' CLAUDE_CODE_SESSION_ID="$_SID_E")"

# ── E-219.6: rollback restores the legacy guard exactly ────────────────────
assert_contains "E-219.06a: AI_OS_SOVEREIGNTY_LOCK=0 restores the omitted-role allow" "allow" \
  "$(_drive src '{}' CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE= AI_OS_SOVEREIGNTY_LOCK=0)"
assert_contains "E-219.06b: rollback still blocks a VOLUNTEERED architect outside scope" "BLOCK" \
  "$(_drive src '{"caller_role":"architect"}' CLAUDE_CODE_SESSION_ID= AI_OS_SOVEREIGNTY_LOCK=0)"

# ── E-219.7: structure — one rule, one implementation ──────────────────────
CALLER_ROLE="${REPO_ROOT}/src/mcp/shared/caller-role.mjs"
assert_status 0 "E-219.07a: the scope check delegates to architectPathVerdict" \
  grep -q 'architectPathVerdict(absPath, findProjectRootFrom(cwd))' "$CALLER_ROLE"
# Root resolution must match the other gates: this project has a documented MCP rooting
# trap where a server's cwd is not the project root, so passing the raw cwd would let
# the two gates agree on the RULE while disagreeing on where the root is.
assert_status 0 "E-219.07a2: and resolves the project root the same way safe-exec does" \
  grep -q 'findProjectRootFrom' "$CALLER_ROLE"
assert_status 0 "E-219.07a3: the scope check fails closed on a predicate error" \
  grep -q 'return false;' "$CALLER_ROLE"
assert_status 1 "E-219.07b: no hand-rolled prefix test remains" \
  bash -c "grep -q 'rel.startsWith(\".ai/\")' '$CALLER_ROLE'"
# safe-exec must be located relative to THIS MODULE: a cwd-relative candidate meant any
# project containing src/mcp/safe-exec-mcp/index.js got it EXECUTED, and its stdout is
# trusted to name a role.
assert_status 0 "E-219.07c: safe-exec is located via import.meta.url, not the cwd" \
  grep -q 'new URL("../safe-exec-mcp/index.js", import.meta.url)' "$CALLER_ROLE"
assert_status 1 "E-219.07d: no cwd-relative safe-exec candidate remains" \
  bash -c "grep -q 'join(cwd, \"src\", \"mcp\", \"safe-exec-mcp\"' '$CALLER_ROLE'"
# The router must forward role evidence, or a proxied server derives `architect` and
# refuses the ENGINEER's writes on a route the Code domain uses by design.
assert_status 0 "E-219.07e: mcp-router forwards CLAUDE_CODE_SESSION_ID to children" \
  grep -q 'CLAUDE_CODE_SESSION_ID: process.env.CLAUDE_CODE_SESSION_ID' "${REPO_ROOT}/src/mcp/mcp-router/index.js"
assert_status 0 "E-219.07f: mcp-router forwards AI_OS_CALLER_ROLE to children" \
  grep -q 'AI_OS_CALLER_ROLE: process.env.AI_OS_CALLER_ROLE' "${REPO_ROOT}/src/mcp/mcp-router/index.js"
# The forward is SCOPED: PATH+HOME was itself an isolation property, and several routable
# targets are third-party npx packages with no business receiving a session id — which is
# the selector for the role record.
assert_status 0 "E-219.07f2: the forward is scoped to role-aware servers only" \
  grep -q 'ROLE_AWARE_SERVERS' "${REPO_ROOT}/src/mcp/mcp-router/index.js"
assert_status 0 "E-219.07f3: a registry-declared env still wins over the forward" \
  bash -c "awk '/ROLE_AWARE_SERVERS.has/{r=NR} /\.\.\.\(env && typeof env/{e=NR} END{exit !(r && e && r<e)}' '${REPO_ROOT}/src/mcp/mcp-router/index.js'"

# Both servers must delegate — a divergent copy is how this class returns.
for _srv in patch-mcp propose-patch-mcp; do
  assert_status 0 "E-219.07g [$_srv]: delegates to the shared guard" \
    grep -q 'architectScopeGuard' "${REPO_ROOT}/src/mcp/${_srv}/index.js"
done

rm -f "${HOME}/.ai-os/run/role-${_SID_E}.lock" "${HOME}/.ai-os/run/role-${_SID_A}.lock"
assert_summary
