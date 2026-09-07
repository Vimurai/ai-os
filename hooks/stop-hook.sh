#!/usr/bin/env bash
# AI-OS Stop Hook — auto-stamps .ai/SESSION.md when a Claude session ends.
# Installed to ~/.ai-os/hooks/stop-hook.sh and referenced in .claude/settings.json

AI_DIR="$(pwd)/.ai"
SESSION_FILE="${AI_DIR}/SESSION.md"

# Only run if this is an AI-OS project
[[ -d "$AI_DIR" ]] || exit 0
[[ -f "$SESSION_FILE" ]] || exit 0

TIMESTAMP=$(date '+%Y-%m-%d %H:%M %Z')

# Try to read the session summary from stdin (Claude may pass context as JSON)
SESSION_JSON=""
if read -t 1 -r line 2>/dev/null; then
  SESSION_JSON="$line"
fi

# Extract a brief summary if JSON is available
# Pass JSON via env var — avoids shell injection from embedding $SESSION_JSON in Python source
SUMMARY="auto-stamped by Stop hook"
if [[ -n "$SESSION_JSON" ]] && command -v python3 &>/dev/null; then
  EXTRACTED=$(HOOK_JSON="$SESSION_JSON" python3 - <<'PY'
import json, os
try:
    d = json.loads(os.environ.get("HOOK_JSON", ""))
    msg = d.get("summary") or d.get("message") or ""
    print(msg[:100] if msg else "")
except Exception:
    print("")
PY
  )
  [[ -n "$EXTRACTED" ]] && SUMMARY="$EXTRACTED"
fi

# E-213 (§Components 4): stamp WHICH provider ran WHICH role, instead of a hardcoded
# "Claude". Under a same-provider Triad both panes are Claude, so the provider alone no
# longer identifies the session. Role comes from the launch-time pane role (set by
# `ai pane`) or the advisory env; provider from .ai/roles.json. Fails soft to "Claude"
# — a session stamp must never break the Stop hook.
ACTOR="Claude"
_E213_ROLE="${AI_OS_PANE_ROLE:-${AI_OS_CALLER_ROLE:-engineer}}"
case "$_E213_ROLE" in architect|engineer) ;; *) _E213_ROLE="engineer" ;; esac
if command -v node >/dev/null 2>&1; then
  for _pa in "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/src/shared/provider-adapter.mjs" \
             "${HOME}/.ai-os/shared/provider-adapter.mjs"; do
    if [[ -f "$_pa" ]]; then
      _E213_PROV="$(node --no-warnings -e '
const { pathToFileURL } = require("node:url");
import(pathToFileURL(process.argv[1]).href).then(m =>
  process.stdout.write(m.roleProvider(process.argv[2], process.argv[3]) || ""));
' "$_pa" "$AI_DIR" "$_E213_ROLE" 2>/dev/null || true)"
      break
    fi
  done
fi
[[ -z "${_E213_PROV:-}" ]] && _E213_PROV="claude"
# "claude" -> "Claude" so the stamp reads the way it always has.
_E213_PROV="$(printf '%s' "$_E213_PROV" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
ACTOR="${_E213_PROV} (${_E213_ROLE})"

cat >> "$SESSION_FILE" <<STAMP
---
- Time: ${TIMESTAMP}
- Actor: ${ACTOR}
- Notes: ${SUMMARY}
---
STAMP

# Also append a one-liner to DIGEST.md "Recent changes" section
DIGEST_FILE="${AI_DIR}/DIGEST.md"
if [[ -f "$DIGEST_FILE" ]]; then
  TODAY=$(date '+%Y-%m-%d')
  # Only append if the last entry isn't from today already (avoid duplicate stamps)
  if ! grep -q "^- ${TODAY}:" "$DIGEST_FILE" 2>/dev/null; then
    # Build a meaningful entry: use SUMMARY if it came from Claude, otherwise
    # pull the last written file from LOG.md as a hint
    DIGEST_NOTE="$SUMMARY"
    LOG_FILE="${AI_DIR}/LOG.md"
    if [[ "$DIGEST_NOTE" == "auto-stamped by Stop hook" && -f "$LOG_FILE" ]]; then
      LAST_FILE=$(grep -o '| [A-Z_]*\.md$' "$LOG_FILE" 2>/dev/null | tail -1 | tr -d '| ' || true)
      [[ -n "$LAST_FILE" ]] && DIGEST_NOTE="updated ${LAST_FILE}"
    fi
    # Never pollute DIGEST's curated "Recent Changes" with the generic placeholder
    # (no real session summary AND no LOG-derived note). The curated section is
    # maintained by digest_updater / ai-digest; the stale-warning below prompts a
    # proper regen. Writing "auto-stamped by Stop hook" here was a recurring junk
    # line that had to be hand-reverted before every commit.
    if [[ "$DIGEST_NOTE" != "auto-stamped by Stop hook" ]]; then
      printf -- "- %s: %s\n" "$TODAY" "$DIGEST_NOTE" >> "$DIGEST_FILE"
    fi
  fi
fi

# Reactive Memory (E-138, §24): detect digest_stale flag set by run_handover.
# Read from state.sqlite directly via sqlite3 CLI (P-18 — no python3/state.json dependency).
SQLITE_FILE="${AI_DIR}/state.sqlite"
STALE_REASON=""
if [[ -f "$SQLITE_FILE" ]] && command -v sqlite3 &>/dev/null; then
  DIGEST_STALE=$(sqlite3 "$SQLITE_FILE" "SELECT value FROM meta WHERE key='digest_stale'" 2>/dev/null || echo "false")
  if [[ "$DIGEST_STALE" == "true" ]]; then
    STALE_REASON=$(sqlite3 "$SQLITE_FILE" "SELECT value FROM meta WHERE key='digest_stale_reason'" 2>/dev/null || echo "task completed")
    STALE_REASON="${STALE_REASON:0:80}"
  fi
fi

if [[ -n "$STALE_REASON" ]]; then
  cat >&2 <<WARN

╔══════════════════════════════════════════════════════════════╗
║  REACTIVE MEMORY — DIGEST.md IS STALE (§24)                 ║
╠══════════════════════════════════════════════════════════════╣
║  Reason: ${STALE_REASON}
║                                                              ║
║  Regenerate DIGEST.md before the next session:              ║
║    skill: "ai-digest"                                        ║
║    or: activate_skill('digest_updater')                      ║
╚══════════════════════════════════════════════════════════════╝

WARN
fi

exit 0
