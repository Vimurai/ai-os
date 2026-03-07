#!/usr/bin/env bash
# AI-OS PostToolUse Hook — appends a one-liner to .ai/LOG.md when .ai/ files are written.
# Also logs [SECURITY] prefix for EXECUTE/write system-state operations.
# Installed to ~/.ai-os/hooks/post-tool-log.sh

INPUT=$(cat)

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

# ── SECURITY: detect EXECUTE operations ──────────────────────────────────────
# Tools that modify system state beyond .ai/ file edits
EXECUTE_TOOLS = {
    "run_shell_command",
    "execute_python",
    "execute_bash",
    "Bash",
    "computer",
}

# Read-only shell patterns — these do NOT get [SECURITY] tags
READ_ONLY_PATTERNS = [
    "cat ", "ls ", "find ", "echo ", "pwd", "which ", "head ", "tail ",
    "grep ", "rg ", "wc ", "stat ", "file ", "diff ", "git log",
    "git status", "git diff", "git show", "git branch", "git remote",
    "curl -s", "curl --silent", "wget -q",
]

def is_read_only_cmd(cmd):
    cmd = cmd.strip()
    for pattern in READ_ONLY_PATTERNS:
        if cmd.startswith(pattern):
            return True
    return False

# Check if this is an EXECUTE-tier operation
is_security_event = False
security_detail = ""

if tool in EXECUTE_TOOLS:
    cmd = inp.get("command") or inp.get("cmd") or inp.get("code") or ""
    if cmd and not is_read_only_cmd(cmd):
        is_security_event = True
        security_detail = cmd[:120].replace("\n", " ")

# ── Determine file path for .ai/ logging ─────────────────────────────────────
file_path = inp.get("file_path") or inp.get("path") or ""

ai_file = ""
if file_path:
    norm = os.path.normpath(os.path.abspath(file_path))
    if "/.ai/" in norm or norm.endswith("/.ai"):
        ai_file = os.path.basename(file_path)

# Output format: type|tool|detail
if is_security_event:
    print(f"SECURITY|{tool}|{security_detail}")
elif ai_file:
    print(f"LOG|{tool}|{ai_file}")
else:
    print("")
PY
)

[[ -z "$RESULT" ]] && exit 0

TYPE="${RESULT%%|*}"
REST="${RESULT#*|}"
TOOL="${REST%%|*}"
DETAIL="${REST#*|}"

AI_DIR="$(pwd)/.ai"
LOG_FILE="${AI_DIR}/LOG.md"

[[ -f "$LOG_FILE" ]] || exit 0

TIMESTAMP=$(date '+%Y-%m-%d %H:%M %Z')

if [[ "$TYPE" == "SECURITY" ]]; then
  printf "- %s | Claude | [SECURITY] %s | %s\n" "$TIMESTAMP" "$TOOL" "$DETAIL" >> "$LOG_FILE"
else
  printf "- %s | Claude | %s | %s\n" "$TIMESTAMP" "$TOOL" "$DETAIL" >> "$LOG_FILE"
fi

exit 0
