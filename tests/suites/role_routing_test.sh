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
assert_contains "E-137.08b: fallback architect → agy:1 (D-050 default, E-188)" "agy:1" "$(_role_pp '' architect)"
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

# ── E-209 (D-054): resolve_pane precedence — config beats heuristics ──────────
# REGRESSION for the live G3 misroute (COMM.md 2026-09-04, reproduced twice): Claude
# Code renames its tmux pane to the conversation summary, so the Engineer pane was
# titled "✳ Engineer and architect separation with Claude" while the Architect pane
# was "✳ Claude Code". Under the old E-117 order the fuzzy title pass matched
# "architect" inside the ENGINEER pane's summary and swallowed the handoff.
# 6-field rows (with a command column) so the E-122 agent-pane filter is exercised
# rather than the TIER-B degrade.
PANES_G3='%107\t1\t✳ Engineer and architect separation with Claude\tWindow\t/p\t2.1.261\n%108\t2\t✳ Claude Code\tWindow\t/p\t2.1.261\n'
MAP_G3='architect:claude:1|engineer:claude:0'
assert_contains "E-209.01a: G3 — architect resolves to the ordinal-1 pane, NOT the summary-title match" "%108" \
  "$(_resolve_with "$MAP_G3" "$PANES_G3" architect)"
assert_contains "E-209.01b: G3 — engineer still resolves to the ordinal-0 pane" "%107" \
  "$(_resolve_with "$MAP_G3" "$PANES_G3" engineer)"

# Exact title still wins over the ordinal (Pass 1) — what `ai pane <role>` pins.
PANES_TITLED='%a\t1\tarchitect\tWindow\t/p\t2.1.261\n%b\t2\tengineer\tWindow\t/p\t2.1.261\n'
assert_contains "E-209.02a: exact title beats the ordinal (architect pinned at index 1)" "%a" \
  "$(_resolve_with "$MAP_G3" "$PANES_TITLED" architect)"
assert_contains "E-209.02b: exact title beats the ordinal (engineer pinned at index 2)" "%b" \
  "$(_resolve_with "$MAP_G3" "$PANES_TITLED" engineer)"

# Fuzzy/window remain reachable as a LAST resort — only when no agent pane sits at
# the ordinal (e.g. the mapped pane is not running yet). Single agent pane, want_idx=1.
PANES_ONE='%solo\t1\tmy architect console\tWindow\t/p\t2.1.261\n'
assert_contains "E-209.03: fuzzy title still resolves when no agent pane exists at the ordinal" "%solo" \
  "$(_resolve_with "$MAP_G3" "$PANES_ONE" architect)"
PANES_WIN='%w\t1\tMac.lan\tarchitect-win\t/p\t2.1.261\n'
assert_contains "E-209.04: window-name fallback still reachable for semantic targets" "%w" \
  "$(_resolve_with "$MAP_G3" "$PANES_WIN" architect)"

# A handoff must never land in a shell — the E-122 rule is unchanged by the re-order.
PANES_SHELL='%sh\t1\tarchitect\tWindow\t/p\tbash\n%ag\t2\tMac.lan\tWindow\t/p\t2.1.261\n'
assert_contains "E-209.05: exact-title pass may match a shell pane (E-122 applies to the ordinal only)" "%sh" \
  "$(_resolve_with "$MAP_G3" "$PANES_SHELL" architect)"
PANES_SHELL2='%sh\t1\tMac.lan\tWindow\t/p\tbash\n%ag\t2\tMac.lan\tWindow\t/p\t2.1.261\n'
assert_status 1 "E-209.06: no agent pane at the ordinal and no title/window hit → no route (never a shell)" \
  bash -c "source '$WATCH' 2>/dev/null; ROLES_MAPPING='architect:claude:5|engineer:claude:0'; _project_panes() { printf '%b' \"$PANES_SHELL2\"; }; resolve_pane architect"

