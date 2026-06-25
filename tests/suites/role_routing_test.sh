#!/usr/bin/env bash
# role_routing_test.sh — E-137 ai-watch dynamic role→pane routing via .ai/roles.json
# (role-abstraction.md §Components 4). Sources src/bin/ai-watch (guarded, exposes
# helpers without launching the loop) and drives resolve_pane / _load_roles_mapping /
# _role_to_provider_pane with mocked panes. No tmux required.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH="${REPO_ROOT}/src/bin/ai-watch"

echo "── Suite: role_routing_test (E-137) ────────────────────────────────"

# resolve_pane under a given ROLES_MAPPING + mocked panes (5-field → TIER B ordinal).
_resolve_with() {  # <roles_mapping> <panes(%b)> <target> → pane id
  local rm="$1" panes="$2" tgt="$3"
  ( source "$WATCH" 2>/dev/null
    ROLES_MAPPING="$rm"
    _project_panes() { printf '%b' "$panes"; }
    resolve_pane "$tgt" )
}
_load_map() {  # <project_dir> → serialized mapping
  local pd="$1"
  ( source "$WATCH" 2>/dev/null; PROJECT_DIR="$pd"; _load_roles_mapping )
}
_role_pp() {  # <roles_mapping> <role> → provider:pane
  local rm="$1" role="$2"
  ( source "$WATCH" 2>/dev/null; ROLES_MAPPING="$rm"; _role_to_provider_pane "$role" )
}

# Two distinct-provider panes (claude idx0, gemini idx1).
PANES_AB='%cl\t0\tclaude\twin\t/p\n%ge\t1\tgemini\twin\t/p\n'
# Two SAME-provider panes (claude idx0, claude idx1) — the dual-Claude case.
PANES_CC='%c0\t0\tclaude\twin\t/p\n%c1\t1\tclaude\twin\t/p\n'

# ── E-137.01: legacy fallback (no roles.json) — engineer→claude, architect→gemini ─
assert_contains "E-137.01a: fallback engineer → claude pane (idx0)" "%cl" "$(_resolve_with '' "$PANES_AB" engineer)"
assert_contains "E-137.01b: fallback architect → gemini pane (idx1)" "%ge" "$(_resolve_with '' "$PANES_AB" architect)"

# ── E-137.02: legacy provider-name targets still resolve (backwards compat) ───
assert_contains "E-137.02a: 'claude' → idx0 pane" "%cl" "$(_resolve_with '' "$PANES_AB" claude)"
assert_contains "E-137.02b: 'gemini' → idx1 pane" "%ge" "$(_resolve_with '' "$PANES_AB" gemini)"

# ── E-137.03: dynamic roles.json mapping (default) routes like the fallback ───
MAP_DEFAULT='architect:gemini:1|engineer:claude:0'
assert_contains "E-137.03a: mapped engineer → claude pane" "%cl" "$(_resolve_with "$MAP_DEFAULT" "$PANES_AB" engineer)"
assert_contains "E-137.03b: mapped architect → gemini pane" "%ge" "$(_resolve_with "$MAP_DEFAULT" "$PANES_AB" architect)"

# ── E-137.04: DUAL-CLAUDE — distinct pane indices keep roles separate ─────────
# architect=claude:1, engineer=claude:0 against two claude panes → different panes.
MAP_DUAL='architect:claude:1|engineer:claude:0'
eng_pane="$(_resolve_with "$MAP_DUAL" "$PANES_CC" engineer)"
arch_pane="$(_resolve_with "$MAP_DUAL" "$PANES_CC" architect)"
assert_contains "E-137.04a: engineer (claude:0) → pane idx0 (%c0)" "%c0" "$eng_pane"
assert_contains "E-137.04b: architect (claude:1) → pane idx1 (%c1)" "%c1" "$arch_pane"
assert_status 1 "E-137.04c: dual-Claude roles route to DIFFERENT panes" \
  bash -c "[ '$eng_pane' = '$arch_pane' ]"

# ── E-137.05: _load_roles_mapping parses .ai/roles.json ──────────────────────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "${TMP}/.ai"; cp "${REPO_ROOT}/src/templates/roles.json" "${TMP}/.ai/roles.json"
assert_contains "E-137.05a: parses template → engineer:claude:0" "engineer:claude:0" "$(_load_map "$TMP")"
assert_contains "E-137.05b: parses template → architect:agy:1 (D-050/E-183)" "architect:agy:1" "$(_load_map "$TMP")"

# ── E-137.06: missing roles.json → empty mapping (silent legacy fallback) ─────
EMPTYP="$(mktemp -d)"; mkdir -p "${EMPTYP}/.ai"
empty_map="$(_load_map "$EMPTYP")"
assert_status 0 "E-137.06: absent roles.json → empty mapping" bash -c "[ -z '$empty_map' ]"
rm -rf "$EMPTYP"

# ── E-137.07: non-numeric pane_identifier is filtered (defends `set -u`) ──────
BADP="$(mktemp -d)"; mkdir -p "${BADP}/.ai"
cat > "${BADP}/.ai/roles.json" <<'JSON'
{ "roles": {
  "architect": { "provider": "gemini", "pane_identifier": "x" },
  "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON
bad_map="$(_load_map "$BADP")"
assert_contains "E-137.07a: numeric engineer entry kept" "engineer:claude:0" "$bad_map"
assert_not_contains "E-137.07b: non-numeric architect entry dropped" "architect:" "$bad_map"
rm -rf "$BADP"

# ── E-137.08: _role_to_provider_pane fallback for unmapped roles ──────────────
assert_contains "E-137.08a: fallback engineer → claude:0" "claude:0" "$(_role_pp '' engineer)"
assert_contains "E-137.08b: fallback architect → gemini:1" "gemini:1" "$(_role_pp '' architect)"
assert_status 1 "E-137.08c: non-role returns 1" bash -c "source '$WATCH' 2>/dev/null; _role_to_provider_pane bob"

# ── E-137.09: WATCH_TARGETS drains semantic roles + legacy names ─────────────
assert_status 0 "E-137.09: WATCH_TARGETS includes engineer + architect" \
  grep -qE 'WATCH_TARGETS="engineer architect claude gemini"' "$WATCH"

# ── E-134: handoff routes to the agy (Antigravity) provider when a role maps to it ─
# Proves the end-to-end role→pane handoff works for a brand-new provider (agy), not
# just claude/gemini — the payoff of the provider-agnostic abstraction.
PANES_AGY='%cl\t0\tclaude\twin\t/p\n%agy\t1\tagy\twin\t/p\n'
assert_contains "E-134: architect→agy:1 routes to the agy pane" "%agy" \
  "$(_resolve_with 'architect:agy:1|engineer:claude:0' "$PANES_AGY" architect)"
assert_contains "E-134b: engineer→claude:0 co-resident with agy still routes to claude" "%cl" \
  "$(_resolve_with 'architect:agy:1|engineer:claude:0' "$PANES_AGY" engineer)"

assert_summary
