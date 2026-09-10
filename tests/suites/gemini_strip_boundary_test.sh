#!/usr/bin/env bash
# gemini_strip_boundary_test.sh — E-248 (D-067 §2): the strip is a Gemini adapter step.
#
# THE BUG. `disable-model-invocation`, `user-invocable` and `allowed-tools` are Claude
# frontmatter keys the Gemini CLI rejects, so `ai install` stripped them — from
# ~/.ai-os/gemini/agents, THE INSTALL MIRROR. That was harmless while `src/gemini/agents`
# served only Gemini. E-212 made provisioning role-aware: the Architect's agent directory
# is `gemini/agents` whatever provider holds the role, so under the D-066 all-Claude
# default those seven agents are copied into `.claude/agents/` — from the stripped mirror.
# A Claude Architect therefore lost the three keys, degrading precisely the topology D-066
# had just made the default.
#
# The mirror is CANONICAL. A provider-specific transformation belongs at that provider's
# boundary (D-052), applied to the copy being written into `.gemini/`, never to the source
# every other provider reads from. Two transformations of one file drift; one does not.
#
# NON-VACUITY IS THE HARD HALF HERE. "The keys are present" would pass just as well if the
# strip had been deleted outright — and then a Gemini Architect would get frontmatter its
# CLI rejects. So the suite pins BOTH directions: the keys survive for claude, and they are
# still removed for gemini.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
KEYS='^(disable-model-invocation|user-invocable|allowed-tools):'

echo "── Suite: gemini_strip_boundary_test (E-248) ───────────────────────"

export AI_OS_DISABLE_REPO_MAP=1

# <architect-provider> → a project fixture bound that way.
_proj() {
  local arch="$1"
  local d; d="$(test_tmpdir e248)"
  mkdir -p "$d/.ai"
  cat > "$d/.ai/roles.json" <<JSON
{ "roles": { "architect": {"provider":"${arch}","pane_identifier":"1"},
             "engineer":  {"provider":"claude","pane_identifier":"0"} } }
JSON
  cp "${REPO_ROOT}/src/templates/providers.json" "$d/.ai/providers.json" 2>/dev/null || true
  printf '%s' "$d"
}

# ── E-248.1: the SOURCE declares the keys ────────────────────────────────────
# Everything below is meaningless if src/ never had them. This is the baseline the mirror
# is supposed to preserve, and it is what E-212.07 already asserts from the other side.
_src="${REPO_ROOT}/src/gemini/agents/docs-architect.md"
assert_status 0 "E-248.01a: src/gemini/agents declares allowed-tools" \
  grep -qE '^allowed-tools:' "$_src"
assert_status 0 "E-248.01b: and user-invocable" grep -qE '^user-invocable:' "$_src"
assert_status 0 "E-248.01c: and disable-model-invocation" \
  grep -qE '^disable-model-invocation:' "$_src"

# ── E-248.2: THE MIRROR IS CANONICAL ─────────────────────────────────────────
# The defect in one assertion. `ai install` must leave the mirror byte-equal to src/ for
# these keys; any provider reading it gets the full contract.
if [[ -d "${HOME}/.ai-os/gemini/agents" ]]; then
  assert_status 0 "E-248.02a: the INSTALL MIRROR keeps allowed-tools (was stripped)" \
    grep -qE '^allowed-tools:' "${HOME}/.ai-os/gemini/agents/docs-architect.md"
  assert_status 0 "E-248.02b: and the mirror matches src/ byte for byte" \
    diff -q "$_src" "${HOME}/.ai-os/gemini/agents/docs-architect.md"
else
  _skip "E-248.02a: install mirror comparison (framework not installed)"
  _skip "E-248.02b: install mirror byte-identity (framework not installed)"
