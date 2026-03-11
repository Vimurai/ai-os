#!/usr/bin/env bash
# cli_test.sh — Core `ai` CLI command tests (P-15 / §22)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

AI_BIN="${SCRIPT_DIR}/../../src/bin/ai"

echo "── Suite: cli_test ──────────────────────────────────────────────────"

# ai version exits 0 and contains version string
out=$("$AI_BIN" version 2>&1)
assert_status 0 "ai version exits 0" "$AI_BIN" version
assert_contains "ai version contains version number" "3." "$out"

# ai usage exits 0 and lists commands
out=$("$AI_BIN" 2>&1 || true)
assert_contains "usage lists 'install'" "install" "$out"
assert_contains "usage lists 'review'" "review" "$out"
assert_contains "usage lists 'mcp-setup'" "mcp-setup" "$out"

# ai where exits 0
assert_status 0 "ai where exits 0" "$AI_BIN" where

# Unknown subcommand exits 1
assert_status 1 "unknown subcommand exits 1" "$AI_BIN" __nonexistent_command__

assert_summary
