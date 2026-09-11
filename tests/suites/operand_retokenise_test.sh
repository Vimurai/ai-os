#!/usr/bin/env bash
# operand_retokenise_test.sh — E-231 (D-060 §2): re-tokenise a code operand.
#
# Two indirections put a project path beyond the E-225 operand walk, both recorded in
# THREAT_MODEL as KNOWN UNCAUGHT rather than left to be re-found later as bugs:
#
#     bash -c "node src/bin/ai"    the interpreter is INSIDE a quoted operand
#     cat src/bin/ai | bash        the program arrives on stdin, left of the pipe
#
# What kept them invisible is worth stating: an `.mjs`/`.sh` target is still caught by the
# rule's second signal, so ONLY an extension-less target such as `src/bin/ai` ever slipped
# through — which is why the shipped corpus contains none of these shapes and the gap
# stayed theoretical.
#
# D-060 §2 called this "the change most likely to resurrect an over-block" and required
# fixtures in BOTH directions FIRST. The allow half below is therefore the point of this
# suite, not its afterthought: any new hit there is a REGRESSION, not a finding. Writing
# these before the change earned its keep immediately — the first implementation passed
# every catch case and broke `bash -c "node \"${HOME}/…\""`, because inside a double-quoted
# operand a nested quote arrives escaped, so the token began with a backslash and defeated
# the "variable we cannot read" test.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export CHECKER_URL="file://${REPO_ROOT}/src/shared/standards-checker.mjs"

echo "── Suite: operand_retokenise_test (E-231) ──────────────────────────"

# <line> [relPath] → HIT | MISS
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

# ── E-231.1: the indirections must now be caught ───────────────────────────
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-231.01 catches: ${label}" "HIT" "$(_v "$line")"
done <<'CASES'
bash -c double quoted|Check: !bash -c "node src/bin/ai"
sh -c single quoted|Check: !sh -c 'node src/bin/ai'
zsh -c|Check: !zsh -c "node src/shared/helper.mjs"
ksh -c|Check: !ksh -c "bash src/tool.sh"
eval|Check: !eval "bash src/bin/ai"
bash -c nested source|Check: !bash -c ". src/shared/locate.sh"
bash -c with an extension|Check: !bash -c "node src/shared/evil.mjs"
pipe-fed bash|Check: !cat src/bin/ai | bash
pipe-fed sh|Check: !cat src/shared/x.mjs | sh
xargs node|Check: !ls src/shared/helper.mjs | xargs node
bash -c after a label|Failing: !bash -c "node src/bin/ai" || echo none
CASES

# ── E-231.2: OVER-BLOCK GUARD — the half that breaks when a rule is widened ─
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-231.02 allows: ${label}" "MISS" "$(_v "$line")"
done <<'CASES'
bash -c with no path at all|Check: !bash -c "echo hello"
bash -c npm query|Check: !bash -c "npm outdated"
bash -c absolute path|Check: !bash -c "node /usr/local/bin/tool.mjs"
bash -c home-anchored path|Check: !bash -c "node ~/.ai-os/shared/x.mjs"
bash -c resolver call|Check: !bash -c "ai_os_locate shared/incident.mjs"
bash -c allowlisted suite|Check: !bash -c "bash tests/run.sh"
bash -c variable operand|Check: !bash -c "node \"$HELPER\""
eval of a command substitution|Check: !eval "$(command -v node)"
plain git inspection|Check: !git diff --name-only | head -10
a doc piped to head|Check: !cat README.md | head -20
grep of a .ai file|Check: !grep "^- \[ \]" .ai/TASKS.md
xargs without an interpreter|Check: !ls *.md | xargs -n1 echo
find without -exec|Check: !find . -name "*.mjs" | head
python3 inline code only|Check: !python3 -c "print(1)"
CASES

# The escaped-quote case, spelled out because it is the regression this suite caught.
# Inside `bash -c "..."` a nested quote is written \" , so the operand token begins with a
# BACKSLASH — not a `$` — and the "variable we cannot read" test missed it.
_esc='Check: !bash -c "node \"${HOME}/.ai-os/shared/x.mjs\""'
assert_contains "E-231.02 allows: bash -c with an escaped \${HOME} path (the caught regression)" \
  "MISS" "$(_v "$_esc")"

