#!/usr/bin/env bash
# ai_watch_test.sh — the `ai-watch` Interactive Bridge tmux watcher routes
# .ai/signal.json handoffs to the target agent's pane, scoped to the current
# project, with literal (injection-safe) send-keys.
#   E-115 base · E-117 hardened resolution · E-118 queue + busy-gate ·
#   E-122 version-string readiness + submit delay ·
#   E-123 SMART delivery: persistent delivered-flag consumption, startup backlog
#         drain (latest per target), per-target independence, agent-aware pane
#         resolution (shells excluded), single-writer lock, hold-not-drop.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH="${REPO_ROOT}/src/bin/ai-watch"
AI="${REPO_ROOT}/src/bin/ai"
INSTALLER="${REPO_ROOT}/install-ai-os.sh"

echo "===== ai_watch_test.sh ====="

# ── S01: script exists, is executable, parses ────────────────────────────────
assert_status 0 "src/bin/ai-watch exists"      test -f "$WATCH"
assert_status 0 "src/bin/ai-watch executable"  test -x "$WATCH"
assert_status 0 "src/bin/ai-watch parses"      bash -n "$WATCH"

# ── S02: preconditions guarded (tmux, tmux session, .ai/, python3) ───────────
assert_status 0 "guards on tmux install"   grep -qE 'command -v tmux' "$WATCH"
assert_status 0 "guards on tmux session"   grep -qE 'tmux info' "$WATCH"
assert_status 0 "guards on .ai/ presence"  grep -qE '\.ai.*AI-OS project root|no \.ai/' "$WATCH"

# ── S03: isolation — only panes rooted in the project dir (Security §) ───────
assert_status 0 "scopes to pane_current_path within PROJECT_DIR" \
  grep -qF 'pane_current_path' "$WATCH"
assert_status 0 "filters panes by PROJECT_DIR" \
  grep -qE '"\$PROJECT_DIR"\|"\$PROJECT_DIR"/\*' "$WATCH"

# ── S04: injection-safe — message sent literally with -l -- ──────────────────
assert_status 0 "send-keys uses literal -l -- (no key/shell interpretation)" \
  grep -qE 'send-keys -t "\$pane" -l -- "\$message"' "$WATCH"

# ── S05: target→pane mapping (claude→0, gemini→1, or pane title) ─────────────
assert_status 0 "maps claude→index 0" grep -qE 'claude\) want_idx=0' "$WATCH"
assert_status 0 "maps gemini→index 1" grep -qE 'gemini\) want_idx=1' "$WATCH"
assert_status 0 "prefers pane title match" grep -qE 'ptitle" == "\$target"' "$WATCH"

# ── S06: behavioural — run outside an AI-OS project exits fast (never loops) ──
SB="$(mktemp -d)"
out="$(cd "$SB" && bash "$WATCH" 2>&1)"; rc=$?
assert_status 0 "exits non-zero without a valid project/tmux (no hang)" bash -c "[ $rc -ne 0 ]"
assert_contains "emits an ai-watch: diagnostic" "ai-watch:" "$out"
rm -rf "$SB"

# ── S07: `ai watch` dispatches to the global ai-watch ────────────────────────
assert_status 0 "ai CLI has a 'watch)' dispatch" \
  grep -qE '^\s*watch\)\s*exec.*ai-watch' "$AI"

# ── S08: installer deploys src/bin (rsync) + makes ai-watch executable ───────
assert_status 0 "installer rsyncs src/bin → ~/.ai-os/bin" \
  grep -qE 'src/bin/.*\$\{AIOS\}/bin/' "$INSTALLER"
assert_status 0 "installer chmod +x ai-watch" \
  grep -qE 'chmod \+x "\$\{AIOS\}/bin/ai-watch"' "$INSTALLER"

# ── S09: mirror identity (src ↔ ~/.ai-os) ────────────────────────────────────
assert_status 0 "ai-watch ~/.ai-os mirror identical" \
  diff -q "$WATCH" "${HOME}/.ai-os/bin/ai-watch"

# ── E-117: hardened pane resolution (fuzzy titles, window names, base-index 1) ─
echo "── E-117: hardened pane resolution ─────────────────────────────────"

assert_status 0 "E-117.S10: _project_panes emits window_name" \
  grep -qF '#{window_name}' "$WATCH"
assert_status 0 "E-117.S10: _lc lowercases for case-insensitive match" \
  grep -qE "_lc\(\).*tr '\[:upper:\]' '\[:lower:\]'" "$WATCH"
assert_status 0 "E-117.S11: fuzzy substring match on title/window" \
  grep -qE '\*"\$lc_target"\*' "$WATCH"
assert_status 0 "E-117.S12: ordinal fallback sorts by pane index" \
  grep -qE 'sort -t.* -k2,2n' "$WATCH"
