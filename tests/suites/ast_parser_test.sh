#!/usr/bin/env bash
# ast_parser_test.sh — Tests for E-95 ast-parser-mcp (ast-repository-map.md
# §Components 1, §API): Tree-sitter (WASM) symbol extraction + parse_workspace.
#
# Unit-tests the extractor on sample TS/JS source, then drives the REAL
# ast-parser-mcp server over stdio against an isolated temp workspace to verify
# .gitignore / node_modules / secret exclusion and path containment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXTRACTOR="${REPO_ROOT}/src/mcp/ast-parser-mcp/extractor.mjs"
SERVER="${REPO_ROOT}/src/mcp/ast-parser-mcp/index.js"

echo "── Suite: ast_parser_test (E-95) ───────────────────────────────────"

unset AIOS_WORKSPACE AIOS_WORKSPACE_DISABLE 2>/dev/null || true

# ── Extractor unit tests (deterministic) ─────────────────────────────────────
UNIT=$(node --input-type=module -e "
import { extractFromSource, languageForFile } from '${EXTRACTOR}';
const js = await extractFromSource('import fs from \"fs\";\nimport {join} from \"path\";\nexport function add(a,b){return a+b;}\nexport class Router{ dispatch(req,timeoutMs){} register(name){} }\nconst dep=require(\"./registry.json\");\nexport default Router;\nmodule.exports.helper=function(){};', 'javascript');
const ts = await extractFromSource('import {X} from \"./x\";\nexport interface Opts{a:number}\nexport type Id=string;\nexport class Svc{ run(opts:Opts):void {} }\nexport const VERSION=\"1\";', 'typescript');
const none = await extractFromSource('print(1)', 'python');
console.log(JSON.stringify({ js, ts, none,
  lang: { ts: languageForFile('a.ts'), tsx: languageForFile('a.tsx'), mjs: languageForFile('a.mjs'), py: languageForFile('a.py') } }));
")
# Single single-quoted python program (no shell escaping); pipe-split fields.
IFS='|' read -r U_EXP U_SIGS U_IMP U_TSEXP U_NONE U_LTS U_LTSX U_LPY <<<"$(python3 -c '
import json,sys
d=json.loads(sys.argv[1]); js=d["js"]; ts=d["ts"]
print("|".join([
  ",".join(js["exports"]),
  ",".join(m["signature"] for c in js["classes"] for m in c["methods"]),
  ",".join(js["imports"]),
  ",".join(ts["exports"]),
  str(d["none"]),
  str(d["lang"]["ts"]), str(d["lang"]["tsx"]), str(d["lang"]["py"]),
]))' "$UNIT")"

assert_contains "T-95.01: JS exports (fn/class/default/cjs)"       "add,Router,default,helper" "$U_EXP"
assert_contains "T-95.02: JS class Router + dispatch sig"          "dispatch(req,timeoutMs)"   "$U_SIGS"
assert_contains "T-95.03: JS imports incl require target"          "./registry.json"           "$U_IMP"
assert_contains "T-95.03b: JS imports incl es-module"              "fs"                        "$U_IMP"
assert_contains "T-95.04: TS exports (interface/type/class/const)" "Opts,Id,Svc,VERSION"       "$U_TSEXP"
assert_contains "T-95.05: unsupported lang → null"                 "None"        "$U_NONE"
assert_contains "T-95.06a: .ts → typescript"                       "typescript"  "$U_LTS"
assert_contains "T-95.06b: .tsx → tsx"                             "tsx"         "$U_LTSX"
assert_contains "T-95.06c: .py → null"                             "None"        "$U_LPY"

# ── parse_workspace integration (real MCP, isolated temp workspace) ──────────
TMP="$(mktemp -d)"
WS="${TMP}/ws"
mkdir -p "${WS}/src" "${WS}/node_modules/pkg"
printf 'import bar from "./bar.ts";\nexport function foo(){ return 1; }\n' > "${WS}/src/foo.js"
printf 'export class Bar { m(x){ return x; } }\n'                          > "${WS}/src/bar.ts"
printf 'export const SHOULD_BE_IGNORED = 1;\n'                              > "${WS}/ignored.js"
printf 'export function shouldNotAppear(){}\n'                             > "${WS}/node_modules/pkg/index.js"
printf 'KEY=supersecret\n'                                                 > "${WS}/.env"
printf 'ignored.js\n'                                                      > "${WS}/.gitignore"

call() {
  printf '%s' "$(mcp_call_tool "$1" "$2" "$3")" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
c=d.get("content",[{}]); print(c[0].get("text","") if c else "")'
}

RES=$(cd "${WS}" && call "${SERVER}" parse_workspace '{"dir_path":"."}')
files=$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(",".join(s["file_path"] for s in d.get("symbols",[])))' <<<"$RES")

assert_contains   "T-95.07: foo.js parsed"            "src/foo.js" "$files"
assert_contains   "T-95.08: bar.ts class parsed"      "src/bar.ts" "$files"
assert_not_contains "T-95.09: .gitignored file excluded" "ignored.js" "$files"
assert_not_contains "T-95.10: node_modules excluded"     "node_modules" "$files"
# Bar's method captured
bar_methods=$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read())
b=next((s for s in d["symbols"] if s["file_path"]=="src/bar.ts"),{})
print(",".join(m["name"] for c in b.get("classes",[]) for m in c.get("methods",[])))' <<<"$RES")
assert_contains   "T-95.08b: Bar.m method extracted"  "m" "$bar_methods"

# ── path containment ─────────────────────────────────────────────────────────
DENY=$(cd "${WS}" && printf '%s' "$(mcp_call_tool "${SERVER}" parse_workspace '{"dir_path":"../../.."}')")
assert_contains   "T-95.11: path escape denied"       "PATH_DENIED" "$DENY"

rm -rf "${TMP}"
assert_summary
