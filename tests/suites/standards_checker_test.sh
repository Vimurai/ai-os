#!/usr/bin/env bash
# standards_checker_test.sh — Tests for E-80 standards.json + standards-checker CLI.
#
# Verifies the implementation against .ai/blueprints/engineering-standards.md:
#
#   - standards.json conforms to the §Data Model (rule_id, severity,
#     threshold, description, auto_fix_available)
#   - validateFile / validateStaged / validateStandards exported from
#     src/shared/standards-checker.mjs return well-typed ComplianceReports
#   - Every rule_id in standards.json has a registered handler
#   - Each rule fires only on its applies_to pattern (path scoping)
#   - The CLI exits 0/1/2 per the documented contract
#   - --json output is parseable + carries the full envelope
#   - AI_OS_SKIP_STANDARDS=1 short-circuits (§Rollback Plan)
#   - Performance budget < 200ms on a 10-file synthetic check
#   - ~/.ai-os mirrors byte-identical

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STANDARDS_JSON="${REPO_ROOT}/src/shared/standards.json"
CHECKER="${REPO_ROOT}/src/shared/standards-checker.mjs"
CLI="${REPO_ROOT}/scripts/standards.mjs"

echo "===== standards_checker_test.sh ====="

# ── T-STD-S01: standards.json schema integrity ──────────────────────────────
echo ""
echo "  [T-STD-S01] standards.json conforms to the §Data Model"

assert_status 0 "standards.json exists"               test -f "$STANDARDS_JSON"
assert_status 0 "standards.json is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('$STANDARDS_JSON','utf8'))"
assert_status 0 "loadStandards() returns rules array" \
  node --input-type=module -e "
    const m = await import('file://${CHECKER}');
    const s = m.loadStandards();
    process.exit(Array.isArray(s.rules) && s.rules.length > 0 ? 0 : 1);
  "
assert_status 0 "every rule has rule_id + severity + description + auto_fix_available" \
  node --input-type=module -e "
    const m = await import('file://${CHECKER}');
    const s = m.loadStandards();
    const ok = s.rules.every(r =>
      typeof r.rule_id === 'string' && r.rule_id.length > 0 &&
      ['info','warning','error'].includes(r.severity) &&
      typeof r.description === 'string' && r.description.length > 0 &&
      typeof r.auto_fix_available === 'boolean');
    process.exit(ok ? 0 : 1);
  "

# ── T-STD-S02: Every rule_id has a registered handler ───────────────────────
echo ""
echo "  [T-STD-S02] RULE_REGISTRY covers every rule_id"

assert_status 0 "every rule_id maps to a function in RULE_REGISTRY" \
  node --input-type=module -e "
    const m = await import('file://${CHECKER}');
    const s = m.loadStandards();
    const missing = s.rules.filter(r => typeof m.RULE_REGISTRY[r.rule_id] !== 'function');
    if (missing.length) { console.error('missing:', missing.map(r=>r.rule_id)); process.exit(1); }
    process.exit(0);
  "

# Confirm the six expected rule ids are present.
for rid in file_size_limit_lines mcp_stdout_purity no_committed_tmp_files \
           kebab_case_filenames no_secrets_in_diff mandatory_shared_helper; do
  assert_status 0 "rule_id present: ${rid}" \
    bash -c "node -e \"const s=require('${STANDARDS_JSON}'); process.exit(s.rules.some(r=>r.rule_id==='${rid}')?0:1)\""
done

# ── Set up a sandboxed git repo for behavioural tests ───────────────────────
SBOX="$(mktemp -d -t e80-XXXXXX)"
on_exit 'rm -rf "$SBOX"'
PROJ="${SBOX}/proj"
mkdir -p "${PROJ}/src/mcp/foo" "${PROJ}/src/shared" "${PROJ}/scripts"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email "t@t"
git -C "$PROJ" config user.name "tester"

# Helper: run validateFile against an absolute path with the real rules.
_validate_file() {
  node --input-type=module -e "
    const m = await import('file://${CHECKER}');
    const rules = m.loadStandards().rules;
    const r = m.validateFile('$1', rules, { repoRoot: '${PROJ}' });
    console.log(JSON.stringify(r));
  " 2>/dev/null
}

# ── T-STD-S03: file_size_limit_lines triggers on >1000 lines ────────────────
echo ""
echo "  [T-STD-S03] file_size_limit_lines fires at >1000 lines (error) and >500 (warn)"