assert_status 0 "E-117.S13: source-guard via return idiom" \
  grep -qE 'return 0 2>/dev/null' "$WATCH"
assert_status 0 "E-117.S13: preconditions are guarded in a function" \
  grep -qE '^_preconditions\(\)' "$WATCH"

# ── E-117 behavioural: source the script, mock _project_panes, drive resolve ──
# The mock reads $_PANES (printf %b → \t/\n become real); the subshell inherits it.
_PANES=""
_resolve() {  # _resolve <target> → resolved pane id (sourced + mocked, no tmux)
  ( source "$WATCH" 2>/dev/null
    _project_panes() { printf '%b' "$_PANES"; }
    resolve_pane "$1" )
}

# Pass 1 — exact pane-title (5-field mocks: no command column → TIER B ordinal).
_PANES='%0\t0\tclaude\twin0\t/p\n%1\t1\tgemini\twin1\t/p\n'
assert_contains "E-117.B1: exact title claude→%0" "%0" "$(_resolve claude)"
assert_contains "E-117.B1: exact title gemini→%1" "%1" "$(_resolve gemini)"

# Pass 2 — fuzzy, case-insensitive pane-title ("Claude-Code").
_PANES='%7\t0\tClaude-Code\tbash\t/p\n%8\t1\tGemini-CLI\tbash\t/p\n'
assert_contains "E-117.B2: fuzzy CI title claude-code→%7" "%7" "$(_resolve claude)"

# Pass 3 — window-name match when pane titles are generic shells.
_PANES='%3\t0\tzsh\tclaude-engineer\t/p\n%4\t1\tzsh\tgemini-arch\t/p\n'
assert_contains "E-117.B3: window-name claude→%3" "%3" "$(_resolve claude)"
assert_contains "E-117.B3: window-name gemini→%4" "%4" "$(_resolve gemini)"

# Pass 4 — base-index 1, NO command column → TIER B all-panes ordinal still works.
_PANES='%21\t1\tzsh\tmain\t/p\n%22\t2\tzsh\tmain\t/p\n'
assert_contains "E-117.B4: base-index-1 claude→1st(%21)" "%21" "$(_resolve claude)"
assert_contains "E-117.B4: base-index-1 gemini→2nd(%22)" "%22" "$(_resolve gemini)"

# Pass 4 — unsorted input still picks the lowest-index pane for claude.
_PANES='%32\t2\tzsh\tmain\t/p\n%31\t1\tzsh\tmain\t/p\n'
assert_contains "E-117.B4: unsorted→claude lowest idx(%31)" "%31" "$(_resolve claude)"

# No matching pane → empty (caller logs "no pane").
_PANES=''
_b5_got="$(_resolve claude)"
assert_status 0 "E-117.B5: no pane → empty result" test -z "$_b5_got"

# ── E-122: agent-aware ordinal resolution — shells excluded ───────────────────
echo "── E-122: agent-aware pane resolution (shells excluded) ─────────────"
assert_status 0 "E-122.R0: _is_agent_cmd shared predicate defined" \
  grep -qE '^_is_agent_cmd\(\)' "$WATCH"
assert_status 0 "E-122.R0: resolution adds pane_current_command field" \
  grep -qF '#{pane_current_command}' "$WATCH"

# 6-field mock (with command column): claude=version pane, gemini=node pane, plus
# two plain shells that MUST be skipped — reproduces the live ai-os-v2 bug.
_PANES='%1\t1\tt1\twin\t/p\t2.1.161\n%2\t2\tt2\twin\t/p\tnode\n%33\t3\tt3\twin\t/p\tbash\n%34\t1\tt4\twin\t/p\tzsh\n'
assert_contains "E-122.R1: claude → 1st agent pane (%1 version cmd)" "%1" "$(_resolve claude)"
assert_contains "E-122.R2: gemini → 2nd agent pane (%2 node, NOT %34 zsh)" "%2" "$(_resolve gemini)"

# v3.0 (E-134 post-migration): the Architect runs `agy` (Antigravity CLI). Without
# agy in the agent-command set the agy pane was treated as a shell and architect/
# gemini handoffs resolved to NOTHING (the live bug: handoffs stuck delivered:false).
_PANES='%1\t1\tt1\twin\t/p\t2.1.168\n%2\t2\tt2\twin\t/p\tagy\n%33\t3\tt3\twin\t/p\tbash\n'
assert_contains "E-134: gemini → agy pane (%2), not dropped"      "%2" "$(_resolve gemini)"
assert_contains "E-134: architect → agy pane (%2) via legacy map" "%2" "$(_resolve architect)"
assert_contains "E-134: claude still → 1st agent (%1) past agy"   "%1" "$(_resolve claude)"

