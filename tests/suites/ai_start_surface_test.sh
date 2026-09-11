#!/usr/bin/env bash
# ai_start_surface_test.sh — E-228 (D-059): --status, --kill, doctor line, docs.
#
# --kill is DESTRUCTIVE, so the assertions are weighted toward refusing rather than acting.
# The case that matters most is the non-interactive one: with no TTY there is no prompt to
# answer, and "no answer" must never read as consent. A --kill that proceeds in a pipeline
# or a hook would tear down a running Triad because something invoked it, not because
# anyone agreed to it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"

echo "── Suite: ai_start_surface_test (E-228) ────────────────────────────"

_proj() {  # → a project dir with two roles
  local d; d="$(mktemp -d)"; mkdir -p "$d/.ai"
  cat > "$d/.ai/roles.json" <<'JSON'
{ "roles": { "engineer":  {"provider":"claude","pane_identifier":"0"},
             "architect": {"provider":"claude","pane_identifier":"1"} } }
JSON
  printf '%s' "$d"
}

# A tmux shim bound to a socket with NO SERVER on it. The "nothing is running" cases below
# must test exactly that, and they cannot be left to the ambient host: on a developer
# machine a tmux server is usually already up, so those assertions passed locally while
# `ai start --status` was exiting 1 and printing nothing on CI, which has no server. A test
# whose subject depends on whether the machine happens to be running tmux is not a test of
# the code.
_nosrv_shim() {  # → dir containing a `tmux` that talks to an empty socket
  local dir; dir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexec %s -L aios-nosrv-%s "$@"\n' "$(command -v tmux)" "$$" > "${dir}/tmux"
  chmod +x "${dir}/tmux"
  printf '%s' "$dir"
}

# ── E-228.1: the flags are parsed and documented ───────────────────────────
_help="$(bash "$AI" start --help 2>&1)"
assert_contains "E-228.01a: --help documents --status" "--status" "$_help"
assert_contains "E-228.01b: --help documents --kill"   "--kill"   "$_help"
assert_contains "E-228.01c: --help says --kill asks first" "unless --yes" "$_help"

_p="$(_proj)"
( cd "$_p" && bash "$AI" start --status --kill >/dev/null 2>&1 )
assert_status 0 "E-228.01d: --status and --kill together are refused (exit 2)" \
  bash -c "[[ $? -eq 2 ]]"
rm -rf "$_p"

# ── E-228.2: --status reports, and answers 0 when nothing runs ─────────────
# "Nothing is up" is a true answer to a status question. A non-zero exit would force every
# caller to write `|| true`, which is how a status command stops being usable in scripts.
_p="$(_proj)"
if command -v tmux >/dev/null 2>&1; then
  _ns="$(_nosrv_shim)"
  _out="$( cd "$_p" && PATH="$_ns:$PATH" bash "$AI" start --status 2>&1 )"; _rc=$?
  rm -rf "$_ns"
else
  _out="$( cd "$_p" && bash "$AI" start --status 2>&1 )"; _rc=$?
fi
assert_status 0 "E-228.02a: --status exits 0 when nothing is running (rc=${_rc})" bash -c "[[ $_rc -eq 0 ]]"
assert_contains "E-228.02b: it says so rather than printing nothing" "not running" "$_out"
assert_contains "E-228.02c: and reports the watcher too" "watcher:" "$_out"
rm -rf "$_p"

# ── E-228.3: LIVE tmux — status sees real panes, kill removes them ─────────
if command -v tmux >/dev/null 2>&1; then
  # E-240 (D-063 §2): the socket is registered for cleanup BEFORE it is created, and its
  # name carries the sweepable test prefix. The old form set the trap AFTER creating the
  # server and used `$$`, so a mid-suite failure leaked it and a recycled PID later
  # attached to the leftover — 50 servers accumulated that way.
  _tb="$(command -v tmux)"
  _sock="$(test_tmux_socket e228)"
  _shim="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexec %s -L %s "$@"\n' "$_tb" "$_sock" > "$_shim/tmux"
  chmod +x "$_shim/tmux"
  _lp="$(_proj)"
  ( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --detach --no-watch >/dev/null 2>&1 )

  _st="$( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --status 2>&1 )"
  assert_contains "E-228.03a: --status names the engineer pane"  "engineer"  "$_st"
  assert_contains "E-228.03b: --status names the architect pane" "architect" "$_st"
  assert_contains "E-228.03c: --status reports the watcher as not running" "watcher: not running" "$_st"

  # THE SAFETY CASE. stdin is /dev/null here, exactly as in a pipeline or a hook.
  _ko="$( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --kill </dev/null 2>&1 )"; _krc=$?
  assert_status 0 "E-228.03d: --kill without --yes and without a TTY REFUSES (exit 2)" \
    bash -c "[[ $_krc -eq 2 ]]"
  assert_contains "E-228.03e: and says why" "without --yes" "$_ko"
  # NON-VACUITY: the refusal must have actually preserved the window, not merely printed.
  _still="$("$_tb" -L "$_sock" list-windows -a 2>/dev/null | grep -c .)"
  assert_status 0 "E-228.03f: the window SURVIVED the refused kill (windows=${_still})" \
    bash -c "[[ '${_still:-0}' -ge 1 ]]"

  # --dry-run states the plan and changes nothing.
  _dry="$( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --kill --dry-run </dev/null 2>&1 )"
  assert_contains "E-228.03g: --kill --dry-run names kill-window" "kill-window" "$_dry"
  _still2="$("$_tb" -L "$_sock" list-windows -a 2>/dev/null | grep -c .)"
  assert_status 0 "E-228.03h: dry run changed nothing (windows=${_still2})" \
    bash -c "[[ '${_still2:-0}' -eq '${_still:-0}' ]]"

  # --yes is the explicit consent, and it must actually tear down.
  _kill="$( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --kill --yes </dev/null 2>&1 )"
  assert_contains "E-228.03i: --kill --yes reports the window killed" "killed" "$_kill"
  # `grep -c` PRINTS the count and exits 1 when it is zero, so a `|| printf 0` fallback
  # appends a SECOND zero and the value becomes "0\n0" — which then fails an integer test
  # while the label reads "windows=0". The exit code is not the answer here; the count is.
  _gone="$("$_tb" -L "$_sock" list-windows -a 2>/dev/null | grep -c .)"
  assert_status 0 "E-228.03j: the window is actually gone (windows=${_gone})" \
    bash -c "[[ '${_gone:-1}' -eq 0 ]]"

  "$_tb" -L "$_sock" kill-server 2>/dev/null
  rm -rf "$_shim" "$_lp"
