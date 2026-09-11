#!/usr/bin/env bash
# program_position_test.sh — E-234 (D-061 §2): only a PROGRAM position is a program.
#
# The E-225 walk scanned every operand of an interpreter, so a trailing DATA argument read
# as a program. `memory_curator.md` was blocked for six lines of the shape
#
#     node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-show .ai/memory/dlq.json
#
# where the program is correctly resolved through ${AIOS} and `.ai/memory/dlq.json` is an
# argument to a --dlq-show flag. `src/**/agents/*.md` IS in the rule's applies_to, so this
# blocked the next editor of that file at the commit gate.
#
# D-061 §2: a token is a program only in PROGRAM POSITION — the segment head, the first
# non-option operand after an interpreter, or the operand after a wrapper that RESTARTS
# program position (-c, eval, exec, xargs, env, sudo, nohup, time, command, source/.).
# Data-typed extensions are never programs in any position.
#
# WHY THE WALK STILL CONTINUES PAST THE FIRST OPERAND: because the first operand does not
# always RESOLVE the program. `node "$HELPER" src/bin/ai` hands over a variable this rule
# cannot read, and `bash tests/run.sh src/bin/ai` names an allowlisted entrypoint — in both
# the real target may still be further right, and D-061 keeps those caught. An unreadable
# or allowlisted operand therefore leaves program position OPEN; a resolved one closes it.
#
# Fixtures BOTH ways, written before the change (D-056 R3).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export CHECKER_URL="file://${REPO_ROOT}/src/shared/standards-checker.mjs"
export REPO_ROOT

echo "── Suite: program_position_test (E-234) ────────────────────────────"

# <line> [relPath] → HIT | MISS   (the E-231/E-225 locator rule)
_v() {
  MDLINE="$1" RELPATH="${2:-src/shared/skills/x/SKILL.md}" node --input-type=module -e '
    const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
    const rule = RULE_REGISTRY.skill_locator_install_first;
    const content = "---\nname: x\n---\n\n## Dynamic Context Injection\n" + process.env.MDLINE + "\n";
    const r = rule({ relPath: process.env.RELPATH, content, lines: content.split("\n"),
                     rule: { rule_id: "skill_locator_install_first" } });
    console.log(r ? "HIT" : "MISS");
  ' 2>/dev/null
}

# The consent rule (E-232) shares the same notion of "runs a program".
_vc() {
  MDLINE="$1" node --input-type=module -e '
    const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
    const rule = RULE_REGISTRY.skill_consent_no_project_exec;
    const content = "---\nname: x\n---\n\n## Dynamic Context Injection\n" + process.env.MDLINE + "\n";
    console.log(rule({ relPath: "src/shared/skills/x/SKILL.md", content }) ? "HIT" : "MISS");
  ' 2>/dev/null
}

# ── E-234.1: ARGUMENTS are not programs (the over-block being removed) ─────
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-234.01 allows: ${label}" "MISS" "$(_v "$line")"
done <<'CASES'
the memory_curator --dlq-show line|Ops: !node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-show .ai/memory/dlq.json
the memory_curator --dlq-clear line|Ops: !node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-clear .ai/memory/dlq.json
a .json argument to a resolved program|Ops: !node "${HOME}/.ai-os/shared/x.mjs" .ai/state.json
a .md argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" .ai/TASKS.md
a .yml argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" .github/workflows/test.yml
a .sqlite argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" .ai/state.sqlite
a .ndjson argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" .ai/incidents.ndjson
a .csv argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" data/rows.csv
a .log argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" build/out.log
a .txt argument|Ops: !node "${HOME}/.ai-os/shared/x.mjs" notes/todo.txt
data file after an absolute program|Ops: !node /usr/local/bin/tool.mjs src/config/registry.json
CASES

# ── E-234.2: PROGRAM POSITION is still caught (no catch is lost) ───────────
# Every one of these was caught before E-234 and must remain so. A narrowing that quietly
# drops a real catch is worse than the over-block it removes.
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-234.02 catches: ${label}" "HIT" "$(_v "$line")"
done <<'CASES'
bare interpreter + project path|Check: !node src/bin/ai doctor
first operand is the program|Check: !bash src/tool.sh
after an allowlisted entrypoint (position still open)|Check: !bash tests/run.sh src/bin/ai
after an unreadable variable (position still open)|Check: !node "$HELPER" src/bin/ai
bash -c restarts program position|Check: !bash -c "node src/bin/ai"
sh -c restarts program position|Check: !sh -c 'node src/bin/ai'
eval restarts program position|Check: !eval "bash src/bin/ai"
pipe-fed interpreter|Check: !cat src/bin/ai | bash
xargs-fed interpreter|Check: !ls src/shared/helper.mjs | xargs node
env restarts program position|Check: !env FOO=1 node src/bin/ai
command restarts program position|Check: !command node src/bin/ai
an .mjs program is still a program|Check: !node src/shared/evil.mjs
CASES

# ── E-234.3: a data extension is never a program, even in program position ─
# This is the strong half of the ruling: position alone does not make a .json a program,
# so an author cannot launder one by putting it first.
assert_contains "E-234.03a: a .json in program position is still not a program" "MISS" \
  "$(_v 'Check: !node .ai/state.json')"
assert_contains "E-234.03b: a .md in program position is not a program" "MISS" \
  "$(_v 'Check: !bash .ai/TASKS.md')"
