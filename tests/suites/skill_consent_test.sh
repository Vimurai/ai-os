#!/usr/bin/env bash
# skill_consent_test.sh — E-232 (D-060 §3): a `!`-line may inspect, never execute.
#
# A `!`-prefixed line in a SKILL.md or agents/*.md file is run by the harness the moment
# the file LOADS — before the agent has decided anything and before the operator has been
# asked. `ai-debug` opened with `!bash tests/run.sh`, so merely loading the debugging
# skill executed the VISITED project's test script. `ai-upgrade` did the same via
# `!npm run test`, which the threat model had recorded as "agent-initiated"; it is not.
#
# The rule is a DENYLIST of execution shapes, not an allowlist of safe commands, and the
# assertions below are weighted accordingly: over-blocking would reject every ordinary
# `git`/`grep` inspection line a skill author writes next, so each catch case is paired
# with cases that must NOT fire. The distinction the rule encodes is EXECUTION, not
# mention: `npm outdated` and `npm audit` query the manifest and registry and run none of
# the project's own code, so they stay allowed.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECKER="${REPO_ROOT}/src/shared/standards-checker.mjs"

echo "── Suite: skill_consent_test (E-232) ────────────────────────────────"

# <line> → "HIT" | "MISS"
_verdict() {
  # DYNAMIC import: a static `import ... from process.env.X` is a syntax error — the
  # specifier must be a literal — and node then printed nothing, so every case using this
  # helper failed identically and said only "expected to contain: MISS".
  MDLINE="$1" node --input-type=module -e '
    const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
    const rule = RULE_REGISTRY.skill_consent_no_project_exec;
    const content = "---\nname: x\n---\n\n## Dynamic Context Injection\n" + process.env.MDLINE + "\n";
    const r = rule({ relPath: "src/shared/skills/x/SKILL.md", content });
    console.log(r ? "HIT" : "MISS");
  ' 2>/dev/null
}
export CHECKER_URL="file://${CHECKER}"

# ── E-232.1: executions that MUST be caught ─────────────────────────────────
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-232.01 catches: ${label}" "HIT" "$(_verdict "$line")"
done <<'CASES'
bash tests/run.sh|Failing tests: !bash tests/run.sh 2>&1 | grep x
npm run test|Status: !npm run test 2>&1 | tail -1
yarn test|Status: !yarn test
pnpm run build|Build: !pnpm run build
make|Build: !make all
npx|Lint: !npx eslint .
./relative script|Run: !./repro.sh
scripts/ path|Setup: !scripts/setup.sh
node on src/|Check: !node src/bin/ai doctor
python3 on scripts/|Gen: !python3 scripts/gen.py
hidden after a pipe|Tests: !git status | bash tests/run.sh
hidden after &&|Tests: !git status && bash tests/run.sh
CASES

# ── E-232.2: OVER-BLOCK GUARD — ordinary inspection must still be allowed ───
# Every one of these appears in the shipped corpus. If the rule fires on any of them it
# has stopped being a consent check and become a ban on dynamic context.
while IFS='|' read -r label line; do
  [[ -z "$label" ]] && continue
  assert_contains "E-232.02 allows: ${label}" "MISS" "$(_verdict "$line")"
done <<'CASES'
git diff|Recent changes: !git diff --name-only | head -10
git log|Recent commits: !git log --oneline -10 || echo none
grep .ai/TASKS.md|Open tasks: !grep "^- \[ \]" .ai/TASKS.md || echo none
cat .ai file|Scope: !cat .ai/CAPABILITIES.md 2>/dev/null || echo none
npm outdated (query only)|Packages: !npm outdated 2>/dev/null || echo none
npm audit (query only)|Vulns: !npm audit --json 2>/dev/null | jq .x || echo 0
date|Today: !date "+%Y-%m-%d"
echo env var|Target: !echo "${TARGET:-(not set)}"
wc on .ai|Lines: !wc -l < .ai/SESSION.md || echo 0
find workflows|CI: !find . -name "*.yml" -path "*/.github/workflows/*" | head
command -v probe|Copilot: !command -v gh &>/dev/null && echo yes || echo no
test -d|Archive: !test -d .ai/archive && echo YES || echo NO
ls listing|Structure: !ls -1 . | head -20
python3 inline code|Next: !python3 -c "print(1)"
framework helper via resolver|Agg: !node "${HOME}/.ai-os/shared/incident-aggregate.mjs" || echo none
CASES

