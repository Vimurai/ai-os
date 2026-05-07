#!/usr/bin/env bash
# managed_agents_spike_test.sh — Tests for E-47 architectural spike.
#
# Runs tests/managed_agents_spike.js and asserts the JSON report carries the
# fields the blueprint mandates and that the verdict is one of the documented
# outcomes (PROCEED / INCONCLUSIVE / ABANDON).
#
# The spike must not make any network calls — we keep the test offline.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPIKE="${REPO_ROOT}/tests/managed_agents_spike.js"

echo "===== managed_agents_spike_test.sh ====="

# ── T-MGR-S01: File presence + shebang ────────────────────────────────────────
echo ""
echo "  [T-MGR-S01] Spike file structure"

assert_status 0 "spike script exists"     test -f "$SPIKE"
assert_status 0 "spike has node shebang"  bash -c "head -1 '$SPIKE' | grep -q 'node'"

# ── T-MGR-S02: Spike produces valid JSON report ──────────────────────────────
echo ""
echo "  [T-MGR-S02] Spike runs and emits JSON"

# Disable the harmless ES-module reparse warning so test output stays clean.
SPIKE_OUT="$(NODE_OPTIONS=--no-warnings node "$SPIKE" 2>/dev/null)"
SPIKE_EXIT=$?

assert_status 0 "spike exited 0 (PROCEED|INCONCLUSIVE)" \
  bash -c "[[ $SPIKE_EXIT -eq 0 ]]"

# Capture parsed verdict for downstream assertions.
VERDICT="$(printf '%s' "$SPIKE_OUT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])')"
assert_status 0 "verdict is one of PROCEED/INCONCLUSIVE/ABANDON" \
  bash -c "[[ '$VERDICT' == 'PROCEED' || '$VERDICT' == 'INCONCLUSIVE' || '$VERDICT' == 'ABANDON' ]]"

# ── T-MGR-S03: Required fields in the report ─────────────────────────────────
echo ""
echo "  [T-MGR-S03] Required report fields"

REPORT_FILE="$(mktemp -t spike-XXXXXX.json)"
printf '%s' "$SPIKE_OUT" > "$REPORT_FILE"
trap 'rm -f "$REPORT_FILE"' EXIT

for field in spike_version api_version generated_at contract state projection redactions structural_issues webhook_plan verdict rationale; do
  assert_status 0 "report.$field present" \
    python3 -c "
import json,sys
data = json.load(open('$REPORT_FILE'))
sys.exit(0 if '$field' in data else 1)
"
done

# ── T-MGR-S04: API contract version is 2026-04-01 ────────────────────────────
echo ""
echo "  [T-MGR-S04] API version pin"

assert_status 0 "api_version = managed-agents-2026-04-01" \
  python3 -c "
import json
d = json.load(open('$REPORT_FILE'))
exit(0 if d.get('api_version') == 'managed-agents-2026-04-01' else 1)
"

# ── T-MGR-S05: Webhook plan covers all lifecycle events ──────────────────────
echo ""
echo "  [T-MGR-S05] Webhook lifecycle coverage"

assert_status 0 "every contract.endpoints.lifecycle event has a webhook_plan entry" \
  python3 -c "
import json
d = json.load(open('$REPORT_FILE'))
events = d['contract']['endpoints']['lifecycle']
plan   = d['webhook_plan']
missing = [e for e in events if e not in plan]
exit(0 if not missing else 1)
"

# ── T-MGR-S06: Sanitisation gate is wired ────────────────────────────────────
echo ""
echo "  [T-MGR-S06] Sanitisation gate exists"

# We only assert the gate exists and is exercised — we don't assert that any
# fields were redacted, since a clean state.json should have none.
assert_status 0 "redactions field is an array" \
  python3 -c "
import json
d = json.load(open('$REPORT_FILE'))
exit(0 if isinstance(d.get('redactions'), list) else 1)
"

# Source-grep: confirm the spike has the sanitiser. No protocol surface to test.
assert_status 0 "spike defines SENSITIVE_KEY_RE" grep -q 'SENSITIVE_KEY_RE' "$SPIKE"
assert_status 0 "spike defines SENSITIVE_PATH_RE" grep -q 'SENSITIVE_PATH_RE' "$SPIKE"
assert_status 0 "spike calls sanitise()" grep -q 'sanitise(' "$SPIKE"

# ── T-MGR-S07: Spike makes no network calls (security mandate) ───────────────
echo ""
echo "  [T-MGR-S07] No network surface"

# Static check: no fetch / http / https / undici / axios imports.
assert_status 1 "no fetch() call"   grep -qE '\bfetch\(' "$SPIKE"
assert_status 1 "no http import"    grep -qE 'from ["\x27]node:https?["\x27]|require\(["\x27]https?["\x27]\)' "$SPIKE"
# Match only real import / require statements — not bare mentions inside comments.
assert_status 1 "no SDK import"     grep -qE '^[[:space:]]*(import .* from|const .* = require\()[^"]*["\x27](?:@anthropic-ai/sdk|undici|axios)' "$SPIKE"

# ── T-MGR-S08: Sanitiser actually redacts sensitive keys ─────────────────────
echo ""
echo "  [T-MGR-S08] Sanitiser unit check"

# Build a synthetic state file with a sensitive field, run the spike against
# it in a sandbox, and confirm the field is reported as redacted.
SANDBOX="$(mktemp -d -t mgrspike-XXXXXX)"
trap 'rm -rf "$SANDBOX"; rm -f "$REPORT_FILE"' EXIT
mkdir -p "${SANDBOX}/.ai"
cat > "${SANDBOX}/.ai/state.json" <<'JSON'
{
  "project": { "focus": null, "api_key": "sk-should-be-redacted" },
  "tasks": [],
  "stamps": [],
  "deltas": []
}
JSON

SANDBOX_OUT="$(cd "$SANDBOX" && NODE_OPTIONS=--no-warnings node "$SPIKE" 2>/dev/null)"
assert_status 0 "redactions captured the sensitive api_key" \
  bash -c "
printf '%s' \"\$1\" | python3 -c '
import json,sys
d = json.load(sys.stdin)
red = d.get(\"redactions\", [])
sys.exit(0 if any(\"api_key\" in r for r in red) else 1)
'
" _ "$SANDBOX_OUT"

assert_summary
