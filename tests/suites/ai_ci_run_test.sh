#!/usr/bin/env bash
# ai_ci_run_test.sh — E-265 (D-072, local-ci.md §Components 1-2): `ai ci run`.
#
# A local CI run is only worth recording if it measures the COMMIT, not the laptop. The
# assertions are weighted toward the three isolation properties the GitHub runner gave us
# for free and a bare `bash tests/run.sh` does not:
#   * a clean checkout — an uncommitted file is invisible unless --dirty asks for it;
#   * a fresh environment — no CI, TMUX or launch variable leaks in, and HOME is throwaway;
#   * nothing left behind — the worktree, the throwaway HOME and the lock are gone after.
#
# Every run here targets a FIXTURE repository whose tests/run.sh is a stub that prints what
# it can see, under a fake HOME and a private TMPDIR, so the operator's ~/.ai-os/ci is
# never touched by the suite.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"

echo "── Suite: ai_ci_run_test (E-265) ───────────────────────────────────"

FAKE_HOME="$(test_tmpdir ci-home)"
RUN_TMP="$(test_tmpdir ci-tmp)"

# _mk_repo <dir> [--no-gitignore] — a committed fixture repo with a probing stub runner.
_mk_repo() {
  local d="$1"
  mkdir -p "${d}/tests"
  cat > "${d}/tests/run.sh" <<'STUB'
#!/usr/bin/env bash
echo "PROBE_HOME=${HOME}"
echo "PROBE_ENV CI=${CI-unset} TMUX=${TMUX-unset} ROLE=${AI_OS_PANE_ROLE-unset} AI_OS_CI=${AI_OS_CI-unset}"
[[ -f UNCOMMITTED.txt ]] && echo "PROBE_UNCOMMITTED=present" || echo "PROBE_UNCOMMITTED=absent"
[[ -f tracked.txt ]] && echo "PROBE_TRACKED=present" || echo "PROBE_TRACKED=absent"
# A run that writes under HOME must land in the throwaway HOME, never the caller's.
mkdir -p "${HOME}/.ai-os" && echo probe > "${HOME}/.ai-os/probe-written"
echo "   Total: 3 passed, 0 failed"
exit "$(cat stub_exit)"
STUB
  echo 0 > "${d}/stub_exit"
  echo tracked > "${d}/tracked.txt"
  [[ "${2:-}" == "--no-gitignore" ]] || printf '.env\nnode_modules\n' > "${d}/.gitignore"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm fixture
}

# _ci <repo> <args...> — run `ai ci` from the repo under the fake HOME and private TMPDIR,
# with the variables the runner must NOT pass through set in the caller.
_ci() {
  local d="$1"; shift
  ( cd "$d" && HOME="$FAKE_HOME" TMPDIR="${RUN_TMP}/" CI=true TMUX=/tmp/fake,1,0 \
      AI_OS_PANE_ROLE=architect bash "$AI" ci "$@" ) 2>&1
}

REPO="$(test_tmpdir ci-repo)"
_mk_repo "$REPO"
SHA="$(git -C "$REPO" rev-parse HEAD)"
echo "uncommitted" > "${REPO}/UNCOMMITTED.txt"
rm -f "${REPO}/tracked.txt"
STATUS_BEFORE="$(git -C "$REPO" status --porcelain)"

# ── E-265.1: a non-dirty run tests the COMMIT ─────────────────────────────
OUT="$(_ci "$REPO" run)"; RC=$?
assert_status 0 "E-265.01a: a passing fixture run exits 0" test "$RC" -eq 0
assert_contains "E-265.01b: an uncommitted file is NOT visible to a non-dirty run" \
  "PROBE_UNCOMMITTED=absent" "$OUT"
assert_contains "E-265.01c: a file deleted only in the working tree is still present" \
  "PROBE_TRACKED=present" "$OUT"
assert_contains "E-265.01d: the summary names PASS and the sha" "ai ci: PASS ${SHA:0:7}" "$OUT"
assert_contains "E-265.01e: the suite step parses the runner's totals" \
  "3 passed, 0 failed, 0 skipped, leaked 0" "$OUT"
assert_contains "E-265.01f: a fixture with no package.json skips deps, not errors" \
  "deps       skip" "$OUT"

