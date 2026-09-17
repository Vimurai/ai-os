#!/usr/bin/env bash
# pane_option_binding_test.sh — E-269 (D-073, interactive-bridge.md §Binding by Pane Option).
#
# The live defect: `ai pane <role>` pinned its role with an UNTARGETED `select-pane -T`, so
# the title landed on whichever pane was ACTIVE — after `ai start`'s split, the watcher's
# bash pane — and ai-watch then routed the role's handoffs to bash and held them for a day.
#
# This suite reproduces that layout on a private tmux server: `ai pane engineer` runs in a
# pane that is NOT the active one. The binding must land on the pane that ran it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
WATCH="${REPO_ROOT}/src/bin/ai-watch"

echo "── Suite: pane_option_binding_test (E-269) ─────────────────────────"

if skip_unless_cmd tmux "live tmux pane-option binding"; then
  SOCK="$(test_tmux_socket e269)"
  register_cleanup "tmux -L '${SOCK}' kill-server 2>/dev/null || true"
  PROJ="$(test_tmpdir e269-proj)"
  BIN="$(test_tmpdir e269-bin)"
  mkdir -p "${PROJ}/.ai"
  cat > "${PROJ}/.ai/roles.json" <<'JSON'
{ "roles": { "engineer":  { "provider": "claude", "pane_identifier": "0" },
             "architect": { "provider": "claude", "pane_identifier": "1" } } }
JSON
  # A stand-in provider: `ai pane` execs it, and it must keep the pane alive while we look.
  printf '#!/usr/bin/env bash\nexec sleep 30\n' > "${BIN}/claude"
  chmod +x "${BIN}/claude"
  # tmux resolves `tmux` inside the pane through PATH, so the pane must reach THIS server.
  printf '#!/usr/bin/env bash\nexec %s -L %s "$@"\n' "$(command -v tmux)" "$SOCK" > "${BIN}/tmux"
  chmod +x "${BIN}/tmux"

  T="$(command -v tmux)"
  "$T" -L "$SOCK" new-session -d -s e269 -x 160 -y 40 -c "$PROJ"
  AGENT="$("$T" -L "$SOCK" list-panes -t e269 -F '#{pane_id}' | head -1)"
  "$T" -L "$SOCK" split-window -t "$AGENT" -c "$PROJ"
  WATCHER="$("$T" -L "$SOCK" list-panes -t e269 -F '#{pane_id}' | tail -1)"
  "$T" -L "$SOCK" select-pane -t "$WATCHER"    # the watcher pane is ACTIVE, as after ai start
  "$T" -L "$SOCK" select-pane -t "$WATCHER" -T "untouched"

  # Run `ai pane engineer` IN the non-active agent pane (TMUX_PANE is that pane's id).
  "$T" -L "$SOCK" send-keys -t "$AGENT" \
    "PATH='${BIN}':\$PATH HOME='$(test_tmpdir e269-home)' bash '${AI}' pane engineer" C-m

  _opt=""
  for _i in $(seq 1 60); do
    _opt="$("$T" -L "$SOCK" show-options -p -v -t "$AGENT" @ai_os_role 2>/dev/null || true)"
    [[ -n "$_opt" ]] && break
    sleep 0.1
  done
  assert_contains "E-269.L1: ai pane sets @ai_os_role on the pane that ran it" "engineer" "$_opt"
  assert_status 0 "E-269.L2: the ACTIVE (watcher) pane carries no role option" \
    test -z "$("$T" -L "$SOCK" show-options -p -v -t "$WATCHER" @ai_os_role 2>/dev/null)"
  assert_contains "E-269.L3: the cosmetic title is on the agent pane" "engineer" \
    "$("$T" -L "$SOCK" display-message -p -t "$AGENT" '#{pane_title}')"
  assert_contains "E-269.L4: the watcher pane's title is left alone" "untouched" \
    "$("$T" -L "$SOCK" display-message -p -t "$WATCHER" '#{pane_title}')"

  # The watcher's own pane listing (real tmux, real format) sees the option.
  _rows="$( TMUX_TMPDIR="${TMUX_TMPDIR:-}" PATH="${BIN}:$PATH" bash -c "
    source '$WATCH' 2>/dev/null
    PROJECT_DIR='$(cd "$PROJ" && pwd -P)'; WATCH_SESSION=e269
    _project_panes" )"
  assert_match "E-269.L5: _project_panes reports the option as the 7th field" \
    "^${AGENT}"$'\t'".*"$'\t'"engineer\$" "$_rows"
  assert_match "E-269.L6: and '-' for a pane without one" "^${WATCHER}"$'\t'".*"$'\t'"-\$" "$_rows"
  # Claude Code retitles its pane; the option must survive that.
  "$T" -L "$SOCK" select-pane -t "$AGENT" -T "✳ Summarise the diff"
  assert_contains "E-269.L7: the option survives a retitle" "engineer" \
    "$("$T" -L "$SOCK" show-options -p -v -t "$AGENT" @ai_os_role 2>/dev/null)"

  # `ai start --status` reports the role from the option, not the title. (Its live output
  # is covered by ai_start_test's session; here the format string is pinned.)
  assert_status 0 "E-269.L8: --status reads @ai_os_role" \
    grep -q "#{pane_index}|#{@ai_os_role}|#{pane_current_command}" "$AI"
fi

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== pane_option_binding_test.sh PASS ====="
else
  echo "===== pane_option_binding_test.sh FAIL (${FAIL_COUNT}) ====="
fi
