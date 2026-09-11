#!/usr/bin/env bash
# ai_start_test.sh — E-227 (D-059, cli-collapse.md §`ai start`): the Triad launcher.
#
# `ai start` COMPOSES two commands it does not own — `ai pane <role>` and `ai watch`. The
# properties worth pinning are therefore about composition: which command reaches which
# pane, in what order, and what the launcher refuses to do.
#
# Two layers, because neither alone is enough:
#   - dry-run assertions cover ordering, flags and config rejection without a tmux server;
#   - a LIVE run on a private tmux socket covers what only real tmux reveals. That layer
#     earned its keep immediately: the dry run was green while the real one could not
#     address a single pane, because tmux parses `session:window.pane` and the window name
#     is the project basename — any project with a dot in its name was unusable — and
#     because tmux rejects `@window.0` as a pane target at all.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"

echo "── Suite: ai_start_test (E-227) ─────────────────────────────────────"

# _proj <engineer_pane> <architect_pane> [start.json] → project dir
_proj() {
  local d; d="$(mktemp -d)"; mkdir -p "$d/.ai"
  cat > "$d/.ai/roles.json" <<EOF
{ "roles": { "engineer":  { "provider": "claude", "pane_identifier": "$1" },
             "architect": { "provider": "claude", "pane_identifier": "$2" } } }
EOF
  [[ -n "${3:-}" ]] && printf '%s' "$3" > "$d/.ai/start.json"
  printf '%s' "$d"
}
_dry() { ( cd "$1" && shift && bash "$AI" start --dry-run "$@" 2>&1 ); }

# ── E-227.1: pane order follows pane_identifier, in BOTH directions ─────────
# The role with the lower pane_identifier takes the lower pane position, so E-209's
# ordinal fallback and the visible layout agree by construction rather than by luck.
_p="$(_proj 0 1)"; _out="$(_dry "$_p")"
assert_match "E-227.01a: engineer=0 → first pane" \
  'send-keys -t pane0 ai.\ pane.\ engineer' "$_out"
assert_match "E-227.01b: architect=1 → second pane" \
  'send-keys -t pane1 ai.\ pane.\ architect' "$_out"
assert_match "E-227.01c: watcher takes the third pane" 'send-keys -t pane2 ai.\ watch' "$_out"
rm -rf "$_p"

_p="$(_proj 1 0)"; _out="$(_dry "$_p")"
assert_match "E-227.01d: REVERSED — architect=0 → first pane" \
  'send-keys -t pane0 ai.\ pane.\ architect' "$_out"
assert_match "E-227.01e: REVERSED — engineer=1 → second pane" \
  'send-keys -t pane1 ai.\ pane.\ engineer' "$_out"
assert_match "E-227.01f: titles are pinned in the same order" \
  'select-pane -t pane0 -T architect' "$_out"
rm -rf "$_p"

# ── E-227.2: composition only — never a provider, never a project script ───
_p="$(_proj 0 1)"; _out="$(_dry "$_p")"
# Tightened by E-242: the intent is "ai start COMPOSES `ai pane`, it never execs a provider
# itself". Testing that by the bare substring `claude` also matches the DIRECTORY `.claude/`,
# which the overlay pre-check legitimately names — so the assertion failed on a path, not on
# a launch. Match an invocation instead: the provider in command position.
assert_status 1 "E-227.02a: no provider binary is launched directly" \
  bash -c "printf '%s' \"\$_out\" | grep -qE '(^|[;&|]|send-keys .)[[:space:]]*(claude|agy|gemini)[[:space:]]'"
# The dry run prints commands through `printf %q`, so the sent string appears as
# `ai\ pane\ engineer`. An assertion written against a literal space silently matched
# nothing and passed for the wrong reason.
assert_status 0 "E-227.02b: every send-keys carries only 'ai pane' or 'ai watch'" \
  python3 -c "
import re, sys
sent = [l for l in sys.argv[1].splitlines() if 'send-keys' in l]
sys.exit(0 if sent and all(re.search(r'ai\\\\? (pane|watch)', l) for l in sent) else 1)
" "$_out"
rm -rf "$_p"