# v3.0 (E-134): agy panes carry an EMPTY pane_title. The tmux -F format MUST guard
# empty title/window with a placeholder — otherwise `IFS=$'\t' read` collapses the
# resulting consecutive tabs (tab is whitespace-class) and shifts pane_current_path
# out of position, so the PROJECT_DIR filter silently drops the agy pane (the live
# bug: handoffs to the Architect stuck delivered:false). Structural guard — a real
# empty-title repro needs live tmux (absent in CI).
assert_status 0 "E-134: _project_panes guards empty pane_title (agy has none)" \
  grep -qF '#{?pane_title,#{pane_title}' "$WATCH"
assert_status 0 "E-134: _project_panes guards empty window_name" \
  grep -qF '#{?window_name,#{window_name}' "$WATCH"

# All eligible panes are shells (command column present) → no misroute, empty.
_PANES='%5\t1\tt\twin\t/p\tbash\n%6\t2\tt\twin\t/p\tzsh\n'
_r_allsh="$(_resolve gemini)"
assert_status 0 "E-122.R3: all-shells (cmd present) → empty, never a shell" test -z "$_r_allsh"

# ── E-118: queue parsing helpers + busy-state gate (source contract) ──────────
echo "── E-118: queue helpers + busy gate ────────────────────────────────"
assert_status 0 "E-118.S14: _queue_len helper present"   grep -qE '^_queue_len\(\)'   "$WATCH"
assert_status 0 "E-118.S14: _queue_field helper present" grep -qE '^_queue_field\(\)' "$WATCH"
assert_status 0 "E-118.S15: _pane_ready helper present" grep -qE '^_pane_ready\(\)' "$WATCH"
assert_status 0 "E-118.S15: reads pane_current_command" grep -qF '#{pane_current_command}' "$WATCH"
assert_status 0 "E-118.S15: configurable ready set"     grep -qF 'AI_WATCH_READY_CMDS' "$WATCH"
assert_status 0 "E-118.S15: NO_BUSY_CHECK bypass"       grep -qF 'AI_WATCH_NO_BUSY_CHECK' "$WATCH"
assert_status 0 "E-118.S16: _drain_once helper present" grep -qE '^_drain_once\(\)' "$WATCH"
assert_status 0 "E-118.S16: legacy mode preserves the in-memory cursor (rollback)" \
  grep -qF 'CURSOR' "$WATCH"

# Busy-gate unit: ready set vs busy command, plus the bypass flag (mocked tmux
# returns the command-under-test for any call — that is what _pane_ready reads).
_ready_probe() {  # _ready_probe <cmd> <bypass:0|1> → "READY"|"BUSY"
  ( source "$WATCH" 2>/dev/null
    AI_WATCH_NO_BUSY_CHECK="$2"
    _probe_cmd="$1"
    tmux() { printf '%s' "$_probe_cmd"; }
    if _pane_ready "%X"; then echo READY; else echo BUSY; fi )
}
assert_contains "E-118.B7: node → READY"   "READY" "$(_ready_probe node 0)"
assert_contains "E-134: agy → READY (Antigravity Architect pane)" "READY" "$(_ready_probe agy 0)"
assert_contains "E-118.B7: bash → BUSY"    "BUSY"  "$(_ready_probe bash 0)"
assert_contains "E-118.B7: python → BUSY"  "BUSY"  "$(_ready_probe python3 0)"
assert_contains "E-118.B7: bypass → READY" "READY" "$(_ready_probe bash 1)"

# ── E-122: version-string ready heuristic + configurable submission delay ─────
echo "── E-122: version-string readiness + submit delay ──────────────────"
assert_status 0 "E-122.S17: version-string regex permits N.N.N commands" \
  grep -qF '=~ ^[0-9]+\.[0-9]+\.[0-9]+' "$WATCH"
assert_status 0 "E-122.S17: submit delay configurable via AI_WATCH_SUBMIT_DELAY" \
  grep -qF 'AI_WATCH_SUBMIT_DELAY' "$WATCH"
assert_status 0 "E-122.S17: submit delay defaults to 0.1s" \
  grep -qE 'SUBMIT_DELAY="\$\{AI_WATCH_SUBMIT_DELAY:-0\.1\}"' "$WATCH"
assert_status 0 "E-122.S17: _drain_once sleeps SUBMIT_DELAY before Enter" \
  grep -qE 'sleep "\$SUBMIT_DELAY"' "$WATCH"

assert_contains "E-122.B8: version 2.1.161 → READY"              "READY" "$(_ready_probe 2.1.161 0)"
assert_contains "E-122.B8: version 0.10.5 → READY"               "READY" "$(_ready_probe 0.10.5 0)"
assert_contains "E-122.B8: version + suffix 2.1.161-rc1 → READY" "READY" "$(_ready_probe 2.1.161-rc1 0)"
assert_contains "E-122.B8: two-part 2.1 → BUSY (needs 3 groups)" "BUSY"  "$(_ready_probe 2.1 0)"
assert_contains "E-122.B8: bare pid 12345 → BUSY"                "BUSY"  "$(_ready_probe 12345 0)"

