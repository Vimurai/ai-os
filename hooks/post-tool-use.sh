#!/usr/bin/env bash
# AI-OS PostToolUse — Automatic Quality Gate (AQG)
# Intercepts Write/Edit tool calls on src/** files and runs tests/run.sh.
# Exits 1 with [LOCKED - AQG FAILED] if tests fail, blocking the agent.
# Installed to ~/.ai-os/hooks/post-tool-use.sh

INPUT=$(cat)

# Detect if the modified file is under src/ — pass via env var to avoid injection
RESULT=$(HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, sys, os

try:
    data = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

tool = data.get("tool_name", "")
inp  = data.get("tool_input", {})

if tool not in ("Write", "Edit"):
    sys.exit(0)

file_path = inp.get("file_path") or inp.get("path") or ""
if not file_path:
    sys.exit(0)

norm = os.path.normpath(os.path.abspath(file_path))
cwd  = os.path.normpath(os.getcwd())
rel  = os.path.relpath(norm, cwd)

if rel.startswith("src" + os.sep) or rel == "src":
    print("RUN_TESTS|" + rel)
PY
)

[[ -z "$RESULT" ]] && exit 0

FILE_REL="${RESULT#*|}"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TEST_RUNNER="${PROJECT_ROOT}/tests/run.sh"

[[ -f "$TEST_RUNNER" ]] || exit 0  # No test runner — skip silently

if bash "$TEST_RUNNER" >/dev/null 2>&1; then
  exit 0
else
  echo "[LOCKED - AQG FAILED] Tests failed after editing ${FILE_REL} — fix before proceeding."
  echo "Run: bash tests/run.sh"
  exit 1
fi