# ── E-227.3: --no-watch drops the watcher pane AND its command ─────────────
_p="$(_proj 0 1)"; _out="$(_dry "$_p" --no-watch)"
assert_not_contains "E-227.03a: no watcher command" "ai watch" "$_out"
assert_not_contains "E-227.03b: no second split, so no third pane" "split-window -v" "$_out"
assert_match "E-227.03c: the agent panes are still bound" 'send-keys -t pane1' "$_out"
rm -rf "$_p"

# ── E-227.4: .ai/start.json is an EXEC SURFACE, so it is validated, not sanitised ─
# Every value becomes a tmux argument and the file is Architect-writable, which the E-208
# audit established is attacker-adjacent input. Anything outside the blueprint's shapes is
# refused outright.
while IFS='|' read -r label json; do
  [[ -z "$label" ]] && continue
  _p="$(_proj 0 1 "$json")"
  _out="$(_dry "$_p")"; _rc=$?
  assert_status 0 "E-227.04 rejected ($label)" bash -c "[[ $_rc -eq 2 ]]"
  assert_contains "E-227.04 says why ($label)" "start.json rejected" "$_out"
  rm -rf "$_p"
done <<'CASES'
session with a space|{"session":"has space"}
command substitution in session|{"session":"$(touch /tmp/pwn)"}
unblueprinted layout|{"layout":"quad"}
non-boolean watch|{"watch":"yes"}
out-of-range size|{"sizes":{"main":0}}
string size|{"sizes":{"main":"50"}}
unknown key|{"unknown":1}
malformed JSON|not json
non-object top level|[]
CASES

# A VALID config must still be honoured, or the validation is just a wall.
_p="$(_proj 0 1 '{"session":"proj","sizes":{"main":40,"top":70}}')"
_out="$(_dry "$_p")"
assert_contains "E-227.04v: a valid session is used"      "-s proj" "$_out"
# The size, in the modern spelling. tmux 3.4 rejects the deprecated `-p N` with
# "size missing", so `-l N%` is what is emitted now; `-p` survives only as a runtime
# fallback for tmux older than 3.1 and never appears in a dry run.
assert_contains "E-227.04w: a valid main size is applied" "-l 60%" "$_out"
assert_contains "E-227.04x: watch:false implies --no-watch" "split-window -h" \
  "$(_dry "$(_proj 0 1 '{"watch":false}')")"
rm -rf "$_p"

# ── E-227.5: refusals ──────────────────────────────────────────────────────
_d="$(mktemp -d)"
( cd "$_d" && bash "$AI" start --dry-run >/dev/null 2>&1 )
assert_status 0 "E-227.05a: outside an AI-OS project → exit 2" bash -c "[[ $? -eq 2 ]]"
rm -rf "$_d"
_p="$(_proj 0 1)"
( cd "$_p" && bash "$AI" start --bogus >/dev/null 2>&1 )
assert_status 0 "E-227.05b: unknown option → exit 2" bash -c "[[ $? -eq 2 ]]"
rm -rf "$_p"

