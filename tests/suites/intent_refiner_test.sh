#!/usr/bin/env bash
# intent_refiner_test.sh — Functional tests for intent-refiner-mcp --stdin mode (E-97)
# Tests run against the installed server at ~/.ai-os/mcp/intent-refiner-mcp/index.js
# (source is synced there by `ai install` / `ai sync`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

INSTALLED_REFINER="${HOME}/.ai-os/mcp/intent-refiner-mcp/index.js"

echo "── Suite: intent_refiner_test ─────────────────────────────────────"

# Skip if not installed (ci environments without ai install)
if [[ ! -f "$INSTALLED_REFINER" ]]; then
  printf "  ⚠ intent-refiner-mcp not installed at %s — skipping suite\n" "$INSTALLED_REFINER"
  assert_summary
  exit 0
fi

CHAT_AUTH="We need to add a new authentication module and implement token refresh logic.
Update the user profile endpoint to include role data.
Remove the deprecated v1 ping route. Must ensure no credentials are logged."

CHAT_DOCS="fix typo in readme, update comment formatting, whitespace cleanup only"

# ── T-04.01–T-04.05: --stdin produces structured UPDATE.md output ────
AI_DIR=$(mktemp -d)
mkdir -p "${AI_DIR}/.ai"
output=$(cd "$AI_DIR" && printf '%s' "$CHAT_AUTH" | node "$INSTALLED_REFINER" --stdin 2>/dev/null)
assert_contains "T-04.01: --stdin emits UPDATE header" "# UPDATE (Refined by intent-refiner-mcp)" "$output"
assert_contains "T-04.02: --stdin extracts Add signals" "## Add" "$output"
assert_contains "T-04.03: --stdin extracts Modify signals" "## Modify" "$output"
assert_contains "T-04.04: --stdin extracts Remove signals" "## Remove" "$output"
assert_contains "T-04.05: --stdin detects Tier 3 for auth content" "Tier 3" "$output"
rm -rf "$AI_DIR"

# ── T-04.06: --stdin writes UPDATE.md to .ai/ in cwd ─────────────────
AI_WRITE_DIR=$(mktemp -d)
mkdir -p "${AI_WRITE_DIR}/.ai"
(cd "$AI_WRITE_DIR" && printf '%s' "$CHAT_AUTH" | node "$INSTALLED_REFINER" --stdin >/dev/null 2>&1)
assert_exists "${AI_WRITE_DIR}/.ai/UPDATE.md"
written=$(cat "${AI_WRITE_DIR}/.ai/UPDATE.md" 2>/dev/null || echo "")
assert_contains "T-04.06: UPDATE.md written with correct header" "# UPDATE (Refined by intent-refiner-mcp)" "$written"
rm -rf "$AI_WRITE_DIR"

# ── T-04.07: --stdin exits 1 on empty input ──────────────────────────
EMPTY_DIR=$(mktemp -d)
mkdir -p "${EMPTY_DIR}/.ai"
empty_exit=0
(cd "$EMPTY_DIR" && printf '' | node "$INSTALLED_REFINER" --stdin >/dev/null 2>&1) || empty_exit=$?
assert_contains "T-04.07: --stdin exits non-zero on empty input" "1" "$empty_exit"
rm -rf "$EMPTY_DIR"

# ── T-04.08: --stdin exits 1 when no .ai/ dir ────────────────────────
NO_AI_DIR=$(mktemp -d)
no_ai_exit=0
(cd "$NO_AI_DIR" && printf 'add something' | node "$INSTALLED_REFINER" --stdin >/dev/null 2>&1) || no_ai_exit=$?
assert_contains "T-04.08: --stdin exits non-zero when no .ai/ dir" "1" "$no_ai_exit"
rm -rf "$NO_AI_DIR"

# ── T-04.09: --stdin detected (Tier 1 for low-risk) ─────────────────
TIER1_DIR=$(mktemp -d)
mkdir -p "${TIER1_DIR}/.ai"
tier1_out=$(cd "$TIER1_DIR" && printf '%s' "$CHAT_DOCS" | node "$INSTALLED_REFINER" --stdin 2>/dev/null || echo "")
assert_contains "T-04.09: --stdin detects Tier 1 for doc-only content" "Tier 1" "$tier1_out"
rm -rf "$TIER1_DIR"

# ── T-04.10: Includes Risk Tier section ──────────────────────────────
TIER_DIR=$(mktemp -d)
mkdir -p "${TIER_DIR}/.ai"
tier_out=$(cd "$TIER_DIR" && printf '%s' "$CHAT_AUTH" | node "$INSTALLED_REFINER" --stdin 2>/dev/null || echo "")
assert_contains "T-04.10: output includes Risk Tier section" "## Risk Tier" "$tier_out"
rm -rf "$TIER_DIR"

assert_summary