else
  # E-236: SKIP, not a fabricated pass — see tests/lib/assert.sh.
  for _n in a b c d e f g h i j; do
    _skip "E-228.03${_n}: live tmux layer (tmux not installed)"
  done
fi

# ── E-228.4: --kill with nothing to kill is a no-op, not an error ──────────
_p="$(_proj)"
if command -v tmux >/dev/null 2>&1; then
  _ns="$(_nosrv_shim)"
  _out="$( cd "$_p" && PATH="$_ns:$PATH" bash "$AI" start --kill --yes </dev/null 2>&1 )"; _rc=$?
  rm -rf "$_ns"
  assert_status 0 "E-228.04a: --kill on an idle project exits 0 (rc=${_rc})" bash -c "[[ $_rc -eq 0 ]]"
  assert_contains "E-228.04b: and says there was nothing to do" "nothing to tear down" "$_out"
else
  _skip "E-228.04a: --kill on an idle project (no tmux)"
  _skip "E-228.04b: nothing-to-do message (no tmux)"
fi
rm -rf "$_p"

# ── E-228.5: doctor reports launcher readiness ────────────────────────────
_doc="$(cd "$REPO_ROOT" && bash "$AI" doctor 2>&1)"
assert_contains "E-228.05a: doctor has a Triad launcher section" "Triad launcher" "$_doc"
assert_contains "E-228.05b: it reports tmux"   "tmux" "$_doc"
assert_contains "E-228.05c: it reports roles"  "roles mapped" "$_doc"
# Each role's provider is checked against PATH: a missing provider yields a pane that
# opens and then fails at the first keystroke, which reads as a launcher bug.
assert_contains "E-228.05d: and each role's provider" "engineer →" "$_doc"

# ── E-228.6: the docs point at the launcher, and keep the fallback ────────
assert_status 0 "E-228.06a: README documents ai start"        grep -q '^ai start$' "${REPO_ROOT}/README.md"
assert_status 0 "E-228.06b: README documents --status"        grep -q 'ai start --status' "${REPO_ROOT}/README.md"
assert_status 0 "E-228.06c: README documents --kill"          grep -q 'ai start --kill' "${REPO_ROOT}/README.md"
# The manual recipe must SURVIVE: hosts without tmux still need it, and `ai start` exits 2
# and prints it. Replacing the docs with "just run ai start" would strand those users.
assert_status 0 "E-228.06d: README keeps the manual fallback" \
  grep -q 'Manual fallback' "${REPO_ROOT}/README.md"
# E-252 (D-068): the recipe is now PER PROJECT. It used to read `tmux new-session -s
# ai-os` — a single shared session, which is the arrangement D-068 removed because one
# session has one current window shared by every attached client. The assertion follows the
# recipe rather than pinning the old literal, and checks BOTH halves: the recipe still
# exists (tmux-less hosts depend on it) and it no longer hands every project one session.
assert_status 0 "E-228.06e: README still shows a manual tmux recipe" \
  grep -q 'tmux new-session -s' "${REPO_ROOT}/README.md"
assert_status 0 "E-252.07a: and the recipe is per-project, not one shared session" \
  grep -q 'tmux new-session -s "\$(basename "\$PWD")"' "${REPO_ROOT}/README.md"
assert_status 1 "E-252.07b: the shared 'ai-os' session name is gone from the recipe" \
  grep -q 'new-session -s ai-os' "${REPO_ROOT}/README.md"
assert_status 0 "E-228.06f: CONTRIBUTING points at ai start" \
  grep -q 'ai start' "${REPO_ROOT}/CONTRIBUTING.md"

# ── E-228.7: init/sync surface the launcher ───────────────────────────────
assert_status 0 "E-228.07a: ai init prints an 'ai start' hint" \
  grep -q 'Or let the launcher do it:  ai start' "$AI"
assert_status 0 "E-228.07b: the sync tail hints too, only when tmux exists" \
  grep -q "Tip: 'ai start' opens the Triad layout" "$AI"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== ai_start_surface_test.sh PASS ====="
else
  echo "===== ai_start_surface_test.sh FAIL (${FAIL_COUNT}) ====="
fi
