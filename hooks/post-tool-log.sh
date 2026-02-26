#!/usr/bin/env bash
# AI-OS PostToolUse Hook — appends a one-liner to .ai/LOG.md when .ai/ files are written.
# Installed to ~/.ai-os/hooks/post-tool-log.sh

INPUT=$(cat)

# Extract tool name and file path
# Pass input via env var — avoids shell injection from embedding $INPUT in Python source
RESULT=$(HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, sys, os

try:
    data = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    print("")
    sys.exit(0)

tool = data.get("tool_name", "")
inp  = data.get("tool_input", {})

file_path = inp.get("file_path") or inp.get("path") or ""
if not file_path:
    print("")
    sys.exit(0)

# Only log writes to .ai/ files
# Resolve to absolute path so both absolute and relative paths match
norm = os.path.normpath(os.path.abspath(file_path))
if "/.ai/" not in norm and not norm.endswith("/.ai"):
    print("")
    sys.exit(0)

filename = os.path.basename(file_path)
print(f"{tool}|{filename}")
PY
)

[[ -z "$RESULT" ]] && exit 0

TOOL="${RESULT%%|*}"
FILENAME="${RESULT##*|}"

AI_DIR="$(pwd)/.ai"
LOG_FILE="${AI_DIR}/LOG.md"

[[ -f "$LOG_FILE" ]] || exit 0

TIMESTAMP=$(date '+%Y-%m-%d %H:%M %Z')
printf "- %s | Claude | %s | %s\n" "$TIMESTAMP" "$TOOL" "$FILENAME" >> "$LOG_FILE"

exit 0
