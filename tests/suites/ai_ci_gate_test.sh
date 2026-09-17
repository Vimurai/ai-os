#!/usr/bin/env bash
# ai_ci_gate_test.sh — E-267 (D-072, local-ci.md §Components 5-6a): the local CI gates.
#
# Two gates read the ci_runs record: `git push` (hooks/pre-push.sh, through a fail-closed
# stub) and update_task_status(DONE). Both are driven for real here — a real `git push` to
# a bare remote, a real MCP roundtrip — because a gate that only greps well is the
# pre-D-060 state with better prose.
#
# The certification rules themselves (self / bookkeeping ancestor / SKIPPED) are unit
# tested in tests/unit/ci-runs.test.mjs; this suite proves the wiring carries them.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
SYNC_SERVER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: ai_ci_gate_test (E-267) ──────────────────────────────────"

# A fake HOME whose ~/.ai-os mirror points at THIS tree, so the stub's canonical and the
# hook's helper are the code under test, and the operator's real mirror is never read.
FAKE_HOME="$(test_tmpdir cigate-home)"
mkdir -p "${FAKE_HOME}/.ai-os/hooks"
ln -s "${REPO_ROOT}/src/shared" "${FAKE_HOME}/.ai-os/shared"
ln -s "${REPO_ROOT}/src/mcp" "${FAKE_HOME}/.ai-os/mcp"
ln -s "${REPO_ROOT}/hooks/pre-push.sh" "${FAKE_HOME}/.ai-os/hooks/pre-push.sh"

REPO="$(test_tmpdir cigate-repo)"
REMOTE="$(test_tmpdir cigate-remote)"
git init -q --bare "$REMOTE"
git -C "$REPO" init -q -b main
git -C "$REPO" remote add origin "$REMOTE"
mkdir -p "${REPO}/.ai" "${REPO}/src"
printf '.ai/state.sqlite*\n' > "${REPO}/.gitignore"

