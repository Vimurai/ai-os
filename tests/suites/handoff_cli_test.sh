#!/usr/bin/env bash
# handoff_cli_test.sh — E-158 (cli-agnostic-handoff): the provider-agnostic
# `ai handoff` shell command + src/shared/signal-handoff.mjs helper.
#
# WHY: agy (Antigravity Architect) runs shell via `run_command` reliably but does
# NOT dependably invoke custom project MCP servers, so a shell-native handoff is the
# robust path. This suite proves the CLI/helper writes the SAME locked signal.json
# queue entry as task-synchronizer-mcp::handoff_control (see handoff_control_test.sh),
# validates targets/messages, discovers .ai/ from subdirs, and never executes input.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
HELPER="${REPO_ROOT}/src/shared/signal-handoff.mjs"

echo "── Suite: handoff_cli_test (E-158) ─────────────────────────────────"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJECT="${TMP}/proj"; mkdir -p "${PROJECT}/.ai" "${PROJECT}/src/deep"
SIGNAL="${PROJECT}/.ai/signal.json"

# qlen/qfield mirror handoff_control_test.sh so the two suites assert identically.
qlen()   { python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); print(len(d) if isinstance(d,list) else 1)' "$1"; }
qfield() { I="$2" F="$3" python3 -c 'import json,os,sys
d=json.load(open(sys.argv[1])); d=d if isinstance(d,list) else [d]
i=int(os.environ["I"]); print(d[i].get(os.environ["F"],"MISSING") if -len(d)<=i<len(d) else "OOB")' "$1"; }

# ── 158.01: helper is present (the install copies it into ~/.ai-os/shared/) ───
assert_status 0 "158.01: signal-handoff.mjs exists in src/shared" test -f "$HELPER"

# ── 158.02: `ai handoff engineer <msg>` writes a valid queued entry ───────────
rm -f "$SIGNAL"
out="$(AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff engineer "Sprint planned: E-10..E-12 ready." 2>&1)"
assert_contains "158.02: HANDOFF confirmation → engineer" "[HANDOFF] → engineer" "$out"
assert_status 0 "158.02: signal.json created" test -f "$SIGNAL"
assert_status 0 "158.02: signal.json valid JSON" python3 -c "import json;json.load(open('${SIGNAL}'))"
assert_contains "158.02: target persisted"    "engineer" "$(qfield "$SIGNAL" 0 target)"
assert_contains "158.02: message persisted"   "E-10..E-12 ready" "$(qfield "$SIGNAL" 0 message)"
assert_contains "158.02: timestamp present"   "T" "$(qfield "$SIGNAL" 0 timestamp)"
assert_contains "158.02: delivered=false (pending)" "False" "$(qfield "$SIGNAL" 0 delivered)"
assert_contains "158.02: top-level is a queue (len 1)" "1" "$(qlen "$SIGNAL")"

# ── 158.03: second handoff APPENDS (FIFO, no overwrite) ──────────────────────
AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff architect "Engineer done — review the diff." >/dev/null 2>&1
assert_contains "158.03: queue grew to 2"            "2" "$(qlen "$SIGNAL")"
assert_contains "158.03: entry[0] preserved"        "engineer"  "$(qfield "$SIGNAL" 0 target)"
assert_contains "158.03: entry[1] appended"         "architect" "$(qfield "$SIGNAL" 1 target)"

# ── 158.04: omitted message → sensible role-based default (one-word handoff) ──
rm -f "$SIGNAL"
AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff architect >/dev/null 2>&1
assert_contains "158.04: default message for architect" "queue exhausted" "$(qfield "$SIGNAL" -1 message)"
rm -f "$SIGNAL"
AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff engineer >/dev/null 2>&1
assert_contains "158.04b: default message for engineer" "execute the open Engineer queue" "$(qfield "$SIGNAL" -1 message)"

# ── 158.05: invalid target → [INVALID_TARGET], exit 1, NOT queued ────────────
rm -f "$SIGNAL"
AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff engineer "seed" >/dev/null 2>&1
before="$(qlen "$SIGNAL")"
set +e
out="$(AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff designer "nope" 2>&1)"; rc=$?
set -e
assert_contains "158.05: [INVALID_TARGET] on bad target" "[INVALID_TARGET]" "$out"
assert_status 0 "158.05: invalid target exits nonzero" bash -c "[ $rc -ne 0 ]"
assert_contains "158.05: invalid target not queued" "$before" "$(qlen "$SIGNAL")"

# ── 158.06: no target → usage + exit 2 ───────────────────────────────────────
set +e
out="$(AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff 2>&1)"; rc=$?
set -e
assert_contains "158.06: usage printed" "usage: ai handoff" "$out"
assert_status 0 "158.06: missing target exits 2" bash -c "[ $rc -eq 2 ]"

# ── 158.07: EMPTY_MESSAGE guard at the helper layer (emitHandoff direct) ──────
# The CLI substitutes a default, so the empty-message rejection is exercised by
# calling emitHandoff() directly (the path handoff_control also relies on).
out="$(node --input-type=module -e "
import { emitHandoff } from '${HELPER}';
const r = emitHandoff({ aiDir: '${PROJECT}/.ai', target: 'engineer', message: '   ' });
console.log(r.ok ? 'OK' : r.code);
")"
assert_contains "158.07: blank message rejected by helper" "EMPTY_MESSAGE" "$out"

# ── 158.08: shell metacharacters are stored as DATA, never executed ──────────
rm -f "$SIGNAL"
GUARD="${TMP}/PWNED"
AI_OS_AIDIR="${PROJECT}/.ai" bash "$AI" handoff claude "do \$(touch ${GUARD}); echo \`id\`" >/dev/null 2>&1
assert_status 0 "158.08: injected command did NOT execute" bash -c "[ ! -e '${GUARD}' ]"
assert_contains "158.08: metachars stored verbatim" 'touch' "$(qfield "$SIGNAL" -1 message)"

# ── 158.09: .ai/ discovery walks UP from a subdirectory (git-style) ──────────
rm -f "$SIGNAL"
( cd "${PROJECT}/src/deep" && bash "$AI" handoff engineer "from a deep subdir" >/dev/null 2>&1 )
assert_status 0 "158.09: signal written to the project root .ai/ from a subdir" test -f "$SIGNAL"
assert_contains "158.09: subdir handoff message landed" "deep subdir" "$(qfield "$SIGNAL" -1 message)"

assert_summary
