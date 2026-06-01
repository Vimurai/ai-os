#!/usr/bin/env bash
# AI-OS PostToolUse — Automatic Quality Gate (AQG) + Universal Telemetry (E-105)
# 1. AQG: intercepts Write/Edit on src/** and runs tests/run.sh. Exits 1
#    with [LOCKED - AQG FAILED] if tests fail, blocking the agent.
# 2. Telemetry: pipes every tool execution to telemetry.mjs --record-tool
#    in a backgrounded, fail-open path so 100% of invocations land in
#    ~/.ai-os/telemetry.sqlite (per .ai/blueprints/universal-telemetry.md).
# Installed to ~/.ai-os/hooks/post-tool-use.sh

INPUT=$(cat)

# ── Universal Telemetry (E-105) ──────────────────────────────────────────────
# Background-record every tool execution. Locator chain mirrors E-58:
#   1. ${PROJECT_ROOT}/src/shared/telemetry.mjs (dev tree)
#   2. ${HOME}/.ai-os/shared/telemetry.mjs     (installed mirror)
# Fail-open: all errors swallowed. <50ms synchronous hook budget preserved by
# putting BOTH the python schema-translation AND the node write inside the
# detached subshell — only the cheap helper-locator runs on the hot path.
{
  TELEMETRY_HELPER=""
  for c in "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/src/shared/telemetry.mjs" \
           "${HOME}/.ai-os/shared/telemetry.mjs"; do
    if [[ -f "$c" ]]; then TELEMETRY_HELPER="$c"; break; fi
  done
  if [[ -n "$TELEMETRY_HELPER" ]] && command -v node >/dev/null 2>&1; then
    (
      # Translate Claude Code PostToolUse schema → blueprint flat schema
      # ({tool_name, execution_time_ms, status}). tool_input/tool_response
      # bodies are NEVER forwarded — only the three privacy-safe fields
      # the CLI persists.
      TELEMETRY_JSON="$(HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null
import json, os, sys
try:
    d = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
tool_name = d.get("tool_name") or ""
if not tool_name:
    sys.exit(0)
tr = d.get("tool_response") or {}
status = "ERROR" if tr.get("isError") else "SUCCESS"
exec_ms = tr.get("duration_ms")
if not isinstance(exec_ms, (int, float)):
    exec_ms = 0
print(json.dumps({
    "tool_name": tool_name,
    "execution_time_ms": int(exec_ms),
    "status": status,
}))
PY
)"
      [[ -n "$TELEMETRY_JSON" ]] \
        && echo "$TELEMETRY_JSON" | node "$TELEMETRY_HELPER" --record-tool
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
} 2>/dev/null


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
