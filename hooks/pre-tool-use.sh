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
# E-208 (D-054, role-abstraction.md §Components 5): the gate also covers the WRITE
# tools (Write|Edit|MultiEdit|NotebookEdit). When the HMAC-verified session role is
# `architect`, a write to any path outside .ai/ or plans/ is BLOCKED. The Engineer
# path is unchanged: for role=engineer the write gate is a fast no-op.
#
# SCOPE (widened by E-216 / D-055 R1). The Architect write gate now has THREE layers:
#   1. this hook — the native Write/Edit tools, path-checked against .ai//plans/
#   2. safe-exec analyzeArchitectWrites — shell redirections, tee/cp/mv/install/ln/
#      rsync/dd/truncate/patch, sed -i / perl -i, git apply; inline interpreters
#      (python3 -c, node -e, bash -c, eval, heredoc-fed) blocked outright
#   3. permissions.deny in .claude/settings.architect.json — the MCP write tools
# STATED RESIDUAL: exotic encodings, git plumbing (hash-object/update-index), and
# interactive editors are NOT covered. Strong defence in depth; not airtight. The Git
# Lane (E-214) remains the last checkpoint before anything reaches history.
#
# Rollback / emergency bypass: AI_OS_SAFE_EXEC_GATE=0.
# ── E-223 (D-057 §3): install-first helper resolution ────────────────────────
# The locators below used to start at "$(git rev-parse --show-toplevel)/src/...", which
# names the USER's repository, not the AI-OS install. Any project containing
# src/mcp/safe-exec-mcp/index.js had THAT file executed by node from inside this hook,
# with its stdout trusted to decide whether a write is allowed — cloning a repo was
# enough to run its code and disable the gate meant to stop it.
#
# Bootstrapping the shared resolver must not repeat the mistake, so it is install-mirror
# first and script-relative second — never the visited repo.
# The env here may have been chosen by the repo we are visiting (a project's
# .claude/settings.json `env` block is inherited by hooks), so AI_OS_HOME is NOT read:
# pointing it at a decoy made this bootstrap SOURCE the decoy's own locate.sh, i.e.
# arbitrary shell inside a fail-closed gate. Assigned here, in the hook's own text, so it
# overrides anything inherited.
# Exported so a child process — an `ai` subcommand spawned from this hook — inherits
# the same judgement rather than defaulting back to trusting the environment.
export AI_OS_LOCATE_UNTRUSTED_ENV=1
_AI_OS_HOME_DIR="${HOME}/.ai-os"
# The guard below asks `declare -f ai_os_locate`, which means "is a name defined", NOT
# "did my source succeed". bash imports exported functions from the environment at
# startup, so an inherited `ai_os_locate` satisfies it, the safe inline fallback is never
# installed, and the attacker's function IS the resolver — reachable whenever
# shared/locate.sh is absent, i.e. exactly the degraded install the fallback exists for.
unset -f ai_os_locate ai_os_locate_enable_dev_tree ai_os_is_framework_clone 2>/dev/null || true
for _l in "${_AI_OS_HOME_DIR}/shared/locate.sh" \
          "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/../src/shared/locate.sh"; do
  [[ -f "$_l" ]] && { . "$_l"; break; }
done
# Fail-open: these hooks must still run without the resolver (a missing helper is a
# degraded gate, an aborted hook is a broken session). The fallback is the install
# mirror alone — it never falls back to the visited repo.
if ! declare -f ai_os_locate >/dev/null 2>&1; then
  ai_os_locate() { local _c="${_AI_OS_HOME_DIR}/${1}"; [[ -f "$_c" ]] && { printf '%s' "$_c"; return 0; }; return 1; }
fi

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
# E-208: Write/Edit/MultiEdit carry file_path; NotebookEdit carries notebook_path.
fp = ""
if isinstance(ti, dict):
    fp = ti.get("file_path") or ti.get("notebook_path") or ""
print(tool)
print(base64.b64encode((cmd or "").encode()).decode())
print(d.get("session_id", "") or "")   # E-129: tamper-resistant role token key
print(base64.b64encode((fp or "").encode()).decode())
' 2>/dev/null)"

TOOL="$(printf '%s\n' "$PARSED" | sed -n '1p')"
CMD="$(printf '%s\n' "$PARSED" | sed -n '2p' | base64 --decode 2>/dev/null)"
SID="$(printf '%s\n' "$PARSED" | sed -n '3p')"   # E-129: session id (from harness, not env)
FILE_PATH="$(printf '%s\n' "$PARSED" | sed -n '4p' | base64 --decode 2>/dev/null)"

# ── E-208: Architect write-scope gate (Write|Edit|MultiEdit|NotebookEdit) ──────
# Delegates to safe-exec `--check-path`, which resolves the role from the SAME
# HMAC-verified session token the Bash gate uses and exits 0 immediately for a
# non-architect role. Fail-open ONLY when the analyzer is missing (no node / not
# installed) — an analyzer that is present but crashes exits 2 and blocks (E-128).
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    [[ -z "$FILE_PATH" ]] && exit 0
    SE_W=""
    SE_W="$(ai_os_locate mcp/safe-exec-mcp/index.js || true)"
    if [[ -n "$SE_W" ]] && command -v node >/dev/null 2>&1; then
      # Argument order is fixed: <path> <role> --session <sid>. safe-exec anchors its
      # --session scan past those positionals, so a target path literally named
      # "--session" cannot hijack the parse (E-208 audit).
      W_REPORT="$(node --no-warnings "$SE_W" --check-path "$FILE_PATH" "${AI_OS_CALLER_ROLE:-engineer}" --session "$SID" 2>/dev/null)"
      W_RC=$?
      # ANY non-zero exit blocks, not just 2. A module that fails to LOAD exits 1,
      # and E-128's in-JS fail-closed guarantee cannot cover a file that never ran —
      # so treating only 2 as a block left a fail-open hole (E-208 audit).
      if [[ "$W_RC" -ne 0 ]]; then
        {
          echo "[SOVEREIGNTY_BLOCK] Architect write-scope gate (E-208) blocked this ${TOOL}:"
          echo "$W_REPORT"
          echo "Rollback (only if you are certain): re-run with AI_OS_SAFE_EXEC_GATE=0."
        } >&2
        exit 2
      fi
    fi
    exit 0
    ;;
esac

# Only gate shell execution below this point. Other tools pass through.
[[ "$TOOL" != "Bash" ]] && exit 0
[[ -z "$CMD" ]] && exit 0

# This gate runs in the Engineer's (Claude's) session. Role-specific architect
# sovereignty blocks are keyed on caller_role; default to engineer here.
ROLE="${AI_OS_CALLER_ROLE:-engineer}"

# ── Primary: the node analyzer (single source of truth with the MCP tool) ─────
SE=""
SE="$(ai_os_locate mcp/safe-exec-mcp/index.js || true)"

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