# ── E-227.6: LIVE tmux — the layer that caught the targeting bugs ──────────
if command -v tmux >/dev/null 2>&1; then
  # E-240 (D-063 §2): the socket is registered for cleanup BEFORE it is created, and its
  # name carries the sweepable test prefix. The old form set the trap AFTER creating the
  # server and used `$$`, so a mid-suite failure leaked it and a recycled PID later
  # attached to the leftover — 50 servers accumulated that way.
  _tb="$(command -v tmux)"
  _sock="$(test_tmux_socket e227)"
  _shim="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexec %s -L %s "$@"\n' "$_tb" "$_sock" > "$_shim/tmux"
  chmod +x "$_shim/tmux"
  _lp="$(_proj 0 1)"
  # Keep `ai start`'s own output. Discarding it meant that when only one pane appeared on
  # CI, the suite could say the pane count was wrong but not what the launcher had said
  # about it — which is the only thing that explains a tmux-version difference.
  _startout="$( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --detach 2>&1 )"

  _win="$(basename "$_lp")"
  # Resolve by ID — the window name is the project basename and mktemp names contain a
  # dot, which is exactly the target ambiguity this suite exists to keep closed.
  # E-252 (D-068): the project now gets its OWN session, named after it — this lookup used
  # to hard-code `-t aios`, which is the shared session that no longer exists by default.
  _sess="$(awk '/^_start_session_name\(\) \{/,/^\}$/' "$AI" > "$_shim/fn.sh"; ( . "$_shim/fn.sh"; _start_session_name "$_lp" ))"
  _wid="$("$_tb" -L "$_sock" list-windows -t "$_sess" -F '#{window_id} #{window_name}' 2>/dev/null \
          | awk -v n="$_win" '$2 == n { print $1; exit }')"
  assert_status 0 "E-227.06a: the project window exists" bash -c "[[ -n '$_wid' ]]"

  # Carry the tmux version and the raw listing into the labels. When this failed on CI
  # it reported only "expected to contain: 3" — which does not distinguish "two panes were
  # created" from "list-panes returned nothing", and those have completely different causes.
  _tmuxv="$("$_tb" -V 2>&1 | head -1)"
  _panes="$("$_tb" -L "$_sock" list-panes -t "$_wid" -F '#{pane_index} #{pane_id}' 2>/dev/null | sort -n | awk '{print $2}')"
  _npanes="$(printf '%s\n' "$_panes" | grep -c .)"
  _wins="$("$_tb" -L "$_sock" list-windows -a -F '#{session_name}:#{window_id}:#{window_name}' 2>&1 | tr '\n' ' ')"
  assert_contains "E-227.06b: three panes were created (${_tmuxv}; wid=${_wid}; panes=[${_panes//$'\n'/,}]; windows=[${_wins}]; start said: ${_startout//$'\n'/ | })" \
    "3" "$_npanes"

  _titles="$("$_tb" -L "$_sock" list-panes -t "$_wid" -F '#{pane_title}' 2>/dev/null | tr '\n' ' ')"
  assert_contains "E-227.06c: pane 0 titled engineer"  "engineer"  "$_titles"
  assert_contains "E-227.06d: pane 1 titled architect" "architect" "$_titles"

  # Each pane received ITS command — the composition property, verified against real tmux.
  _i=0
  for _want in "ai pane engineer" "ai pane architect" "ai watch"; do
    _pid="$(printf '%s\n' "$_panes" | sed -n "$((_i + 1))p")"
    _body="$("$_tb" -L "$_sock" capture-pane -p -t "$_pid" 2>/dev/null || true)"
    assert_contains "E-227.06e: pane ${_i} received '${_want}'" "$_want" "$_body"
    _i=$((_i + 1))
  done

  # Idempotent: a re-run must not duplicate panes.
  # NON-VACUITY: on CI this passed while comparing 0 panes to 0 panes — "unchanged" is
  # trivially true when nothing was ever created, so the idempotence claim was empty.
  # Pin that there were panes to begin with before comparing counts.
  _before="$_npanes"
  assert_status 0 "E-227.06f-pre: there were panes to duplicate (guards 06f)" \
    bash -c "[[ '$_before' -gt 0 ]]"
  ( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --detach >/dev/null 2>&1 )
  _after="$("$_tb" -L "$_sock" list-panes -t "$_wid" 2>/dev/null | grep -c .)"
  assert_contains "E-227.06f: a re-run does not duplicate panes (before=${_before} after=${_after})" \
    "$_before" "$_after"

  "$_tb" -L "$_sock" kill-server 2>/dev/null
  rm -rf "$_shim" "$_lp"
else
  # E-236: a missing tmux is a SKIP, not a pass. Recording nine passes for a layer that
  # never ran is how a suite reports all-green while testing less than it claims — the
  # totals now say "skipped" so the gap is visible in the run.
  for _n in a b c d e0 e1 e2 f f-pre; do
    _skip "E-227.06${_n}: live tmux layer (tmux not installed)"
  done
fi


# ── E-252 (D-068): one tmux session per project ────────────────────────────
#
# `ai start` used to put every project into ONE shared `aios` session. A tmux session has
# a single CURRENT WINDOW shared by every attached client, so starting project B flipped
# the terminal showing project A; and the project window was found by NAME ONLY, so two
# checkouts with the same basename shared one window.
#
# THE STAMP IS THE IDENTITY, THE NAME IS A LABEL: a session carries AI_OS_PROJECT and is
# discovered by it, so a suffixed name is still found and a foreign session that merely
# shares a name is never adopted.

