#!/usr/bin/env bash
# incident_aggregator_test.sh — Tests for E-66 + E-67.
#
# E-66: incident-aggregate.mjs reads ~/.ai-os/incidents.ndjson, groups by
#       stack_signature, surfaces THRESHOLD_REACHED at >=3 occurrences.
# E-67: ai-preflight SKILL.md wires the aggregator and emits the
#       [INCIDENT_THRESHOLD_REACHED] context block when the threshold trips.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGGR="${REPO_ROOT}/src/shared/incident-aggregate.mjs"
APPEND="${REPO_ROOT}/src/shared/incident-append.mjs"
SKILL="${REPO_ROOT}/src/shared/skills/ai-preflight/SKILL.md"
SKILL_MIRROR="${HOME}/.ai-os/shared/skills/ai-preflight/SKILL.md"
AGGR_MIRROR="${HOME}/.ai-os/shared/incident-aggregate.mjs"

echo "===== incident_aggregator_test.sh ====="

SBOX="$(mktemp -d -t aggr-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT

run_aggr() {
  HOME="$SBOX" node "$AGGR"
}

run_append() {
  HOME="$SBOX" node "$APPEND" "$1" >/dev/null 2>&1 || true
}

# ── T-AG-S01: helper exists ──────────────────────────────────────────────────
echo ""
echo "  [T-AG-S01] aggregator file present"

assert_status 0 "incident-aggregate.mjs exists" \
  test -f "$AGGR"

# ── T-AG-S02: NO_INCIDENTS when log absent ──────────────────────────────────
echo ""
echo "  [T-AG-S02] missing log → status NO_INCIDENTS"

OUT="$(run_aggr)"
assert_status 0 "status NO_INCIDENTS reported" \
  bash -c "echo '$OUT' | grep -q '\"status\": \"NO_INCIDENTS\"'"

# ── T-AG-S03: DISABLED short-circuit ─────────────────────────────────────────
echo ""
echo "  [T-AG-S03] AI_INCIDENT_TRACKER_DISABLE=1 → status DISABLED"

OUT="$(HOME="$SBOX" AI_INCIDENT_TRACKER_DISABLE=1 node "$AGGR")"
assert_status 0 "status DISABLED reported" \
  bash -c "echo '$OUT' | grep -q '\"status\": \"DISABLED\"'"

# ── T-AG-S04: OK when below threshold ────────────────────────────────────────
echo ""
echo "  [T-AG-S04] count < threshold → status OK"

run_append '{"incident_type":"X","message":"first","stack_signature":"foo:1"}'
run_append '{"incident_type":"X","message":"second","stack_signature":"foo:1"}'
OUT="$(run_aggr)"
assert_status 0 "status OK when distinct sig has count=2" \
  bash -c "echo '$OUT' | grep -q '\"status\": \"OK\"'"
assert_status 0 "total_incidents reflects appended rows" \
  bash -c "echo '$OUT' | grep -q '\"total_incidents\": 2'"

# ── T-AG-S05: THRESHOLD_REACHED at 3 occurrences ────────────────────────────
echo ""
echo "  [T-AG-S05] count >= threshold trips THRESHOLD_REACHED"

run_append '{"incident_type":"X","message":"third","stack_signature":"foo:1"}'
OUT="$(run_aggr)"
assert_status 0 "status THRESHOLD_REACHED at count=3" \
  bash -c "echo '$OUT' | grep -q '\"status\": \"THRESHOLD_REACHED\"'"
assert_status 0 "stack_signature foo:1 listed in groups" \
  bash -c "echo '$OUT' | grep -q '\"stack_signature\": \"foo:1\"'"
assert_status 0 "threshold_reached: true on the offending group" \
  bash -c "echo '$OUT' | grep -q '\"threshold_reached\": true'"

# ── T-AG-S06: distinct signatures grouped independently ─────────────────────
echo ""
echo "  [T-AG-S06] distinct signatures counted independently"

