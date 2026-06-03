#!/usr/bin/env bash
# ai_watch_test.sh — E-115 (interactive-bridge.md): the `ai-watch` tmux watcher
# routes .ai/signal.json handoffs to the target agent's pane, scoped to the
# current project, with literal (injection-safe) send-keys.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH="${REPO_ROOT}/src/bin/ai-watch"
AI="${REPO_ROOT}/src/bin/ai"
INSTALLER="${REPO_ROOT}/install-ai-os.sh"

echo "===== ai_watch_test.sh (E-115) ====="

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

# S10: resolution reads window_name and lowercases for case-insensitive match.
assert_status 0 "E-117.S10: _project_panes emits window_name" \
  grep -qF '#{window_name}' "$WATCH"
assert_status 0 "E-117.S10: _lc lowercases for case-insensitive match" \
  grep -qE "_lc\(\).*tr '\[:upper:\]' '\[:lower:\]'" "$WATCH"

# S11: fuzzy (substring) pane-title + window-name passes exist.
assert_status 0 "E-117.S11: fuzzy substring match on title/window" \
  grep -qE '\*"\$lc_target"\*' "$WATCH"

# S12: base-index-agnostic ordinal fallback (sorts by pane index, not literal).
assert_status 0 "E-117.S12: ordinal fallback sorts by pane index" \
  grep -qE 'sort -t.* -k2,2n' "$WATCH"

# S13: source-guard exposes helpers without launching the loop / needing tmux.
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

# Pass 1 — exact pane-title.
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

# Pass 4 — base-index 1: panes start at index 1; ordinal picks 1st/2nd.
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

# ── E-118: signal queue + busy-state detection ──────────────────────────────
echo "── E-118: signal queue + busy-state detection ──────────────────────"

# S14: queue parsing helpers (array-aware, legacy-tolerant).
assert_status 0 "E-118.S14: _queue_len helper present"   grep -qE '^_queue_len\(\)'   "$WATCH"
assert_status 0 "E-118.S14: _queue_field helper present" grep -qE '^_queue_field\(\)' "$WATCH"

# S15: busy-state gate reads pane_current_command against a ready set.
assert_status 0 "E-118.S15: _pane_ready helper present" grep -qE '^_pane_ready\(\)' "$WATCH"
assert_status 0 "E-118.S15: reads pane_current_command" grep -qF '#{pane_current_command}' "$WATCH"
assert_status 0 "E-118.S15: configurable ready set"     grep -qF 'AI_WATCH_READY_CMDS' "$WATCH"
assert_status 0 "E-118.S15: NO_BUSY_CHECK bypass"       grep -qF 'AI_WATCH_NO_BUSY_CHECK' "$WATCH"

# S16: cursor-based FIFO drain (no mtime replay; busy holds via return).
assert_status 0 "E-118.S16: _drain_once helper present" grep -qE '^_drain_once\(\)' "$WATCH"
assert_status 0 "E-118.S16: cursor tracks consumed entries" grep -qF 'CURSOR' "$WATCH"
assert_status 0 "E-118.S16: busy holds FIFO via return" \
  grep -qE '_pane_ready "\$pane" \|\| return 0' "$WATCH"

# ── E-118 behavioural: source + mock tmux/resolve/ready, drive _drain_once ────
# Echoes "cursor=<N> sent=[<send-keys args>]" so assertions run in the main shell.
_Q2='[{"timestamp":"t0","target":"claude","message":"alpha"},{"timestamp":"t1","target":"gemini","message":"beta"}]'
_drain_scenario() {  # _drain_scenario <queue_json> <ready:0|1> <pane_id|''> <start_cursor>
  local qjson="$1" ready="$2" rid="$3" start="$4"
  ( source "$WATCH" 2>/dev/null
    SIGNAL="$(mktemp)"; printf '%s' "$qjson" > "$SIGNAL"
    _SENT=""
    tmux() { if [ "$1" = "send-keys" ]; then shift; _SENT="${_SENT}|$*"; fi; return 0; }
    resolve_pane() { [ -n "$rid" ] && printf '%s' "$rid"; }
    _pane_ready() { [ "$ready" = "1" ]; }
    CURSOR="$start"
    _drain_once 2>/dev/null
    printf 'cursor=%s sent=[%s]' "$CURSOR" "$_SENT"
    rm -f "$SIGNAL" )
}

out="$(_drain_scenario "$_Q2" 1 '%P' 0)"
assert_contains "E-118.B1: ready drains both → cursor=2" "cursor=2" "$out"
assert_contains "E-118.B1: alpha injected literally (-l --)" "-l -- alpha" "$out"
assert_contains "E-118.B1: beta injected literally (-l --)"  "-l -- beta"  "$out"

out="$(_drain_scenario "$_Q2" 0 '%P' 0)"
assert_contains "E-118.B2: busy holds cursor at 0 (FIFO)" "cursor=0" "$out"
assert_contains "E-118.B2: nothing injected while busy"   "sent=[]"  "$out"

out="$(_drain_scenario "$_Q2" 1 '' 0)"
assert_contains "E-118.B3: no pane → entries dropped, cursor advances" "cursor=2" "$out"
assert_contains "E-118.B3: no pane → nothing injected" "sent=[]" "$out"

out="$(_drain_scenario "$_Q2" 1 '%P' 2)"
assert_contains "E-118.B4: startup backlog not replayed" "sent=[]" "$out"

out="$(_drain_scenario '[]' 1 '%P' 5)"
assert_contains "E-118.B5: queue shrink resyncs cursor down" "cursor=0" "$out"

out="$(_drain_scenario '[{"target":"claude"},{"target":"gemini","message":"ok"}]' 1 '%P' 0)"
assert_contains "E-118.B6: malformed entry skipped" "-l -- ok" "$out"
assert_contains "E-118.B6: cursor past skipped+valid" "cursor=2" "$out"

# Busy-gate unit: ready set vs busy command, plus the bypass flag. The mocked
# tmux returns the command-under-test for any call (that is what _pane_ready reads).
_ready_probe() {  # _ready_probe <cmd> <bypass:0|1> → "READY"|"BUSY"
  ( source "$WATCH" 2>/dev/null
    AI_WATCH_NO_BUSY_CHECK="$2"
    _probe_cmd="$1"
    tmux() { printf '%s' "$_probe_cmd"; }
    if _pane_ready "%X"; then echo READY; else echo BUSY; fi )
}
assert_contains "E-118.B7: node → READY"   "READY" "$(_ready_probe node 0)"
assert_contains "E-118.B7: bash → BUSY"    "BUSY"  "$(_ready_probe bash 0)"
assert_contains "E-118.B7: python → BUSY"  "BUSY"  "$(_ready_probe python3 0)"
assert_contains "E-118.B7: bypass → READY" "READY" "$(_ready_probe bash 1)"

assert_summary
