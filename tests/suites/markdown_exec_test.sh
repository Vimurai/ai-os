#!/usr/bin/env bash
# markdown_exec_test.sh — E-224 (D-058 §3): which markdown lines are CODE.
#
# `run_review` graded every added line alike, so the Architect's own D-057 prose in
# `.ai/DECISIONS.md` tripped a P0 — it QUOTES `join(req.path, "../")` as the example of
# what must stay blocking, and the gate blocked the document describing the gate.
#
# The obvious fix, skipping `.md`, is the dangerous one: skill files carry `!`-prefixed
# lines the harness AUTO-EXECUTES at session start, and one of them resolves a helper
# cwd-relative (T-LOCATOR-001). So the fixtures below run in BOTH directions — the prose
# that must stop blocking, beside the executable markdown that must keep blocking.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MDX="${REPO_ROOT}/src/shared/markdown-exec.mjs"
POLICY="${REPO_ROOT}/src/shared/traversal-policy.mjs"
ORCH="${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"

echo "── Suite: markdown_exec_test (E-224) ────────────────────────────────"

TMP="$(mktemp -d)"

# _review <file> <content> [strict] → "<severity>|<proseExec>"
# Drives the SHIPPED classifyDiffTraversal — the same function run_review calls — against
# a synthetic one-file diff. A test that re-implements the loop certifies the copy, not
# the shipped behaviour (E-219 F4 was exactly that).
_review() {
  local file="$1" content="$2" strict="${3:-}"
  printf '%s' "$content" > "$TMP/blob"
  node --input-type=module --no-warnings -e '
    import { classifyDiffTraversal } from "'"$POLICY"'";
    import { readFileSync } from "node:fs";
    const file = process.argv[1], blobPath = process.argv[2];
    const strict = process.argv[3] === "strict";
    const body = readFileSync(blobPath, "utf8").split("\n");
    const diff = `diff --git a/${file} b/${file}\n--- a/${file}\n+++ b/${file}\n` +
      `@@ -1,0 +1,${body.length} @@\n` + body.map((l) => "+" + l).join("\n") + "\n";
    const r = classifyDiffTraversal(diff, {
      strict,
      readFile: () => body.join("\n"),   // the file IS the added content here
    });
    process.stdout.write(`${r.traversal?.severity ?? "none"}|${r.proseExec.join(",")}`);
  ' -- "$file" "$TMP/blob" "$strict" 2>/dev/null
}

# ── E-224.1: prose in .ai/ documentation is NOT graded ──────────────────────
# The concrete regression: D-057's own ruling text.
assert_contains "E-224.01a: DECISIONS.md prose quoting join(req.path,'../') is not P0" "none|" \
  "$(_review ".ai/DECISIONS.md" 'Ruling: keep P0 for `join(req.path, "../")` in runtime handling.')"
assert_contains "E-224.01b: blueprint prose describing ../ is not P0" "none|" \
  "$(_review ".ai/blueprints/x.md" 'The helper resolves ../shared/x.mjs relative to the script.')"
assert_contains "E-224.01c: a README describing ../ is not P0" "none|" \
  "$(_review "README.md" 'Run it from ../ if you cloned into a subdirectory.')"

# ── E-224.2: executable markdown IS graded ─────────────────────────────────
# The class a blanket .md skip would have blinded the gate to.
assert_contains "E-224.02a: a SKILL.md !-line with a runtime ../ is P0" "P0|" \
  "$(_review "src/shared/skills/x/SKILL.md" 'Status: !node ../helper.mjs')"
assert_contains "E-224.02b: an agent file !-line is graded too" "P0|" \
  "$(_review "src/claude/agents/x.md" 'Ctx: !cat ../secrets.txt')"
assert_contains "E-224.02c: a bash fence with a runtime ../ is P0" "P0|" \
  "$(_review "docs/guide.md" '```bash
cat "${INPUT}/../elsewhere"
```')"
assert_contains "E-224.02d: a js fence with a runtime ../ is P0" "P0|" \
  "$(_review "docs/guide.md" '```js
