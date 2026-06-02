#!/usr/bin/env bash
# telemetry_hook_matcher_test.sh — universal-telemetry.md §Components 2 / E-105
#
# The telemetry edge hook (post-tool-use.sh) must be registered with matcher
# ".*" so it captures 100% of tool invocations — NOT just Write|Edit (which
# would silently drop Bash/Read/Grep/mcp__* calls and defeat the blueprint's
# "ground truth" goal). The AQG test-runner inside the script self-gates to
# Write/Edit, so ".*" is safe. The sibling logger hook (post-tool-log.sh) stays
# on Write|Edit.
#
# Drives the SHIPPED generator (_configure_project_claude_settings in src/bin/ai)
# by extracting its embedded Python at runtime — no logic is reimplemented.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
REGISTRY="${REPO_ROOT}/src/config/registry.json"

echo "── Suite: telemetry_hook_matcher_test (E-105) ──────────────────────"

SANDBOX="$(mktemp -d -t aios-hookmatch-XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

# Extract just the claude-settings generator Python (uniquely prefixed with
# AIOS_WORKSPACE_VALUE) between its <<'PY' marker and the closing PY.
GEN_PY="${SANDBOX}/gen.py"
awk '
  /AIOS_WORKSPACE_VALUE.*python3 - "\$TARGET_DIR" "\$REGISTRY" <</ {cap=1; next}
  cap && /^PY$/ {cap=0}
  cap {print}
' "$AI_BIN" > "$GEN_PY"

assert_status 0 "generator Python extracted" test -s "$GEN_PY"

# matcher_for <settings.json> <command-substring> → prints the matcher of the
# PostToolUse entry whose hook command contains the substring (or MISSING).
matcher_for() {
  F="$1" SUB="$2" python3 -c 'import json,os,sys
try: d=json.load(open(os.environ["F"]))
except Exception: print("NOFILE"); sys.exit(0)
sub=os.environ["SUB"]
for e in d.get("hooks",{}).get("PostToolUse",[]):
    if any(sub in h.get("command","") for h in e.get("hooks",[])):
        print(e.get("matcher","")); sys.exit(0)
print("MISSING")'
}

run_gen() {  # run_gen <target_dir> — mirrors the bash wrapper's mkdir -p
  mkdir -p "${SANDBOX}/$1"
  ( cd "$SANDBOX" && python3 "$GEN_PY" "$1" "$REGISTRY" >/dev/null 2>&1 )
}

# ── T-HM-01: fresh generation registers post-tool-use.sh at ".*" ─────────────
run_gen "fresh"
assert_contains "T-HM-01: telemetry hook matcher is .*" \
  ".*" "$(matcher_for "${SANDBOX}/fresh/settings.json" post-tool-use.sh)"
assert_contains "T-HM-01: logger hook stays Write|Edit" \
  "Write|Edit" "$(matcher_for "${SANDBOX}/fresh/settings.json" post-tool-log.sh)"

# ── T-HM-02: a stale Write|Edit telemetry matcher is healed to ".*" ──────────
mkdir -p "${SANDBOX}/stale"
cat > "${SANDBOX}/stale/settings.json" <<'JSON'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "bash $HOME/.ai-os/hooks/post-tool-log.sh" }] },
      { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "bash $HOME/.ai-os/hooks/post-tool-use.sh" }] }
    ]
  }
}
JSON
run_gen "stale"
assert_contains "T-HM-02: stale telemetry matcher healed to .*" \
  ".*" "$(matcher_for "${SANDBOX}/stale/settings.json" post-tool-use.sh)"
assert_not_contains "T-HM-02: telemetry matcher no longer Write|Edit" \
  "Write|Edit" "$(matcher_for "${SANDBOX}/stale/settings.json" post-tool-use.sh)"
assert_contains "T-HM-02: logger matcher untouched (Write|Edit)" \
  "Write|Edit" "$(matcher_for "${SANDBOX}/stale/settings.json" post-tool-log.sh)"

# ── T-HM-03: idempotent — second run keeps exactly one telemetry entry at .* ──
run_gen "stale"
COUNT=$(F="${SANDBOX}/stale/settings.json" python3 -c 'import json,os
d=json.load(open(os.environ["F"]))
print(sum(1 for e in d["hooks"]["PostToolUse"] for h in e.get("hooks",[]) if "post-tool-use.sh" in h.get("command","")))')
assert_contains "T-HM-03: exactly one telemetry hook after re-run" "1" "$COUNT"

# ── T-HM-04: generator source appends agq_cmd with the ".*" matcher ──────────
assert_status 0 "T-HM-04: src/bin/ai appends agq_cmd at matcher .*" \
  grep -qF '{"matcher": ".*", "hooks": [{"type": "command", "command": agq_cmd}]}' "$AI_BIN"

assert_summary
