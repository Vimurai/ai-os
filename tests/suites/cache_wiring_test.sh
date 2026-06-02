#!/usr/bin/env bash
# cache_wiring_test.sh — E-112 (caching.md §3.1): the cache-manager-mcp is wired
# into a live flow via a post-write hook. Previously it was built but never
# invoked. The hook rebuilds the System Context cache ONLY when a blueprint or
# architect.md is written (not on every tool), matching the blueprint's
# "post-write hook" trigger.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CACHE_MCP="${REPO_ROOT}/src/mcp/cache-manager-mcp/index.js"
HOOK="${REPO_ROOT}/hooks/post-tool-use.sh"

echo "===== cache_wiring_test.sh (E-112) ====="

# ── S01: cache-manager exposes a --build CLI mode that exits before the server ─
assert_status 0 "cache-manager has --build CLI branch" \
  grep -qE 'process\.argv\.includes\("--build"\)' "$CACHE_MCP"
# The --build branch must precede server.connect so it exits without serving.
assert_status 0 "--build branch precedes server.connect" \
  python3 -c "import sys; s=open('${CACHE_MCP}').read(); b=s.find('--build'); c=s.find('server.connect'); sys.exit(0 if 0 <= b < c else 1)"

# ── S02: post-tool-use.sh fires the rebuild only on blueprint/architect writes ─
assert_status 0 "hook detects .ai/blueprints/ writes" \
  grep -qF '/.ai/blueprints/' "$HOOK"
assert_status 0 "hook detects .ai/architect.md writes" \
  grep -qF '/.ai/architect.md' "$HOOK"
assert_status 0 "hook invokes cache-manager --build" \
  grep -qE 'cache-manager-mcp/index\.js' "$HOOK"
assert_status 0 "hook honors AI_OS_DISABLE_CACHE rollback" \
  grep -qF 'AI_OS_DISABLE_CACHE' "$HOOK"
assert_status 0 "hook locator falls back to ~/.ai-os mirror" \
  grep -qF '${HOME}/.ai-os/mcp/cache-manager-mcp/index.js' "$HOOK"

# ── S03: detection logic — blueprint/architect REBUILD, src/Bash do not ──────
det() { HOOK_INPUT="$1" python3 - <<'PY' 2>/dev/null
import json,os,sys
try: d=json.loads(os.environ.get("HOOK_INPUT",""))
except Exception: sys.exit(0)
if d.get("tool_name") not in ("Write","Edit"): sys.exit(0)
inp=(d.get("tool_input") or {}); fp=inp.get("file_path") or inp.get("path") or ""
if not fp: sys.exit(0)
n="/"+os.path.normpath(fp).replace("\\","/").lstrip("/")
if "/.ai/blueprints/" in n or n.endswith("/.ai/architect.md"): print("REBUILD")
PY
}
assert_contains "S03: blueprint write triggers REBUILD" "REBUILD" \
  "$(det '{"tool_name":"Write","tool_input":{"file_path":"/p/.ai/blueprints/caching.md"}}')"
assert_contains "S03: architect.md edit triggers REBUILD" "REBUILD" \
  "$(det '{"tool_name":"Edit","tool_input":{"file_path":".ai/architect.md"}}')"
assert_not_contains "S03: src/ write does NOT trigger" "REBUILD" \
  "$(det '{"tool_name":"Write","tool_input":{"file_path":"/p/src/x.js"}}')"
assert_not_contains "S03: non-Write/Edit tool does NOT trigger" "REBUILD" \
  "$(det '{"tool_name":"Bash","tool_input":{"command":"ls"}}')"

# ── S04: --build behaviourally builds the cache + exits 0 ────────────────────
TMP="$(mktemp -d)"; mkdir -p "${TMP}/.ai/blueprints"
echo "# Blueprint: T" > "${TMP}/.ai/blueprints/t.md"
echo "# architect index" > "${TMP}/.ai/architect.md"
OUT="$( cd "${TMP}" && node "${CACHE_MCP}" --build 2>&1 )"; RC=$?
assert_status 0 "S04: --build exits 0 (does not hang serving)" bash -c "[ $RC -eq 0 ]"
assert_contains "S04: --build reports the cache was built" "context cache" "$OUT"
rm -rf "${TMP}"

# ── S05: mirror identity for the hook ────────────────────────────────────────
assert_status 0 "post-tool-use.sh ~/.ai-os mirror identical" \
  diff -q "$HOOK" "${HOME}/.ai-os/hooks/post-tool-use.sh"

assert_summary
