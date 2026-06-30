#!/usr/bin/env bash
# stop_hook_test.sh — the Stop hook (hooks/stop-hook.sh) must auto-stamp SESSION.md
# but must NEVER pollute DIGEST's curated "Recent Changes" with the generic
# placeholder when there is no real session summary. Regression guard for the
# recurring `- <date>: auto-stamped by Stop hook` junk line that had to be
# hand-reverted before every commit.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/stop-hook.sh"
HOOK_MIRROR="${HOME}/.ai-os/hooks/stop-hook.sh"

echo "── Suite: stop_hook_test ───────────────────────────────────────────"

assert_exists "$HOOK"

# Helper: fresh sandbox project with a curated DIGEST.
new_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.ai"
  printf '# SESSION\n' > "$d/.ai/SESSION.md"
  printf '# DIGEST\n\n## Recent Changes\n- 2026-01-01: real curated entry\n' > "$d/.ai/DIGEST.md"
  printf '# LOG\n' > "$d/.ai/LOG.md"
  printf '%s' "$d"
}

# ── T-1: no session summary → NO placeholder line in DIGEST ───────────────────
SB="$(new_sandbox)"
( cd "$SB" && printf '' | bash "$HOOK" >/dev/null 2>&1 )
assert_status 1 "T-1: DIGEST has NO 'auto-stamped by Stop hook' placeholder" \
  grep -q 'auto-stamped by Stop hook' "$SB/.ai/DIGEST.md"
assert_status 0 "T-1b: curated DIGEST line preserved" \
  grep -q '2026-01-01: real curated entry' "$SB/.ai/DIGEST.md"

# ── T-2: SESSION.md bookkeeping still stamped (the hook's real job) ───────────
assert_status 0 "T-2: SESSION.md got a stop stamp even with no summary" \
  grep -q 'Actor: Claude' "$SB/.ai/SESSION.md"
rm -rf "$SB"

# ── T-3: a REAL summary IS appended to DIGEST ────────────────────────────────
SB="$(new_sandbox)"
# Note: hook reads one line via `read` — stdin must be newline-terminated.
( cd "$SB" && printf '%s\n' '{"summary":"E-999 shipped widget refactor"}' | bash "$HOOK" >/dev/null 2>&1 )
assert_status 0 "T-3: real session summary appended to DIGEST" \
  grep -q 'E-999 shipped widget refactor' "$SB/.ai/DIGEST.md"
assert_status 1 "T-3b: no placeholder leaked alongside the real summary" \
  grep -q 'auto-stamped by Stop hook' "$SB/.ai/DIGEST.md"
rm -rf "$SB"

# ── T-4: non-AI-OS dir (no .ai/) is a clean no-op ────────────────────────────
SB="$(mktemp -d)"
assert_status 0 "T-4: exits 0 with no .ai/ directory" \
  bash -c "cd '$SB' && printf '' | bash '$HOOK'"
rm -rf "$SB"

# ── T-5: ~/.ai-os mirror is byte-identical to the repo source ────────────────
if [[ -f "$HOOK_MIRROR" ]]; then
  assert_status 0 "T-5: ~/.ai-os/hooks/stop-hook.sh identical to repo source" \
    diff -q "$HOOK" "$HOOK_MIRROR"
else
  echo "  [SKIP] T-5 — ~/.ai-os/hooks/stop-hook.sh not installed"
fi

assert_summary
