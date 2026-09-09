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
assert_not_contains "E-227.02a: no provider binary is launched directly" "claude" "$_out"
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
assert_contains "E-227.04w: a valid main size is applied" "-p 60"   "$_out"
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
  _sock="aios-e227-$$"
  _tb="$(command -v tmux)"
  _shim="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexec %s -L %s "$@"\n' "$_tb" "$_sock" > "$_shim/tmux"
  chmod +x "$_shim/tmux"
  _lp="$(_proj 0 1)"
  ( cd "$_lp" && PATH="$_shim:$PATH" bash "$AI" start --detach >/dev/null 2>&1 )

  _win="$(basename "$_lp")"
  # Resolve by ID — the window name is the project basename and mktemp names contain a
  # dot, which is exactly the target ambiguity this suite exists to keep closed.
  _wid="$("$_tb" -L "$_sock" list-windows -t aios -F '#{window_id} #{window_name}' 2>/dev/null \
          | awk -v n="$_win" '$2 == n { print $1; exit }')"
  assert_status 0 "E-227.06a: the project window exists" bash -c "[[ -n '$_wid' ]]"

  # Carry the tmux version and the raw listing into the labels. When this failed on CI
  # it reported only "expected to contain: 3" — which does not distinguish "two panes were
  # created" from "list-panes returned nothing", and those have completely different causes.
  _tmuxv="$("$_tb" -V 2>&1 | head -1)"
  _panes="$("$_tb" -L "$_sock" list-panes -t "$_wid" -F '#{pane_index} #{pane_id}' 2>/dev/null | sort -n | awk '{print $2}')"
  _npanes="$(printf '%s\n' "$_panes" | grep -c .)"
  _wins="$("$_tb" -L "$_sock" list-windows -a -F '#{session_name}:#{window_id}:#{window_name}' 2>&1 | tr '\n' ' ')"
  assert_contains "E-227.06b: three panes were created (${_tmuxv}; wid=${_wid}; panes=[${_panes//$'\n'/,}]; windows=[${_wins}])" \
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
  # Keep the assertion count stable across hosts: a missing tmux is a skip, not a gap.
  for _n in a b c d e0 e1 e2 f f-pre; do
    _pass "E-227.06${_n}: live tmux layer skipped (tmux not installed)"
  done
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
_notmux=""
while IFS= read -r _d; do
  [[ -z "$_d" ]] && continue
  [[ -x "${_d}/tmux" ]] && continue
  _notmux="${_notmux}${_d}:"
done < <(printf '%s\n' "$PATH" | tr ':' '\n')
_notmux="${_notmux%:}"
assert_status 1 "E-227.07pre: the no-tmux PATH really has no tmux (guards the experiment)" \
  env PATH="$_notmux" command -v tmux
_out="$( cd "$_p" && PATH="$_notmux" bash "$AI" start 2>&1 )"; _rc=$?
assert_status 0 "E-227.07a: no tmux → exit 2 (rc=$_rc)" bash -c "[[ $_rc -eq 2 ]]"
assert_contains "E-227.07b: the recipe names ai pane engineer"  "ai pane engineer"  "$_out"
assert_contains "E-227.07c: the recipe names ai pane architect" "ai pane architect" "$_out"
assert_contains "E-227.07d: the recipe names ai watch"          "ai watch"          "$_out"
rm -rf "$_p"

assert_summary