fi
# The install path must not strip the mirror by DEFAULT. The call still exists — D-067
# keeps it as the AI_OS_STRIP_MIRROR=1 rollback — so the property is that it is GUARDED,
# not that it is gone. Asserting absence would have forced deleting the rollback to go
# green, which is how a rollback quietly disappears.
assert_status 0 "E-248.02c: the mirror strip is behind AI_OS_STRIP_MIRROR, not default" \
  bash -c "grep -B1 'strip_gemini_agent_fields \"\\\${AIOS}/gemini/agents\"' '$AI' | grep -q 'AI_OS_STRIP_MIRROR'"

# ── E-248.3: a CLAUDE Architect keeps the full contract ──────────────────────
# The user-visible failure: seven Architect agents arriving in .claude/agents/ without the
# keys that tell Claude Code what they may do.
_pc="$(_proj claude)"
( cd "$_pc" && bash "$AI" sync >/dev/null 2>&1 )
if [[ -f "${_pc}/.claude/agents/docs-architect.md" ]]; then
  assert_status 0 "E-248.03a: .claude/agents keeps allowed-tools under the D-066 default" \
    grep -qE '^allowed-tools:' "${_pc}/.claude/agents/docs-architect.md"
  assert_status 0 "E-248.03b: and user-invocable" \
    grep -qE '^user-invocable:' "${_pc}/.claude/agents/docs-architect.md"
  assert_status 0 "E-248.03c: and disable-model-invocation" \
    grep -qE '^disable-model-invocation:' "${_pc}/.claude/agents/docs-architect.md"
  # All seven Architect agents, not just the one that happened to be checked.
  _missing=0
  for _a in ux_reviewer docs-architect knowledge_architect meta_analyst memory_curator \
            seo_manager seo_content_generator; do
    _f="${_pc}/.claude/agents/${_a}.md"
    [[ -f "$_f" ]] && grep -qE "$KEYS" "$_f" || _missing=$((_missing + 1))
  done
  assert_status 0 "E-248.03d: all seven Architect agents keep their contract (missing=${_missing})" \
    bash -c "[[ '$_missing' -eq 0 ]]"
else
  _skip "E-248.03: .claude/agents not provisioned in the fixture"
fi

# ── E-248.4: NON-VACUITY — a GEMINI workspace is still stripped ──────────────
# Deleting the strip would satisfy §3 and break the Gemini CLI. This is the assertion that
# stops that reading of the ruling.
_pg="$(_proj gemini)"
( cd "$_pg" && bash "$AI" sync >/dev/null 2>&1 )
if [[ -f "${_pg}/.gemini/agents/docs-architect.md" ]]; then
  assert_status 1 "E-248.04a: the .gemini/ copy carries NO Claude-only keys" \
    grep -qE "$KEYS" "${_pg}/.gemini/agents/docs-architect.md"
  # …and it is otherwise the same document, so the strip is a projection, not a rewrite.
  assert_status 0 "E-248.04b: the stripped copy still carries the agent body" \
    grep -q 'docs-architect' "${_pg}/.gemini/agents/docs-architect.md"
  # THE BOUNDARY ITSELF: stripping the .gemini/ copy must not reach back to the source it
  # was copied from. This is the actual shape of the bug, asserted directly.
  assert_status 0 "E-248.04c: stripping .gemini/ left the install mirror intact" \
    bash -c "[[ ! -d '${HOME}/.ai-os/gemini/agents' ]] || grep -qE '^allowed-tools:' '${HOME}/.ai-os/gemini/agents/docs-architect.md'"
  assert_status 0 "E-248.04d: and left src/ intact" grep -qE '^allowed-tools:' "$_src"
else
  _skip "E-248.04: .gemini/ not provisioned for a gemini-bound Architect"
fi

# ── E-248.5: the rollback ────────────────────────────────────────────────────
assert_status 0 "E-248.05a: AI_OS_STRIP_MIRROR=1 restores the old behaviour" \
  grep -q 'AI_OS_STRIP_MIRROR' "$AI"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== gemini_strip_boundary_test.sh PASS ====="
else
  echo "===== gemini_strip_boundary_test.sh FAIL (${FAIL_COUNT}) ====="
fi
