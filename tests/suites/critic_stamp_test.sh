#!/usr/bin/env bash
# critic_stamp_test.sh — Tier-3 critics persist verdicts via add_stamp, not by
# appending to .ai/REVIEWS.md (which is a regenerated view of the SQLite stamps
# table — direct appends are clobbered on the next _regenerateViews). Aligns
# critic_arch/security/tests with the E-72 distributed-stamping pattern that
# critic_clean_code already follows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: critic_stamp_test ────────────────────────────────────────"

# critic → expected stamp prefix
declare -a CRITICS=("critic_arch:ARCH" "critic_security:SEC" "critic_tests:TESTS")

for row in "${CRITICS[@]}"; do
  name="${row%%:*}"; pfx="${row##*:}"
  SRC="${REPO_ROOT}/src/claude/agents/${name}.md"

  assert_status 0 "${name}: source exists" test -f "$SRC"

  # Stamps via the MCP, with the PASS and FAIL stamp types present.
  assert_status 0 "${name}: invokes add_stamp" \
    grep -q 'mcp__task-synchronizer-mcp__add_stamp' "$SRC"
  assert_status 0 "${name}: declares ${pfx}_PASS stamp" \
    grep -qE "\"${pfx}_PASS\"|${pfx}_PASS" "$SRC"
  assert_status 0 "${name}: declares ${pfx}_FAIL stamp" \
    grep -qE "\"${pfx}_FAIL\"|${pfx}_FAIL" "$SRC"

  # Must NOT instruct a direct append to the regenerated REVIEWS.md view.
  assert_status 1 "${name}: no 'Append ... to .ai/REVIEWS.md' instruction" \
    grep -qE 'Append.*\.ai/REVIEWS\.md' "$SRC"
  assert_status 1 "${name}: Target is not 'REVIEWS.md (append only)'" \
    grep -qE 'Target: \.ai/REVIEWS\.md \(append only\)' "$SRC"

  # Frontmatter integrity preserved.
  assert_status 0 "${name}: frontmatter name matches" \
    grep -qE "^name: ${name}$" "$SRC"

  # 3-copy mirror identity (src ↔ .claude ↔ ~/.ai-os/claude).
  assert_status 0 "${name}: .claude mirror identical" \
    diff -q "$SRC" "${REPO_ROOT}/.claude/agents/${name}.md"
  assert_status 0 "${name}: ~/.ai-os mirror identical" \
    diff -q "$SRC" "${HOME}/.ai-os/claude/agents/${name}.md"
done

assert_summary