# PROVIDER targets keep the historical E-117 order (fuzzy BEFORE ordinal).
PANES_LEGACY='%x\t1\tMac.lan\tWindow\t/p\t2.1.261\n%y\t2\tclaude-code\tWindow\t/p\t2.1.261\n'
# Non-colliding map (only engineer is claude) — E-211 fails closed on a colliding one.
assert_contains "E-209.07: legacy 'claude' target keeps E-117 order — fuzzy title wins over ordinal 0" "%y" \
  "$(_resolve_with 'architect:agy:1|engineer:claude:0' "$PANES_LEGACY" claude 2>/dev/null)"

# TIER-B degrade (no command column) still works through the re-ordered path.
PANES_TIERB='%p0\t1\tMac.lan\tWindow\t/p\t\n%p1\t2\tMac.lan\tWindow\t/p\t\n'
assert_contains "E-209.08: TIER-B degrade intact — architect → ordinal 1 with no command column" "%p1" \
  "$(_resolve_with "$MAP_G3" "$PANES_TIERB" architect)"


# ── E-211 (D-054): legacy provider targets deprecated + ambiguity fail-closed ──
# A legacy provider target carries a FIXED ordinal, so once both roles run on the same
# provider it cannot express which pane is meant. Warn always; refuse to guess when
# ambiguous (a misrouted handoff is worse than a refused one — that was gap G3).
_stderr_of() {  # <roles_mapping> <panes> <target> → stderr only
  local rm="$1" panes="$2" tgt="$3"
  ( source "$WATCH" 2>/dev/null
    ROLES_MAPPING="$rm"
    _project_panes() { printf '%b' "$panes"; }
    resolve_pane "$tgt" ) 2>&1 >/dev/null
}
MAP_DUAL_CLAUDE='architect:claude:1|engineer:claude:0'
MAP_MIXED='architect:agy:1|engineer:claude:0'

assert_contains "E-211.01: 'claude' target warns DEPRECATED on stderr" "DEPRECATED" \
  "$(_stderr_of "$MAP_MIXED" "$PANES_LEGACY" claude)"
assert_contains "E-211.01b: deprecation warning names the removal version" "v4.0" \
  "$(_stderr_of "$MAP_MIXED" "$PANES_LEGACY" claude)"
assert_contains "E-211.02: 'gemini' target warns DEPRECATED on stderr" "DEPRECATED" \
  "$(_stderr_of "$MAP_MIXED" "$PANES_AB" gemini)"

# Same-provider ambiguity → fail closed with an actionable hint.
assert_contains "E-211.03a: dual-claude makes 'claude' AMBIGUOUS" "AMBIGUOUS" \
  "$(_stderr_of "$MAP_DUAL_CLAUDE" "$PANES_LEGACY" claude)"
assert_contains "E-211.03b: ambiguity error hints at the semantic roles" 'use "architect" or "engineer"' \
  "$(_stderr_of "$MAP_DUAL_CLAUDE" "$PANES_LEGACY" claude)"
assert_status 1 "E-211.03c: ambiguous legacy target returns 1 (fails closed)" \
  bash -c "source '$WATCH' 2>/dev/null; ROLES_MAPPING='$MAP_DUAL_CLAUDE'; _project_panes() { printf '%b' \"$PANES_LEGACY\"; }; resolve_pane claude 2>/dev/null"

# Fail-closed must print NOTHING on stdout — a caller must never get a pane id.
assert_not_contains "E-211.03d: ambiguous legacy target emits no pane id on stdout" "%" \
  "$(_resolve_with "$MAP_DUAL_CLAUDE" "$PANES_LEGACY" claude 2>/dev/null)"

# Mixed-provider map is NOT ambiguous — legacy target still resolves (warn only).
assert_status 0 "E-211.04: non-colliding map keeps the legacy target working" \
  bash -c "source '$WATCH' 2>/dev/null; ROLES_MAPPING='$MAP_MIXED'; _project_panes() { printf '%b' \"$PANES_LEGACY\"; }; resolve_pane claude 2>/dev/null"

# Semantic targets are never warned about and never fail closed under dual-claude.
assert_not_contains "E-211.05: semantic 'architect' target emits no deprecation warning" "DEPRECATED" \
  "$(_stderr_of "$MAP_DUAL_CLAUDE" "$PANES_G3" architect)"


assert_summary