# The derivation is a PURE function, so it is driven directly rather than through a live
# server — the cases that matter (a dot, a leading dash, non-ASCII, over-length) are
# exactly the ones that are awkward to create as real directories on every platform.
_sname_direct() {
  # `ai` is a command script, not a library: sourcing it runs main. The function is
  # extracted and run in a subshell instead — which also keeps this honest about testing
  # the SHIPPED definition rather than a copy of it drifting in the test file.
  awk '/^_start_session_name\(\) \{/,/^\}$/' "$AI" > "${_E252_FN:?}"
  ( set -u; AI_OS_SHARED_SESSION="${AI_OS_SHARED_SESSION:-0}"; . "${_E252_FN}"; _start_session_name "$1" "${2:-}" )
}
_E252_FN="$(test_tmpdir e252)/fn.sh"

assert_contains "E-252.01a: a dot in the project name becomes a dash (tmux parses session:window.pane)" \
  "my-app" "$(_sname_direct /tmp/my.app)"
assert_contains "E-252.01b: a leading dash is stripped (tmux would read it as a flag)" \
  "weird" "$(_sname_direct /tmp/-weird)"
# Non-ASCII: the exact output matters less than the guarantee — whatever comes out is a
# legal tmux session name, because the rewrite is a WHITELIST rather than a blocklist.
_uber="$(_sname_direct /tmp/über)"
assert_status 0 "E-252.01c: a non-ASCII name yields a legal tmux name ('${_uber}')" \
  bash -c "printf '%s' '${_uber}' | grep -qE '^[A-Za-z0-9_][A-Za-z0-9_-]*$'"
_long="$(_sname_direct "/tmp/$(printf 'a%.0s' $(seq 1 40))")"
assert_contains "E-252.01d: a 40-character name is truncated to 32" "32" "${#_long}"
assert_contains "E-252.01e: an explicit start.json session wins verbatim" \
  "pinned" "$(_sname_direct /tmp/my.app pinned)"
assert_contains "E-252.01f: AI_OS_SHARED_SESSION=1 restores the single shared session" \
  "aios" "$(AI_OS_SHARED_SESSION=1 _sname_direct /tmp/my.app)"

# The dry run shows the two commands that make a session a project's own.
_p="$(_proj 0 1)"
_out="$(_dry "$_p")"
_derived="$(_sname_direct "$_p")"
assert_contains "E-252.02a: --dry-run creates the DERIVED session, not 'aios'" \
  "new-session -d -s ${_derived}" "$_out"
assert_contains "E-252.02b: and stamps it with the project path" \
  "set-environment -t ${_derived} AI_OS_PROJECT" "$_out"
assert_status 1 "E-252.02c: select-window is no longer composed (it moves OTHER clients)" \
  bash -c "printf '%s' \"\$_out\" | grep -q 'select-window'"
rm -rf "$_p"

