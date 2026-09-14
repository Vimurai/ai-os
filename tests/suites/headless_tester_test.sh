#!/usr/bin/env bash
# headless_tester_test.sh — E-255 (D-069, claude-native-consolidation.md §Components 3):
# the Tester is a headless Claude role. Pins the roles.json template and writer, that
# `ai start` / `ai pane` / the settings overlays ignore a headless role, the derived
# labels for all three roles, the ai-test command detection and --fast model selection,
# and that TestSprite has left the registry, the MCP domains and the generated .mcp.json.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
ADAPTER="${REPO_ROOT}/src/shared/provider-adapter.mjs"
TESTCMD="${REPO_ROOT}/src/shared/test-command.mjs"
export AIOS="${HOME}/.ai-os"

echo "── Suite: headless_tester_test (E-255) ──────────────────────────────"

SBOX="$(mktemp -d -t headless-tester-XXXXXX)"
register_cleanup "rm -rf '$SBOX'"

# _proj <name> <roles-json> → project dir with .ai/roles.json
_proj() {
  local d="${SBOX}/$1"; mkdir -p "$d/.ai"
  printf '%s' "$2" > "$d/.ai/roles.json"
  printf '%s' "$d"
}
V4_ROLES='{ "roles": {
  "architect": { "provider": "claude", "pane_identifier": "1", "model": "fable" },
  "engineer":  { "provider": "claude", "pane_identifier": "0", "model": "opus" },
  "tester":    { "provider": "claude", "model": "sonnet", "headless": true } } }'

# ── E-255.1: the template and the writer carry the headless tester ──────────
echo "  [E-255.1] roles.json template + _write_roles_json"
_t="$(node -e "const r=require('${REPO_ROOT}/src/templates/roles.json').roles.tester||{}; process.stdout.write([r.provider,r.model,r.headless,r.pane_identifier===undefined].join(','))")"
assert_contains "E-255.01a: template tester = claude · sonnet, headless, no pane" "claude,sonnet,true,true" "$_t"

_w="${SBOX}/writer"; mkdir -p "$_w/.ai"
( cd "$_w" && bash -c "source '$AI'; _write_roles_json" >/dev/null )
_t="$(node -e "const r=require('${_w}/.ai/roles.json').roles; process.stdout.write([r.architect.provider,r.engineer.provider,r.tester.provider,r.tester.model,r.tester.headless].join(','))")"
assert_contains "E-255.01b: _write_roles_json emits the headless tester beside both panes" "claude,claude,claude,sonnet,true" "$_t"

# ── E-255.2: ai start ignores headless roles ────────────────────────────────
echo "  [E-255.2] ai start / _start_roles"
# _start_roles is defined past bin/ai's source guard (E-53), so drive it through the
# dry run — the same path an operator's `ai start` takes.
_p="$(_proj start "$V4_ROLES")"
_out="$(cd "$_p" && bash "$AI" start --dry-run 2>&1)"
assert_match "E-255.02a: dry run binds the engineer to the first pane" 'send-keys -t pane0 ai.\ pane.\ engineer' "$_out"
assert_match "E-255.02b: …and the architect to the second" 'send-keys -t pane1 ai.\ pane.\ architect' "$_out"
assert_match "E-255.02c: the watcher still takes the third pane (tester occupies none)" 'send-keys -t pane2 ai.\ watch' "$_out"
assert_not_contains "E-255.02d: the tester is never sent 'ai pane'" 'pane\ tester' "$_out"

# Non-vacuity: the headless FLAG is what excludes a role, not the name "tester". An
# architect marked headless disappears from the layout too.
_p2="$(_proj start-headless-arch '{ "roles": {
  "architect": { "provider": "claude", "pane_identifier": "1", "headless": true },
  "engineer":  { "provider": "claude", "pane_identifier": "0" } } }')"
_out2="$(cd "$_p2" && bash "$AI" start --dry-run 2>&1)"
assert_match "E-255.02e: headless:true — the engineer is still bound" 'ai.\ pane.\ engineer' "$_out2"
assert_not_contains "E-255.02f: headless:true removes any role from the layout, the architect included" 'pane\ architect' "$_out2"

# ── E-255.3: ai pane tester refuses with the pointer to ai-test ─────────────
echo "  [E-255.3] ai pane tester"
assert_status 2 "E-255.03a: ai pane tester exits 2" bash -c "cd '$_p' && bash '$AI' pane tester 2>/dev/null"
assert_contains "E-255.03b: the message says headless and names skill: ai-test" \
  "tester is headless; run skill: ai-test" "$(cd "$_p" && bash "$AI" pane tester 2>&1)"

