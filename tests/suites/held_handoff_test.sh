#!/usr/bin/env bash
# held_handoff_test.sh — E-271 (D-073 rules 2-5): a held handoff is never silent, and the
# two bridge writers are safe.
#
# The live failure this suite exists for: two Engineer handoffs sat undelivered for a DAY
# while a healthy watcher printed nothing, because MAX_HOLD=0 means "hold forever" and a
# hold produced no record and no output. Holding is still the default — being quiet about it
# is not.
#
# Everything runs against a fixture signal.json with the watcher's own functions sourced,
# so the assertions exercise the real writers, the real lock and the real hold bookkeeping.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH="${REPO_ROOT}/src/bin/ai-watch"
AI="${REPO_ROOT}/src/bin/ai"
HANDOFF="${REPO_ROOT}/src/shared/signal-handoff.mjs"
NODE_Q=(--disable-warning=MODULE_TYPELESS_PACKAGE_JSON --disable-warning=ExperimentalWarning)

echo "── Suite: held_handoff_test (E-271) ────────────────────────────────"

# _mkproj [queue-json] → a project dir with .ai/ and a queue on disk.
_mkproj() {
  local d q
  d="$(test_tmpdir e271-proj)"
  # The default is assigned SEPARATELY: `${1:-[{…}]}` ends at the first `}` in the JSON,
  # so an inline default silently produced `…"hello"]}` — malformed, and the drain then
  # had nothing pending to hold.
  q="${1:-}"
  [[ -n "$q" ]] || q='[{"timestamp":"1","target":"engineer","message":"hello"}]'
  mkdir -p "${d}/.ai"
  printf '%s' "$q" > "${d}/.ai/signal.json"
  printf '%s' "$d"
}