# 1100-line synthetic source file under src/.
python3 -c "print('let x = 1;\n' * 1100)" > "${PROJ}/src/big.mjs"
out="$(_validate_file "${PROJ}/src/big.mjs")"
assert_status 0 "1100-line file → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"file_size_limit_lines\",\"severity\":\"error\"'"
assert_status 0 "report status = FAIL" \
  bash -c "echo '$out' | grep -q '\"status\":\"FAIL\"'"

# 600-line file → warn-only.
python3 -c "print('let x = 1;\n' * 600)" > "${PROJ}/src/medium.mjs"
out="$(_validate_file "${PROJ}/src/medium.mjs")"
assert_status 0 "600-line file → warning" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"file_size_limit_lines\",\"severity\":\"warning\"'"
assert_status 0 "report status = WARN" \
  bash -c "echo '$out' | grep -q '\"status\":\"WARN\"'"

# 50-line file → PASS.
python3 -c "print('let x = 1;\n' * 50)" > "${PROJ}/src/small.mjs"
out="$(_validate_file "${PROJ}/src/small.mjs")"
assert_status 0 "50-line file → PASS"   bash -c "echo '$out' | grep -q '\"status\":\"PASS\"'"

# ── T-STD-S04: mcp_stdout_purity scoped to src/mcp/** only ──────────────────
echo ""
echo "  [T-STD-S04] mcp_stdout_purity refuses console.log under src/mcp/** only"

cat > "${PROJ}/src/mcp/foo/dirty.js" <<'JS'
function go() { console.log('boom'); }
JS
out="$(_validate_file "${PROJ}/src/mcp/foo/dirty.js")"
assert_status 0 "console.log in src/mcp/** → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"mcp_stdout_purity\",\"severity\":\"error\"'"

# Same line content but path OUTSIDE src/mcp/ should NOT trigger the rule.
cat > "${PROJ}/src/shared/clean.js" <<'JS'
function go() { console.log('this is fine outside mcp'); }
JS
out="$(_validate_file "${PROJ}/src/shared/clean.js")"
assert_status 1 "console.log outside src/mcp/** does NOT fire mcp_stdout_purity" \
  bash -c "echo '$out' | grep -q 'mcp_stdout_purity'"

# Comment-wrapped console.log should be tolerated.
cat > "${PROJ}/src/mcp/foo/commented.js" <<'JS'
// console.log('still allowed inside a comment')
/* console.log('block-comment fine too') */
function go() {}
JS
out="$(_validate_file "${PROJ}/src/mcp/foo/commented.js")"
assert_status 1 "commented console.log does NOT trigger purity rule" \
  bash -c "echo '$out' | grep -q 'mcp_stdout_purity'"

# ── T-STD-S05: no_committed_tmp_files ───────────────────────────────────────
echo ""
echo "  [T-STD-S05] no_committed_tmp_files rejects editor cruft"

cat > "${PROJ}/src/leftover.tmp" <<<"junk"
out="$(_validate_file "${PROJ}/src/leftover.tmp")"
assert_status 0 ".tmp file → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"no_committed_tmp_files\"'"

cat > "${PROJ}/src/scratch.bak" <<<"junk"
out="$(_validate_file "${PROJ}/src/scratch.bak")"
assert_status 0 ".bak file → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"no_committed_tmp_files\"'"

# ── T-STD-S06: kebab_case_filenames warns on bad names ──────────────────────
echo ""
echo "  [T-STD-S06] kebab_case_filenames warns on Mixed_Snake names"

cat > "${PROJ}/src/My_Bad_File.mjs" <<<"export const x = 1;"
out="$(_validate_file "${PROJ}/src/My_Bad_File.mjs")"
assert_status 0 "My_Bad_File.mjs → warning" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"kebab_case_filenames\",\"severity\":\"warning\"'"

# kebab-case + camelCase + PascalCase are all accepted.
for name in good-name.mjs goodName.mjs GoodName.mjs ALLOK.mjs; do
  cat > "${PROJ}/src/${name}" <<<"export const x = 1;"
  out="$(_validate_file "${PROJ}/src/${name}")"
  assert_status 1 "${name} accepted (no kebab_case_filenames warn)" \
    bash -c "echo '$out' | grep -q 'kebab_case_filenames'"
done

# ── T-STD-S07: no_secrets_in_diff fires on canonical secret patterns ────────
echo ""
echo "  [T-STD-S07] no_secrets_in_diff fires on canonical secret patterns"