# ── E-255.4: no settings overlay for a headless role ────────────────────────
echo "  [E-255.4] settings overlays"
_ov="$(_proj overlay "$V4_ROLES")"; mkdir -p "$_ov/.claude"
( cd "$_ov" && bash -c "source '$AI'; _write_role_settings_overlays .claude .ai" >/dev/null 2>&1 )
assert_exists "${_ov}/.claude/settings.engineer.json"
assert_exists "${_ov}/.claude/settings.architect.json"
assert_status 1 "E-255.04a: no settings.tester.json is written" test -e "${_ov}/.claude/settings.tester.json"

# ── E-255.5: labels are derived for all three roles ─────────────────────────
echo "  [E-255.5] derived labels"
_lab() {
  AI_OS_MOD="file://${ADAPTER}" node --input-type=module -e '
const m = await import(process.env.AI_OS_MOD);
const d = process.argv[1];
process.stdout.write(["architect","engineer","tester"].map(r => m.roleLabel(d, r)).join("|") + "|" +
  ["architect","engineer","tester"].map(r => m.isHeadless(d, r)).join(","));
' "$1"
}
assert_contains "E-255.05a: v4 roles → claude · fable / opus / sonnet, only tester headless" \
  "Architect (claude · fable)|Engineer (claude · opus)|Tester (claude · sonnet)|false,false,true" "$(_lab "$_p/.ai")"
_cust="$(_proj custom '{ "roles": { "tester": { "provider": "claude", "model": "opus", "headless": false } } }')"
assert_contains "E-255.05b: a re-bound tester model changes the label (never a literal)" \
  "Tester (claude · opus)" "$(_lab "$_cust/.ai")"
assert_contains "E-255.05c: explicit headless:false wins over the default" "false,false,false" "$(_lab "$_cust/.ai")"
assert_contains "E-255.05d: no roles.json falls back to the defaults" \
  "Tester (claude · sonnet)|false,false,true" "$(_lab "${SBOX}/nonexistent/.ai")"

_bl="$(cd "$_cust" && bash -c "source '$AI'; _roles_banner_labels")"
assert_contains "E-255.05e: banner labels carry three fields, tester from roles.json" "claude·fable|claude·opus|claude·opus" "$_bl"
assert_status 1 "E-255.05f: the init banner no longer hard-codes a Tester vendor" \
  grep -qE "Tester +%-18s.*\"\\((TestSprite|[A-Za-z]+)\\)\"" "$AI"

# ── E-255.6: ai-test resolves the real test command ─────────────────────────
echo "  [E-255.6] test-command detection"
_tc() { node "$TESTCMD" "$@" 2>/dev/null; }
_d="${SBOX}/npm"; mkdir -p "$_d/tests"; echo '{"scripts":{"test":"vitest run"}}' > "$_d/package.json"; : > "$_d/tests/run.sh"
assert_contains "E-255.06a: package.json test wins over tests/run.sh" '"command":"npm test","source":"package.json"' "$(_tc "$_d")"
_d="${SBOX}/placeholder"; mkdir -p "$_d/tests"; : > "$_d/tests/run.sh"
echo '{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}' > "$_d/package.json"
assert_contains "E-255.06b: the npm init placeholder is skipped → tests/run.sh" '"command":"bash tests/run.sh"' "$(_tc "$_d")"
_d="${SBOX}/py"; mkdir -p "$_d"; printf '[tool.pytest.ini_options]\n' > "$_d/pyproject.toml"
assert_contains "E-255.06c: pyproject [tool.pytest] → pytest" '"command":"pytest"' "$(_tc "$_d")"
_d="${SBOX}/pytests"; mkdir -p "$_d/tests"; : > "$_d/tests/test_app.py"
assert_contains "E-255.06d: tests/test_*.py → pytest" '"command":"pytest"' "$(_tc "$_d")"
_d="${SBOX}/go"; mkdir -p "$_d"; echo 'module x' > "$_d/go.mod"
assert_contains "E-255.06e: go.mod → go test ./..." '"command":"go test ./..."' "$(_tc "$_d")"
_d="${SBOX}/none"; mkdir -p "$_d"; printf '[tool.black]\n' > "$_d/pyproject.toml"
assert_status 3 "E-255.06f: no test command → exit 3, never a guess" node "$TESTCMD" "$_d"
assert_contains "E-255.06g: …and command is null" '"command":null' "$(_tc "$_d")"
assert_contains "E-255.06h: this repository resolves to its own harness" '"command":"npm test"' "$(_tc "$REPO_ROOT")"

