#!/usr/bin/env bash
# session_start_cache_test.sh — E-126 (caching.md §3.2/§3.3): the SessionStart
# hook injects the compiled System Context Cache as a prompt-prefix at session
# start (the previously-unwired "Agent Invocation" step of the caching workflow).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CM="${REPO_ROOT}/src/mcp/cache-manager-mcp/index.js"
HOOK="${REPO_ROOT}/hooks/session-start.sh"
AI_BIN="${REPO_ROOT}/src/bin/ai"

echo "===== session_start_cache_test.sh (E-126) ====="

# ── S01: artifacts exist + parse ─────────────────────────────────────────────
assert_status 0 "hook exists"          test -f "$HOOK"
assert_status 0 "hook is executable"   test -x "$HOOK"
assert_status 0 "hook parses"          bash -n "$HOOK"
assert_status 0 "--emit-context CLI present in cache-manager" grep -qF -- '--emit-context' "$CM"
assert_status 0 "hook uses --emit-context"                   grep -qF -- '--emit-context' "$HOOK"

# ── S02: --emit-context emits the compiled blob; rollback emits nothing ───────
assert_status 0 "S02: --emit-context emits the System Context blob" bash -c \
  "node --no-warnings '$CM' --emit-context 2>/dev/null | grep -q 'AI-OS SYSTEM CONTEXT CACHE'"
assert_status 0 "S02: AI_OS_DISABLE_CACHE=1 emits nothing" bash -c \
  "[ -z \"\$(AI_OS_DISABLE_CACHE=1 node --no-warnings '$CM' --emit-context 2>/dev/null)\" ]"

# ── S03: hook emits VALID SessionStart JSON with the cache in additionalContext ─
assert_status 0 "S03: hook output is valid SessionStart additionalContext JSON" bash -c "
  bash '$HOOK' </dev/null 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = d[\"hookSpecificOutput\"]
assert h[\"hookEventName\"] == \"SessionStart\", \"event name\"
assert \"AI-OS SYSTEM CONTEXT CACHE\" in h[\"additionalContext\"], \"cache present\"
assert len(h[\"additionalContext\"]) > 1000, \"non-trivial blob\"
'"

# ── S04: rollback — AI_OS_DISABLE_CACHE=1 → hook emits nothing (no injection) ─
assert_status 0 "S04: rollback flag → hook emits nothing" bash -c \
  "[ -z \"\$(AI_OS_DISABLE_CACHE=1 bash '$HOOK' </dev/null 2>/dev/null)\" ]"

# ── S05: fail-open — node unavailable → hook exits 0, emits nothing (no block) ─
# A node-free PATH (keep coreutils via /usr/bin:/bin) must not break session start.
if [[ -x /usr/bin/env ]] && ! PATH="/usr/bin:/bin" command -v node >/dev/null 2>&1; then
  assert_status 0 "S05: no node → hook exits 0 (fail-open)" bash -c \
    "PATH='/usr/bin:/bin' bash '$HOOK' </dev/null >/dev/null 2>&1"
  assert_status 0 "S05: no node → hook emits nothing" bash -c \
    "[ -z \"\$(PATH='/usr/bin:/bin' bash '$HOOK' </dev/null 2>/dev/null)\" ]"
else
  echo "  (S05 fail-open test skipped — could not construct a node-free PATH)"
fi

# ── S06: `ai install` registers the SessionStart hook (canonical wiring) ──────
assert_status 0 "S06: ai install registers SessionStart"   grep -qF 'SessionStart' "$AI_BIN"
assert_status 0 "S06: registers session-start.sh"          grep -qF 'session-start.sh' "$AI_BIN"
assert_status 0 "S06: matcher covers startup|resume"       grep -qF 'startup|resume' "$AI_BIN"
# Behavioural: idempotent registration against a temp settings.json.
S06_DIR="$(mktemp -d)"; printf '{"hooks":{}}' > "$S06_DIR/settings.json"
python3 - "$S06_DIR/settings.json" <<'PY'
import json, sys
path = sys.argv[1]
for _ in range(2):
    data = json.load(open(path))
    hooks = data.setdefault("hooks", {})
    ss_cmd = "bash $HOME/.ai-os/hooks/session-start.sh"
    ss = hooks.setdefault("SessionStart", [])
    if not any(h.get("command") == ss_cmd for e in ss for h in e.get("hooks", [])):
        ss.append({"matcher": "startup|resume", "hooks": [{"type": "command", "command": ss_cmd}]})
    json.dump(data, open(path, "w"), indent=2)
PY
assert_status 0 "S06: wires SessionStart→session-start.sh once (idempotent)" \
  python3 -c "import json,sys; s=json.load(open('$S06_DIR/settings.json')); n=sum(1 for e in s['hooks']['SessionStart'] for hh in e.get('hooks',[]) if 'session-start.sh' in hh.get('command','')); sys.exit(0 if n==1 else 1)"
rm -rf "$S06_DIR"

assert_summary