cat > "${PROJ}/src/leaky-aws.mjs" <<'JS'
// Test fixture (NOT a real key)
const k = "AKIAIOSFODNN7EXAMPLE";
JS
out="$(_validate_file "${PROJ}/src/leaky-aws.mjs")"
assert_status 0 "AWS access-key pattern → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"no_secrets_in_diff\"'"

cat > "${PROJ}/src/leaky-stripe.mjs" <<'JS'
const k = "sk_live_4eC39HqLyjWDarjtT1zdp7dc";
JS
out="$(_validate_file "${PROJ}/src/leaky-stripe.mjs")"
assert_status 0 "Stripe live-key pattern → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"no_secrets_in_diff\"'"

cat > "${PROJ}/src/private-key.mjs" <<'JS'
const pem = "-----BEGIN RSA PRIVATE KEY-----\n...";
JS
out="$(_validate_file "${PROJ}/src/private-key.mjs")"
assert_status 0 "PRIVATE KEY block pattern → error" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"no_secrets_in_diff\"'"

# Sanity: a generic string with no secret pattern is fine.
cat > "${PROJ}/src/no-secret.mjs" <<'JS'
const greeting = "hello world";
JS
out="$(_validate_file "${PROJ}/src/no-secret.mjs")"
assert_status 1 "regular file does NOT trigger no_secrets_in_diff" \
  bash -c "echo '$out' | grep -q 'no_secrets_in_diff'"

# E-82 hotfix: tests/** is exempted via applies_to_excludes — fixtures
# document the very patterns the rule detects, so refusing to scan them
# is the documented behaviour (commit blocked by self-trip otherwise).
mkdir -p "${PROJ}/tests/suites"
cat > "${PROJ}/tests/suites/sample_test.sh" <<'BASH'
# fixture: AKIAIOSFODNN7EXAMPLE — should NOT trip the gate from a tests/** path
BASH
out="$(_validate_file "${PROJ}/tests/suites/sample_test.sh")"
assert_status 1 "tests/** path exempt from no_secrets_in_diff" \
  bash -c "echo '$out' | grep -q 'no_secrets_in_diff'"
# Same pattern in src/** STILL trips — proves the exclude is path-scoped.
cat > "${PROJ}/src/leaky-again.mjs" <<'JS'
const k = "AKIAIOSFODNN7EXAMPLE";
JS
out="$(_validate_file "${PROJ}/src/leaky-again.mjs")"
assert_status 0 "src/** path STILL trips no_secrets_in_diff" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"no_secrets_in_diff\"'"

# ── T-STD-S08: mandatory_shared_helper warns on raw node:sqlite import ──────
echo ""
echo "  [T-STD-S08] mandatory_shared_helper warns on raw node:sqlite imports"

cat > "${PROJ}/src/mcp/foo/raw-sqlite.js" <<'JS'
import { DatabaseSync } from "node:sqlite";
JS
out="$(_validate_file "${PROJ}/src/mcp/foo/raw-sqlite.js")"
assert_status 0 "raw node:sqlite import → warning" \
  bash -c "echo '$out' | grep -q '\"rule_id\":\"mandatory_shared_helper\"'"

# Same import but OUTSIDE src/mcp/** → no warning (helpers themselves use it).
cat > "${PROJ}/src/shared/wal-thing.mjs" <<'JS'
import { DatabaseSync } from "node:sqlite";
JS
out="$(_validate_file "${PROJ}/src/shared/wal-thing.mjs")"
assert_status 1 "node:sqlite in src/shared/** does NOT warn" \
  bash -c "echo '$out' | grep -q 'mandatory_shared_helper'"

# ── T-STD-S09: validateStaged integrates `git diff --cached` ────────────────
echo ""
echo "  [T-STD-S09] validateStaged reads the staged set"

# Stage a clean file + a dirty file (.tmp).
echo 'export const x = 1' > "${PROJ}/src/staged-ok.mjs"
echo 'temp data' > "${PROJ}/src/staged.tmp"
git -C "$PROJ" add src/staged-ok.mjs src/staged.tmp

staged_out="$(node --input-type=module -e "
  const m = await import('file://${CHECKER}');
  const rules = m.loadStandards().rules;
  const envelope = m.validateStaged('${PROJ}', rules);
  console.log(JSON.stringify(envelope));
" 2>/dev/null)"

assert_status 0 "validateStaged reports both staged files" \
  bash -c "echo '$staged_out' | grep -q '\"files_checked\":2'"
assert_status 0 "validateStaged surfaces the .tmp error" \
  bash -c "echo '$staged_out' | grep -q 'no_committed_tmp_files'"
