#!/usr/bin/env bash
# role_identity_test.sh — E-213 (architect-provider-parity.md §Components 3-4):
# the Architect settings overlay and role-correct identity labels.
#
# "Architect (Agy)" was hardcoded, so an all-Claude Triad (D-054) attributed every
# Architect-created task to a provider that is not even running, and the Stop hook
# stamped a bare "Claude" — which stopped identifying anything once BOTH panes are
# Claude. Both halves now resolve the provider from .ai/roles.json.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
STOP_HOOK="${REPO_ROOT}/hooks/stop-hook.sh"
ADD_TASK="${REPO_ROOT}/src/shared/cli-add-task.mjs"
SAFE_EXEC="${REPO_ROOT}/src/mcp/safe-exec-mcp/index.js"

echo "── Suite: role_identity_test (E-213) ────────────────────────────────"

# ── E-213.1: owner labels carry the bound provider ─────────────────────────
_owner() {  # <role> <aiDir> → owner label
  AI_OS_R="$1" AI_OS_D="$2" node --input-type=module -e '
const m = await import(process.env.AI_OS_MOD);
process.stdout.write(m.resolveOwner({ role: process.env.AI_OS_R, aiDir: process.env.AI_OS_D }));
' 2>/dev/null
}
export AI_OS_MOD="file://${ADD_TASK}"

_DUAL="$(mktemp -d)"
cat > "$_DUAL/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "claude", "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON
_SPLIT="$(mktemp -d)"
cat > "$_SPLIT/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "agy",    "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON

assert_contains "E-213.01a: dual-claude architect is attributed to Claude, not Agy" \
  "Architect (Claude)" "$(_owner architect "$_DUAL")"
assert_contains "E-213.01b: dual-claude engineer label unchanged" \
  "Engineer (Claude)" "$(_owner engineer "$_DUAL")"
assert_contains "E-213.01c: a split Triad still attributes the Architect to Agy" \
  "Architect (Agy)" "$(_owner architect "$_SPLIT")"
# Fail-soft: an attribution label must never break task creation.
assert_contains "E-213.01d: a missing roles.json falls back to the D-050 default" \
  "Architect (Agy)" "$(_owner architect "/nonexistent-dir")"

# roleFromOwner splits on " (", so the generated TASKS.md headers must NOT churn
# when the provider half changes — that is what makes this change safe.
_ROLEOF="$(node --input-type=module -e '
const m = await import("file://'"${REPO_ROOT}"'/src/mcp/shared/state-db.js");
process.stdout.write([m.roleFromOwner("Architect (Claude)"), m.roleFromOwner("Architect (Agy)"), m.roleFromOwner("Engineer (Claude)")].join(","));
' 2>/dev/null)"
assert_contains "E-213.01e: section headers are provider-agnostic (no churn)" \
  "Architect,Architect,Engineer" "$_ROLEOF"

# An explicit --owner still wins over any role mapping.
assert_contains "E-213.01f: explicit --owner still wins" "QA (TestSprite)" \
  "$(AI_OS_MOD="file://${ADD_TASK}" node --input-type=module -e '
const m = await import(process.env.AI_OS_MOD);
process.stdout.write(m.resolveOwner({ owner: "QA (TestSprite)", role: "architect" }));
' 2>/dev/null)"

# ── E-213.2: the Architect overlay carries its allow rules ─────────────────
_OV="$(mktemp -d)/.claude"; mkdir -p "$_OV"
bash -c "source '$AI_BIN' 2>/dev/null; _write_role_settings_overlays '$_OV' '$_DUAL'" >/dev/null 2>&1
_ARCH_OV="$(cat "$_OV/settings.architect.json" 2>/dev/null)"
_ENG_OV="$(cat "$_OV/settings.engineer.json" 2>/dev/null)"

for _rule in "Bash(ai add-task *)" "Bash(ai handoff *)" \
             "mcp__task-synchronizer-mcp__handoff_control" \
             "mcp__task-synchronizer-mcp__add_topic_seed" \
             "mcp__task-synchronizer-mcp__add_cluster_page" \
             "mcp__context-guardian-mcp__check_role_access"; do
  assert_contains "E-213.02 [$_rule]: present in the architect overlay" "$_rule" "$_ARCH_OV"