# Submission reliability — message injected, THEN a delay, THEN Enter. Mock sleep
# + tmux to record the call ORDER without real latency; captured "sleep(0.1)" also
# proves the 0.1s default reaches the sleep call.
_submit_seq() {  # → ">msg>sleep(<delay>)>enter" trace for one queued entry
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$(mktemp)"; printf '%s' '[{"timestamp":"t","target":"claude","message":"go"}]' > "$SIGNAL"
    _SEQ=""
    tmux() {
      if [ "$1" = "send-keys" ]; then shift
        case " $* " in *" Enter "*) _SEQ="${_SEQ}>enter" ;; *) _SEQ="${_SEQ}>msg" ;; esac
      fi; return 0; }
    sleep() { _SEQ="${_SEQ}>sleep(${1})"; }
    resolve_pane() { printf '%s' '%P'; }
    _pane_ready() { return 0; }
    _drain_once 2>/dev/null
    printf '%s' "$_SEQ"
    rm -f "$SIGNAL" )
}
assert_contains "E-122.B9: order is message → delay → Enter" ">msg>sleep(0.1)>enter" "$(_submit_seq)"

# ── E-123: SMART delivery (persistent flag, per-target, drain, lock) ───────────
echo "── E-123: smart delivery (persistent / per-target / lock) ──────────"

# Source contract: the new mechanism is present.
assert_status 0 "E-123.S20: persistent delivered-flag readers" grep -qE '^_next_pending_ts\(\)' "$WATCH"
assert_status 0 "E-123.S20: delivered-flag writer (atomic)"    grep -qE '^_mark_delivered\(\)' "$WATCH"
assert_status 0 "E-123.S20: startup reconciliation present"    grep -qE '^_reconcile_startup\(\)' "$WATCH"
assert_status 0 "E-123.S20: single-writer lock present"        grep -qE '^_acquire_lock\(\)' "$WATCH"
assert_status 0 "E-123.S20: atomic write via os.replace"       grep -qF 'os.replace' "$WATCH"
assert_status 0 "E-123.S20: drain-backlog knob"               grep -qF 'AI_WATCH_DRAIN_BACKLOG' "$WATCH"
assert_status 0 "E-123.S20: legacy rollback mode"             grep -qF 'AI_WATCH_CURSOR_MODE' "$WATCH"

# Behavioural harness: write a queue to a temp SIGNAL, mock tmux/resolve/ready
# (TARGET-AWARE), run _drain_once N times, report sends + final delivered flags.
_run_drain() {  # <qjson> <claude_pane|''> <gemini_pane|''> <ready_panes> <passes>
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$(mktemp)"; printf '%s' "$1" > "$SIGNAL"
    SUBMIT_DELAY=0; MAX_HOLD=0
    _CL="$2"; _GE="$3"; _READY="$4"; _P="${5:-1}"
    _SENT=""
    tmux() { if [ "$1" = "send-keys" ]; then shift; _SENT="${_SENT}|$*"; fi; return 0; }
    resolve_pane() { case "$1" in claude) printf '%s' "$_CL" ;; gemini) printf '%s' "$_GE" ;; esac; }
    _pane_ready() { case " $_READY " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
    _i=0; while [ "$_i" -lt "$_P" ]; do _drain_once 2>/dev/null; _i=$((_i + 1)); done
    _c=$(printf '%s' "$_SENT" | grep -o -- '-l --' | wc -l | tr -d ' ')
    _f="$(python3 - "$SIGNAL" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(",".join("%s:%s" % (e.get("target"), "D" if e.get("delivered") else "P") for e in d))
PY
)"
    printf 'sent=[%s] count=%s flags=[%s]' "$_SENT" "$_c" "$_f"
    rm -f "$SIGNAL" )
}

# TC-03 (THE live bug): a busy/blocked gemini must NOT hold up ready claude work.
out="$(_run_drain '[{"timestamp":"1","target":"gemini","message":"g1"},{"timestamp":"2","target":"claude","message":"c1"}]' '%cl' '%ge' '%cl' 1)"
assert_contains "E-123.TC03: claude delivered though gemini busy" "-l -- c1" "$out"
assert_contains "E-123.TC03: only claude delivered (gemini held)" "count=1" "$out"
assert_contains "E-123.TC03: gemini pending, claude delivered"    "gemini:P,claude:D" "$out"

# TC-02 sequential per target: two claude entries deliver in FIFO order over 2 passes.
out="$(_run_drain '[{"timestamp":"1","target":"claude","message":"a"},{"timestamp":"2","target":"claude","message":"b"}]' '%cl' '%ge' '%cl' 2)"
assert_contains "E-123.TC02: both claude entries delivered"  "count=2" "$out"
assert_contains "E-123.TC02: FIFO a before b"                "-l -- a|-t %cl Enter|-t %cl -l -- b" "$out"