assert_status 0 "validateStaged summary.error_count >= 1" \
  bash -c "echo '$staged_out' | python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin)[\"summary\"][\"error_count\"] >= 1 else 1)'"

# ── T-STD-S10: Performance budget — <200ms on a 10-file synthetic set ───────
echo ""
echo "  [T-STD-S10] validateStaged completes within the 200ms budget"

for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "export const x${i} = ${i}" > "${PROJ}/src/perf-${i}.mjs"
  git -C "$PROJ" add "src/perf-${i}.mjs"
done
elapsed="$(node --input-type=module -e "
  const m = await import('file://${CHECKER}');
  const rules = m.loadStandards().rules;
  const r = m.validateStaged('${PROJ}', rules);
  console.log(r.summary.elapsed_ms);
" 2>/dev/null)"
assert_status 0 "elapsed_ms <= 500ms (generous CI floor)" bash -c "[[ ${elapsed:-9999} -le 500 ]]"

# ── T-STD-S11: CLI exit codes + --json output shape ────────────────────────
echo ""
echo "  [T-STD-S11] CLI exit code contract: PASS=0, error=1, usage=2"

# `check --file` on a clean file → exit 0.
( cd "$PROJ" && node "$CLI" check --file src/staged-ok.mjs >/dev/null 2>&1 )
assert_status 0 "clean file → exit 0" bash -c "[[ $? -eq 0 ]]"

# `check --file` on the .tmp file → exit 1.
( cd "$PROJ" && node "$CLI" check --file src/staged.tmp >/dev/null 2>&1 )
rc=$?
assert_status 0 "error-grade violation → exit 1" bash -c "[[ $rc -eq 1 ]]"

# Unknown subcommand → exit 2.
( cd "$PROJ" && node "$CLI" bogus >/dev/null 2>&1 )
rc=$?
assert_status 0 "unknown subcommand → exit 2" bash -c "[[ $rc -eq 2 ]]"

# `--json` mode produces parseable JSON on stdout.
json_out="$( ( cd "$PROJ" && node "$CLI" check --file src/staged-ok.mjs --json ) 2>/dev/null)"
assert_status 0 "--json output parses cleanly" \
  bash -c "echo '$json_out' | python3 -c 'import json, sys; json.loads(sys.stdin.read())'"

# `list-rules --json` round-trips the standards.json shape.
# E-250: the JSON is piped, never interpolated into a quoted shell string. It used to be
# embedded as \$list_json, so the first apostrophe in any rule description or
# exemption reason closed the quote and the assertion failed on the CONTENT of
# standards.json rather than on its shape — which is what happened when a reason
# containing "rule's scope" was added.
list_json="$(node "$CLI" list-rules --json 2>/dev/null)"
_lj_file="$(test_tmpdir std-json)/list.json"
printf '%s' "$list_json" > "$_lj_file"
assert_status 0 "list-rules --json parses + carries rules[]" \
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get("rules"), list) and len(d["rules"]) >= 6 else 1)' "$_lj_file"

# ── T-STD-S12: AI_OS_SKIP_STANDARDS=1 rollback path ─────────────────────────
echo ""
echo "  [T-STD-S12] AI_OS_SKIP_STANDARDS=1 short-circuits the gate"

stderr_out="$( ( cd "$PROJ" && AI_OS_SKIP_STANDARDS=1 node "$CLI" check --file src/staged.tmp ) 2>&1 >/dev/null )"
rc=$?
assert_status 0 "skip flag → exit 0 (even on would-be error)" bash -c "[[ $rc -eq 0 ]]"
assert_status 0 "stderr carries STANDARDS_SKIPPED marker" \
  bash -c "echo '$stderr_out' | grep -q 'STANDARDS_SKIPPED'"

# ── T-STD-S13: reportDrift envelope shape ──────────────────────────────────
echo ""
echo "  [T-STD-S13] reportDrift returns the §API drift envelope"

drift_json="$(node --input-type=module -e "
  const m = await import('file://${CHECKER}');
  const rules = m.loadStandards().rules;
  const env = m.validateFiles(['${PROJ}/src/staged.tmp'], rules, { repoRoot: '${PROJ}' });
  console.log(JSON.stringify(m.reportDrift(env.reports)));
" 2>/dev/null)"
assert_status 0 "drift_count present"   bash -c "echo '$drift_json' | grep -q '\"drift_count\"'"
assert_status 0 "entries array present" bash -c "echo '$drift_json' | grep -q '\"entries\"'"
assert_status 0 "every entry has rule_id+severity" \
  bash -c "echo '$drift_json' | python3 -c '
