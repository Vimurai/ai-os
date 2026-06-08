#!/usr/bin/env bash
# role_header_view_test.sh — E-136 provider-agnostic TASKS.md section headers
# (role-abstraction.md). roleFromOwner() strips the "(Provider)" suffix so a CLI
# swap never churns headers; "Engineer (Claude)" and bare "Engineer" merge into a
# single "## Engineer" section. state.json retains the full owner string.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
STATE_DB="${REPO_ROOT}/src/mcp/shared/state-db.js"

echo "── Suite: role_header_view_test (E-136) ────────────────────────────"

# ── E-136.10: roleFromOwner strips the provider suffix (pure unit) ───────────
roles=$(node --input-type=module -e "import {roleFromOwner} from 'file://${STATE_DB}'; process.stdout.write([roleFromOwner('Engineer (Claude)'),roleFromOwner('Architect (Gemini)'),roleFromOwner('Engineer'),roleFromOwner('Tester (TestSprite)'),roleFromOwner('')].join('|'))")
assert_contains "E-136.10a: 'Engineer (Claude)' -> Engineer" "Engineer|" "$roles"
assert_contains "E-136.10b: 'Architect (Gemini)' -> Architect" "|Architect|" "$roles"
assert_contains "E-136.10c: bare 'Engineer' -> Engineer" "|Engineer|" "$roles"
assert_contains "E-136.10d: 'Tester (TestSprite)' -> Tester" "|Tester|" "$roles"
assert_contains "E-136.10e: '' -> Unassigned" "|Unassigned" "$roles"

# ── E-136.11: regenerated TASKS.md uses provider-agnostic headers ────────────
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJECT="${TMP}/proj"; mkdir -p "${PROJECT}/.ai"
cat > "${PROJECT}/.ai/state.json" <<'JSON'
{
  "version": "1.0",
  "project": {},
  "tasks": [
    { "id": "E-1", "owner": "Engineer (Claude)", "status": "OPEN", "description": "legacy-owner task", "tier": 1, "created_at": "2026-06-01T00:00:00Z" },
    { "id": "E-2", "owner": "Engineer", "status": "OPEN", "description": "agnostic-owner task", "tier": 2, "created_at": "2026-06-01T00:00:00Z" },
    { "id": "P-1", "owner": "Architect (Gemini)", "status": "OPEN", "description": "architect task", "tier": 1, "created_at": "2026-06-01T00:00:00Z" }
  ],
  "stamps": [],
  "deltas": []
}
JSON
cd "${PROJECT}"
# A state mutation migrates state.json -> state.sqlite and regenerates TASKS.md.
mcp_call_tool "${SERVER}" add_task '{"prefix":"E","owner":"Engineer (Claude)","description":"regen trigger","tier":3}' >/dev/null
TASKS="${PROJECT}/.ai/TASKS.md"
assert_status 0 "E-136.11: TASKS.md regenerated" test -f "$TASKS"
tasks_md="$(cat "$TASKS")"
assert_contains  "E-136.11a: provider-agnostic '## Engineer' header"  "## Engineer" "$tasks_md"
assert_contains  "E-136.11b: provider-agnostic '## Architect' header" "## Architect" "$tasks_md"
assert_not_contains "E-136.11c: no '## Engineer (Claude)' header"  "## Engineer (Claude)"  "$tasks_md"
assert_not_contains "E-136.11d: no '## Architect (Gemini)' header" "## Architect (Gemini)" "$tasks_md"
# "Engineer (Claude)" + bare "Engineer" must MERGE into exactly one section.
eng_headers="$(grep -c '^## Engineer$' "$TASKS" || true)"
assert_contains "E-136.11e: exactly one '## Engineer' section (merged)" "1" "$eng_headers"
# state.json still stores the full owner string (backwards compat).
assert_status 0 "E-136.11f: state.json retains full owner 'Engineer (Claude)'" \
  grep -q '"owner": "Engineer (Claude)"' "${PROJECT}/.ai/state.json"

cd "${REPO_ROOT}"
assert_summary
