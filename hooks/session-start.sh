#!/usr/bin/env bash
# session-start.sh — E-126 (caching.md §3) + E-129 (sovereignty-hardening.md §Security).
#   E-126: inject the compiled AI-OS System Context Cache as a prompt-prefix.
#   E-129: mint a tamper-resistant role token for this session so the safe-exec
#          gate (--check) reads the role from an HMAC-verified file, not the
#          mutable AI_OS_CALLER_ROLE env var.
#
# Claude Code SessionStart contract: a hook that prints JSON with
# hookSpecificOutput.additionalContext has that text added to the session context.
# Fail-open everywhere — emit nothing / skip the mint rather than block a session.
# Arg $1 = the agent role baked in by `ai install` (engineer for Claude); the
# session id comes from the harness payload, never the env (no circularity).
set -uo pipefail

ROLE="${1:-engineer}"

# Read the SessionStart payload ONCE for the E-129 session id. (The E-126 cache
# step below sources its content from `--emit-context`, not stdin, so consuming
# stdin here does not affect it.)
PAYLOAD="$(cat 2>/dev/null || true)"

# ── E-129: mint the per-session role token ────────────────────────────────────
# Fail-open: a mint failure only degrades --check to the legacy env path; it never
# blocks session start. Rollback: AI_OS_ROLE_TOKEN=0.
if [[ "${AI_OS_ROLE_TOKEN:-1}" != "0" ]] && command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  _SID="$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id","") or "")
except Exception: pass' 2>/dev/null)"
  if [[ -n "$_SID" ]]; then
    for s in "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/src/mcp/safe-exec-mcp/index.js" \
             "${HOME}/.ai-os/mcp/safe-exec-mcp/index.js"; do
      if [[ -f "$s" ]]; then node --no-warnings "$s" --mint-token "$ROLE" "$_SID" >/dev/null 2>&1; break; fi
    done
  fi
fi

# ── E-126: inject the compiled System Context Cache as a prompt-prefix ─────────
[[ "${AI_OS_DISABLE_CACHE:-0}" == "1" ]] && exit 0
command -v node    >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CM=""
for c in "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/src/mcp/cache-manager-mcp/index.js" \
         "${HOME}/.ai-os/mcp/cache-manager-mcp/index.js"; do
  [[ -f "$c" ]] && { CM="$c"; break; }
done
[[ -z "$CM" ]] && exit 0

BLOB="$(node --no-warnings "$CM" --emit-context 2>/dev/null)"
[[ -z "$BLOB" ]] && exit 0

printf '%s' "$BLOB" | python3 -c '
import json, sys
blob = sys.stdin.read()
sys.stdout.write(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": blob,
    }
}))
' 2>/dev/null || exit 0
exit 0
