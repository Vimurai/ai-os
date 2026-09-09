#!/usr/bin/env bash
# watcher_reexec_test.sh — E-229: `ai watch` survives its own script being rewritten.
#
# THE FAILURE THIS PREVENTS: bash reads a script by BYTE OFFSET as it executes, so
# rewriting the file in place moves the ground under a running process. A watcher started
# 2026-09-04 survived a 2026-09-07 mirror update, then spammed tmux "not in a mode" every
# poll and delivered nothing for 24 hours. It was "running" throughout — which is why
# nothing alerted, and why the fix has to be in the watcher rather than in monitoring.
#
# The re-exec keeps the same PID, so the single-writer lock stays ours; the tests below
# pin that, because a watcher that locks itself out on self-update is no better than one
# that wedges.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH="${REPO_ROOT}/src/bin/ai-watch"
AI="${REPO_ROOT}/src/bin/ai"
INSTALLER="${REPO_ROOT}/install-ai-os.sh"

echo "── Suite: watcher_reexec_test (E-229) ───────────────────────────────"

# ── E-229.1: the mechanism is present and rollback-able ────────────────────
assert_status 0 "E-229.01a: the watcher records its own mtime at start" \
  grep -q '_SELF_STAMP="$(_self_stamp)"' "$WATCH"
assert_status 0 "E-229.01b: it re-execs itself, preserving the PID" \
  grep -q 'exec "$_SELF" "$@"' "$WATCH"
assert_status 0 "E-229.01c: the re-exec runs between polls, not mid-drain" \
  bash -c "python3 - '$WATCH' <<'PYX'
import sys
s = open(sys.argv[1]).read()
i = s.index('_drain_once\n    _maybe_reexec')
sys.exit(0 if i > 0 else 1)
PYX"
assert_status 0 "E-229.01d: AI_WATCH_NO_REEXEC=1 disables it" \
  grep -q 'AI_WATCH_NO_REEXEC' "$WATCH"
# A half-written script must never be exec'd — that would turn a self-heal into a crash.
assert_status 0 "E-229.01e: it refuses to exec a script that does not parse" \
  grep -q 'bash -n "$_SELF"' "$WATCH"

# ── E-229.2: the lock recognises its own PID across a re-exec ──────────────
# Without this the watcher locks itself out on the first self-update and exits reporting
# "another watcher is already running" — pointing at itself.
assert_status 0 "E-229.02a: a lock held by our own pid is ours" \
  grep -q 'holder" == "\$\$" \]\] && return 0' "$WATCH"

_lock_probe() {  # → ACQUIRED | REFUSED, simulating a lock already held by THIS process
  local d; d="$(mktemp -d)"; mkdir -p "$d/.ai"
  ( PROJECT_DIR="$d" USE_LOCK=1 LOCK_DIR="$d/.ai/.ai-watch.lock"
    source "$WATCH" 2>/dev/null
    PROJECT_DIR="$d"; LOCK_DIR="$d/.ai/.ai-watch.lock"; USE_LOCK=1
    mkdir -p "$LOCK_DIR"; echo "$$" > "$LOCK_DIR/pid"
    if _acquire_lock; then echo ACQUIRED; else echo REFUSED; fi )
  rm -rf "$d"
}
assert_contains "E-229.02b: re-acquiring our own lock succeeds" "ACQUIRED" "$(_lock_probe)"