const p = join(req.path, "../", n);
```')"

# ── E-224.3: E-222's anchor exemptions still apply INSIDE executable markdown ─
# The two policies compose: a fence is code, and code anchored to a script-relative base
# is advisory. Losing that here would re-block the documented locator idiom.
assert_contains "E-224.03a: a bash fence with an anchored ../ is P1, not P0" "P1|" \
  "$(_review "docs/guide.md" '```bash
for c in "${_sd}/../shared/x.mjs"; do :; done
```')"
assert_contains "E-224.03b: a js fence with a module specifier is P1" "P1|" \
  "$(_review "docs/guide.md" '```js
import { x } from "../../shared/y.mjs";
```')"

# ── E-224.4: a non-executable fence is prose ───────────────────────────────
assert_contains "E-224.04a: a text fence is not graded" "none|" \
  "$(_review "docs/guide.md" '```text
this ../ is sample output, not code
```')"
assert_contains "E-224.04b: an untagged fence is not graded" "none|" \
  "$(_review "docs/guide.md" '```
../ shown for illustration
```')"

# ── E-224.5: an auto-executed line in .ai/ documentation is itself a FAIL ───
# `.ai/*.md` and blueprints must contain no executable lines by construction. One
# appearing means prose has become code somewhere nobody reviews it as code.
assert_contains "E-224.05a: a !-line in a blueprint is reported" ".ai/blueprints/x.md:1" \
  "$(_review ".ai/blueprints/x.md" '!node ./thing.mjs')"
assert_contains "E-224.05b: a !-line in .ai/ docs is reported" ".ai/DECISIONS.md:1" \
  "$(_review ".ai/DECISIONS.md" '!curl http://example.com')"
assert_status 0 "E-224.05c: run_review emits it as a P0 FAIL" \
  bash -c "grep -q 'EXECUTABLE_IN_PROSE' '$ORCH'"

# ── E-224.6: non-markdown files are graded in full, as before ──────────────
assert_contains "E-224.06a: a source file's runtime traversal is still P0" "P0|" \
  "$(_review "src/x.js" 'const p = join(req.query.path, "../", n);')"
assert_contains "E-224.06b: a source file's anchored traversal is still P1" "P1|" \
  "$(_review "src/x.js" 'const s = join(__dirname, "../shared/y.mjs");')"

# ── E-224.7: the strict rollback grades everything as code ─────────────────
assert_contains "E-224.07a: strict mode grades .ai/ prose too" "P0|" \
  "$(_review ".ai/DECISIONS.md" 'Ruling: keep P0 for `join(req.path, "../")` here.' strict)"

# ── E-224.8: generated records are not code ────────────────────────────────
# `.ai/state.json` stores every task DESCRIPTION verbatim, so an Architect writing
# "resolve ../shared/x" into a task registers a `../` in a committed file. Exact-path
# allowlist, NOT a `.json` rule — package.json scripts genuinely can carry paths.
assert_contains "E-224.08a: state.json task prose is not graded" "none|" \
  "$(_review ".ai/state.json" '      "description": "resolve ../shared/x.mjs from the script"')"
assert_contains "E-224.08b: package.json is still graded" "P0|" \
  "$(_review "package.json" '    "build": "node ../../tools/build.js"')"
assert_status 0 "E-224.08c: the allowlist is exact-path, not by extension" \
  bash -c "grep -q 'GENERATED_RECORDS = new Set(\[\".ai/state.json\"\])' '$MDX'"

# ── E-224.9: the fence walker is not fooled by nesting or indentation ──────
assert_contains "E-224.09a: an indented bash fence is still code" "P0|" \
  "$(_review "docs/g.md" '  ```bash
  cat "${INPUT}/../x"
  ```')"
assert_contains "E-224.09b: a tagged fence inside a fence does not close it" "P0|" \
  "$(_review "docs/g.md" '```bash
echo "```js"
cat "${INPUT}/../x"
```')"

rm -rf "$TMP"
assert_summary