# ── E-255.7: model selection — sonnet by default, haiku under --fast ────────
echo "  [E-255.7] tester model"
_d="${SBOX}/npm"
assert_contains "E-255.07a: default Tester model is sonnet" '"model":"sonnet"' "$(_tc "$_d")"
assert_contains "E-255.07b: --fast runs the Tester on haiku" '"model":"haiku"' "$(_tc --fast "$_d")"
mkdir -p "$_d/.ai"; echo '{ "roles": { "tester": { "provider": "claude", "model": "opus", "headless": true } } }' > "$_d/.ai/roles.json"
assert_contains "E-255.07c: roles.json tester model is honoured" '"model":"opus"' "$(_tc "$_d")"
assert_contains "E-255.07d: --fast still wins over roles.json" '"model":"haiku"' "$(_tc --fast "$_d")"

# ── E-255.8: the agent and the skill ────────────────────────────────────────
echo "  [E-255.8] test_engineer agent + ai-test skill"
AGENT="${REPO_ROOT}/src/claude/agents/test_engineer.md"
SKILL="${REPO_ROOT}/src/shared/skills/ai-test/SKILL.md"
assert_exists "$AGENT"
assert_status 0 "E-255.08a: test_engineer frontmatter pins model: sonnet" \
  bash -c "sed -n '1,/^---\$/{/^---\$/!p;}' '$AGENT' | sed -n '1,12p' | grep -qx 'model: sonnet'"
assert_status 0 "E-255.08b: test_engineer stamps through add_stamp, and only that MCP tool" \
  bash -c "grep -E '^allowed-tools:' '$AGENT' | grep -q 'mcp__task-synchronizer-mcp__add_stamp' && [ \"\$(grep -E '^allowed-tools:' '$AGENT' | grep -oE 'mcp__[a-z-]+__[a-z_]+' | wc -l | tr -d ' ')\" = 1 ]"
assert_status 0 "E-255.08c: test_engineer writes only under tests/" grep -q 'Write ONLY under `tests/`' "$AGENT"
for _flag in -- --generate --fast --vibe; do
  [[ "$_flag" == "--" ]] && continue
  assert_status 0 "E-255.08d: ai-test documents ${_flag}" grep -q -- "## ${_flag}\|(${_flag} flag)" "$SKILL"
done
assert_status 0 "E-255.08e: ai-test resolves the command through test-command.mjs" grep -q 'shared/test-command.mjs' "$SKILL"
assert_mirror_if_present "E-255.08f: .claude/agents/test_engineer.md mirrors src" "$AGENT" "${REPO_ROOT}/.claude/agents/test_engineer.md"

# ── E-255.9: TestSprite is gone from every generated surface ────────────────
echo "  [E-255.9] third-party test cloud removed"
_ts='test''sprite'   # split so this suite does not trip the repo-wide grep acceptance
assert_status 1 "E-255.09a: registry.json has no ${_ts} server" grep -qi "$_ts" "${REPO_ROOT}/src/config/registry.json"
assert_status 0 "E-255.09b: the Quality domain lists only real local servers" \
  node --input-type=module -e "
const m = await import('file://${REPO_ROOT}/src/mcp/shared/mcp-domains.mjs');
const all = Object.values(m.DOMAINS ?? m.default ?? {}).flatMap(d => d.servers ?? []);
process.exit(all.length > 0 && !all.some(s => /${_ts}/i.test(s)) ? 0 : 1);"
_mcp="${SBOX}/mcp"; mkdir -p "$_mcp"
( cd "$_mcp" && bash -c "source '$AI'; DEST_DIR='$_mcp'; generate_mcp_json" >/dev/null 2>&1 )
if [[ -f "${_mcp}/.mcp.json" ]]; then
  assert_status 1 "E-255.09c: a generated .mcp.json carries no ${_ts} entry" grep -qi "$_ts" "${_mcp}/.mcp.json"
  assert_status 0 "E-255.09d: …but still carries the filesystem server (non-vacuous)" grep -q '"filesystem"' "${_mcp}/.mcp.json"
else
  assert_status 0 "E-255.09c: generate_mcp_json produced a file" test -f "${_mcp}/.mcp.json"
fi

assert_summary
