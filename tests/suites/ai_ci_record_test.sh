#!/usr/bin/env bash
# ai_ci_record_test.sh — E-266 (D-072, local-ci.md §Components 3-4): the run record.
#
# From D-072 on, "CI green" is a fact in state.sqlite, not a badge: a NON-DIRTY ci_runs
# row with status PASS for the commit. This suite drives the real `ai ci run` against a
# fixture repo and then reads the record back through every reader — `ai ci status`
# (both forms, all four outcomes), `ai ci list`, `ai ci log [--failed]`, the `ai doctor`
# line and the get_ci_status MCP tool — so a reader that disagrees with the writer fails
# here rather than at a gate.
#
# The table, parser, verdict rules and retention are unit-tested in
# tests/unit/ci-runs.test.mjs; this suite is the end-to-end layer.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
SYNC_SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: ai_ci_record_test (E-266) ────────────────────────────────"

FAKE_HOME="$(test_tmpdir cirec-home)"
RUN_TMP="$(test_tmpdir cirec-tmp)"
REPO="$(test_tmpdir cirec-repo)"

_commit() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qam "$1"; }
_ci() { ( cd "$REPO" && HOME="$FAKE_HOME" TMPDIR="${RUN_TMP}/" bash "$AI" ci "$@" ) 2>&1; }
_sql() { python3 - "$REPO/.ai/state.sqlite" "$1" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
for row in con.execute(sys.argv[2]):
    print("|".join("" if v is None else str(v) for v in row))
PY
}

mkdir -p "${REPO}/tests" "${REPO}/.ai"
cat > "${REPO}/tests/run.sh" <<'STUB'
#!/usr/bin/env bash
echo "── Suite: stub_test ──"
if [[ "$(cat stub_exit)" != 0 ]]; then
  echo "  ✗ stub assertion that fails on purpose"
  echo "SUITE_RESULT PASS=2 FAIL=1 SKIP=0"
  echo "━━ Results ━━"
  echo "  ✗ stub_test.sh (2 passed, 1 failed)"
  echo "   Total: 2 passed, 1 failed"
  exit 1
fi
echo "  ✓ stub assertion"
echo "SUITE_RESULT PASS=3 FAIL=0 SKIP=1"
echo "━━ Results ━━"
echo "   Total: 3 passed, 0 failed, 1 skipped"
STUB
echo 0 > "${REPO}/stub_exit"
printf '.env\nnode_modules\n.ai/\n' > "${REPO}/.gitignore"
git -C "$REPO" init -q -b main
git -C "$REPO" add -A
_commit "green"
SHA_PASS="$(git -C "$REPO" rev-parse HEAD)"

# ── E-266.1: a run writes its row ─────────────────────────────────────────
OUT="$(_ci run)"; RC=$?
assert_status 0 "E-266.01a: the fixture run passes" test "$RC" -eq 0
assert_not_contains "E-266.01b: the run did not warn about recording" "not recorded" "$OUT"
ROW="$(_sql "SELECT sha,ref,branch,dirty,status,suite_pass,suite_fail,suite_skip,leaked,unit_status,secrets_status FROM ci_runs")"
assert_contains "E-266.01c: the row carries the run's facts" \
  "${SHA_PASS}|HEAD|main|0|PASS|3|0|1|0|SKIPPED|PASS" "$ROW"
NULLS="$(_sql "SELECT (started_at IS NULL)+(finished_at IS NULL)+(duration_ms IS NULL)+(node_version IS NULL)+(bash_version IS NULL)+(os IS NULL)+(log_path IS NULL) FROM ci_runs")"
assert_status 0 "E-266.01d: timing, toolchain and log path are populated" test "$NULLS" = "0"
LOGP="$(_sql "SELECT log_path FROM ci_runs")"
assert_status 0 "E-266.01e: log_path points at the kept log" test -f "$LOGP"
assert_status 0 "E-266.01f: started_at is ISO-8601 T-form" \
  bash -c "[[ '$(_sql "SELECT started_at FROM ci_runs")' =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]"

