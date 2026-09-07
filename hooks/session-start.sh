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
#
# E-208 (D-054, role-abstraction.md §Components 2): the LAUNCH-TIME role wins over
# the positional default. `ai pane <role>` exports AI_OS_PANE_ROLE in the launch
# environment of the provider CLI, so a second Claude pane bound to `architect`
# mints an ARCHITECT token even though the project settings bake `engineer`. The
# positional default is unchanged, so a plain `claude` launch still mints engineer.
#
# Why launch env is trusted here: E-129 defends against IN-SESSION mutation (a Bash
# subprocess exporting a role before reaching the gate). Launch-time environment is
# set before the CLI starts and is exactly as trusted as the settings file on disk —
# this is inside the E-129 threat model, not a widening of it (D-054 §Constraints).
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

ROLE="${AI_OS_PANE_ROLE:-${1:-engineer}}"

# Only ever mint a role the system actually defines — an unknown value falls back to
# the positional default rather than minting a token for a role no gate understands.
case "$ROLE" in
  architect|engineer) : ;;
  *) ROLE="${1:-engineer}" ;;
esac

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
    _s="$(ai_os_locate mcp/safe-exec-mcp/index.js || true)"
    [[ -n "$_s" ]] && node --no-warnings "$_s" --mint-token "$ROLE" "$_SID" >/dev/null 2>&1
  fi
fi

# ── E-126 + E-208: emit additionalContext ─────────────────────────────────────
# E-208 (D-054, role-abstraction.md §Components 2): the FIRST line of the injected
# context is an `[AI_OS_ROLE] <role>` stamp naming the role this session actually
# minted. The Role Resolution clause at the top of ENGINEER.md / ARCHITECT.md keys
# off it, so a Claude pane bound to `architect` is governed by ARCHITECT.md even
# though CLAUDE.md statically imports ENGINEER.md (gap G1 — @import cannot branch).
#
# The stamp is emitted even when the E-126 cache is unavailable or disabled: the
# persona layer must never silently lose its role binding just because the cache is
# off. Only a missing python3 (no way to build the JSON envelope) skips it.
ROLE_STAMP="[AI_OS_ROLE] ${ROLE}"

command -v python3 >/dev/null 2>&1 || exit 0

BLOB=""
if [[ "${AI_OS_DISABLE_CACHE:-0}" != "1" ]] && command -v node >/dev/null 2>&1; then
  CM=""
  CM="$(ai_os_locate mcp/cache-manager-mcp/index.js || true)"
  [[ -n "$CM" ]] && BLOB="$(node --no-warnings "$CM" --emit-context 2>/dev/null)"
fi

printf '%s\n\n%s' "$ROLE_STAMP" "$BLOB" | python3 -c '
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