# ── E-229.3: a live re-exec delivers exactly once ──────────────────────────
# The property that matters operationally: the update must not drop an undelivered entry
# and must not deliver one twice. Delivery state lives in signal.json, which is why
# re-exec between polls is safe at all.
_reexec_probe() {
  # A FIXTURE watcher: the real script with its tmux-facing edges replaced, inserted
  # BEFORE the main-guard so the overrides win over the originals. The stubs must live
  # in the FILE, not in the calling shell — `exec` starts a fresh process, so anything
  # the test defined around it is gone by the time the new image runs. That is exactly
  # the property under test: the loop that comes back is the one on disk.
  local d; d="$(mktemp -d)"; mkdir -p "$d/.ai" "$d/bin"
  local fixture="$d/bin/ai-watch" delivered="$d/delivered.log" sig="$d/.ai/signal.json"

  local ov="$d/overrides.sh"
  {
    echo "# ── test fixture overrides (E-229 probe) ─────────────────────────"
    echo "_preconditions()     { return 0; }"
    echo "_acquire_lock()      { return 0; }"
    echo "_release_lock()      { return 0; }"
    echo "_reconcile_startup() { return 0; }"
    echo "SIGNAL=\"${sig}\""
    echo "POLL_INTERVAL=0.2"
    echo "_drain_once() {"
    echo "  python3 - \"\$SIGNAL\" \"${delivered}\" <<\"PY2\""
    echo "import json, sys"
    echo "try:"
    echo "    q = json.load(open(sys.argv[1]))"
    echo "except Exception:"
    echo "    q = []"
    echo "if q:"
    echo "    open(sys.argv[2], \"a\").write(q[0][\"message\"] + chr(10))"
    echo "    json.dump(q[1:], open(sys.argv[1], \"w\"))"
    echo "PY2"
    echo "}"
  } > "$ov"

  awk -v ovf="$ov" '
    /^if ! \(return 0 2>\/dev\/null\); then$/ && !done {
      while ((getline line < ovf) > 0) print line
      done = 1
    }
    { print }
  ' "$WATCH" > "$fixture"
  chmod +x "$fixture"

  : > "$delivered"
  printf '[{"timestamp":"1","target":"claude","message":"MSG-A"}]' > "$sig"

  local outlog="$d/watcher.out"
  ( cd "$d" && AI_WATCH_NO_REEXEC="${_NO_REEXEC:-0}" bash "$fixture" > "$outlog" 2>&1 ) &
  local wp=$!

  # Three phases, in this order, so each fact is established separately. The first
  # version queued MSG-B and touched the script together, then killed the watcher the
  # instant the second delivery landed — which raced the re-exec and made the whole probe
  # VACUOUS: it passed with the mechanism never firing, because the loop would have
  # delivered MSG-B either way.
  local w=0
  # 1. the pre-rewrite entry is delivered
  while [[ ! -s "$delivered" ]] && [[ "$w" -lt 200 ]]; do sleep 0.05; w=$((w + 1)); done
  # 2. the script is rewritten and the watcher re-execs (waited for, not assumed)
  touch "$fixture"
  w=0
  while ! grep -q "re-executing" "$outlog" 2>/dev/null && [[ "$w" -lt 300 ]]; do
    sleep 0.05; w=$((w + 1))
  done
  # 3. the process that came back still delivers
  printf '[{"timestamp":"2","target":"claude","message":"MSG-B"}]' > "$sig"
  w=0
  while [[ "$(grep -c . "$delivered" 2>/dev/null || printf 0)" -lt 2 ]] && [[ "$w" -lt 300 ]]; do
    sleep 0.05; w=$((w + 1))
  done
  kill -TERM "$wp" 2>/dev/null; wait "$wp" 2>/dev/null

  local out reexeced
  out="$(tr "\n" " " < "$delivered" 2>/dev/null)"
  reexeced="no"
  grep -q "re-executing to pick up the new version" "$outlog" 2>/dev/null && reexeced="yes"
  rm -rf "$d"
  printf '%s reexec=%s' "$out" "$reexeced"
}
_deliv="$(_reexec_probe)"
assert_contains "E-229.03a: the entry queued BEFORE the rewrite was delivered" "MSG-A" "$_deliv"
assert_contains "E-229.03b: the entry queued AFTER it was delivered too" "MSG-B" "$_deliv"
# NON-VACUITY: MSG-B would arrive whether or not the re-exec happened, because the loop
# keeps polling either way — so the delivery assertions alone prove nothing about the
# mechanism. These pin that the re-exec actually occurred, and that with the rollback flag
# set it does not (same fixture, same rewrite, no re-exec).
assert_contains "E-229.03d: the re-exec actually happened" "reexec=yes" "$_deliv"
_NO_REEXEC=1
_deliv_off="$(_reexec_probe)"
unset _NO_REEXEC
assert_contains "E-229.03e: AI_WATCH_NO_REEXEC=1 suppresses it (control)" "reexec=no" "$_deliv_off"
assert_contains "E-229.03f: and delivery still works without re-exec" "MSG-B" "$_deliv_off"

assert_status 0 "E-229.03c: neither was delivered twice" \
  bash -c "python3 -c \"
import sys
d = sys.argv[1].split()
sys.exit(0 if d.count('MSG-A') == 1 and d.count('MSG-B') == 1 else 1)
\" '$_deliv'"

# ── E-229.4: mirror writes are atomic ──────────────────────────────────────
# rsync already writes to a temp file and renames; the cp fallback did not, and the cp
# fallback is the path a machine without rsync takes.
assert_status 0 "E-229.04a: the installer has an atomic copy helper" \
  grep -q '_atomic_copy_tree()' "$INSTALLER"
assert_status 0 "E-229.04b: it renames into place rather than writing in place" \
  bash -c "grep -A 12 '_atomic_copy_tree()' '$INSTALLER' | grep -q 'mv -f'"
assert_status 1 "E-229.04c: no bare 'cp -rf' mirror write survives" \
  bash -c "grep -qE '^\\s*cp -rf \"\\\$\\{REPO_DIR\\}/src/' '$INSTALLER'"
# Comments stripped first: the explanation above the helper NAMES `--inplace` as the
# thing that would defeat atomicity, and an assertion that matched its own documentation
# failed on correct code — the same trap as E-223.06a.
assert_status 0 "E-229.04d: rsync is not used with --inplace (which would defeat it)" \
  bash -c "! sed 's/#.*//' '$INSTALLER' | grep -q 'rsync.*--inplace'"

# ── E-229.5: `ai start` restarts a watcher older than its own script ───────
assert_status 0 "E-229.05a: staleness is judged by script mtime vs lock mtime" \
  bash -c "grep -A 20 '_start_watch_running()' '$AI' | grep -q 's_mtime.*-gt.*l_mtime'"
# The lock path must be the one the watcher actually creates. E-227 shipped a path no
# component writes, so the check silently always said "no watcher running".
_wlock="$(grep -A 3 '_start_watch_lock()' "$AI" | grep printf | head -1)"
assert_contains "E-229.05b: the launcher uses the watcher's real lock path" \
  ".ai/.ai-watch.lock" "$_wlock"
assert_status 0 "E-229.05c: and the watcher agrees on it" \
  grep -q 'LOCK_DIR="\${PROJECT_DIR}/.ai/.ai-watch.lock"' "$WATCH"

assert_summary