# ── E-266.2: status — PASS ────────────────────────────────────────────────
OUT="$(_ci status)"; RC=$?
assert_status 0 "E-266.02a: status on a green HEAD exits 0" test "$RC" -eq 0
assert_contains "E-266.02b: and names PASS and the sha" "local CI: PASS ${SHA_PASS:0:7}" "$OUT"
OUT="$(_ci status --short)"; RC=$?
assert_status 0 "E-266.02c: --short exits 0 too" test "$RC" -eq 0
assert_match "E-266.02d: --short is one line in the injected format" \
  "^PASS ${SHA_PASS:0:7} [0-9]+[smhd] ago \(suite 3/0/1, unit SKIPPED, leaked 0\)$" "$OUT"

# ── E-266.3: status — FAIL ────────────────────────────────────────────────
echo 1 > "${REPO}/stub_exit"; _commit "red"
SHA_FAIL="$(git -C "$REPO" rev-parse HEAD)"
_ci run >/dev/null
OUT="$(_ci status --short)"; RC=$?
assert_status 0 "E-266.03a: status on a red HEAD exits 1" test "$RC" -eq 1
assert_match "E-266.03b: --short says FAIL" "^FAIL ${SHA_FAIL:0:7} " "$OUT"
OUT="$(_ci status --ref "$SHA_PASS" --short)"; RC=$?
assert_status 0 "E-266.03c: --ref reads another commit's row (the green one)" test "$RC" -eq 0

# ── E-266.4: log and log --failed ────────────────────────────────────────
OUT="$(_ci log --failed)"; RC=$?
assert_status 0 "E-266.04a: log --failed exits 0" test "$RC" -eq 0
assert_contains "E-266.04b: it shows the failing assertion" "stub assertion that fails on purpose" "$OUT"
assert_contains "E-266.04c: and the failing suite in the summary" "stub_test.sh (2 passed, 1 failed)" "$OUT"
assert_not_contains "E-266.04d: and not the full log" "[ci] toolchain" "$OUT"
OUT="$(_ci log "$SHA_PASS")"; RC=$?
assert_contains "E-266.04e: log <sha> prints that run's whole log" "[ci] sha=${SHA_PASS}" "$OUT"

# ── E-266.5: status — dirty only ─────────────────────────────────────────
echo 0 > "${REPO}/stub_exit"; _commit "green again"
SHA_DIRTY="$(git -C "$REPO" rev-parse HEAD)"
echo "scratch" > "${REPO}/scratch.txt"
_ci run --dirty >/dev/null
OUT="$(_ci status --short)"; RC=$?
assert_status 0 "E-266.05a: a dirty-only commit exits 2 (no certifying run)" test "$RC" -eq 2
assert_match "E-266.05b: --short says DIRTY and why it does not count" \
  "^DIRTY ${SHA_DIRTY:0:7} .*not a certification; run: ai ci run$" "$OUT"
assert_status 0 "E-266.05c: the dirty row is marked dirty=1" \
  test "$(_sql "SELECT dirty FROM ci_runs WHERE sha='${SHA_DIRTY}'")" = "1"
rm -f "${REPO}/scratch.txt"

# ── E-266.6: status — no row ─────────────────────────────────────────────
echo "more" >> "${REPO}/stub_exit.note"; git -C "$REPO" add -A; _commit "untested"
SHA_NONE="$(git -C "$REPO" rev-parse HEAD)"
OUT="$(_ci status --short)"; RC=$?
assert_status 0 "E-266.06a: an untested commit exits 2" test "$RC" -eq 2
assert_contains "E-266.06b: --short says NONE and what to run" \
  "NONE ${SHA_NONE:0:7} — no local CI run; run: ai ci run" "$OUT"
OUT="$(_ci log)"; RC=$?
assert_status 0 "E-266.06c: log for an untested commit exits 2" test "$RC" -eq 2
OUT="$(_ci status --ref nope)"; RC=$?
assert_status 0 "E-266.06d: status --ref <unknown> exits 2" test "$RC" -eq 2

# ── E-266.7: list ────────────────────────────────────────────────────────
OUT="$(_ci list)"; RC=$?
assert_status 0 "E-266.07a: list exits 0" test "$RC" -eq 0
assert_status 0 "E-266.07b: list shows the three recorded runs" \
  test "$(printf '%s\n' "$OUT" | grep -cE '^(PASS|FAIL|ERROR|SKIPPED) ')" = "3"
