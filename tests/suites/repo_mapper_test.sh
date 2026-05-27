#!/usr/bin/env bash
# repo_mapper_test.sh — Tests for E-96 dependency-graph centrality ranking
# (ast-repository-map.md §Components 2, §Core Concept): src/mcp/ast-parser-mcp/
# repo-mapper.mjs + its wiring into parse_workspace.
#
# Unit-tests the pure ranking module (import resolution, PageRank centrality,
# sorting) via labeled node output, then drives the real ast-parser-mcp server
# to confirm parse_workspace now returns centrality_score.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAPPER="${REPO_ROOT}/src/mcp/ast-parser-mcp/repo-mapper.mjs"
SERVER="${REPO_ROOT}/src/mcp/ast-parser-mcp/index.js"

echo "── Suite: repo_mapper_test (E-96) ──────────────────────────────────"
unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true

# ── Unit tests (deterministic; node prints KEY=value lines) ──────────────────
OUT=$(node --input-type=module -e "
import { rankSymbols, resolveImport, normalizePath, buildDependencyGraph } from '${MAPPER}';
const syms=[
 {file_path:'src/util.js',exports:['helper'],classes:[],imports:[]},
 {file_path:'src/a.js',exports:['A'],classes:[],imports:['./util.js']},
 {file_path:'src/b.js',exports:['B'],classes:[],imports:['./util']},
 {file_path:'src/c.js',exports:['C'],classes:[],imports:['./util.js','fs']},
 {file_path:'src/lonely.js',exports:['L'],classes:[],imports:[]},
];
const r=rankSymbols(syms);
const util=r.find(s=>s.file_path==='src/util.js');
const a=r.find(s=>s.file_path==='src/a.js');
console.log('TOP='+r[0].file_path);
console.log('UTIL='+util.centrality_score);
console.log('HUB_GT_LEAF='+(util.centrality_score>a.centrality_score));
console.log('SORTED='+r.every((s,i)=>i===0||r[i-1].centrality_score>=s.centrality_score));
console.log('INRANGE='+r.every(s=>s.centrality_score>=0&&s.centrality_score<=1));
console.log('RESOLVE_NOEXT='+resolveImport('src/b.js','./util',new Set(['src/util.js'])));
console.log('RESOLVE_INDEX='+resolveImport('src/a/b.js','../util',new Set(['src/util/index.js'])));
console.log('RESOLVE_EXTERNAL='+resolveImport('src/b.js','fs',new Set(['src/util.js'])));
console.log('NORM='+normalizePath('a/./b/../c'));
console.log('EMPTY='+JSON.stringify(rankSymbols([])));
console.log('EDGE='+[...(buildDependencyGraph(syms).edges.get('src/a.js')||[])].join(','));
")

assert_contains "T-96.01: hub (util) ranks first"        "TOP=src/util.js"        "$OUT"
assert_contains "T-96.02: hub centrality normalized to 1" "UTIL=1"                "$OUT"
assert_contains "T-96.03: hub outranks a leaf"           "HUB_GT_LEAF=true"       "$OUT"
assert_contains "T-96.04: output sorted desc"            "SORTED=true"            "$OUT"
assert_contains "T-96.05: scores within [0,1]"           "INRANGE=true"           "$OUT"
assert_contains "T-96.06: resolves extension-less import" "RESOLVE_NOEXT=src/util.js" "$OUT"
assert_contains "T-96.07: resolves dir/index import"     "RESOLVE_INDEX=src/util/index.js" "$OUT"
assert_contains "T-96.08: external import → null"        "RESOLVE_EXTERNAL=null"  "$OUT"
assert_contains "T-96.09: normalizePath collapses ./.."  "NORM=a/c"               "$OUT"
assert_contains "T-96.10: empty input → []"              "EMPTY=[]"               "$OUT"
assert_contains "T-96.11: graph edge a→util built"       "EDGE=src/util.js"       "$OUT"

# ── Integration: parse_workspace now returns centrality_score ────────────────
TMP="$(mktemp -d)"; WS="${TMP}/ws"; mkdir -p "${WS}/src"
printf 'export function helper(){ return 1; }\n'                 > "${WS}/src/hub.js"
printf 'import {helper} from "./hub.js";\nexport function useIt(){ return helper(); }\n' > "${WS}/src/importer.js"
call() {
  printf '%s' "$(mcp_call_tool "$1" "$2" "$3")" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'
}
RES=$(cd "${WS}" && call "${SERVER}" parse_workspace '{"dir_path":"."}')
# hub.js (imported by importer.js) must have a centrality_score and outrank importer
verdict=$(python3 -c 'import json,sys
d=json.loads(sys.stdin.read()); m={s["file_path"]:s.get("centrality_score") for s in d["symbols"]}
hub=m.get("src/hub.js"); imp=m.get("src/importer.js")
print("HAS_SCORE="+str(hub is not None)+" HUB_TOP="+str(hub is not None and imp is not None and hub>=imp))' <<<"$RES")
assert_contains "T-96.12: parse_workspace emits centrality_score" "HAS_SCORE=True" "$verdict"
assert_contains "T-96.13: imported hub outranks importer"         "HUB_TOP=True"   "$verdict"

rm -rf "${TMP}"
assert_summary