# TC-04 persistent idempotency: 1 claude + 1 gemini, ready, 2 passes → 2 sends, no replay.
out="$(_run_drain '[{"timestamp":"1","target":"claude","message":"a"},{"timestamp":"2","target":"gemini","message":"g"}]' '%cl' '%ge' '%cl %ge' 2)"
assert_contains "E-123.TC04: delivered-flag blocks replay (2 not 4)" "count=2" "$out"
assert_contains "E-123.TC04: both flagged delivered"                "claude:D,gemini:D" "$out"

# TC-02b busy → held (not dropped): busy target injects nothing, entry stays pending.
out="$(_run_drain '[{"timestamp":"1","target":"claude","message":"a"}]' '%cl' '%ge' '' 1)"
assert_contains "E-123.TC02b: busy target injects nothing" "count=0" "$out"
assert_contains "E-123.TC02b: held entry stays pending"    "claude:P" "$out"

# TC-09 malformed entry (no message) skipped; the valid neighbour is delivered.
out="$(_run_drain '[{"timestamp":"1","target":"claude"},{"timestamp":"2","target":"claude","message":"ok"}]' '%cl' '%ge' '%cl' 2)"
assert_contains "E-123.TC09: malformed skipped, valid delivered" "-l -- ok" "$out"

# TC-NoPane: a transient missing pane HOLDS (not drops); MAX_HOLD bounds the hold.
_nopane_probe() {  # <max_hold> <passes> → "<D|P>:<reason>:att<n>"
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$(mktemp)"; printf '%s' '[{"timestamp":"1","target":"gemini","message":"g"}]' > "$SIGNAL"
    SUBMIT_DELAY=0; MAX_HOLD="$1"
    tmux() { return 0; }
    resolve_pane() { printf ''; }            # no pane resolvable
    _pane_ready() { return 0; }
    _i=0; while [ "$_i" -lt "$2" ]; do _drain_once 2>/dev/null; _i=$((_i + 1)); done
    python3 - "$SIGNAL" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))[0]
print(("D" if e.get("delivered") else "P") + ":" + str(e.get("delivered_reason", "")) + ":att" + str(e.get("attempts", 0)))
PY
    rm -f "$SIGNAL" )
}
assert_contains "E-123.TCnp: MAX_HOLD=0 holds forever (still pending)" "P:" "$(_nopane_probe 0 3)"
assert_contains "E-123.TCnp: MAX_HOLD=2 expires after 2 attempts"      "D:expired" "$(_nopane_probe 2 2)"

# TC-06 startup reconciliation: drain collapses duplicates to latest; drain=0 skips all.
_reconcile_probe() {  # <qjson> <drain> → per-entry flags
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$(mktemp)"; printf '%s' "$1" > "$SIGNAL"
    _reconcile_startup "$2"
    python3 - "$SIGNAL" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(",".join("%s:%s:%s" % (e.get("target"), "D" if e.get("delivered") else "P", e.get("delivered_reason", "")) for e in d))
PY
    rm -f "$SIGNAL" )
}
out="$(_reconcile_probe '[{"timestamp":"1","target":"claude","message":"x"},{"timestamp":"2","target":"claude","message":"x"}]' 1)"
assert_contains "E-123.TC06: drain supersedes the older duplicate" "claude:D:superseded" "$out"
assert_contains "E-123.TC06: drain keeps the latest pending"       "claude:P:" "$out"
out="$(_reconcile_probe '[{"timestamp":"1","target":"gemini","message":"g"}]' 0)"
assert_contains "E-123.TC06: drain=0 marks backlog skipped" "gemini:D:skipped-backlog" "$out"

# TC-07 single-writer lock: fresh acquire ok; live holder rejected; stale reclaimed; disabled.
_lock_probe() {  # <mode> → OK|FAIL
  ( source "$WATCH" 2>/dev/null
    USE_LOCK=1; LOCK_DIR="$(mktemp -d)/ai-watch.lock"
    case "$1" in
      acquire)  _acquire_lock && echo OK || echo FAIL ;;
      double)   _acquire_lock >/dev/null; _acquire_lock && echo OK || echo FAIL ;;
      stale)    mkdir -p "$LOCK_DIR"; echo 999999 > "$LOCK_DIR/pid"; _acquire_lock && echo OK || echo FAIL ;;
      disabled) USE_LOCK=0; _acquire_lock && echo OK || echo FAIL ;;
    esac )
}
assert_contains "E-123.TC07: fresh lock acquired"          "OK"   "$(_lock_probe acquire)"
assert_contains "E-123.TC07: live holder rejects 2nd watcher" "FAIL" "$(_lock_probe double)"
assert_contains "E-123.TC07: stale lock (dead pid) reclaimed" "OK"   "$(_lock_probe stale)"
assert_contains "E-123.TC07: AI_WATCH_LOCK=0 disables locking" "OK"   "$(_lock_probe disabled)"