# ── E-232.3: the shipped corpus is clean, and the scan is not vacuous ───────
_corpus_violations() {
  node --input-type=module -e '
    const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
    const { readFileSync } = await import("fs");
    const { execSync } = await import("child_process");
    const rule = RULE_REGISTRY.skill_consent_no_project_exec;
    const out = execSync("find src .claude .agents .gemini -name \"SKILL.md\" -o -path \"*/agents/*.md\" 2>/dev/null",
      { encoding: "utf8", maxBuffer: 1e8, cwd: process.env.REPO_ROOT });
    const files = out.trim().split("\n").filter(Boolean);
    let hits = 0;
    for (const f of files) {
      let c; try { c = readFileSync(process.env.REPO_ROOT + "/" + f, "utf8"); } catch { continue; }
      if (rule({ relPath: f, content: c })) hits++;
    }
    console.log(files.length + " " + hits);
  ' 2>/dev/null
}
export REPO_ROOT
_scan="$(_corpus_violations)"
_files="${_scan%% *}"; _hits="${_scan##* }"
# NON-VACUITY: a scan that found no files would report zero violations just as loudly.
assert_status 0 "E-232.03a: the corpus scan actually read files (files=${_files})" \
  bash -c "[[ '${_files:-0}' -gt 100 ]]"
assert_status 0 "E-232.03b: no shipped skill or agent auto-executes a project program" \
  bash -c "[[ '${_hits:-1}' -eq 0 ]]"

# ── E-232.4: the three converted skills kept their capability, as STEPS ────
# Removing the `!` line must not remove the ability — otherwise this "fix" is a deletion.
for f in src/shared/skills/ai-debug/SKILL.md \
         src/claude/skills/bug-reproducer/SKILL.md \
         src/shared/skills/ai-upgrade/SKILL.md; do
  assert_status 0 "E-232.04: ${f##*/} ($(dirname "$f" | xargs basename)) still instructs the agent to run the suite" \
    grep -q "Step 0" "${REPO_ROOT}/$f"
done
assert_status 0 "E-232.04b: ai-debug still names the project's test command" \
  grep -q "tests/run.sh" "${REPO_ROOT}/src/shared/skills/ai-debug/SKILL.md"
assert_status 0 "E-232.04c: ai-upgrade still names npm run test" \
  grep -q "npm run test" "${REPO_ROOT}/src/shared/skills/ai-upgrade/SKILL.md"

# ── E-232.5: mirrors are byte-identical ────────────────────────────────────
assert_status 0 "E-232.05a: ai-debug .claude mirror matches src" \
  diff -q "${REPO_ROOT}/src/shared/skills/ai-debug/SKILL.md" "${REPO_ROOT}/.claude/skills/ai-debug/SKILL.md"
assert_status 0 "E-232.05b: ai-debug .agents mirror matches src" \
  diff -q "${REPO_ROOT}/src/shared/skills/ai-debug/SKILL.md" "${REPO_ROOT}/.agents/skills/ai-debug/SKILL.md"
assert_status 0 "E-232.05c: ai-upgrade .claude mirror matches src" \
  diff -q "${REPO_ROOT}/src/shared/skills/ai-upgrade/SKILL.md" "${REPO_ROOT}/.claude/skills/ai-upgrade/SKILL.md"
assert_status 0 "E-232.05d: bug-reproducer .claude mirror matches src" \
  diff -q "${REPO_ROOT}/src/claude/skills/bug-reproducer/SKILL.md" "${REPO_ROOT}/.claude/skills/bug-reproducer/SKILL.md"

# ── E-232.6: the rule is registered, and has a rollback ────────────────────
assert_status 0 "E-232.06a: registered in standards.json" \
  grep -q "skill_consent_no_project_exec" "${REPO_ROOT}/src/shared/standards.json"
assert_contains "E-232.06b: AI_OS_STANDARDS_SKIP=skill-consent disables it" "MISS" \
  "$(AI_OS_STANDARDS_SKIP=skill-consent _verdict 'Failing tests: !bash tests/run.sh')"

echo ""
assert_summary
# Only claim PASS if it actually passed. Several suites print this banner unconditionally,
# so a failing run still ends with the word PASS on screen; the runner reads SUITE_RESULT
# and is unaffected, but a human reading the log is misled.
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== skill_consent_test.sh PASS ====="
else
  echo "===== skill_consent_test.sh FAIL (${FAIL_COUNT}) ====="
fi
