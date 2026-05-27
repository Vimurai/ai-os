#!/usr/bin/env bash
# repo_map_wiring_test.sh — Tests for E-98 wiring (ast-repository-map.md
# §Components 3): --generate-map CLI, the `ai sync` hook, ai-preflight Step 8,
# vendored grammars, and the lazy-SDK invariant that keeps the CLI path
# self-contained for the installed ~/.ai-os server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/ast-parser-mcp/index.js"
AI_BIN="${REPO_ROOT}/src/bin/ai"
PREFLIGHT="${REPO_ROOT}/src/shared/skills/ai-preflight/SKILL.md"
PKG="${REPO_ROOT}/src/mcp/ast-parser-mcp/package.json"
EXTRACTOR="${REPO_ROOT}/src/mcp/ast-parser-mcp/extractor.mjs"

echo "── Suite: repo_map_wiring_test (E-98) ──────────────────────────────"
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true

# ── T-98.01: --generate-map CLI writes .ai/REPO_MAP.md ───────────────────────
TMP="$(mktemp -d)"; mkdir -p "${TMP}/src"
printf 'export class A{ run(x){} }\nimport b from "./b.js";\n' > "${TMP}/src/a.js"
printf 'export const b = 1;\n'                                 > "${TMP}/src/b.js"
out=$(cd "${TMP}" && node "${SERVER}" --generate-map 2>&1)
assert_contains "T-98.01: CLI reports REPO_MAP write" "REPO_MAP" "$out"
assert_exists   "${TMP}/.ai/REPO_MAP.md"

# ── T-98.02: AI_OS_DISABLE_REPO_MAP=1 → CLI no-op, no write ───────────────────
TMP2="$(mktemp -d)"; mkdir -p "${TMP2}/src"; printf 'export const x=1;\n' > "${TMP2}/src/x.js"
out2=$(cd "${TMP2}" && AI_OS_DISABLE_REPO_MAP=1 node "${SERVER}" --generate-map 2>&1)
assert_contains "T-98.02: disabled flag short-circuits CLI" "REPO_MAP_DISABLED" "$out2"
if [ -f "${TMP2}/.ai/REPO_MAP.md" ]; then _fail "T-98.02b: no REPO_MAP.md when disabled"; else _pass "T-98.02b: no REPO_MAP.md when disabled"; fi
rm -rf "${TMP}" "${TMP2}"

# ── T-98.03: ai sync wires the repo-map hook ─────────────────────────────────
ai_src=$(cat "${AI_BIN}")
assert_contains "T-98.03: _generate_repo_map helper defined" "_generate_repo_map()" "$ai_src"
assert_contains "T-98.03b: helper invoked inside do_sync"     "  _generate_repo_map" "$ai_src"
assert_contains "T-98.04: hook honors AI_OS_DISABLE_REPO_MAP" "AI_OS_DISABLE_REPO_MAP" "$ai_src"
assert_contains "T-98.04b: hook fail-open on missing node"    "node not found — skipping REPO_MAP" "$ai_src"

# ── T-98.05: ai-preflight Step 8 documents REPO_MAP loading ──────────────────
pf=$(cat "${PREFLIGHT}")
assert_contains "T-98.05: Step 8 present"             "### 8. Load REPO_MAP.md" "$pf"
assert_contains "T-98.05b: names E-98"               "E-98" "$pf"
assert_contains "T-98.05c: names blueprint"          "ast-repository-map" "$pf"
assert_contains "T-98.05d: documents rollback flag"  "AI_OS_DISABLE_REPO_MAP" "$pf"

# ── T-98.06: ai-preflight SKILL mirrors are byte-identical ───────────────────
assert_status 0 "T-98.06a: .claude mirror identical" diff -q "${PREFLIGHT}" "${REPO_ROOT}/.claude/skills/ai-preflight/SKILL.md"
assert_status 0 "T-98.06b: .gemini mirror identical" diff -q "${PREFLIGHT}" "${REPO_ROOT}/.gemini/skills/ai-preflight/SKILL.md"

# ── T-98.07: grammars are vendored, tree-sitter-wasms is NOT a runtime dep ───
ext=$(cat "${EXTRACTOR}")
assert_contains "T-98.07: extractor loads vendored grammars dir" "GRAMMARS_DIR" "$ext"
assert_not_contains "T-98.07b: no runtime tree-sitter-wasms resolve" "tree-sitter-wasms/package.json" "$ext"
runtime_dep=$(node -e "const p=require('${PKG}'); console.log(Object.keys(p.dependencies||{}).includes('tree-sitter-wasms'))")
assert_contains "T-98.07c: tree-sitter-wasms not a runtime dep" "false" "$runtime_dep"
dev_dep=$(node -e "const p=require('${PKG}'); console.log(Object.keys(p.devDependencies||{}).includes('tree-sitter-wasms'))")
assert_contains "T-98.07d: tree-sitter-wasms is a devDependency" "true" "$dev_dep"

# ── T-98.08: vendored grammar .wasm files exist ──────────────────────────────
assert_exists "${REPO_ROOT}/src/mcp/ast-parser-mcp/grammars/tree-sitter-javascript.wasm"
assert_exists "${REPO_ROOT}/src/mcp/ast-parser-mcp/grammars/tree-sitter-typescript.wasm"

# ── T-98.09: SDK is lazy-loaded (not a top-level static import) ──────────────
srv=$(cat "${SERVER}")
assert_contains "T-98.09: SDK imported lazily (await import)" 'await import("@modelcontextprotocol/sdk/server/index.js")' "$srv"
assert_not_contains "T-98.09b: no top-level static SDK import" 'import { Server } from "@modelcontextprotocol/sdk' "$srv"

assert_summary