# _drain <proj> <panes> <ready:0|1> → the combined output of ONE real _drain_once.
#
# The pane rows and the ready probe are separate inputs on purpose, because the two holds
# are reached differently: `no-pane` when resolve_pane finds nothing, `busy` when it DOES
# resolve but the pane's foreground command is not the agent REPL. So a busy fixture needs
# an AGENT pane (it must resolve) whose ready probe answers something else.
_drain() {
  local proj="$1" panes="$2" ready="${3:-0}"
  ( cd "$proj" && env PANES="$panes" READY="$ready" bash -c "
      source '$WATCH' 2>/dev/null
      PROJECT_DIR='$proj'; SIGNAL='${proj}/.ai/signal.json'
      WATCH_TARGETS='engineer'; ROLES_MAPPING='architect:claude:1|engineer:claude:0'
      _project_panes() { printf '%b' \"\$PANES\"; }
      tmux() {
        # display-message is the ready probe: an agent command means ready, empty means busy.
        if [[ \"\$1\" == display-message && \"\$READY\" == 1 ]]; then printf '2.1.161'; fi
        return 0
      }
      _drain_once" ) 2>&1
}
_field() {  # <proj> <key> [index] → queue[index][key]
  python3 - "${1}/.ai/signal.json" "$2" "${3:-0}" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
if isinstance(d, dict): d = [d]
e = d[int(sys.argv[3])]
v = e.get(sys.argv[2], "")
print("" if v is None else v)
PY
}

# An AGENT pane bound to the role: it RESOLVES, so the hold that follows is about readiness.
PANES_AGENT='%9\t0\t-\twin\t/proj\t2.1.161\tengineer\n'
PANES_NONE=''

# ── E-271.1: busy → hold_reason written once, reported once ──────────────
P="$(_mkproj)"
OUT="$(_drain "$P" "$PANES_AGENT" 0)"
assert_contains "E-271.01a: a busy pane prints one HELD line naming the reason" \
  "HELD engineer entry 1 — reason busy" "$OUT"
assert_contains "E-271.01b: and says nothing expires" "nothing expires" "$OUT"
assert_status 0 "E-271.01c: hold_reason is recorded on the entry" \
  test "$(_field "$P" hold_reason)" = "busy"
assert_status 0 "E-271.01d: hold_since is recorded" bash -c "[[ -n '$(_field "$P" hold_since)' ]]"
assert_status 0 "E-271.01e: attempts counts the try" test "$(_field "$P" attempts)" = "1"
_SINCE="$(_field "$P" hold_since)"
OUT2="$(_drain "$P" "$PANES_AGENT" 0)"
assert_not_contains "E-271.01f: an unchanged reason does NOT print again" "HELD engineer" "$OUT2"
assert_status 0 "E-271.01g: hold_since is not reset by a repeat hold" \
  test "$(_field "$P" hold_since)" = "$_SINCE"
assert_status 0 "E-271.01h: attempts keeps counting" test "$(_field "$P" attempts)" = "2"
assert_status 0 "E-271.01i: the entry is still undelivered (MAX_HOLD=0 holds)" \
  test "$(_field "$P" delivered)" = ""

# ── E-271.2: the reason CHANGES → reported again ─────────────────────────
OUT3="$(_drain "$P" "$PANES_NONE" 0)"
assert_contains "E-271.02a: a changed reason prints a fresh HELD line" \
  "reason no-pane" "$OUT3"
assert_status 0 "E-271.02b: and replaces hold_reason" test "$(_field "$P" hold_reason)" = "no-pane"
assert_status 1 "E-271.02c: hold_since moves with the new reason" \
  test "$(_field "$P" hold_since)" = "$_SINCE"

# ── E-271.3: delivery clears the hold marks ──────────────────────────────
OUT4="$(_drain "$P" "$PANES_AGENT" 1)"
assert_contains "E-271.03a: the entry is delivered once a ready pane exists" "routed → engineer" "$OUT4"
assert_status 0 "E-271.03b: delivered is set" test "$(_field "$P" delivered)" = "True"
assert_status 0 "E-271.03c: hold_reason is cleared" test "$(_field "$P" hold_reason)" = ""
assert_status 0 "E-271.03d: hold_since is cleared" test "$(_field "$P" hold_since)" = ""

# ── E-271.4: foreign-session is distinguished from no-pane ───────────────
# The role's pane exists for this project but lives in ANOTHER tmux session, so this
# watcher (scoped to its own session since D-068) cannot see it. That is a different fault
# from "the pane was never started", and the operator needs to be told which one it is.
P2="$(_mkproj)"
OUT="$( cd "$P2" && env PANES="" bash -c "
    source '$WATCH' 2>/dev/null
    PROJECT_DIR='$P2'; SIGNAL='${P2}/.ai/signal.json'
    WATCH_TARGETS='engineer'; ROLES_MAPPING='architect:claude:1|engineer:claude:0'
    WATCH_SESSION='mine'
    _project_panes() { printf ''; }                      # nothing in MY session
    tmux() {                                             # but the pane exists elsewhere
      if [[ \"\$1\" == list-panes ]]; then
        printf '%b' '%7\t0\t-\twin\t${P2}\t2.1.161\tengineer\n'
      fi
      return 0
    }
    _drain_once" 2>&1 )"
assert_contains "E-271.04a: a pane in another session is reported as foreign-session" \
  "reason foreign-session" "$OUT"
assert_status 0 "E-271.04b: and recorded as such" test "$(_field "$P2" hold_reason)" = "foreign-session"

# ── E-271.5: the queued line (ai start --status and ai doctor) ───────────
_ql() { bash -c ". '${SCRIPT_DIR}/../lib/assert.sh' >/dev/null 2>&1
  $(awk '/^_queued_handoffs\(\) \{/,/^}$/' "$AI")
  _queued_handoffs '$1'"; }
assert_match "E-271.05a: a held entry is reported with age and reason" \
  'queued: 1 \(oldest held [0-9]+[smhd].*reason foreign-session, target engineer, attempts 1\)' "$(_ql "$P2")"
assert_contains "E-271.05b: a fully delivered queue reports zero" "queued: 0" "$(_ql "$P")"
_EMPTY="$(test_tmpdir e271-empty)"
assert_contains "E-271.05c: no signal.json is not an error" "queued: 0 (no signal.json)" "$(_ql "$_EMPTY")"
mkdir -p "${_EMPTY}/.ai" && printf 'not json' > "${_EMPTY}/.ai/signal.json"
assert_contains "E-271.05d: a corrupt queue says so rather than printing 0" "queued: ?" "$(_ql "$_EMPTY")"
assert_status 0 "E-271.05e: ai doctor prints the bridge section" grep -q 'echo "Handoff bridge:"' "$AI"
assert_status 0 "E-271.05f: ai start --status prints the queue line" \
  bash -c "grep -A3 'watcher: STALE lock' '$AI' | grep -q '_queued_handoffs'"

# ── E-271.6: roles.json is re-read when it changes, no restart ───────────
P3="$(_mkproj)"
mkdir -p "${P3}/.ai"
cat > "${P3}/.ai/roles.json" <<'JSON'
{ "roles": { "engineer": { "provider": "claude", "pane_identifier": "0" },
             "architect": { "provider": "claude", "pane_identifier": "1" } } }
JSON
_reload="$( cd "$P3" && bash -c "
    source '$WATCH' 2>/dev/null
    PROJECT_DIR='$P3'
    ROLES_MAPPING=\"\$(_load_roles_mapping)\"; _ROLES_MTIME=\"\$(_roles_mtime)\"
    echo \"before=\$ROLES_MAPPING\"
    sleep 1.1
    cat > '${P3}/.ai/roles.json' <<'J2'
{ \"roles\": { \"engineer\": { \"provider\": \"claude\", \"pane_identifier\": \"3\" },
             \"architect\": { \"provider\": \"claude\", \"pane_identifier\": \"1\" } } }
J2
    _refresh_roles_mapping
    echo \"after=\$ROLES_MAPPING\"" 2>&1 )"
assert_contains "E-271.06a: the mapping starts at pane 0 for the engineer" "before=architect:claude:1|engineer:claude:0" "$_reload"
assert_contains "E-271.06b: an edited roles.json is picked up mid-run" "after=architect:claude:1|engineer:claude:3" "$_reload"
assert_contains "E-271.06c: and the reload is announced" "role routing RELOADED" "$_reload"
assert_status 0 "E-271.06d: the watch loop refreshes every tick" \
  bash -c "grep -A3 'while true; do' '$WATCH' | grep -q '_refresh_roles_mapping'"

# ── E-271.7: the writers — [SIGNAL_LOCKED] and stale-lock reclaim ────────
P4="$(_mkproj)"
LOCK="${P4}/.ai/signal.json.lock"
mkdir -p "$LOCK" && echo $$ > "${LOCK}/pid"      # held by THIS (live) process
_emit() { ( cd "$P4" && node "${NODE_Q[@]}" --input-type=module -e "
  import { emitHandoff } from '${HANDOFF}';
  const r = emitHandoff({ aiDir: '${P4}/.ai', target: 'engineer', message: 'x' });
  console.log(r.ok ? 'OK' : r.code);" ) 2>&1; }
_t0="$(date +%s)"
OUT="$(_emit)"   # waits the full LOCK_WAIT_MS (5s) and then fails, by design
_elapsed=$(( $(date +%s) - _t0 ))
assert_contains "E-271.07a: a lock held by a LIVE owner fails with [SIGNAL_LOCKED]" "SIGNAL_LOCKED" "$OUT"
assert_status 0 "E-271.07b: after waiting ~5s, not appending unlocked" bash -c "[[ $_elapsed -ge 4 ]]"
assert_status 0 "E-271.07c: the queue was NOT touched" test "$(_field "$P4" message)" = "hello"
# A dead owner's lock, older than the stale window, is reclaimed rather than honoured.
echo 999999 > "${LOCK}/pid"
python3 -c "import os,sys,time; t=time.time()-3600; os.utime(sys.argv[1], (t,t))" "$LOCK"
OUT="$(_emit)"
assert_contains "E-271.07d: a stale lock with a dead owner is reclaimed and the emit succeeds" "OK" "$OUT"
assert_status 1 "E-271.07e: and the lock directory is released" test -e "$LOCK"
assert_status 0 "E-271.07f: the new entry landed" test "$(_field "$P4" message 1)" = "x"
assert_status 0 "E-271.07g: the writer renames a tmp file into place (atomic)" \
  grep -q 'renameSync(tmp, signalPath)' "$HANDOFF"
assert_status 0 "E-271.07h: no .tmp file is left behind" \
  bash -c "! compgen -G '${P4}/.ai/signal.json.tmp.*' >/dev/null"
assert_status 0 "E-271.07i: the watcher shares the reclaim contract" \
  grep -q '_signal_lock_reclaim' "$WATCH"

# ── E-271.8: a concurrent emit and a watcher rewrite lose nothing ────────
# 100 iterations: each round appends one entry while the watcher's own writer marks the
# previous one delivered. Losing an entry is the failure an unlocked append caused.
P5="$(_mkproj '[]')"
printf '%s' '[]' > "${P5}/.ai/signal.json"
_conc="$( cd "$P5" && bash -c "
    source '$WATCH' 2>/dev/null
    PROJECT_DIR='$P5'; SIGNAL='${P5}/.ai/signal.json'
    for i in \$(seq 1 100); do
      ( node ${NODE_Q[*]} --input-type=module -e \"
          import { emitHandoff } from '${HANDOFF}';
          emitHandoff({ aiDir: '${P5}/.ai', target: 'engineer', message: 'm'+\$i });\" >/dev/null 2>&1 ) &
      _bump_attempt \"\$i\" >/dev/null 2>&1
      wait
    done" 2>&1 )"
_n="$(python3 -c "
import json
d=json.load(open('${P5}/.ai/signal.json'))
print(len(d), len({e.get('message') for e in d if isinstance(e, dict)}))" 2>/dev/null)"
assert_contains "E-271.08a: all 100 concurrent emits survived (entries, distinct messages)" "100 100" "$_n"
assert_status 0 "E-271.08b: the queue is valid JSON after the run" \
  python3 -c "import json;json.load(open('${P5}/.ai/signal.json'))"

# ── E-271.9: test watchers are reaped, and the harness counts them ───────
assert_status 0 "E-271.09a: watcher_reexec_test registers its watcher for cleanup" \
  bash -c "grep -A2 'wp=\\\$!' '${REPO_ROOT}/tests/suites/watcher_reexec_test.sh' | grep -q 'register_cleanup'"
assert_status 0 "E-271.09b: and execs it, so the pid it kills IS the watcher" \
  grep -q 'exec env AI_WATCH_NO_REEXEC' "${REPO_ROOT}/tests/suites/watcher_reexec_test.sh"
assert_status 0 "E-271.09c: the runner's leak snapshot counts ai-watch processes" \
  bash -c "sed -n '/^_leak_snapshot() {/,/^}/p' '${REPO_ROOT}/tests/run.sh' | grep -q 'watcher|'"
assert_status 0 "E-271.09d: and the sweep can reap one" \
  bash -c "sed -n '/^_leak_sweep() {/,/^}/p' '${REPO_ROOT}/tests/run.sh' | grep -q 'watcher)'"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== held_handoff_test.sh PASS ====="
else
  echo "===== held_handoff_test.sh FAIL (${FAIL_COUNT}) ====="
fi
