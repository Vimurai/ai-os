#!/usr/bin/env bash
# pre-tool-use.sh — E-125 (sovereignty-hardening.md / THREAT_MODEL T-HITL-004):
# FAIL-CLOSED pre-execution gate. Runs every Bash tool command through
# safe-exec-mcp's analysis (`--check`) BEFORE it executes and BLOCKS it (exit 2)
# on a BLOCK verdict — turning safe-exec from advisory into enforcing.
#
# Claude Code PreToolUse contract: exit 2 BLOCKS the tool call and feeds this
# hook's stderr back to the model; exit 0 ALLOWS. The tool call arrives as a JSON
# object on stdin ({ tool_name, tool_input: { command } }).
#
# Defense in depth (T-HITL-004 "gate circumvention"): if the node analyzer is
# unavailable, a hardcoded backstop still blocks the most catastrophic patterns,
# so the gate cannot be silently bypassed by breaking node. If the analyzer is
# present but CRASHES, `--check` itself exits 2 (FAIL-CLOSED, E-128) and this hook
# blocks — an internal error can no longer be used to bypass the gate.
#
# Rollback / emergency bypass: AI_OS_SAFE_EXEC_GATE=0.
set -uo pipefail

# ── Rollback ─────────────────────────────────────────────────────────────────
[[ "${AI_OS_SAFE_EXEC_GATE:-1}" == "0" ]] && exit 0

PAYLOAD="$(cat 2>/dev/null)"
[[ -z "$PAYLOAD" ]] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0   # cannot parse the event → allow

# Extract tool_name + the Bash command. The command is base64-encoded so it
# survives newlines / quotes / shell metacharacters intact across the boundary.
PARSED="$(printf '%s' "$PAYLOAD" | python3 -c '
import json, sys, base64
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool = d.get("tool_name", "") or ""
ti = d.get("tool_input") or {}
cmd = ti.get("command", "") if isinstance(ti, dict) else ""
print(tool)
print(base64.b64encode((cmd or "").encode()).decode())
print(d.get("session_id", "") or "")   # E-129: tamper-resistant role token key
' 2>/dev/null)"

TOOL="$(printf '%s\n' "$PARSED" | sed -n '1p')"
CMD="$(printf '%s\n' "$PARSED" | sed -n '2p' | base64 --decode 2>/dev/null)"
SID="$(printf '%s\n' "$PARSED" | sed -n '3p')"   # E-129: session id (from harness, not env)

# Only gate shell execution. Other tools (Read/Write/Edit/MCP/…) pass through.
[[ "$TOOL" != "Bash" ]] && exit 0
[[ -z "$CMD" ]] && exit 0

# This gate runs in the Engineer's (Claude's) session. Role-specific architect
# sovereignty blocks are keyed on caller_role; default to engineer here.
ROLE="${AI_OS_CALLER_ROLE:-engineer}"

# ── Primary: the node analyzer (single source of truth with the MCP tool) ─────
SE=""
for c in "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/src/mcp/safe-exec-mcp/index.js" \
         "${HOME}/.ai-os/mcp/safe-exec-mcp/index.js"; do
  [[ -f "$c" ]] && { SE="$c"; break; }
done

if [[ -n "$SE" ]] && command -v node >/dev/null 2>&1; then
  # --no-warnings keeps node module-type noise out of the report; report is on
  # stdout, exit code carries the verdict (2 = BLOCK).
  # E-129: pass the session id so --check resolves the role from the HMAC-verified
  # token (tamper-resistant) rather than the mutable env. Positional role stays
  # BEFORE the --session flag so argv parsing of the role is unaffected.
  REPORT="$(node --no-warnings "$SE" --check "$CMD" "$ROLE" --session "$SID" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    {
      echo "[SAFE_EXEC_BLOCK] safe-exec fail-closed gate (E-125) blocked this command:"
      echo "$REPORT"
      echo "Rollback (only if you are certain): re-run with AI_OS_SAFE_EXEC_GATE=0."
    } >&2
    exit 2
  fi
  exit 0   # PASS / WARN → allow (warnings are advisory, only BLOCK is enforced)
fi

# ── Backstop: analyzer unavailable → still block CATASTROPHIC patterns ─────────
# Narrow, false-positive-averse set (truly irreversible). The full ruleset lives
# in the node analyzer above; this only guarantees fail-closed on the worst cases.
_catastrophic() {
  local c="$1"
  # rm with recursive AND force (combined -rf/-fr/-Rfv… OR split -r … -f OR
  # --no-preserve-root) targeting a root/home path (/ ~ ~/ $HOME ${HOME} /*).
  if printf '%s' "$c" | grep -qE '(^|[;&|[:space:]])rm([[:space:]]|$)'; then
    if printf '%s' "$c" | grep -qE '(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR]|--no-preserve-root)' \
       || { printf '%s' "$c" | grep -qE '(-[rR]([[:space:]]|$)|--recursive)' \
            && printf '%s' "$c" | grep -qE '(-f([[:space:]]|$)|--force)'; }; then
      printf '%s' "$c" | grep -qE '([[:space:]=])(/|~|~/|\$HOME|\$\{HOME\})([[:space:]/]|$)' && return 0
      printf '%s' "$c" | grep -qE '[[:space:]]/\*([[:space:]]|$)' && return 0
    fi
  fi
  printf '%s' "$c" | grep -qE '(curl|wget)[[:space:]].*\|[[:space:]]*(ba|z|d)?sh' && return 0
  printf '%s' "$c" | grep -qE ':[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:' && return 0   # fork bomb
  printf '%s' "$c" | grep -qE '\bmkfs(\.[a-z0-9]+)?\b' && return 0
  printf '%s' "$c" | grep -qE '\bdd\b.*[[:space:]]of=/dev/' && return 0
  return 1
}
if _catastrophic "$CMD"; then
  echo "[SAFE_EXEC_BLOCK] safe-exec analyzer unavailable; backstop blocked a catastrophic pattern (E-125)." >&2
  exit 2
fi
exit 0