# NON-VACUITY for 03: the same shape with an EXECUTABLE extension must still be caught,
# or 03 would pass simply because the rule had stopped looking at program position at all.
assert_contains "E-234.03c: but an .mjs in program position is (non-vacuity)" "HIT" \
  "$(_v 'Check: !node src/shared/x.mjs')"
assert_contains "E-234.03d: and an extension-less project path is (non-vacuity)" "HIT" \
  "$(_v 'Check: !node src/bin/ai')"

# ── E-234.4: the consent rule agrees — it shares the notion of "runs a program" ─
assert_contains "E-234.04a: consent allows a data argument" "MISS" \
  "$(_vc 'Ops: !node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-show .ai/memory/dlq.json')"
assert_contains "E-234.04b: consent still blocks a project program" "HIT" \
  "$(_vc 'Tests: !bash tests/run.sh')"
assert_contains "E-234.04c: consent still blocks npm run" "HIT" \
  "$(_vc 'Tests: !npm run test')"

# ── E-234.5: the rollback restores the full walk ──────────────────────────
assert_contains "E-234.05a: AI_OS_STANDARDS_SKIP=program-position restores the old walk" "HIT" \
  "$(AI_OS_STANDARDS_SKIP=program-position _v 'Ops: !node "${AIOS}/shared/memory-worker-pool.mjs" --dlq-show .ai/memory/dlq.json')"

# ── E-234.6: the real file passes, and the corpus is clean ────────────────
# The acceptance criterion, checked against the FILE rather than a reconstruction of it.
_mc() {
  node --input-type=module -e '
    const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
    const { readFileSync } = await import("fs");
    const rule = RULE_REGISTRY.skill_locator_install_first;
    const f = process.argv[1];
    const c = readFileSync(process.env.REPO_ROOT + "/" + f, "utf8");
    const r = rule({ relPath: f, content: c, lines: c.split("\n"),
                     rule: { rule_id: "skill_locator_install_first" } });
    console.log(r ? r.length : 0);
  ' "$1" 2>/dev/null
}
assert_contains "E-234.06a: src memory_curator.md passes unchanged" "0" \
  "$(_mc src/gemini/agents/memory_curator.md)"
assert_contains "E-234.06b: the .claude mirror passes too" "0" \
  "$(_mc .claude/agents/memory_curator.md)"

_CORPUS_FILE="$(test_tmpdir e234-corpus)/corpus.txt"
_corpus_list="$(cd "$REPO_ROOT" && corpus_or_fail 100 src .claude \
                 -- -name node_modules -prune -o -name "*.md" -print)"
_corpus_rc=$?
printf '%s\n' "$_corpus_list" > "$_CORPUS_FILE"

# THE CORPUS STEP IS ITSELF AN ASSERTION (E-251, D-067 §5). Everything below reports on
# this list; if it is empty or short, "no findings" is a statement about nothing. The roots
# are NAMED and REQUIRED rather than filtered for existence — filtering is how the corpus
# silently shrank to zero in the first place.
assert_status 0 "E-234.06c: the corpus was BUILT — roots present, count above the floor" \
  bash -c "[[ '${_corpus_rc}' -eq 0 ]]"

_corpus() {
  CORPUS_FILE="$_CORPUS_FILE" node --input-type=module -e '
    const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
    const { readFileSync } = await import("fs");
    const rule = RULE_REGISTRY.skill_locator_install_first;
    // E-251 (D-067 §5): the corpus arrives as a FILE built by corpus_or_fail in the shell.
    // It used to be built here, by shelling out to `find` over roots that may not exist —
    // and when two of them stopped being provisioned, `find` exited non-zero, execSync
    // threw, and the corpus came back EMPTY. Zero files report zero findings, so this scan
    // would have gone on announcing "clean" forever. The corpus step now fails loudly
    // instead, and this code reads a list it did not have to guess at.
    const files = readFileSync(process.env.CORPUS_FILE, "utf8")
      .split("\n").map(s => s.trim()).filter(Boolean);
    let n = 0;
    for (const f of files) {
      let c; try { c = readFileSync(process.env.REPO_ROOT + "/" + f, "utf8"); } catch { continue; }
      const r = rule({ relPath: f, content: c, lines: c.split("\n"),
                       rule: { rule_id: "skill_locator_install_first" } });
      if (r) n += r.length;
    }
    console.log(files.length + " " + n);
  ' 2>/dev/null
}
_scan="$(_corpus)"; _files="${_scan%% *}"; _found="${_scan##* }"
assert_status 0 "E-234.06d: the whole corpus is now clean (files=${_files}, found=${_found})" \
  bash -c "[[ '${_found:-99}' -eq 0 ]]"
# The corpus gate proves the LIST is long enough; this proves the SCANNER read that same
# list. Without it, a scanner that silently read an empty CORPUS_FILE would still report
# "clean" — the very shape E-251 exists to close, one layer further in.
_corpus_n="$(printf '%s\n' "$_corpus_list" | grep -c . || true)"
assert_contains "E-234.06e: the scanner read the whole corpus (${_corpus_n} files)" \
  "${_corpus_n}" "${_files}"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== program_position_test.sh PASS ====="
else
  echo "===== program_position_test.sh FAIL (${FAIL_COUNT}) ====="
fi