# TC-10 source-guard / no side-effects: sourcing acquires no lock and writes nothing.
_srcdir="$(mktemp -d)"
_noside="$( ( cd "$_srcdir" && mkdir -p .ai && source "$WATCH" 2>/dev/null; ls -a .ai 2>/dev/null | grep -c 'ai-watch.lock' ) )"
assert_contains "E-123.TC10: sourcing creates no lock" "0" "$_noside"
rm -rf "$_srcdir"

# ── E-123 hardening: review-driven coverage (must-fix + should-fix) ────────────
echo "── E-123 hardening (race/lock/portability coverage) ────────────────"

# S21: shared write-lock + MAX_HOLD numeric sanitisation are present in source.
assert_status 0 "E-123.S21: signal write-lock helpers present" grep -qE '^_signal_lock\(\)' "$WATCH"
assert_status 0 "E-123.S21: writers acquire the signal lock"   grep -qF '_signal_lock && _held=1' "$WATCH"
assert_status 0 "E-123.S21: MAX_HOLD sanitised to numeric-only" grep -qF 'MAX_HOLD=0 ;; esac' "$WATCH"
assert_status 0 "E-123.S21: stale lock reclaimed via atomic mv" grep -qF 'mv "$LOCK_DIR" "${LOCK_DIR}.stale.$$"' "$WATCH"
assert_status 0 "E-123.S21: handoff_control shares the .lock + delivered-aware eviction" \
  grep -qE 'signalPath \+ "\.lock"' "${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

# MH: non-numeric MAX_HOLD must NOT abort the watcher (bash-3.2 arithmetic trap).
_maxhold_env_probe() {  # <env_value> → "mh=<v> rc=<r>"
  AI_WATCH_MAX_HOLD="$1" bash -c '
    source "'"$WATCH"'" 2>/dev/null
    printf "mh=%s " "$MAX_HOLD"
    _maybe_expire t claude busy >/dev/null 2>&1
    printf "rc=%s" "$?"'
}
assert_contains "E-123.MH: non-numeric env sanitised to 0" "mh=0" "$(_maxhold_env_probe foo)"
assert_contains "E-123.MH: _maybe_expire survives bad env (no abort)" "rc=0" "$(_maxhold_env_probe foo)"
# defensive in-function guard: bad value set AFTER source (bypasses startup sanitise)
_maxhold_rt="$(bash -c 'source "'"$WATCH"'" 2>/dev/null; MAX_HOLD="2.5"; _maybe_expire t c busy >/dev/null 2>&1; printf "rc=%s" "$?"')"
assert_contains "E-123.MH: defensive guard survives bad runtime MAX_HOLD" "rc=0" "$_maxhold_rt"

# AG: _is_agent_cmd — single source of truth for routing + busy gate (direct table).
_agent_probe() { ( source "$WATCH" 2>/dev/null; _is_agent_cmd "$1" && echo agent || echo no ); }
assert_contains "E-123.AG: node → agent"            "agent" "$(_agent_probe node)"
assert_contains "E-123.AG: claude → agent"          "agent" "$(_agent_probe claude)"
assert_contains "E-123.AG: gemini → agent"          "agent" "$(_agent_probe gemini)"
assert_contains "E-123.AG: 2.1.161 → agent"         "agent" "$(_agent_probe 2.1.161)"
assert_contains "E-123.AG: bash → no"               "no"    "$(_agent_probe bash)"
assert_contains "E-123.AG: zsh → no"                "no"    "$(_agent_probe zsh)"
assert_contains "E-123.AG: fish → no"               "no"    "$(_agent_probe fish)"
assert_contains "E-123.AG: -bash login shell → no"  "no"    "$(_agent_probe -bash)"
assert_contains "E-123.AG: empty → no"              "no"    "$(_agent_probe '')"
assert_contains "E-123.AG: READY_CMDS admits custom 'mycli'" "agent" \
  "$( ( source "$WATCH" 2>/dev/null; AI_WATCH_READY_CMDS='node mycli'; _is_agent_cmd mycli && echo agent || echo no ) )"

# PR: _pane_ready empty-command safe default.
assert_contains "E-123.PR: empty cmd → BUSY (safe default)" "BUSY"  "$(_ready_probe '' 0)"
assert_contains "E-123.PR: empty cmd + bypass → READY"      "READY" "$(_ready_probe '' 1)"