# ── E-252 LIVE: the properties that only a real server can show ────────────
if skip_unless_cmd tmux "E-252 live session-isolation layer"; then
  _tb2="$(command -v tmux)"
  _sock2="$(test_tmux_socket e252)"
  _shim2="$(mktemp -d)"
  register_cleanup "rm -rf '${_shim2}'"
  printf '#!/usr/bin/env bash\nexec %s -L %s "$@"\n' "$_tb2" "$_sock2" > "$_shim2/tmux"
  chmod +x "$_shim2/tmux"
  _t2() { "$_tb2" -L "$_sock2" "$@"; }
  _start2() { ( cd "$1" && PATH="$_shim2:$PATH" bash "$AI" start --detach 2>&1 ); }

  # TWO PROJECTS → TWO SESSIONS. The headline property.
  _pA="$(_proj 0 1)"; _pB="$(_proj 0 1)"
  _outA="$(_start2 "$_pA")"; _outB="$(_start2 "$_pB")"
  _sA="$(_sname_direct "$_pA")"; _sB="$(_sname_direct "$_pB")"
  _sessions="$(_t2 list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
  assert_contains "E-252.03a: project A has its own session (${_sessions})" "$_sA" "$_sessions"
  assert_contains "E-252.03b: project B has its own session" "$_sB" "$_sessions"
  assert_status 1 "E-252.03c: and neither landed in the shared 'aios' session" \
    bash -c "_t2() { '$_tb2' -L '$_sock2' \"\$@\"; }; _t2 has-session -t aios 2>/dev/null"

  # THE STAMP is what makes them findable. Asserted directly, because everything below
  # (reuse, --status, --kill) is a consequence of it.
  assert_contains "E-252.03d: A's session is stamped with A's physical path" \
    "$(cd "$_pA" && pwd -P)" "$(_t2 show-environment -t "$_sA" AI_OS_PROJECT 2>/dev/null)"

  # REUSE goes through the stamp, so a re-run does not create a second session.
  _nbefore="$(_t2 list-sessions 2>/dev/null | grep -c .)"
  _start2 "$_pA" >/dev/null 2>&1
  _nafter="$(_t2 list-sessions 2>/dev/null | grep -c .)"
  assert_status 0 "E-252.03e-pre: there were sessions to duplicate (guards 03e)" \
    bash -c "[[ '$_nbefore' -ge 2 ]]"
  assert_contains "E-252.03e: a re-run reuses the stamped session (before=${_nbefore} after=${_nafter})" \
    "$_nbefore" "$_nafter"

  # THE ORIGINAL COMPLAINT: starting B must not move the terminal showing A. With separate
  # sessions that is structural rather than careful — a session's current window cannot be
  # changed by an operation on a different session — so what is asserted is the structure:
  # A's session still exists, still holds its own window, and B's start touched neither.
  _aWinBefore="$(_t2 display-message -p -t "$_sA" '#{window_id}' 2>/dev/null || true)"
  _start2 "$_pB" >/dev/null 2>&1
  _aWinAfter="$(_t2 display-message -p -t "$_sA" '#{window_id}' 2>/dev/null || true)"
  assert_status 0 "E-252.03f-pre: A had a current window to lose (guards 03f)" \
    bash -c "[[ -n '${_aWinBefore}' ]]"
  assert_contains "E-252.03f: starting B leaves A's current window alone (${_aWinBefore}→${_aWinAfter})" \
    "$_aWinBefore" "$_aWinAfter"

  # --status and --kill find the session BY STAMP and say how they found it.
  _st="$( cd "$_pA" && PATH="$_shim2:$PATH" bash "$AI" start --status 2>&1 )"
  assert_contains "E-252.04a: --status names the owned session" "$_sA" "$_st"
  assert_contains "E-252.04b: and reports how it was found" "[owned]" "$_st"

  # A FOREIGN SESSION with the same name is never adopted — it is suffixed around.
  # This is the security property: reuse requires stamp equality, not a name match.
  _pC="$(_proj 0 1)"
  _sC="$(_sname_direct "$_pC")"
  _t2 kill-session -t "$_sC" 2>/dev/null || true
  _t2 new-session -d -s "$_sC" 2>/dev/null   # unstamped: someone else's session
  _outC="$(_start2 "$_pC")"
  _foundC="$(_t2 list-sessions -F '#{session_name}' 2>/dev/null \
             | while IFS= read -r _s; do
                 [[ "$(_t2 show-environment -t "$_s" AI_OS_PROJECT 2>/dev/null | sed -n 's/^AI_OS_PROJECT=//p')" == "$(cd "$_pC" && pwd -P)" ]] && printf '%s' "$_s"
               done)"
  assert_status 0 "E-252.05a: a foreign same-name session is NOT adopted (got '${_foundC}')" \
    bash -c "[[ -n '${_foundC}' && '${_foundC}' != '${_sC}' ]]"
  assert_match "E-252.05b: the new name carries a path-derived suffix" \
    "^${_sC:0:25}-[0-9a-f]{6}$" "${_foundC}"
  # The suffix is DERIVED FROM THE PATH, so the same project gets the same name next time —
  # a random suffix would strand the previous session on every run.
  _start2 "$_pC" >/dev/null 2>&1
  _nC="$(_t2 list-sessions -F '#{session_name}' 2>/dev/null | grep -c "^${_sC:0:25}-")"
  assert_contains "E-252.05c: and is stable across runs (one suffixed session, not two)" "1" "$_nC"

  # LEGACY ADOPTION: a pre-D-068 window in the shared session is reused IN PLACE, and the
  # operator is told how to migrate. Without this, an upgrade tears down a live layout.
  _pL="$(_proj 0 1)"
  _pLp="$(cd "$_pL" && pwd -P)"
  _t2 new-session -d -s aios -n "$(basename "$_pLp")" -c "$_pLp"
  _wL_before="$(_t2 list-windows -t aios 2>/dev/null | grep -c .)"
  _outL="$(_start2 "$_pL")"
  _wL_after="$(_t2 list-windows -t aios 2>/dev/null | grep -c .)"
  assert_contains "E-252.06a: the legacy window is adopted, not duplicated (${_wL_before}→${_wL_after})" \
    "$_wL_before" "$_wL_after"
  assert_contains "E-252.06b: and the migration path is printed once" "reusing legacy shared window" "$_outL"
  assert_contains "E-252.06c: naming the session it would move to" "ai start --kill" "$_outL"

  _t2 kill-server 2>/dev/null || true
  rm -rf "$_pA" "$_pB" "$_pC" "$_pL"