_commit() {  # <path> <content> <msg> → sha
  mkdir -p "$(dirname "${REPO}/$1")"
  printf '%s\n' "$2" > "${REPO}/$1"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$3"
  git -C "$REPO" rev-parse HEAD
}
_row() {  # <sha> <status> [dirty] [reason] — a ci_runs row, written through the real module
  ( cd "$REPO_ROOT" && node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON --disable-warning=ExperimentalWarning \
      --input-type=module -e "
import { getDb } from './src/mcp/shared/state-db.js';
import { recordCiRun } from './src/mcp/shared/ci-runs.js';
recordCiRun(getDb('${REPO}/.ai'), { sha: '$1', ref: 'HEAD', status: '$2', dirty: ${3:-false},
  skip_reason: '${4:-}' || null, started_at: new Date(Date.now() + ${ROWN:-0}).toISOString() });" )
  ROWN=$(( ${ROWN:-0} + 1000 ))
}
_push() {  # [env...] → push HEAD:main, output + exit code in PUSH_OUT / PUSH_RC
  PUSH_OUT="$( cd "$REPO" && env HOME="$FAKE_HOME" "$@" git push -q origin HEAD:main 2>&1 )"; PUSH_RC=$?
}
_sql() { python3 - "$REPO/.ai/state.sqlite" "$1" <<'PY'
import sqlite3, sys
for row in sqlite3.connect(sys.argv[1]).execute(sys.argv[2]):
    print("|".join("" if v is None else str(v) for v in row))
PY
}

# Install the stub exactly as `ai init` does.
_hooks_out="$( cd "$REPO" && HOME="$FAKE_HOME" bash -c "
  AIOS=\"\$HOME/.ai-os\"; AIOS_STUB_MARKER='# AI-OS-STUB'
  $(awk '/^_write_pre_push_stub\(\) \{/,/^}$/' "$AI")
  _write_pre_push_stub .git/hooks/pre-push && echo written" 2>&1 )"
assert_contains "E-267.00: the pre-push stub is written" "written" "$_hooks_out"

# ── E-267.1: adoption — no rows, the gate does not block ────────────────
C1="$(_commit src/a.js 1 first)"
_push
assert_status 0 "E-267.01a: a project with no ai ci history can push" test "$PUSH_RC" -eq 0
assert_contains "E-267.01b: and is told the gate is not enforced yet" "not enforced" "$PUSH_OUT"

# ── E-267.2: tip tested → push allowed ───────────────────────────────────
C2="$(_commit src/a.js 2 second)"
_row "$C2" PASS
_push
assert_status 0 "E-267.02a: a tip with a green run pushes" test "$PUSH_RC" -eq 0
assert_contains "E-267.02b: and says why" "${C2:0:7} ok (PASS run)" "$PUSH_OUT"

# ── E-267.3: bookkeeping on top of a tested commit rides on it ──────────
C3="$(_commit .ai/TASKS.md "- [x] done" "chore(state): mark DONE")"
_push
assert_status 0 "E-267.03a: a .ai/-only commit above a tested tip pushes" test "$PUSH_RC" -eq 0
assert_contains "E-267.03b: via the tested ancestor" "tested ancestor ${C2:0:7}, only .ai/ differs" "$PUSH_OUT"

# ── E-267.4: code above the tested commit is refused ─────────────────────
C4="$(_commit src/a.js 3 "untested code")"
_push
assert_status 1 "E-267.04a: an untested code commit is refused" test "$PUSH_RC" -eq 0
assert_contains "E-267.04b: with the CI_GATE message and the command" \
  "[CI_GATE] refs/heads/main: no green local CI run for ${C4:0:7}" "$PUSH_OUT"
assert_contains "E-267.04c: naming the nearest tested ancestor and the path" \
  "nearest tested ancestor ${C2:0:7} differs outside .ai/: src/a.js" "$PUSH_OUT"
assert_contains "E-267.04d: and the recorded bypass" 'AI_OS_CI_SKIP=1 AI_OS_CI_SKIP_REASON=' "$PUSH_OUT"
assert_status 0 "E-267.04e: the remote did not move" \
  test "$(git -C "$REMOTE" rev-parse main)" = "$C3"

# A FAIL row on the tip is refused, not rescued by the ancestor.
_row "$C4" FAIL
_push
assert_status 1 "E-267.04f: a tip whose run FAILED is refused" test "$PUSH_RC" -eq 0
assert_contains "E-267.04g: and says so" "its run is FAIL" "$PUSH_OUT"

# ── E-267.5: skip — with a reason recorded, without a reason refused ─────
_push AI_OS_CI_SKIP=1
assert_status 1 "E-267.05a: AI_OS_CI_SKIP=1 without a reason is refused" test "$PUSH_RC" -eq 0
assert_contains "E-267.05b: and says a reason is required" "needs AI_OS_CI_SKIP_REASON" "$PUSH_OUT"
_push AI_OS_CI_SKIP=1 "AI_OS_CI_SKIP_REASON=prod outage hotfix"
assert_status 0 "E-267.05c: a skip with a reason pushes" test "$PUSH_RC" -eq 0
assert_status 0 "E-267.05d: and the remote moved" test "$(git -C "$REMOTE" rev-parse main)" = "$C4"
assert_contains "E-267.05e: the skip is a SKIPPED row carrying the reason and ref" \
  "SKIPPED|prod outage hotfix|refs/heads/main" \
  "$(_sql "SELECT status, skip_reason, ref FROM ci_runs WHERE sha='${C4}' ORDER BY id DESC LIMIT 1")"
_push
assert_status 0 "E-267.05f: a later plain push of the skipped tip is let through (it is recorded)" test "$PUSH_RC" -eq 0

# ── E-267.6: fail closed ─────────────────────────────────────────────────
C6="$(_commit src/a.js 6 "sixth")"
_row "$C6" PASS
rm "${FAKE_HOME}/.ai-os/hooks/pre-push.sh"
_push
assert_status 1 "E-267.06a: a missing canonical refuses the push" test "$PUSH_RC" -eq 0
assert_contains "E-267.06b: and names the fix" "pre-push canonical missing" "$PUSH_OUT"
ln -s "${REPO_ROOT}/hooks/pre-push.sh" "${FAKE_HOME}/.ai-os/hooks/pre-push.sh"
mv "${FAKE_HOME}/.ai-os/shared" "${FAKE_HOME}/.ai-os/shared.off"
_push
assert_status 1 "E-267.06c: a missing helper refuses the push" test "$PUSH_RC" -eq 0
assert_contains "E-267.06d: and names the fix" "ci-record.mjs or node unavailable" "$PUSH_OUT"
mv "${FAKE_HOME}/.ai-os/shared.off" "${FAKE_HOME}/.ai-os/shared"
_push
assert_status 0 "E-267.06e: restored, the tested tip pushes (non-vacuity for 06a-d)" test "$PUSH_RC" -eq 0

# A repo that is not an AI-OS project is not gated.
PLAIN="$(test_tmpdir cigate-plain)"
git -C "$PLAIN" init -q
out="$( cd "$PLAIN" && printf 'refs/heads/x %s refs/heads/x %s\n' "$C6" "$C6" \
  | HOME="$FAKE_HOME" bash "${REPO_ROOT}/hooks/pre-push.sh" 2>&1 )"; rc=$?
assert_status 0 "E-267.06f: a repo without .ai/ is not gated" test "$rc" -eq 0
# Deleting a remote branch pushes no content.
out="$( cd "$REPO" && printf 'refs/heads/gone 0000000000000000000000000000000000000000 refs/heads/gone %s\n' "$C6" \
  | HOME="$FAKE_HOME" bash "${REPO_ROOT}/hooks/pre-push.sh" 2>&1 )"; rc=$?
assert_status 0 "E-267.06g: a branch deletion is not gated" test "$rc" -eq 0

# ── E-267.7: stub chaining preserves the user's hook and stdin ───────────
CH="$(test_tmpdir cigate-chain)"
printf '#!/usr/bin/env bash\ncat > "%s/seen"\nexit 0\n' "$CH" > "${REPO}/.git/hooks/pre-push.pre-aios"
chmod +x "${REPO}/.git/hooks/pre-push.pre-aios"
( cd "$REPO" && HOME="$FAKE_HOME" bash -c "
  AIOS_STUB_MARKER='# AI-OS-STUB'
  $(awk '/^_write_pre_push_stub\(\) \{/,/^}$/' "$AI")
  _write_pre_push_stub .git/hooks/pre-push .git/hooks/pre-push.pre-aios" )
# A NEW tested commit: git hands a hook no ref lines when there is nothing to update.
C7="$(_commit src/a.js 7 "seventh")"
_row "$C7" PASS
_push
assert_status 0 "E-267.07a: the chained push still passes the gate" test "$PUSH_RC" -eq 0
assert_contains "E-267.07b: the user's hook received git's ref line on stdin" "refs/heads/main" "$(cat "${CH}/seen" 2>/dev/null)"
printf '#!/usr/bin/env bash\nexit 7\n' > "${REPO}/.git/hooks/pre-push.pre-aios"
_push
assert_status 1 "E-267.07c: a failing user hook still blocks the push" test "$PUSH_RC" -eq 0
rm -f "${REPO}/.git/hooks/pre-push.pre-aios"

# ── E-267.8: the DONE gate, through the real MCP server ─────────────────
_mcp() { ( cd "$REPO" && env HOME="$FAKE_HOME" "$@" ) | python3 -c '
import json,sys
d=json.load(sys.stdin)
print((d.get("content") or [{}])[0].get("text",""))'; }
_done() {  # <task> [env...] → the update_task_status text
  local id="$1"; shift
  _mcp "$@" bash -c "source '${REPO_ROOT}/tests/lib/mcp-client.sh'; mcp_call_tool '$SYNC_SERVER' update_task_status '{\"id\":\"$id\",\"status\":\"DONE\",\"summary\":\"probe\"}'"
}
_add() { _mcp bash -c "source '${REPO_ROOT}/tests/lib/mcp-client.sh'; mcp_call_tool '$SYNC_SERVER' add_task '{\"owner\":\"Engineer (Claude)\",\"description\":\"Probe the CI gate $1\",\"prefix\":\"E\"}'" >/dev/null; }
for n in 1 2 3; do _add "$n"; done
C8="$(_commit src/a.js 8 "eighth")"
OUT="$(_done E-1)"
assert_contains "E-267.08a: DONE is refused when HEAD has no run" \
  "[CI_GATE] no green local CI run for HEAD ${C8:0:7}" "$OUT"
assert_contains "E-267.08b: the refusal names the command and the bypass" "run: ai ci run (bypass: AI_OS_CI_GATE=0)" "$OUT"
OUT="$(_done E-1 AI_OS_CI_GATE=0)"
assert_contains "E-267.08c: AI_OS_CI_GATE=0 lets DONE through" "E-1 → DONE" "$OUT"
_row "$C8" PASS true
OUT="$(_done E-2)"
assert_contains "E-267.08d: a dirty-only HEAD is refused" "[CI_GATE]" "$OUT"
_row "$C8" FAIL
OUT="$(_done E-2)"
assert_contains "E-267.08e: a FAIL HEAD is refused, and says so" "its run is FAIL" "$OUT"
_row "$C8" PASS
OUT="$(_done E-2)"
assert_contains "E-267.08f: a PASS HEAD is accepted" "E-2 → DONE" "$OUT"
C9="$(_commit .ai/notes.md "bookkeeping" "chore(state)")"
OUT="$(_done E-3)"
assert_contains "E-267.08g: a .ai/-only HEAD above the tested commit is accepted" "E-3 → DONE" "$OUT"

EMPTY="$(test_tmpdir cigate-empty)"
git -C "$EMPTY" init -q; mkdir -p "${EMPTY}/.ai"
git -C "$EMPTY" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m x
OUT="$( cd "$EMPTY" && HOME="$FAKE_HOME" mcp_call_tool "$SYNC_SERVER" add_task '{"owner":"Engineer (Claude)","description":"Probe adoption off","prefix":"E"}' >/dev/null
        cd "$EMPTY" && HOME="$FAKE_HOME" mcp_call_tool "$SYNC_SERVER" update_task_status '{"id":"E-1","status":"DONE","summary":"x"}' \
          | python3 -c 'import json,sys; print((json.load(sys.stdin).get("content") or [{}])[0].get("text",""))' )"
assert_contains "E-267.08h: a project that never ran ai ci is not gated" "E-1 → DONE" "$OUT"

# ── E-267.9: the consumers ───────────────────────────────────────────────
TASK_SKILL="${REPO_ROOT}/src/shared/skills/ai-task/SKILL.md"
assert_status 1 "E-267.09a: ai-task no longer reads gh run" grep -q 'gh run' "$TASK_SKILL"
assert_status 1 "E-267.09b: ai-task's injection no longer shells out to python3" grep -q '^Local CI.*python3' "$TASK_SKILL"
INJ="$(sed -n 's/^Local CI (HEAD): !//p' "$TASK_SKILL")"
assert_contains "E-267.09c: ai-task injects ai ci status --short" "ai ci status --ref HEAD --short" "$INJ"
# Run the injection line itself against a fixture, with an `ai` on PATH that is this tree.
BIN="$(test_tmpdir cigate-bin)"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$AI" > "${BIN}/ai"; chmod +x "${BIN}/ai"
OUT="$( cd "$REPO" && git checkout -qf "$C8" && HOME="$FAKE_HOME" PATH="${BIN}:$PATH" bash -c "$INJ" 2>&1 )"
assert_match "E-267.09d: the injected line reads PASS for a tested HEAD" "^PASS ${C8:0:7} " "$OUT"
OUT="$( cd "$REPO" && git checkout -qf "$C1" && HOME="$FAKE_HOME" PATH="${BIN}:$PATH" bash -c "$INJ" 2>&1 )"
assert_match "E-267.09e: and NONE for an untested one" "^NONE ${C1:0:7} " "$OUT"
OUT="$( cd "$REPO" && HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash -c "$INJ" 2>&1 )"
assert_contains "E-267.09f: and says unavailable when ai is not installed" "(ai ci unavailable" "$OUT"
git -C "$REPO" checkout -qf main

for f in ENGINEER.md src/templates/ENGINEER.md; do
  assert_status 0 "E-267.09g: ${f} triages with ai ci log --failed" grep -q 'ai ci log --failed' "${REPO_ROOT}/${f}"
  assert_status 1 "E-267.09h: ${f} no longer names gh run" grep -q 'gh run view' "${REPO_ROOT}/${f}"
done
for f in src/claude/agents/critic_tests.md src/claude/skills/ai-review/SKILL.md; do
  assert_status 0 "E-267.09i: ${f} says 'under \`ai ci\`'" grep -q 'under `ai ci`' "${REPO_ROOT}/${f}"
  assert_status 1 "E-267.09j: ${f} no longer says 'fails the run on CI'" grep -q 'fails the run on CI' "${REPO_ROOT}/${f}"
done
assert_status 0 "E-267.09k: ci_gate forbids pushing without a green ai ci run" \
  grep -q 'without a green `ai ci run`' "${REPO_ROOT}/src/claude/skills/ci_gate/SKILL.md"
assert_status 0 "E-267.09l: install_git_hooks installs the pre-push stub" \
  grep -q '_write_pre_push_stub "\$PP_DST"' "$AI"
assert_status 0 "E-267.09m: uninstall tells the operator to remove it" \
  grep -q 'rm .git/hooks/pre-push' "$AI"
for m in .claude/skills/ai-task/SKILL.md:src/shared/skills/ai-task/SKILL.md \
         .claude/skills/ai-review/SKILL.md:src/claude/skills/ai-review/SKILL.md \
         .claude/skills/ci_gate/SKILL.md:src/claude/skills/ci_gate/SKILL.md \
         .claude/agents/critic_tests.md:src/claude/agents/critic_tests.md; do
  assert_mirror_if_present "E-267.09n: ${m%%:*} mirrors ${m##*:}" "${REPO_ROOT}/${m##*:}" "${REPO_ROOT}/${m%%:*}"
done

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== ai_ci_gate_test.sh PASS ====="
else
  echo "===== ai_ci_gate_test.sh FAIL (${FAIL_COUNT}) ====="
fi