# HC: has_cmd boundary — an empty-cmd pane is NOT chosen via TIER-B when another
# pane reported a command (otherwise gemini could fall back onto a command-less pane).
_PANES='%1\t1\tt\twin\t/p\tnode\n%2\t2\tt\twin\t/p\t\n'
assert_contains "E-123.HC: mixed cmd/empty → claude = real agent pane %1" "%1" "$(_resolve claude)"
_hc_g="$(_resolve gemini)"
assert_status 0 "E-123.HC: mixed → no 2nd agent pane → empty (TIER-B suppressed)" test -z "$_hc_g"

# RESTART idempotency (the headline claim): a fresh process re-reconciling the SAME
# on-disk file neither replays a delivered entry nor skips an undelivered one.
_restart_file="$(mktemp)"
printf '%s' '[{"timestamp":"1","target":"claude","message":"a"},{"timestamp":"2","target":"gemini","message":"g"}]' > "$_restart_file"
_boot_pass() {  # <signalfile> → number of literal sends this "boot"
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$1"; SUBMIT_DELAY=0; MAX_HOLD=0
    _S=""
    tmux() { if [ "$1" = "send-keys" ]; then shift; _S="${_S}|$*"; fi; return 0; }
    resolve_pane() { case "$1" in claude) printf '%%cl' ;; gemini) printf '%%ge' ;; esac; }
    _pane_ready() { return 0; }
    _reconcile_startup 1
    _drain_once 2>/dev/null
    printf '%s' "$_S" | grep -o -- '-l --' | wc -l | tr -d ' ' )
}
assert_contains "E-123.RESTART: first boot delivers both"                "2" "$(_boot_pass "$_restart_file")"
assert_contains "E-123.RESTART: restart replays nothing (flags persisted)" "0" "$(_boot_pass "$_restart_file")"
rm -f "$_restart_file"

# LEG: legacy rollback path is behaviourally verified (not just grepped).
_legacy_probe() {  # <qjson> <start_cursor> → literal-send count
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$(mktemp)"; printf '%s' "$1" > "$SIGNAL"; SUBMIT_DELAY=0
    _SENT=""
    tmux() { if [ "$1" = "send-keys" ]; then shift; _SENT="${_SENT}|$*"; fi; return 0; }
    resolve_pane() { printf '%s' '%P'; }
    _pane_ready() { return 0; }
    CURSOR="$2"
    _legacy_drain_once 2>/dev/null
    printf '%s' "$_SENT" | grep -o -- '-l --' | wc -l | tr -d ' '
    rm -f "$SIGNAL" )
}
assert_contains "E-123.LEG: legacy CURSOR=len skips backlog" "0" "$(_legacy_probe '[{"timestamp":"1","target":"claude","message":"a"}]' 1)"
assert_contains "E-123.LEG: legacy CURSOR=0 drains queue"    "1" "$(_legacy_probe '[{"timestamp":"1","target":"claude","message":"a"}]' 0)"

# RL: _release_lock removes our own lock but never a foreign one.
_releaselock_probe() {  # <mode> → PRESENT|GONE
  ( source "$WATCH" 2>/dev/null
    USE_LOCK=1; LOCK_DIR="$(mktemp -d)/ai-watch.lock"
    case "$1" in
      own)     _acquire_lock >/dev/null; _release_lock ;;
      foreign) mkdir -p "$LOCK_DIR"; echo 999999 > "$LOCK_DIR/pid"; _release_lock ;;
    esac
    test -d "$LOCK_DIR" && echo PRESENT || echo GONE )
}
assert_contains "E-123.RL: releases our own lock"        "GONE"    "$(_releaselock_probe own)"
assert_contains "E-123.RL: leaves a foreign lock intact" "PRESENT" "$(_releaselock_probe foreign)"

# INT: integration — only tmux (+sleep) mocked at the boundary; the REAL
# resolve_pane → _pane_ready → _is_agent_cmd chain runs. Reproduces the live
# ai-os-v2 layout and proves gemini routes to the node pane, not a shell.
_integration_drain() {  # <qjson> <panes_tsv> → captured send-keys args
  ( source "$WATCH" 2>/dev/null
    PROJECT_DIR="/proj"; SIGNAL="$(mktemp)"; SUBMIT_DELAY=0; MAX_HOLD=0
    printf '%s' "$1" > "$SIGNAL"
    _MP="$2"; _SENT=""
    tmux() {
      if [ "$1" = "list-panes" ]; then printf '%b' "$_MP"; return 0; fi
      if [ "$1" = "display-message" ]; then
        local p="" prev=""; for a in "$@"; do [ "$prev" = "-t" ] && p="$a"; prev="$a"; done
        printf '%b' "$_MP" | awk -F'\t' -v id="$p" '$1==id{printf "%s",$6}'
        return 0
      fi
      if [ "$1" = "send-keys" ]; then shift; _SENT="${_SENT}|$*"; fi
      return 0
    }
    _drain_once 2>/dev/null
    printf '%s' "$_SENT"
    rm -f "$SIGNAL" )
}
_panes_live='%1\t1\tt\twin\t/proj\t2.1.161\n%2\t2\tt\twin\t/proj\tnode\n%33\t3\tt\twin\t/proj\tbash\n%34\t1\tt\twin\t/proj\tzsh\n'
assert_contains "E-123.INT: gemini → node agent pane %2 (real chain, shells skipped)" \
  "%2 -l -- hello" "$(_integration_drain '[{"timestamp":"1","target":"gemini","message":"hello"}]' "$_panes_live")"
