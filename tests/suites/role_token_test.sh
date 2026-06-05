#!/usr/bin/env bash
# role_token_test.sh — E-129 (sovereignty-hardening.md §Security): tamper-resistant
# role verification. The safe-exec gate's --check path resolves the role from an
# HMAC-signed per-session token (minted at SessionStart) instead of the mutable
# AI_OS_CALLER_ROLE env var, so an in-session `unset/export` can no longer bypass
# the role check. All token I/O is sandboxed under a hermetic HOME.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SE="${REPO_ROOT}/src/mcp/safe-exec-mcp/index.js"
SSH_HOOK="${REPO_ROOT}/hooks/session-start.sh"
PTU="${REPO_ROOT}/hooks/pre-tool-use.sh"
AI_BIN="${REPO_ROOT}/src/bin/ai"
HSB="$(mktemp -d)"                      # hermetic HOME — never touch the real ~/.ai-os
trap 'rm -rf "$HSB"' EXIT

echo "===== role_token_test.sh (E-129) ====="

mint()  { HOME="$HSB" node --no-warnings "$SE" --mint-token "$1" "$2" >/dev/null 2>&1; }
# chk <env_role|-> <cmd> <arg_role> <sid|->  → exit code of --check
# (subshell + if/else avoids empty-array-under-`set -u` on bash 3.2).
chk() {
  local envrole="$1" cmd="$2" arg="$3" sid="$4"
  (
    export HOME="$HSB"
    [[ "$envrole" != "-" ]] && export AI_OS_CALLER_ROLE="$envrole"
    if [[ "$sid" != "-" ]]; then
      node --no-warnings "$SE" --check "$cmd" "$arg" --session "$sid" >/dev/null 2>&1
    else
      node --no-warnings "$SE" --check "$cmd" "$arg" >/dev/null 2>&1
    fi
    echo $?
  )
}

# ── S01: source contract — the token machinery is present ─────────────────────
assert_status 0 "S01: --mint-token CLI present"  grep -qF -- '--mint-token' "$SE"
assert_status 0 "S01: verifyToken helper present" grep -qE 'function verifyToken' "$SE"
assert_status 0 "S01: verifyCheckRole gates on session id" grep -qE 'function verifyCheckRole' "$SE"
assert_status 0 "S01: HMAC signing present" grep -qF 'createHmac' "$SE"
assert_status 0 "S01: --check forwards --session" grep -qF -- '--session' "$PTU"
assert_status 0 "S01: AI_OS_ROLE_TOKEN rollback documented" grep -qF 'AI_OS_ROLE_TOKEN' "$SE"

# ── S02: mint + verify round-trip ─────────────────────────────────────────────
mint engineer T1
assert_status 0 "S02: token minted to ~/.ai-os/run/role-T1.lock" test -f "$HSB/.ai-os/run/role-T1.lock"
assert_contains "S02: engineer token → git push allowed (engineer)" "0" "$(chk - 'git push origin main' engineer T1)"

# ── S03: ACCEPTANCE — env mutation must NOT bypass the token role ─────────────
assert_contains "S03: env=architect IGNORED, engineer token wins → exit 0" "0" "$(chk architect 'git push origin main' engineer T1)"
assert_contains "S03: arg=architect IGNORED, engineer token wins → exit 0"  "0" "$(chk - 'git push origin main' architect T1)"
# Downgrade-resistance the other way: an ARCHITECT token blocks git push even when
# the env claims engineer — proving the token (not env) decides.
mint architect T2
assert_contains "S03: architect token blocks git push despite env=engineer → exit 2" "2" "$(chk engineer 'git push origin main' engineer T2)"
assert_contains "S03: architect token blocks despite unset env → exit 2" "2" "$(chk - 'git push origin main' engineer T2)"

# ── S04: back-compat — no --session → legacy E-127 env-over-arg (every old test) ─
assert_contains "S04: no session id → legacy env=architect blocks → exit 2" "2" "$(chk architect 'git push origin main' engineer -)"
assert_contains "S04: no session id → legacy engineer allows → exit 0"      "0" "$(chk - 'git push origin main' engineer -)"

