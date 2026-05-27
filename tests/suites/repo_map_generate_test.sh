#!/usr/bin/env bash
# repo_map_generate_test.sh — Tests for E-97 generate_map / REPO_MAP.md
# serialization (ast-repository-map.md §API, §Execution Constraints token budget).
#
# Unit-tests the serializer (skeleton format, ⋮ elision, budget trimming) then
# drives the real ast-parser-mcp generate_map tool to confirm it writes
# .ai/REPO_MAP.md and honours the budget + AI_OS_DISABLE_REPO_MAP rollback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SER="${REPO_ROOT}/src/mcp/ast-parser-mcp/serializer.mjs"
SERVER="${REPO_ROOT}/src/mcp/ast-parser-mcp/index.js"

echo "── Suite: repo_map_generate_test (E-97) ────────────────────────────"
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true

# ── Serializer unit tests ────────────────────────────────────────────────────
OUT=$(node --input-type=module -e "
import { serializeRepoMap, estimateTokens } from '${SER}';
const syms=[
 {file_path:'src/hub.js',centrality_score:1,exports:['helper'],classes:[{name:'Hub',methods:[{name:'go',signature:'go(x,y)'}]}],imports:[]},
 {file_path:'src/a.js',centrality_score:0.5,exports:['A'],classes:[],imports:['./hub.js']},
 {file_path:'src/z.js',centrality_score:0.1,exports:['Z'],classes:[],imports:['./hub.js']},
];
const full=serializeRepoMap(syms,{maxTokens:2048});
console.log('FULL_INCLUDED='+full.included+'/'+full.total);
console.log('HAS_ELISION='+full.markdown.includes('go(x,y) ⋮'));
console.log('HAS_CLASS='+full.markdown.includes('class Hub'));
console.log('HUB_FIRST='+(full.markdown.indexOf('src/hub.js')<full.markdown.indexOf('src/z.js')));
const tiny=serializeRepoMap(syms,{maxTokens:60});
console.log('TINY_INCLUDED='+tiny.included);
console.log('TINY_KEEPS_HUB='+tiny.markdown.includes('src/hub.js'));
console.log('TINY_TRIMS_Z='+(!tiny.markdown.includes('src/z.js')));
console.log('EST='+estimateTokens('abcdefgh'));
")
assert_contains "T-97.01: full map includes all files"     "FULL_INCLUDED=3/3"  "$OUT"
assert_contains "T-97.02: function body elided with ⋮"      "HAS_ELISION=true"   "$OUT"
assert_contains "T-97.03: class skeleton rendered"          "HAS_CLASS=true"     "$OUT"
assert_contains "T-97.04: ranked hub-first ordering"        "HUB_FIRST=true"     "$OUT"
assert_contains "T-97.05: tiny budget trims to 1 file"      "TINY_INCLUDED=1"    "$OUT"
assert_contains "T-97.06: budget keeps highest-centrality"  "TINY_KEEPS_HUB=true" "$OUT"
assert_contains "T-97.07: budget trims lowest-centrality"   "TINY_TRIMS_Z=true"  "$OUT"
assert_contains "T-97.08: estimateTokens ~chars/4"          "EST=2"              "$OUT"

# ── generate_map integration (real MCP) ──────────────────────────────────────
TMP="$(mktemp -d)"; WS="${TMP}/ws"; mkdir -p "${WS}/src"
printf 'export function helper(){ return 1; }\nexport class Hub { go(x,y){ return x+y; } }\n' > "${WS}/src/hub.js"
printf 'import {helper} from "./hub.js";\nexport function useIt(){ return helper(); }\n'     > "${WS}/src/importer.js"
call() {
  printf '%s' "$(mcp_call_tool "$1" "$2" "$3")" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'
}

RES=$(cd "${WS}" && call "${SERVER}" generate_map '{"dir_path":"."}')
assert_contains "T-97.09: generate_map reports REPO_MAP.md path" '".ai/REPO_MAP.md"' "$RES"
assert_contains "T-97.10: reports files_included"               '"files_included"'   "$RES"
assert_exists   "${WS}/.ai/REPO_MAP.md"
MAP=$(cat "${WS}/.ai/REPO_MAP.md" 2>/dev/null || echo "")
assert_contains "T-97.11: REPO_MAP.md lists hub.js"   "src/hub.js" "$MAP"
assert_contains "T-97.12: REPO_MAP.md elides body"    "⋮"          "$MAP"
assert_contains "T-97.13: REPO_MAP.md auto-gen header" "AST Repository Map" "$MAP"

# Budget: tiny max_tokens → fewer files than the full run.
RES_TINY=$(cd "${WS}" && call "${SERVER}" generate_map '{"dir_path":".","max_tokens":50}')
inc_tiny=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["files_included"])' <<<"$RES_TINY" 2>/dev/null || echo "?")
assert_match "T-97.14: small budget includes ≤1 file" "^[01]$" "$inc_tiny"

# Rollback: AI_OS_DISABLE_REPO_MAP=1 → no-op, no write.
TMP2="$(mktemp -d)"; WS2="${TMP2}/ws"; mkdir -p "${WS2}/src"
printf 'export const X=1;\n' > "${WS2}/src/x.js"
RES_OFF=$(cd "${WS2}" && export AI_OS_DISABLE_REPO_MAP=1 && call "${SERVER}" generate_map '{"dir_path":"."}')
assert_contains "T-97.15: disabled flag short-circuits" "REPO_MAP_DISABLED" "$RES_OFF"
if [ -f "${WS2}/.ai/REPO_MAP.md" ]; then _fail "T-97.16: no REPO_MAP.md written when disabled"; else _pass "T-97.16: no REPO_MAP.md written when disabled"; fi

rm -rf "${TMP}" "${TMP2}"
assert_summary