# title-matched pane that is mid-tool (bash) → real busy gate holds it.
_panes_titlebusy='%9\t1\tgemini\twin\t/proj\tbash\n'
_int_busy="$(_integration_drain '[{"timestamp":"1","target":"gemini","message":"x"}]' "$_panes_titlebusy")"
assert_status 0 "E-123.INT: title-matched but busy (bash) holds — nothing sent" test -z "$_int_busy"
# title-matched pane that is ready (node) → delivered through the real gate.
_panes_titleready='%9\t1\tgemini\twin\t/proj\tnode\n'
assert_contains "E-123.INT: title-matched + ready delivers (real gate)" \
  "%9 -l -- x" "$(_integration_drain '[{"timestamp":"1","target":"gemini","message":"x"}]' "$_panes_titleready")"

# ── E-123: signal handling (Ctrl-C) + --clear (fresh start) ───────────────────
echo "── E-123: Ctrl-C exit + --clear ────────────────────────────────────"

# SIG (regression): a watch loop MUST exit on SIGINT/SIGTERM. The earlier trap
# only released the lock without exiting, so the INT handler returned and the loop
# RESUMED — Ctrl-C appeared to do nothing.
assert_status 0 "E-123.SIG: INT trap exits (not just releases lock)" grep -qE "trap 'exit 130' INT" "$WATCH"
assert_status 0 "E-123.SIG: TERM trap exits"                         grep -qE "trap 'exit 143' TERM" "$WATCH"
assert_status 0 "E-123.SIG: EXIT trap releases the lock"             grep -qE "trap '_release_lock' EXIT" "$WATCH"

# SIG behavioural: run main() (preconditions/lock/tmux mocked) in the background,
# send a real SIGINT, and assert the process actually terminates.
_sig_probe() {  # <signal> → EXITED | ALIVE   (set -m so a backgrounded loop gets a
                # real, non-ignored SIGINT, mirroring a foreground tmux pane)
  ( set -m 2>/dev/null
    source "$WATCH" 2>/dev/null
    _preconditions() { return 0; }
    _acquire_lock() { return 0; }
    _release_lock() { return 0; }
    _reconcile_startup() { return 0; }
    _drain_once() { return 0; }
    SIGNAL="$(mktemp)"; printf '[]' > "$SIGNAL"; POLL_INTERVAL=0.2
    main >/dev/null 2>&1 &
    local mp=$!
    sleep 0.5
    kill "-$1" "$mp" 2>/dev/null
    local i=0
    while kill -0 "$mp" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
    if kill -0 "$mp" 2>/dev/null; then kill -9 "$mp" 2>/dev/null; echo ALIVE; else echo EXITED; fi
    rm -f "$SIGNAL" )
}
assert_contains "E-123.SIG: SIGINT (Ctrl-C) terminates the watch loop" "EXITED" "$(_sig_probe INT)"
assert_contains "E-123.SIG: SIGTERM terminates the watch loop"         "EXITED" "$(_sig_probe TERM)"

# CLR: `ai watch --clear` empties the queue for a fresh start, exits 0, no tmux.
assert_status 0 "E-123.CLR: --clear handled in arg parse" grep -qE '\-\-clear\|clear\)' "$WATCH"
assert_status 0 "E-123.CLR: _clear_queue helper present"  grep -qE '^_clear_queue\(\)' "$WATCH"
_clear_probe() {  # → "rc=<n> content=<json>"
  local d; d="$(mktemp -d)"; mkdir -p "$d/.ai"
  printf '%s' '[{"timestamp":"1","target":"claude","message":"old"}]' > "$d/.ai/signal.json"
  ( cd "$d" && bash "$WATCH" --clear >/dev/null 2>&1 )
  printf 'rc=%s content=%s' "$?" "$(cat "$d/.ai/signal.json")"
  rm -rf "$d"
}
_clr="$(_clear_probe)"
assert_contains "E-123.CLR: --clear exits 0"       "rc=0"       "$_clr"
assert_contains "E-123.CLR: --clear empties queue" "content=[]" "$_clr"
# --clear must NOT require tmux / must not start the watch loop (returns promptly).
assert_status 0 "E-123.CLR: --clear needs no tmux (a non-AI-OS dir errors cleanly)" \
  bash -c "cd \"\$(mktemp -d)\" && bash '$WATCH' --clear >/dev/null 2>&1; [ \$? -ne 0 ]"

assert_summary