# ── S05: tamper — a forged role with a stale HMAC is rejected (→ legacy fallback) ─
mint engineer T5
python3 - "$HSB/.ai-os/run/role-T5.lock" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["role"] = "architect"      # forge the role but keep the old (engineer) HMAC
json.dump(d, open(p, "w"))
PY
# Token now invalid (HMAC mismatch) → falls back to legacy env; env unset → no architect block.
assert_contains "S05: forged role + stale HMAC rejected → falls back to legacy (exit 0)" "0" "$(chk - 'git push origin main' engineer T5)"
_tamper_err="$(HOME="$HSB" node --no-warnings "$SE" --check 'ls' engineer --session T5 2>&1 >/dev/null)"
assert_contains "S05: HMAC failure logs a tamper warning" "failed HMAC verification" "$_tamper_err"

# ── S06: session mismatch (replay) — token for T1 not honoured for T6 ──────────
assert_contains "S06: --session T6 has no token → legacy env=architect → exit 2" "2" "$(chk architect 'git push origin main' engineer T6)"

# ── S07: key + dir perms ──────────────────────────────────────────────────────
assert_contains "S07: machine key is 0600" "600" "$(stat -f '%Lp' "$HSB/.ai-os/secrets/role-hmac.key" 2>/dev/null || stat -c '%a' "$HSB/.ai-os/secrets/role-hmac.key" 2>/dev/null)"

# ── S08: path traversal — a crafted session id cannot escape the run dir ───────
mint engineer '../../etc/evil'
assert_status 0 "S08: traversal sid does not write outside run/ (no /etc/evil)" test ! -e "$HSB/.ai-os/etc/evil.lock"
assert_status 1 "S08: traversal sid wrote nothing at the literal path" test -e "/etc/evil.lock"

# ── S09: rollback AI_OS_ROLE_TOKEN=0 → token layer off, legacy env path ────────
assert_contains "S09: ROLE_TOKEN=0 + env=architect → legacy env wins → exit 2" "2" \
  "$(HOME="$HSB" AI_OS_ROLE_TOKEN=0 env AI_OS_CALLER_ROLE=architect node --no-warnings "$SE" --check 'git push' engineer --session T1 >/dev/null 2>&1; echo $?)"

# ── S10: hook integration — SessionStart mints; PreToolUse forwards --session ──
# session-start.sh <role> reads session_id from its stdin payload and mints.
printf '%s' '{"session_id":"HK1","source":"startup"}' | HOME="$HSB" bash "$SSH_HOOK" architect >/dev/null 2>&1
assert_status 0 "S10: SessionStart hook minted a token for HK1" test -f "$HSB/.ai-os/run/role-HK1.lock"
# pre-tool-use.sh extracts session_id and forwards --session, so the architect
# token blocks git push even though the env claims engineer.
_ptu_ev='{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"session_id":"HK1"}'
_ptu_rc="$(printf '%s' "$_ptu_ev" | HOME="$HSB" env AI_OS_CALLER_ROLE=engineer bash "$PTU" >/dev/null 2>&1; echo $?)"
assert_contains "S10: hook uses the HK1 architect token over env=engineer → BLOCK (exit 2)" "2" "$_ptu_rc"

# ── S11: installer wiring (src/bin/ai) ────────────────────────────────────────
assert_status 0 "S11: SessionStart hook passes role arg 'engineer'" grep -qF 'ss_script + " engineer"' "$AI_BIN"
assert_status 0 "S11: gemini freezes architect role in per-server env" \
  grep -qF 'servers["safe-exec-mcp"].setdefault("env", {})["AI_OS_CALLER_ROLE"] = "architect"' "$AI_BIN"
assert_status 0 "S11: install_global provisions the HMAC key" grep -qF 'role-hmac.key' "$AI_BIN"

assert_summary