done
# The Engineer overlay must stay env-only — these are Architect-side tools.
assert_not_contains "E-213.02g: the engineer overlay gains no permissions block" \
  "permissions" "$_ENG_OV"
# Still no hooks — the E-208 double-mint guard must survive this change.
assert_not_contains "E-213.02h: the architect overlay still registers NO hooks" \
  '"hooks"' "$_ARCH_OV"
# Deny rules are NOT the sovereignty mechanism (blueprint §Components 3) — the
# pre-tool-use hook and the Git Lane are. Assert we did not quietly add one.
assert_not_contains "E-213.02i: the overlay uses allow rules only, no deny list" \
  '"deny"' "$_ARCH_OV"

# ── E-213.3: the legacy gemini grant is gone from the base settings ────────
assert_status 1 "E-213.03a: the generator no longer ADDS Bash(gemini -p *)" \
  bash -c "grep -q 'new_allow.append(\"Bash(gemini -p \\*)\")' '$AI_BIN'"
assert_status 0 "E-213.03b: the generator PRUNES an existing legacy grant" \
  grep -q 'Removed legacy grant' "$AI_BIN"
# Behavioural: a settings file that already carries the rule loses it on sync.
_LEG="$(mktemp -d)/.claude"; mkdir -p "$_LEG"
printf '{"permissions":{"allow":["Bash(gemini -p *)","mcp__keep-me__tool"]}}' > "$_LEG/settings.json"
bash -c "source '$AI_BIN' 2>/dev/null; AIOS=\"\$HOME/.ai-os\"; _configure_project_claude_settings '$_LEG'" >/dev/null 2>&1
assert_not_contains "E-213.03c: sync removes the legacy grant from an existing file" \
  "gemini -p" "$(cat "$_LEG/settings.json")"
assert_contains "E-213.03d: unrelated allow rules survive the prune" \
  "mcp__keep-me__tool" "$(cat "$_LEG/settings.json")"

# ── E-213.4: the Stop hook stamps provider AND role ───────────────────────
assert_status 0 "E-213.04a: the Actor stamp is no longer the literal 'Claude'" \
  bash -c "! grep -qE '^- Actor: Claude\$' '$STOP_HOOK'"
assert_status 0 "E-213.04b: the Actor stamp is interpolated" \
  grep -qE '^- Actor: \$\{ACTOR\}$' "$STOP_HOOK"
assert_status 0 "E-213.04c: the role comes from the launch-time pane role" \
  grep -q 'AI_OS_PANE_ROLE:-' "$STOP_HOOK"
assert_status 0 "E-213.04d: an unknown role falls back rather than being stamped" \
  grep -q 'architect|engineer) ;;' "$STOP_HOOK"

# ── E-213.5: ACCEPTANCE — MCP spawn identity parity with agy ───────────────
# The point of the whole task: a server spawned by the Architect pane must SEE
# caller_role=architect, so the Architect sovereignty rules actually apply to it.
_analyze() {  # <role> <command> → the analysis report
  ( cd "$REPO_ROOT"
    source tests/lib/mcp-client.sh
    AI_OS_CALLER_ROLE="$1" mcp_call_tool "$SAFE_EXEC" analyze_command "{\"command\":\"$2\"}"
  ) 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["content"][0]["text"])' 2>/dev/null
}
_ARCH_REPORT="$(_analyze architect "git push origin master")"
assert_contains "E-213.05a: an architect-spawned server applies Architect rules" \
  "ARCH_GIT_PUSH" "$_ARCH_REPORT"
assert_contains "E-213.05b: and blocks the forbidden operation" "BLOCK" "$_ARCH_REPORT"
_ENG_REPORT="$(_analyze engineer "git push origin master")"
assert_not_contains "E-213.05c: an engineer-spawned server applies NO Architect rules" \
  "ARCH_" "$_ENG_REPORT"
assert_contains "E-213.05d: and the Engineer may push" "PASS" "$_ENG_REPORT"

assert_summary
