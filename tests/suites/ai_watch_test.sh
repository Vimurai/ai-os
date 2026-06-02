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

assert_summary