assert_match "E-266.07c: newest first (the dirty run)" "^PASS    ${SHA_DIRTY:0:7} dirty" "$(printf '%s\n' "$OUT" | head -1)"
OUT="$(_ci list -n 1)"
assert_status 0 "E-266.07d: -n limits the rows" test "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = "1"
OUT="$(_ci list -n x)"; RC=$?
assert_status 0 "E-266.07e: -n with a non-number exits 2" test "$RC" -eq 2

# ── E-266.8: doctor line, both branches ──────────────────────────────────
_doctor_line() { ( cd "$REPO" && HOME="$FAKE_HOME" bash "$AI" doctor 2>&1 ) | grep 'local CI:' | head -1; }
OUT="$(_doctor_line)"
assert_contains "E-266.08a: doctor reports ✗ with the command for an untested HEAD" \
  "✗ local CI: no run for HEAD ${SHA_NONE:0:7} — run: ai ci run" "$OUT"
git -C "$REPO" checkout -q "$SHA_PASS"
OUT="$(_doctor_line)"
assert_match "E-266.08b: doctor reports ✓ for a green HEAD" "✓ local CI: HEAD ${SHA_PASS:0:7} PASS [0-9]+[smhd] ago" "$OUT"
git -C "$REPO" checkout -q "$SHA_FAIL"
OUT="$(_doctor_line)"
assert_contains "E-266.08c: doctor points a red HEAD at log --failed" "run: ai ci log --failed" "$OUT"
git -C "$REPO" checkout -q main

# ── E-266.9: get_ci_status (task-synchronizer-mcp) ───────────────────────
_mcp() { ( cd "$REPO" && mcp_call_tool "$SYNC_SERVER" get_ci_status "$1" ) | python3 -c '
import json,sys
d=json.load(sys.stdin)
t=(d.get("content") or [{}])[0].get("text","{}")
try: j=json.loads(t)
except Exception: print("UNPARSEABLE", t); sys.exit()
print(j.get("status"), j.get("verdict"), j.get("sha"), j.get("dirty"))'; }
assert_contains "E-266.09a: get_ci_status on the untested HEAD is NONE" "NONE None ${SHA_NONE}" "$(_mcp '{}')"
assert_contains "E-266.09b: get_ci_status by sha returns the PASS row" \
  "PASS PASS ${SHA_PASS} False" "$(_mcp "{\"sha\":\"${SHA_PASS}\"}")"
assert_contains "E-266.09c: an abbreviated sha resolves" \
  "FAIL FAIL ${SHA_FAIL} False" "$(_mcp "{\"sha\":\"${SHA_FAIL:0:7}\"}")"
assert_contains "E-266.09d: a dirty-only commit reports verdict DIRTY" \
  "PASS DIRTY ${SHA_DIRTY} True" "$(_mcp "{\"sha\":\"${SHA_DIRTY}\"}")"
assert_contains "E-266.09e: get_ci_status is advertised" "get_ci_status" "$(mcp_list_tools "$SYNC_SERVER")"

# ── E-266.10: registration and the not-recorded path ─────────────────────
assert_status 0 "E-266.10a: registry allows get_ci_status" \
  grep -q '"get_ci_status"' "${REPO_ROOT}/src/config/registry.json"
assert_status 0 "E-266.10b: the project allow-list grants it" \
  grep -q 'mcp__task-synchronizer-mcp__get_ci_status' "${REPO_ROOT}/.claude/settings.json"
NOAI="$(test_tmpdir cirec-noai)"
mkdir -p "${NOAI}/tests"; cp "${REPO}/tests/run.sh" "${NOAI}/tests/run.sh"; echo 0 > "${NOAI}/stub_exit"
printf '.env\nnode_modules\n' > "${NOAI}/.gitignore"
git -C "$NOAI" init -q; git -C "$NOAI" add -A
git -C "$NOAI" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm x
OUT="$( ( cd "$NOAI" && HOME="$FAKE_HOME" TMPDIR="${RUN_TMP}/" bash "$AI" ci run ) 2>&1 )"; RC=$?
assert_status 0 "E-266.10c: a repo without .ai/ still runs (exit 0)" test "$RC" -eq 0
assert_contains "E-266.10d: and says plainly that it was not recorded" "not recorded" "$OUT"
assert_status 1 "E-266.10e: and no state store was created for it" test -e "${NOAI}/.ai"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== ai_ci_record_test.sh PASS ====="
else
  echo "===== ai_ci_record_test.sh FAIL (${FAIL_COUNT}) ====="
fi
