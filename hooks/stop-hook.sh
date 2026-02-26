#!/usr/bin/env bash
# AI-OS Stop Hook — auto-stamps .ai/SESSION.md when a Claude session ends.
# Installed to ~/.ai-os/hooks/stop-hook.sh and referenced in ~/.claude/settings.json

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

cat >> "$SESSION_FILE" <<STAMP
---
- Time: ${TIMESTAMP}
- Actor: Claude
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
    printf -- "- %s: %s\n" "$TODAY" "$DIGEST_NOTE" >> "$DIGEST_FILE"
  fi
fi

exit 0