run_append '{"incident_type":"Y","message":"alt","stack_signature":"bar:42"}'
OUT="$(run_aggr)"
assert_status 0 "two distinct signatures reported" \
  bash -c "echo '$OUT' | grep -q '\"distinct_signatures\": 2'"
assert_status 0 "bar:42 still below threshold" \
  bash -c "echo '$OUT' | python3 -c \"import json,sys; d=json.load(sys.stdin); print([g for g in d['groups'] if g['stack_signature']=='bar:42'][0]['threshold_reached'])\" | grep -qx False"

# ── T-AG-S07: malformed lines skipped ────────────────────────────────────────
echo ""
echo "  [T-AG-S07] malformed NDJSON lines are skipped, not fatal"

echo "{not-json" >> "$SBOX/.ai-os/incidents.ndjson"
echo ""        >> "$SBOX/.ai-os/incidents.ndjson"
OUT="$(run_aggr)"
assert_status 0 "aggregator still returns valid JSON" \
  bash -c "echo '$OUT' | python3 -c 'import json,sys; json.loads(sys.stdin.read())'"

# ── T-AG-S08: budget — under 200ms even with 100 records ────────────────────
echo ""
echo "  [T-AG-S08] aggregator stays inside reasonable budget on a populated log"

# Seed 100 fresh records into a clean sandbox so the timing is meaningful.
SBOX2="$(mktemp -d -t aggr-bench-XXXXXX)"
for i in $(seq 1 100); do
  HOME="$SBOX2" node "$APPEND" \
    "{\"incident_type\":\"X\",\"message\":\"m${i}\",\"stack_signature\":\"sig:${i}\"}" >/dev/null 2>&1
done
START_NS=$(python3 -c 'import time; print(time.time_ns())')
HOME="$SBOX2" node "$AGGR" >/dev/null
END_NS=$(python3 -c 'import time; print(time.time_ns())')
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
echo "  ⓘ aggregator on 100-record log: ${ELAPSED_MS}ms (budget 200ms)"
assert_status 0 "aggregator under 200ms" \
  bash -c "[[ '$ELAPSED_MS' -lt 200 ]]"
rm -rf "$SBOX2"

# ── T-AG-S09: ai-preflight SKILL.md wires the aggregator (E-67) ─────────────
echo ""
echo "  [T-AG-S09] ai-preflight skill consumes the aggregator"

assert_status 0 "skill names incident-aggregate.mjs in locator chain" \
  grep -q 'incident-aggregate.mjs' "$SKILL"

assert_status 0 "skill names ${HOME}/.ai-os/shared mirror" \
  grep -q 'shared/incident-aggregate.mjs' "$SKILL"

assert_status 0 "skill emits [INCIDENT_THRESHOLD_REACHED] context block" \
  grep -q '\[INCIDENT_THRESHOLD_REACHED\]' "$SKILL"

assert_status 0 "skill adds Bash to allowed-tools (needed for node invocation)" \
  grep -qE '^allowed-tools:.*Bash' "$SKILL"

assert_status 0 "skill defers blueprint drafting to Architect (anti-drift §35)" \
  grep -qE 'Architect|Gemini' "$SKILL"

assert_status 0 "skill documents AI_INCIDENT_TRACKER_DISABLE rollback" \
  grep -q 'AI_INCIDENT_TRACKER_DISABLE' "$SKILL"

# ── T-AG-S10: ~/.ai-os mirrors byte-identical ───────────────────────────────
echo ""
echo "  [T-AG-S10] ~/.ai-os/ mirrors track src/ verbatim"

if [[ -f "$SKILL_MIRROR" ]]; then
  assert_status 0 "ai-preflight skill mirror identical" \
    cmp -s "$SKILL" "$SKILL_MIRROR"
fi
if [[ -f "$AGGR_MIRROR" ]]; then
  assert_status 0 "incident-aggregate.mjs mirror identical" \
    cmp -s "$AGGR" "$AGGR_MIRROR"
fi

assert_summary
