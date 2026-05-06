#!/usr/bin/env bash
# security_engineer_agent_test.sh — Tests for E-44 active pen-testing upgrade.
#
# Verifies the security_engineer agent file (and its tracked mirror) carry the
# contract demanded by workflow-optimizations.md §3:
#   - allowed-tools includes code-execution-mcp.execute_code + advisor-mcp
#   - "Active Pen-Testing" section present
#   - Trust boundary policy (sandbox-only, fail-closed, no host exec)
#   - OWASP Top 10 payload table present
#   - Reporting block (SECURITY.md row schema) present
#   - agents.md description names code-execution-mcp

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== security_engineer_agent_test.sh ====="

AGENT_FILES=(
  "${REPO_ROOT}/src/claude/agents/security_engineer.md"
  "${REPO_ROOT}/.claude/agents/security_engineer.md"
)

echo ""
echo "  [T-SECENG-S01] Agent files exist (Claude-only — no Gemini mirror)"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "exists: ${f#${REPO_ROOT}/}" test -f "$f"
done

echo ""
echo "  [T-SECENG-S02] Frontmatter advertises required MCP tools"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → allowed-tools includes execute_code" \
    grep -qE 'allowed-tools:.*mcp__code-execution-mcp__execute_code' "$f"
  assert_status 0 "${f##*/agents/} → allowed-tools includes ask_architect" \
    grep -qE 'allowed-tools:.*mcp__advisor-mcp__ask_architect' "$f"
done

echo ""
echo "  [T-SECENG-S03] Description names active pen-testing"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → description mentions code-execution-mcp" \
    grep -qE '^description:.*code-execution-mcp' "$f"
done

echo ""
echo "  [T-SECENG-S04] Active Pen-Testing section present"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → Active Pen-Testing heading" \
    grep -q "## Active Pen-Testing" "$f"
done

echo ""
echo "  [T-SECENG-S05] Trust boundary is fail-closed and sandbox-only"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → demands --network=none"           grep -q 'network=none'           "$f"
  assert_status 0 "${f##*/agents/} → demands --read-only sandbox"      grep -q 'read-only'              "$f"
  assert_status 0 "${f##*/agents/} → demands --cap-drop=ALL"           grep -q 'cap-drop=ALL'           "$f"
  assert_status 0 "${f##*/agents/} → references D-008 fail-closed"     grep -q 'D-008'                  "$f"
  assert_status 0 "${f##*/agents/} → handles SANDBOX_UNAVAILABLE"      grep -q 'SANDBOX_UNAVAILABLE'    "$f"
  assert_status 0 "${f##*/agents/} → forbids bare-metal fallback"      grep -qiE 'bare.metal|host shell' "$f"
done

echo ""
echo "  [T-SECENG-S06] OWASP Top 10 payload table"
# Check for canonical OWASP IDs A01..A10 in the payload table.
for code in A01 A02 A03 A04 A05 A06 A07 A08 A09 A10; do
  for f in "${AGENT_FILES[@]}"; do
    assert_status 0 "${f##*/agents/} → ${code} listed" grep -q "$code" "$f"
  done
done

echo ""
echo "  [T-SECENG-S07] Reporting + verdict schema present"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → SECURITY.md row schema" \
    grep -q 'OWASP | Surface | Payload' "$f"
  for verdict in RESISTED EXPLOITED INCONCLUSIVE; do
    assert_status 0 "${f##*/agents/} → ${verdict} verdict listed" \
      grep -q "$verdict" "$f"
  done
done

echo ""
echo "  [T-SECENG-S08] Out-of-scope guards (no DoS / no escape probe / no egress)"
for f in "${AGENT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → DoS payloads excluded"      grep -qE 'DoS|fork-bomb' "$f"
  assert_status 0 "${f##*/agents/} → escape probes deferred"     grep -q 'Sandbox-escape'  "$f"
  assert_status 0 "${f##*/agents/} → outbound network excluded"  grep -q 'outbound'        "$f"
done

echo ""
echo "  [T-SECENG-S09] Source-of-truth and project mirror byte-identical"
SRC_HASH="$(md5sum "${REPO_ROOT}/src/claude/agents/security_engineer.md" | awk '{print $1}')"
MIRROR_HASH="$(md5sum "${REPO_ROOT}/.claude/agents/security_engineer.md" | awk '{print $1}')"
assert_status 0 ".claude mirror matches src" \
  bash -c "[[ '$SRC_HASH' == '$MIRROR_HASH' ]]"

echo ""
echo "  [T-SECENG-S10] agents.md description references code-execution-mcp"
assert_status 0 "agents.md mentions security_engineer + code-execution-mcp" \
  bash -c "grep -A1 'security_engineer' '${REPO_ROOT}/.ai/blueprints/agents.md' | grep -q 'code-execution-mcp'"

echo ""
echo "  [T-SECENG-S11] settings.json grants the new MCP tool"
assert_status 0 ".claude/settings.json permits execute_code" \
  grep -q 'mcp__code-execution-mcp__execute_code' "${REPO_ROOT}/.claude/settings.json"

assert_summary