# ── E-265.2: the environment is curated ──────────────────────────────────
assert_contains "E-265.02a: CI is not inherited" "CI=unset" "$OUT"
assert_contains "E-265.02b: TMUX is not inherited" "TMUX=unset" "$OUT"
assert_contains "E-265.02c: a launch variable (AI_OS_PANE_ROLE) is not inherited" "ROLE=unset" "$OUT"
assert_contains "E-265.02d: AI_OS_CI=local is set for the run" "AI_OS_CI=local" "$OUT"
PROBE_HOME="$(sed -n 's/^PROBE_HOME=//p' <<< "$OUT" | head -1)"
assert_status 0 "E-265.02e: the run's HOME is not the caller's HOME" \
  test -n "$PROBE_HOME" -a "$PROBE_HOME" != "$FAKE_HOME"
assert_status 1 "E-265.02f: the run's HOME is not inside the caller's HOME either" \
  bash -c "[[ '$PROBE_HOME' == '$FAKE_HOME'/* ]]"

# ── E-265.3: the caller's ~/.ai-os is untouched, and nothing is left behind ──
assert_status 1 "E-265.03a: the stub's HOME write did not reach the caller's ~/.ai-os" \
  test -e "${FAKE_HOME}/.ai-os/probe-written"
assert_status 0 "E-265.03b: the caller's ~/.ai-os holds only the ci/ directory" \
  test "$(command ls -A "${FAKE_HOME}/.ai-os")" = "ci"
assert_status 1 "E-265.03c: the throwaway HOME is removed after the run" test -e "$PROBE_HOME"
assert_status 0 "E-265.03d: the worktree is removed from git's list" \
  test "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" = "1"
assert_status 0 "E-265.03e: no ai-os-ci work dir is left in TMPDIR" \
  bash -c "! compgen -G '${RUN_TMP}/ai-os-ci.*' >/dev/null"
assert_status 0 "E-265.03f: the lock is released" \
  bash -c "! compgen -G '${FAKE_HOME}/.ai-os/ci/run-*.lock' >/dev/null"
assert_status 0 "E-265.03g: the operator's working tree is unchanged by the run" \
  test "$(git -C "$REPO" status --porcelain)" = "$STATUS_BEFORE"

# ── E-265.4: the log ──────────────────────────────────────────────────────
LOG="$(compgen -G "${FAKE_HOME}/.ai-os/ci/logs/${SHA}-*.log" | head -1)"
assert_status 0 "E-265.04a: the log is named <sha>-<started>.log" test -f "$LOG"
assert_status 0 "E-265.04b: the log records the result line" \
  grep -q '^\[ci\] result status=PASS suite=PASS pass=3 fail=0 skip=0 leaked=0' "$LOG"
assert_status 0 "E-265.04c: the log records the toolchain" grep -q '^\[ci\] toolchain node=' "$LOG"
assert_status 0 "E-265.04d: the log records dirty=0" grep -q "sha=${SHA} ref=HEAD dirty=0" "$LOG"

# ── E-265.5: --dirty sees the working tree, and only reads it ────────────
OUT="$(_ci "$REPO" run --dirty)"; RC=$?
assert_status 0 "E-265.05a: a dirty run exits 0" test "$RC" -eq 0
assert_contains "E-265.05b: an uncommitted file IS visible under --dirty" \
  "PROBE_UNCOMMITTED=present" "$OUT"
assert_contains "E-265.05c: a working-tree deletion is honoured under --dirty" \
  "PROBE_TRACKED=absent" "$OUT"
assert_contains "E-265.05d: the worktree step reports the overlay" "dirty: 1 copied, 1 removed" "$OUT"
assert_status 0 "E-265.05e: the working tree is unchanged by a dirty run" \
  test "$(git -C "$REPO" status --porcelain)" = "$STATUS_BEFORE"
assert_status 0 "E-265.05f: the dirty run's log says dirty=1" \
  bash -c "grep -l 'dirty=1' '${FAKE_HOME}'/.ai-os/ci/logs/${SHA}-*.log >/dev/null"

# ── E-265.6: exit codes ───────────────────────────────────────────────────
FREPO="$(test_tmpdir ci-fail)"
_mk_repo "$FREPO"
echo 1 > "${FREPO}/stub_exit"
git -C "$FREPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qam fail
OUT="$(_ci "$FREPO" run)"; RC=$?
assert_status 0 "E-265.06a: a failing suite exits 1 (FAIL, not ERROR)" test "$RC" -eq 1
assert_contains "E-265.06b: and says FAIL" "ai ci: FAIL" "$OUT"

