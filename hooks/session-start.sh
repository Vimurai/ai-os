#!/usr/bin/env bash
# session-start.sh — E-126 (caching.md §3.2/§3.3): inject the compiled AI-OS
# System Context Cache as a prompt-prefix at Claude session start. This wires the
# previously-unimplemented "Agent Invocation" step of the caching workflow — the
# cache was built (E-112) but never consumed into the session context.
#
# Claude Code SessionStart contract: a hook that prints JSON with
# hookSpecificOutput.additionalContext has that text added to the session
# context. Fail-open everywhere — emit nothing (exit 0) if the cache is
# unavailable, so a session never fails to start. Rollback: AI_OS_DISABLE_CACHE=1.
set -uo pipefail

[[ "${AI_OS_DISABLE_CACHE:-0}" == "1" ]] && exit 0
command -v node    >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Locate cache-manager-mcp (in-repo dev tree → installed mirror).
CM=""
for c in "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/src/mcp/cache-manager-mcp/index.js" \
         "${HOME}/.ai-os/mcp/cache-manager-mcp/index.js"; do
  [[ -f "$c" ]] && { CM="$c"; break; }
done
[[ -z "$CM" ]] && exit 0

# Emit the compiled System Context blob (the CLI fail-opens to empty on any error).
BLOB="$(node --no-warnings "$CM" --emit-context 2>/dev/null)"
[[ -z "$BLOB" ]] && exit 0

# Wrap as SessionStart additionalContext (python3 guarantees valid JSON escaping
# of the multi-line blob). On any failure, emit nothing rather than malformed JSON.
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
