#!/usr/bin/env bash
# cli_test.sh — Core `ai` CLI command tests (E-34 — collapsed surface)
# After the cli-collapse, the only user-facing commands are: install, init,
# sync, doctor, uninstall, version, help. Removed commands (update, preflight,
# review, test, archive, digest, where, onboard) emit a deprecation message
# pointing to the equivalent agent skill and exit 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

AI_BIN="${SCRIPT_DIR}/../../src/bin/ai"

echo "── Suite: cli_test ──────────────────────────────────────────────────"

# ai version exits 0 and contains version string
out=$("$AI_BIN" version 2>&1)
assert_status 0 "ai version exits 0" "$AI_BIN" version
assert_contains "ai version contains version number" "3." "$out"

# Usage lists the kept commands (install / init / sync / doctor / uninstall)
out=$("$AI_BIN" 2>&1 || true)
assert_contains "usage lists 'install'" "install" "$out"
assert_contains "usage lists 'init'" "init" "$out"
assert_contains "usage lists 'sync'" "sync" "$out"
assert_contains "usage lists 'doctor'" "doctor" "$out"
assert_contains "usage lists 'uninstall'" "uninstall" "$out"

# Removed commands are listed in the migration map
assert_contains "usage references removed 'review' (migration map)" "review" "$out"
assert_contains "usage references removed 'test' (migration map)" "test" "$out"

# Removed commands emit a deprecation message and exit 1
out=$("$AI_BIN" review 2>&1 || true)
assert_contains "ai review prints deprecation pointer to skill" "skill: arch-review" "$out"
assert_status 1 "ai review exits 1 (deprecated)" "$AI_BIN" review

out=$("$AI_BIN" test 2>&1 || true)
assert_contains "ai test prints deprecation pointer to skill" "skill: ai-test" "$out"
assert_status 1 "ai test exits 1 (deprecated)" "$AI_BIN" test

out=$("$AI_BIN" preflight 2>&1 || true)
assert_contains "ai preflight prints deprecation pointer" "skill: ai-preflight" "$out"
assert_status 1 "ai preflight exits 1 (deprecated)" "$AI_BIN" preflight

out=$("$AI_BIN" where 2>&1 || true)
assert_contains "ai where prints deprecation message" "removed" "$out"
assert_status 1 "ai where exits 1 (deprecated)" "$AI_BIN" where

# Unknown subcommand exits 1
assert_status 1 "unknown subcommand exits 1" "$AI_BIN" __nonexistent_command__

assert_summary