fi

# ── E-227.7: non-tmux hosts get the manual recipe, not a stack trace ───────
_p="$(_proj 0 1)"
# A PATH that still has coreutils but NOT tmux. The previous version hard-coded
# `PATH=/usr/bin:/bin` with the comment "tmux lives in /opt/homebrew/bin here" — true on
# macOS, false on Linux, where tmux IS /usr/bin/tmux. So on CI this experiment left tmux
# on the PATH and tested nothing at all, while asserting it had. Derive the PATH by
# REMOVING whichever directories actually provide tmux, then verify the condition holds
# before relying on it — an experiment that can silently stop being the experiment is
# worse than no test.
# Removing the whole directory that provides tmux is not an option on Linux, where tmux is
# /usr/bin/tmux — dropping /usr/bin takes python3, basename and the rest with it, and the
# script died with 127 for the wrong reason (my first attempt did exactly that). Instead,
# for each PATH entry that provides tmux, substitute a symlink FARM of that directory with
# tmux alone omitted. Everything else stays reachable and only tmux disappears.
_farmroot="$(mktemp -d)"
_notmux=""
_fi=0
while IFS= read -r _d; do
  [[ -z "$_d" || ! -d "$_d" ]] && continue
  if [[ -x "${_d}/tmux" ]]; then
    _fi=$((_fi + 1))
    _farm="${_farmroot}/f${_fi}"; mkdir -p "$_farm"
    for _f in "$_d"/*; do
      _b="${_f##*/}"
      [[ "$_b" == "tmux" ]] && continue
      [[ -e "${_farm}/${_b}" ]] && continue
      ln -s "$_f" "${_farm}/${_b}" 2>/dev/null || true
    done
    _notmux="${_notmux}${_farm}:"
  else
    _notmux="${_notmux}${_d}:"
  fi
done < <(printf '%s\n' "$PATH" | tr ':' '\n')
_notmux="${_notmux%:}"
# `command` is a shell BUILTIN, so `env PATH=... command -v tmux` asks env to exec a
# binary called `command`. macOS happens to ship /usr/bin/command and Linux does not, so
# that spelling returned 127 on CI and the guard failed for its own reasons. Run it inside
# a shell instead.
assert_status 1 "E-227.07pre: the no-tmux PATH really has no tmux (guards the experiment)" \
  bash -c "PATH='$_notmux' command -v tmux"
assert_status 0 "E-227.07pre2: but coreutils are still reachable (guards the guard)" \
  bash -c "PATH='$_notmux' command -v python3 >/dev/null && PATH='$_notmux' command -v basename >/dev/null"
_out="$( cd "$_p" && PATH="$_notmux" bash "$AI" start 2>&1 )"; _rc=$?
assert_status 0 "E-227.07a: no tmux → exit 2 (rc=$_rc)" bash -c "[[ $_rc -eq 2 ]]"
assert_contains "E-227.07b: the recipe names ai pane engineer"  "ai pane engineer"  "$_out"
assert_contains "E-227.07c: the recipe names ai pane architect" "ai pane architect" "$_out"
assert_contains "E-227.07d: the recipe names ai watch"          "ai watch"          "$_out"
rm -rf "$_farmroot"
rm -rf "$_p"

assert_summary
