#!/usr/bin/env bash
# handoff_control_test.sh — E-114 (interactive-bridge.md): the handoff_control
# tool writes a structured signal to .ai/signal.json for the `ai watch` tmux
# watcher to consume.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: handoff_control_test (E-114) ─────────────────────────────"

unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJECT="${TMP}/proj"; mkdir -p "${PROJECT}/.ai"
echo '{"version":"1.0","project":{},"tasks":[],"stamps":[],"deltas":[]}' > "${PROJECT}/.ai/state.json"
cd "${PROJECT}"
SIGNAL="${PROJECT}/.ai/signal.json"

call()    { mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'; }
is_error(){ mcp_call_tool "${SERVER}" "$1" "$2" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("PARSEFAIL"); sys.exit(0)
print("ISERROR" if d.get("isError") else "OK")'; }
field()   { F="$2" python3 -c 'import json,os,sys; print(json.load(open(sys.argv[1])).get(os.environ["F"],"MISSING"))' "$1"; }

# ── E-114.01: tool is advertised ─────────────────────────────────────────────
assert_status 0 "E-114.01: handoff_control advertised in tools/list" \
  mcp_assert_tool_listed "${SERVER}" handoff_control

# ── E-114.02: signal to claude writes a valid .ai/signal.json ────────────────
r=$(call handoff_control '{"target":"claude","message":"Planning complete. Execute OPEN tasks."}')
assert_contains "E-114.02: HANDOFF confirmation → claude" "[HANDOFF] → claude" "$r"
assert_status 0 "E-114.02: signal.json created" test -f "$SIGNAL"
assert_status 0 "E-114.02: signal.json is valid JSON" python3 -c "import json;json.load(open('${SIGNAL}'))"
assert_contains "E-114.02: target=claude"        "claude" "$(field "$SIGNAL" target)"
assert_contains "E-114.02: message persisted"    "Execute OPEN tasks" "$(field "$SIGNAL" message)"
assert_status 0 "E-114.02: timestamp present"    bash -c "[ -n \"\$(F=timestamp python3 -c 'import json,os;print(json.load(open(\"${SIGNAL}\")).get(os.environ[\"F\"],\"\"))')\" ]"

# ── E-114.03: signal to gemini overwrites the previous signal ────────────────
call handoff_control '{"target":"gemini","message":"Engineer done. Review the diff."}' >/dev/null
assert_contains "E-114.03: target overwritten to gemini" "gemini" "$(field "$SIGNAL" target)"
assert_contains "E-114.03: message overwritten"          "Review the diff" "$(field "$SIGNAL" message)"

# ── E-114.04: invalid target rejected ────────────────────────────────────────
r=$(call handoff_control '{"target":"bob","message":"hi"}')
assert_contains "E-114.04: [INVALID_TARGET] on bad target" "[INVALID_TARGET]" "$r"
assert_contains "E-114.04: returns isError" "ISERROR" "$(is_error handoff_control '{"target":"bob","message":"hi"}')"

# ── E-114.05: empty message rejected ─────────────────────────────────────────
r=$(call handoff_control '{"target":"claude","message":"   "}')
assert_contains "E-114.05: [EMPTY_MESSAGE] on blank message" "[EMPTY_MESSAGE]" "$r"

# ── E-114.06: shell metacharacters in the message are stored as data (no exec) ─
call handoff_control '{"target":"claude","message":"do $(rm -rf /tmp/x); echo `id`"}' >/dev/null
assert_contains "E-114.06: metachars stored verbatim as JSON data" 'rm -rf /tmp/x' "$(field "$SIGNAL" message)"

cd "${REPO_ROOT}"
assert_summary