import json, sys
d=json.loads(sys.stdin.read())
sys.exit(0 if all((\"rule_id\" in e and \"severity\" in e) for e in d[\"entries\"]) else 1)
'"

# ── T-STD-S14: ~/.ai-os mirrors byte-identical ──────────────────────────────
echo ""
echo "  [T-STD-S14] ~/.ai-os mirrors byte-identical"

assert_status 0 "standards.json mirror"        diff -q "$STANDARDS_JSON" "${HOME}/.ai-os/shared/standards.json"
assert_status 0 "standards-checker mirror"     diff -q "$CHECKER" "${HOME}/.ai-os/shared/standards-checker.mjs"
assert_status 0 "scripts/standards.mjs mirror" diff -q "$CLI"      "${HOME}/.ai-os/scripts/standards.mjs"

# ── T-STD-S15: scripts/standards.mjs locator chain (E-83) ───────────────────
echo ""
echo "  [T-STD-S15] CLI resolves standards-checker.mjs via dynamic locator chain"

# Synthetic install layout: <root>/scripts/standards.mjs + <root>/shared/standards-checker.mjs
# (matches ~/.ai-os/ tree). Asserts Candidate 2 of the locator chain.
INSTALL="${SBOX}/installroot"
mkdir -p "${INSTALL}/scripts" "${INSTALL}/shared"
cp "$CLI"      "${INSTALL}/scripts/standards.mjs"
cp "$CHECKER"  "${INSTALL}/shared/standards-checker.mjs"
cp "$STANDARDS_JSON" "${INSTALL}/shared/standards.json"
# E-225: the checker now imports the E-224 markdown classifier (so "executable markdown"
# has one definition). It is a real runtime dependency of the installed layout, and the
# installer ships it alongside — this fixture must mirror that or it tests a layout that
# does not exist.
cp "${REPO_ROOT}/src/shared/markdown-exec.mjs" "${INSTALL}/shared/markdown-exec.mjs"

assert_status 0 "list-rules works from installed-mode layout (Candidate 2)" \
  bash -c "node '${INSTALL}/scripts/standards.mjs' list-rules --json >/dev/null 2>&1"

# Fail-closed: script alone with no checker anywhere reachable. Override HOME
# so the absolute Candidate 3 fallback also misses. Expect exit 1 + stderr marker.
ORPHAN="${SBOX}/orphan"
mkdir -p "${ORPHAN}/scripts" "${ORPHAN}/fakehome"
cp "$CLI" "${ORPHAN}/scripts/standards.mjs"
stderr_out="$( HOME="${ORPHAN}/fakehome" node "${ORPHAN}/scripts/standards.mjs" list-rules 2>&1 >/dev/null )"
rc=$?
assert_status 0 "orphan layout → exit 1"                bash -c "[[ $rc -eq 1 ]]"
assert_status 0 "fail-closed stderr marker present"     \
  bash -c "echo '$stderr_out' | grep -q '\[standards\] ERROR: standards-checker.mjs not found'"

# ── E-250 (D-067 §4 / D-065 §1): counted suppressions, named exemptions ──────
#
# D-065 ruled that a false positive is silenced by an explicit greppable marker and a
# legitimately out-of-scope file is exempted BY NAME — and that both, being coverage
# REDUCTIONS, must be visible. The markers existed; nothing counted them, and the one
# by-name exemption was a hardcoded regex inside a rule where no report could reach it.
# A suppression nobody counts is indistinguishable from a rule that stopped working.
_e250_sandbox() {
  local d; d="$(test_tmpdir e250)"
  mkdir -p "$d/tests"
  printf '%s\n' 'trap "rm -rf /tmp/x" EXIT' > "$d/tests/plain_test.sh"  # standards:allow-raw-trap - fixture data
  printf '%s\n' 'trap "rm -rf /tmp/x" EXIT  # standards:allow-raw-trap - fixture data' \
    > "$d/tests/suppressed_test.sh"
  printf '%s\n' '# standards:allow-no_raw_exit_trap_in_tests' \
                 'trap "rm -rf /tmp/x" EXIT' > "$d/tests/above_test.sh"  # standards:allow-raw-trap - fixture data
  printf '%s\n' 'echo hi  # standards:allow-not-a-real-rule' > "$d/tests/typo_test.sh"
  printf '%s' "$d"
}
_E250="$(_e250_sandbox)"
_e250_check() { ( cd "$_E250" && node "$CLI" check --file "$1" 2>&1 ); }

# The rule still FIRES — everything below is meaningless if it does not.
_plain="$(_e250_check tests/plain_test.sh)"
assert_contains "E-250.01a: an unsuppressed raw EXIT trap is still an error" \
  "no_raw_exit_trap_in_tests" "$_plain"
assert_contains "E-250.01b: and the run reports zero suppressions" \
  "Active suppressions (# standards:allow-<rule>): 0" "$_plain"

# THE MARKER, on the flagged line and on the line above it (D-065 §1 allows both).
_sup="$(_e250_check tests/suppressed_test.sh)"
assert_status 1 "E-250.02a: a marked line produces NO violation" \
  bash -c "printf '%s' \"\$_sup\" | grep -q 'error'"
assert_contains "E-250.02b: and the suppression is COUNTED, not silently swallowed" \
  "no_raw_exit_trap_in_tests: 1" "$_sup"
assert_contains "E-250.02c: with the file:line that carries it" "tests/suppressed_test.sh:1" "$_sup"

_above="$(_e250_check tests/above_test.sh)"
assert_status 1 "E-250.03a: a marker on the line ABOVE also suppresses" \
  bash -c "printf '%s' \"\$_above\" | grep -q 'error'"
assert_contains "E-250.03b: and the rule_id form of the token works, not just the alias" \
  "no_raw_exit_trap_in_tests: 1" "$_above"

# A MARKER THAT MATCHES NOTHING is a finding: the author believed they had silenced
# something, and a marker that silences nothing reads to the next person as a reviewed
# and accepted exception.
_typo="$(_e250_check tests/typo_test.sh)"
assert_contains "E-250.04a: an unknown suppression token is reported" \
  "standards_suppression_unknown" "$_typo"
assert_contains "E-250.04b: at P1" "[P1]" "$_typo"
assert_contains "E-250.04c: and it lists the tokens that WOULD have matched" \
  "no_raw_exit_trap_in_tests" "$_typo"
# A typo in a comment must not block a commit — over-block is what D-056 governs against.
assert_contains "E-250.04d: it is a warning, not a commit-blocking error" "warnings: 1" "$_typo"

# THE SUMMARY PRINTS ON EVERY RUN, including the clean one. A section that appears only
# when there is something to say is indistinguishable from one that did not run — which is
# review question #5 (E-251) applied to a report instead of a scan.
assert_contains "E-250.05a: the suppression section prints even at zero" \
  "Active suppressions" "$_plain"
assert_contains "E-250.05b: and says (none) rather than omitting itself" "(none)" "$_plain"

# BY-NAME EXEMPTIONS come from standards.json, with their reasons, on every run — NOT from
# the files this run happened to touch. A staged-file run sees only the diff, so an
# exemption that vanished when its file was not staged would read as "none" almost always.
assert_contains "E-250.06a: exemptions are listed from the config" \
  "By-name exemptions (standards.json): 1" "$_plain"
assert_contains "E-250.06b: named by rule and path" "no_raw_exit_trap_in_tests" "$_plain"
assert_contains "E-250.06c: with the one-line reason D-065 requires" "reason:" "$_plain"
assert_status 0 "E-250.06d: the exemption lives in standards.json, not in a rule's code" \
  bash -c "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=[x for x in d[\"rules\"] if x[\"rule_id\"]==\"no_raw_exit_trap_in_tests\"][0]; sys.exit(0 if any(e[\"path\"]==\"tests/run.sh\" and e.get(\"reason\") for e in r.get(\"exempt_files\",[])) else 1)' '${STANDARDS_JSON}'"
# The exemption must still WORK, or moving it was a deletion.
_runsh="$( cd "$REPO_ROOT" && node "$CLI" check --file tests/run.sh 2>&1 )"
assert_contains "E-250.06f: tests/run.sh is still exempt in the real repo" \
  "applied this run" "$_runsh"

# Central application: the marker is applied AFTER a rule produces its finding, which is
# what makes the count possible and what "every E-80 rule supports the marker" means.
assert_status 0 "E-250.07a: suppression is applied centrally in validateFile" \
  grep -q 'isSuppressed(lines, v.line, rule)' "$CHECKER"
assert_status 0 "E-250.07b: and validateFile reports what it suppressed and exempted" \
  grep -q 'suppressions, exemptions' "$CHECKER"

echo ""
assert_summary
echo "===== standards_checker_test.sh PASS ====="
