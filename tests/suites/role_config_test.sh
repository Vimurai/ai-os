#!/usr/bin/env bash
# role_config_test.sh — E-135 Role Configuration Store (.ai/roles.json) + install flags
# (role-abstraction.md §Components 1, §Data Model). Sources src/bin/ai (guarded at the
# dispatch, E-53) to exercise _parse_role_flags / _write_roles_json directly, and
# validates the template default mapping.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
TEMPLATE="${REPO_ROOT}/src/templates/roles.json"
export AIOS="${HOME}/.ai-os"

echo "── Suite: role_config_test (E-135) ─────────────────────────────────"

# T-1: template exists + is valid JSON with the documented schema
assert_exists "$TEMPLATE"
assert_status 0 "T-1: roles.json template is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('${TEMPLATE}','utf8'))"
tmpl=$(node -e "const r=require('${TEMPLATE}').roles; process.stdout.write([r.architect.provider,r.architect.pane_identifier,r.engineer.provider,r.engineer.pane_identifier].join(','))")
assert_contains "T-1b: template defaults architect=agy:1 engineer=claude:0 (D-050/E-183)" "agy,1,claude,0" "$tmpl"

# T-2: _parse_role_flags accepts valid <provider:pane> flags
assert_status 0 "T-2: parses --architect claude:1 --engineer gemini:0" \
  bash -c "source '$AI_BIN'; _parse_role_flags --architect claude:1 --engineer gemini:0; [[ \"\$ROLE_ARCHITECT\" == claude:1 && \"\$ROLE_ENGINEER\" == gemini:0 ]]"

# T-3: malformed role values abort with exit 2 (fail-closed)
assert_status 2 "T-3a: rejects missing pane (no colon)" \
  bash -c "source '$AI_BIN'; _parse_role_flags --architect badformat"
assert_status 2 "T-3b: rejects non-numeric pane (claude:x)" \
  bash -c "source '$AI_BIN'; _parse_role_flags --engineer claude:x"

# T-4: _write_roles_json honors explicit overrides
tmp_over="$(mktemp -d)"
( cd "$tmp_over" && mkdir -p .ai && bash -c "source '$AI_BIN'; ROLE_ARCHITECT=claude:1; ROLE_ENGINEER=claude:0; _write_roles_json" >/dev/null )
assert_status 0 "T-4: override roles.json is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('${tmp_over}/.ai/roles.json','utf8'))"
over=$(node -e "const r=require('${tmp_over}/.ai/roles.json').roles; process.stdout.write([r.architect.provider,r.architect.pane_identifier,r.engineer.provider,r.engineer.pane_identifier].join(','))")
assert_contains "T-4b: dual-claude override architect=claude:1 engineer=claude:0" "claude,1,claude,0" "$over"

# T-5: _write_roles_json falls back to the default mapping when no flags set (D-050/E-183: agy)
tmp_def="$(mktemp -d)"
( cd "$tmp_def" && mkdir -p .ai && bash -c "source '$AI_BIN'; _write_roles_json" >/dev/null )
def=$(node -e "const r=require('${tmp_def}/.ai/roles.json').roles; process.stdout.write([r.architect.provider,r.architect.pane_identifier,r.engineer.provider,r.engineer.pane_identifier].join(','))")
assert_contains "T-5: default architect=agy:1 engineer=claude:0" "agy,1,claude,0" "$def"

# T-6: _write_roles_json is a silent no-op outside a project (.ai/ absent)
tmp_noai="$(mktemp -d)"
assert_status 0 "T-6: no-op (exit 0) when .ai/ absent" \
  bash -c "cd '$tmp_noai' && source '$AI_BIN'; _write_roles_json"
assert_status 1 "T-6b: no roles.json written without .ai/" test -f "${tmp_noai}/.ai/roles.json"

# T-7: ensure_ai_templates scaffolds .ai/roles.json from the template (idempotent)
assert_status 0 "T-7: ensure_ai_templates wires roles.json scaffold" \
  grep -q 'ensure_file_if_missing "$T/roles.json"' "$AI_BIN"

rm -rf "$tmp_over" "$tmp_def" "$tmp_noai"
assert_summary
