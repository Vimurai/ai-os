#!/usr/bin/env bash
# handoff_control_test.sh — E-114 + E-118 (interactive-bridge.md): the
# handoff_control tool writes a structured signal to .ai/signal.json for the
# `ai watch` tmux watcher to consume.
#   E-114: write a structured {target,message,timestamp} payload; validate input.
#   E-118: .ai/signal.json is a FIFO QUEUE (array) — entries are APPENDED (never
#          overwritten); legacy flat objects migrate; corrupt queues reset; the
#          queue is capped to bound growth.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: handoff_control_test (E-114 + E-118) ─────────────────────"

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
# qlen <file> → number of queued entries (legacy flat object counts as 1).
qlen()    { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(len(d) if isinstance(d,list) else 1)' "$1"; }
# qfield <file> <index> <key> → queue[index][key] (negative index = from end).
qfield()  { I="$2" F="$3" python3 -c 'import json,os,sys
d=json.load(open(sys.argv[1]))
d=d if isinstance(d,list) else [d]
i=int(os.environ["I"])
print(d[i].get(os.environ["F"],"MISSING") if -len(d)<=i<len(d) else "OOB")' "$1"; }

# ── E-114.01: tool is advertised ─────────────────────────────────────────────
assert_status 0 "E-114.01: handoff_control advertised in tools/list" \
  mcp_assert_tool_listed "${SERVER}" handoff_control

# ── E-114.02: a signal to claude writes a valid .ai/signal.json ──────────────
rm -f "$SIGNAL"
r=$(call handoff_control '{"target":"claude","message":"Planning complete. Execute OPEN tasks."}')
assert_contains "E-114.02: HANDOFF confirmation → claude" "[HANDOFF] → claude" "$r"
assert_status 0 "E-114.02: signal.json created"  test -f "$SIGNAL"
assert_status 0 "E-114.02: signal.json is valid JSON" python3 -c "import json;json.load(open('${SIGNAL}'))"
assert_contains "E-114.02: payload target=claude"   "claude" "$(qfield "$SIGNAL" 0 target)"
assert_contains "E-114.02: payload message persisted" "Execute OPEN tasks" "$(qfield "$SIGNAL" 0 message)"
assert_contains "E-114.02: payload timestamp present" "T" "$(qfield "$SIGNAL" 0 timestamp)"

# ── E-118.01: signal.json is a JSON ARRAY (queue), not a flat object ─────────
assert_status 0 "E-118.01: signal.json top-level is an array" \
  python3 -c "import json;d=json.load(open('${SIGNAL}'));exit(0 if isinstance(d,list) else 1)"
assert_contains "E-118.01: queue length is 1 after first append" "1" "$(qlen "$SIGNAL")"

# ── E-118.02: a second signal APPENDS (does not overwrite) + preserves order ─
call handoff_control '{"target":"gemini","message":"Engineer done. Review the diff."}' >/dev/null
assert_contains "E-118.02: queue grew to 2"            "2" "$(qlen "$SIGNAL")"
assert_contains "E-118.02: entry[0] preserved (claude)" "claude" "$(qfield "$SIGNAL" 0 target)"
assert_contains "E-118.02: entry[1] appended (gemini)"  "gemini" "$(qfield "$SIGNAL" 1 target)"
assert_contains "E-118.02: entry[1] message"            "Review the diff" "$(qfield "$SIGNAL" 1 message)"
assert_contains "E-118.02: confirmation reports queue position" "queued #3" \
  "$(call handoff_control '{"target":"claude","message":"third"}')"

# ── E-114.04: invalid target rejected (and not appended) ─────────────────────
before="$(qlen "$SIGNAL")"
r=$(call handoff_control '{"target":"bob","message":"hi"}')
assert_contains "E-114.04: [INVALID_TARGET] on bad target" "[INVALID_TARGET]" "$r"
assert_contains "E-114.04: returns isError" "ISERROR" "$(is_error handoff_control '{"target":"bob","message":"hi"}')"
assert_contains "E-114.04: rejected target not queued" "$before" "$(qlen "$SIGNAL")"

# ── E-114.05: empty message rejected (and not appended) ──────────────────────
before="$(qlen "$SIGNAL")"
r=$(call handoff_control '{"target":"claude","message":"   "}')
assert_contains "E-114.05: [EMPTY_MESSAGE] on blank message" "[EMPTY_MESSAGE]" "$r"
assert_contains "E-114.05: rejected blank not queued" "$before" "$(qlen "$SIGNAL")"

# ── E-114.06: shell metacharacters stored as data (no exec) ──────────────────
call handoff_control '{"target":"claude","message":"do $(rm -rf /tmp/x); echo `id`"}' >/dev/null
assert_contains "E-114.06: metachars stored verbatim as JSON data" 'rm -rf /tmp/x' \
  "$(qfield "$SIGNAL" -1 message)"

# ── E-118.03: a legacy flat-object signal is migrated into the queue ─────────
printf '{"timestamp":"2026-06-02T12:00:00Z","target":"gemini","message":"legacy single"}\n' > "$SIGNAL"
call handoff_control '{"target":"claude","message":"after legacy"}' >/dev/null
assert_contains "E-118.03: legacy object migrated → array len 2" "2" "$(qlen "$SIGNAL")"
assert_contains "E-118.03: legacy entry preserved at [0]" "legacy single" "$(qfield "$SIGNAL" 0 message)"
assert_contains "E-118.03: new entry appended at [1]"     "after legacy"  "$(qfield "$SIGNAL" 1 message)"

# ── E-118.04: a corrupt queue is safely reset (not a throw) ──────────────────
printf 'not json at all {{{' > "$SIGNAL"
r=$(call handoff_control '{"target":"claude","message":"recovered"}')
assert_contains "E-118.04: corrupt queue → HANDOFF still succeeds" "[HANDOFF]" "$r"
assert_status 0 "E-118.04: signal.json valid JSON after reset" \
  python3 -c "import json;json.load(open('${SIGNAL}'))"
assert_contains "E-118.04: queue reset to a single fresh entry" "1" "$(qlen "$SIGNAL")"
assert_contains "E-118.04: recovered message present" "recovered" "$(qfield "$SIGNAL" 0 message)"

# ── E-118.05: queue is capped (bounded growth) ──────────────────────────────
rm -f "$SIGNAL"
for i in $(seq 1 55); do
  call handoff_control "{\"target\":\"claude\",\"message\":\"m${i}\"}" >/dev/null
done
cap="$(qlen "$SIGNAL")"
assert_status 0 "E-118.05: queue capped at <=50 (got ${cap})" bash -c "[ '${cap}' -le 50 ]"
assert_contains "E-118.05: newest entry retained after rotation" "m55" "$(qfield "$SIGNAL" -1 message)"

cd "${REPO_ROOT}"
assert_summary