NREPO="$(test_tmpdir ci-noignore)"
_mk_repo "$NREPO" --no-gitignore
OUT="$(_ci "$NREPO" run)"; RC=$?
assert_status 0 "E-265.06c: a repo whose .gitignore misses .env fails the secrets step" test "$RC" -eq 1
assert_contains "E-265.06d: and names it" "secrets    FAIL" "$OUT"

OUT="$(_ci "$REPO" run --ref does-not-exist)"; RC=$?
assert_status 0 "E-265.06e: an unknown ref is ERROR (exit 2)" test "$RC" -eq 2
OUT="$(_ci "$REPO" run --dirty --ref HEAD)"; RC=$?
assert_status 0 "E-265.06f: --dirty with --ref is refused (exit 2)" test "$RC" -eq 2
OUT="$(_ci "$REPO" run --suite-only --unit-only)"; RC=$?
assert_status 0 "E-265.06g: --suite-only with --unit-only is refused (exit 2)" test "$RC" -eq 2
NOGIT="$(test_tmpdir ci-nogit)"
OUT="$(_ci "$NOGIT" run)"; RC=$?
assert_status 0 "E-265.06h: outside a git repository is ERROR (exit 2)" test "$RC" -eq 2
OUT="$(_ci "$REPO" frobnicate)"; RC=$?
assert_status 0 "E-265.06i: an unknown subcommand exits 2" test "$RC" -eq 2

# ── E-265.7: one run at a time per project ───────────────────────────────
KEY="$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | cksum | awk '{print $1}')"
LOCK="${FAKE_HOME}/.ai-os/ci/run-${KEY}.lock"
HOLDER="$(test_bg sleep 60)"
mkdir -p "$LOCK" && echo "$HOLDER" > "${LOCK}/pid"
OUT="$(_ci "$REPO" run)"; RC=$?
assert_status 0 "E-265.07a: a live lock refuses a second run with exit 2" test "$RC" -eq 2
assert_contains "E-265.07b: and names the holder" "another run is in progress for this project (pid ${HOLDER}" "$OUT"
assert_status 0 "E-265.07c: the refused run does not remove the holder's lock" test -f "${LOCK}/pid"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
# A lock whose owner is dead is stale and must not wedge CI forever.
echo 999999 > "${LOCK}/pid"
OUT="$(_ci "$REPO" run --suite-only)"; RC=$?
assert_status 0 "E-265.07d: a stale lock (dead owner) is reclaimed" test "$RC" -eq 0
assert_status 1 "E-265.07e: and released afterwards" test -e "$LOCK"

# ── E-265.8: --keep retains the work dir for debugging ───────────────────
OUT="$(_ci "$REPO" run --keep)"; RC=$?
KEPT="$(sed -nE 's/^ai ci: kept ([^ ]+) \(--keep\).*/\1/p' <<< "$OUT")"
assert_status 0 "E-265.08a: --keep reports the kept directory" test -n "$KEPT"
assert_status 0 "E-265.08b: and the worktree is still there" test -f "${KEPT}/wt/tests/run.sh"
git -C "$REPO" worktree remove --force "${KEPT}/wt" >/dev/null 2>&1
rm -rf "$KEPT"

# ── E-265.9: the runner's shape ──────────────────────────────────────────
assert_status 0 "E-265.09a: steps run under env -i (isolation by construction)" \
  grep -q 'env -i "\${CI_ENV\[@\]}"' "$AI"
assert_status 0 "E-265.09b: the suite runs under /bin/bash, the shell users have" \
  grep -q '/bin/bash tests/run.sh' "$AI"
assert_status 0 "E-265.09c: the caller's ~/.ai-os is stripped from PATH" \
  grep -q '_ci_clean_path' "$AI"
assert_status 0 "E-265.09d: ai --help lists ai ci run" \
  bash -c "HOME='$FAKE_HOME' bash '$AI' --help | grep -q 'ai ci run'"
assert_status 0 "E-265.09e: DEVOPS.md carries the ci_gate entry" \
  grep -q 'DEVOPS-007 — Local CI runner' "${REPO_ROOT}/.ai/DEVOPS.md"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== ai_ci_run_test.sh PASS ====="
else
  echo "===== ai_ci_run_test.sh FAIL (${FAIL_COUNT}) ====="
fi