# ── E-231.3: PROSE is documentation, not code (D-060 §2 names this) ────────
assert_contains "E-231.03a: prose quoting bash -c is not graded as code" "MISS" \
  "$(_v 'Never write `bash -c "node src/bin/ai"` in a skill.' '.ai/THREAT_MODEL.md')"
assert_contains "E-231.03b: prose quoting eval is not graded as code" "MISS" \
  "$(_v 'Avoid `eval "bash src/bin/ai"` — it hides the target.' '.ai/DECISIONS.md')"

# ── E-231.4: recursion is capped at depth 1, and that is deliberate ────────
# Deeper nesting buys shapes nobody writes and adds another chance to invent a finding.
# Asserted so the cap is a DECISION on the record rather than an accident someone
# "fixes" later without noticing the trade.
assert_contains "E-231.04a: depth 1 is caught" "HIT" \
  "$(_v 'Check: !bash -c "node src/bin/ai"')"
assert_contains "E-231.04b: depth 2 is NOT caught (documented cap, not an oversight)" "MISS" \
  "$(_v 'Check: !bash -c "bash -c \"node src/bin/ai\""')"

# ── E-231.5: still-uncaught shapes, asserted as uncaught ───────────────────
# Recorded so the rule's silence is never mistaken for a clean bill, and so that anyone
# who closes one of these sees this suite fail and updates THREAT_MODEL with it.
assert_contains "E-231.05a: find -exec (target is {}) remains uncaught" "MISS" \
  "$(_v 'Check: !find . -name "*.mjs" -exec node {} \;')"
assert_contains "E-231.05b: extension-less bare word remains uncaught (E-225 trade-off)" "MISS" \
  "$(_v 'Check: !bash setup')"
assert_contains "E-231.05c: heredoc-fed interpreter remains uncaught (spans lines)" "MISS" \
  "$(_v 'Check: !node <<"EOF"')"

# ── E-231.6: the shipped corpus gains no new findings ─────────────────────
# The number that matters is DELTA against the pre-E-231 rule, not the absolute count:
# six pre-existing hits in memory_curator.md (a `.json` DATA argument read as a program)
# are unrelated to this change and are recorded in THREAT_MODEL.
_CORPUS_FILE="$(test_tmpdir e231-corpus)/corpus.txt"
_corpus_list="$(cd "$REPO_ROOT" && corpus_or_fail 100 src .claude \
                 -- -name node_modules -prune -o -name "*.md" -print)"
_corpus_rc=$?
printf '%s\n' "$_corpus_list" > "$_CORPUS_FILE"

# THE CORPUS STEP IS ITSELF AN ASSERTION (E-251, D-067 §5). Everything below reports on
# this list; if it is empty or short, "no findings" is a statement about nothing. The roots
# are NAMED and REQUIRED rather than filtered for existence — filtering is how the corpus
# silently shrank to zero in the first place.
assert_status 0 "E-231.06a: the corpus was BUILT — roots present, count above the floor" \
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
export REPO_ROOT
_scan="$(_corpus)"; _files="${_scan%% *}"; _found="${_scan##* }"
# Tightened by E-234 (D-061 §2): the six pre-existing memory_curator hits were a DATA
# argument read as a program, and the program-position rule removed them. The corpus is
# now genuinely clean, so assert 0 rather than "at most 6" — a ceiling that no longer
# binds would let a real new finding slip in under it.
assert_status 0 "E-231.06b: the corpus has NO findings (found=${_found})" \
  bash -c "[[ '${_found:-99}' -eq 0 ]]"
# The corpus gate proves the LIST is long enough; this proves the SCANNER read that same
# list. Without it, a scanner that silently read an empty CORPUS_FILE would still report
# "clean" — the very shape E-251 exists to close, one layer further in.
_corpus_n="$(printf '%s\n' "$_corpus_list" | grep -c . || true)"
assert_contains "E-231.06c: the scanner read the whole corpus (${_corpus_n} files)" \
  "${_corpus_n}" "${_files}"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== operand_retokenise_test.sh PASS ====="
else
  echo "===== operand_retokenise_test.sh FAIL (${FAIL_COUNT}) ====="
fi
