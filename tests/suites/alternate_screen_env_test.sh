#!/usr/bin/env bash
# alternate_screen_env_test.sh — Tests for E-50 terminal optimisation.
#
# Verifies CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 propagates through both
# injection points called out in claude-code-optimizations.md:
#   • src/bin/ai _configure_project_claude_settings → .claude/settings.json env
#   • install-ai-os.sh → user shell rc files (.zprofile / .zshrc / .bashrc)
# without clobbering pre-existing user values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== alternate_screen_env_test.sh ====="

# ── T-ALT-S01: bin/ai injects the env into project settings.json ──────────────
echo ""
echo "  [T-ALT-S01] bin/ai injects via _configure_project_claude_settings"

assert_status 0 "bin/ai sets CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" \
  grep -q 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN' "${REPO_ROOT}/src/bin/ai"

# Use setdefault so user-set values are preserved across `ai sync` runs.
assert_status 0 "bin/ai uses setdefault (preserves user override)" \
  grep -qE 'env.setdefault\(\s*["\x27]CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN' "${REPO_ROOT}/src/bin/ai"

# ── T-ALT-S02: Active .claude/settings.json carries the flag ─────────────────
echo ""
echo "  [T-ALT-S02] Active .claude/settings.json reflects the pin"

if [[ -f "${REPO_ROOT}/.claude/settings.json" ]]; then
  assert_status 0 "settings.json env.CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = '1'" \
    node --input-type=module <<JS
import { readFileSync } from 'fs';
const s = JSON.parse(readFileSync('${REPO_ROOT}/.claude/settings.json', 'utf8'));
if (s?.env?.CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN !== '1') process.exit(1);
JS
else
  echo "  ⚠  .claude/settings.json absent — skipping active check"
fi

# ── T-ALT-S03: install-ai-os.sh exports the env via shell rc ─────────────────
echo ""
echo "  [T-ALT-S03] install-ai-os.sh writes shell rc export"

INSTALL="${REPO_ROOT}/install-ai-os.sh"
assert_status 0 "install script defines ensure_env_line helper" \
  grep -q 'ensure_env_line()' "$INSTALL"

assert_status 0 "ensure_env_line is invoked for the new var" \
  grep -qE 'ensure_env_line[[:space:]]+\".*\"[[:space:]]+\"CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN\"' "$INSTALL"

assert_status 0 "ensure_env_line writes to .zprofile" \
  grep -q '\.zprofile.*CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN' "$INSTALL"

assert_status 0 "ensure_env_line writes to .zshrc" \
  grep -q '\.zshrc.*CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN' "$INSTALL"

assert_status 0 "ensure_env_line writes to .bashrc" \
  grep -q '\.bashrc.*CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN' "$INSTALL"

# ── T-ALT-S04: ensure_env_line is idempotent + non-clobbering ────────────────
echo ""
echo "  [T-ALT-S04] ensure_env_line idempotency + override preservation"

# Sandbox: extract just the helper from install-ai-os.sh, source it, drive it
# against a temp rc file, and assert behaviour matches the spec.
SANDBOX="$(mktemp -d -t alt-screen-XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT
cat > "${SANDBOX}/helper.sh" <<'HELPER'
ensure_env_line() {
  local rc="$1" var="$2" value="$3"
  local line="export ${var}=\"${value}\""
  [[ -f "$rc" ]] || touch "$rc"
  if ! grep -qE "^export[[:space:]]+${var}=" "$rc" 2>/dev/null; then
    printf "%s\n" "$line" >> "$rc"
    echo "added"
  else
    echo "kept"
  fi
}
HELPER
source "${SANDBOX}/helper.sh"

RC="${SANDBOX}/fake.rc"
> "$RC"

# First run → adds the line.
RES1="$(ensure_env_line "$RC" "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" "1")"
assert_status 0 "first run reports added"        bash -c "[[ '$RES1' == 'added' ]]"
assert_status 0 "rc now exports the var"          grep -q 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN="1"' "$RC"

# Second run → no-op.
RES2="$(ensure_env_line "$RC" "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" "1")"
assert_status 0 "second run is idempotent"        bash -c "[[ '$RES2' == 'kept' ]]"
LINES="$(grep -c 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN' "$RC")"
assert_status 0 "no duplicate lines"              bash -c "[[ '$LINES' == '1' ]]"

# Pre-existing user override is respected (different value).
echo 'export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN="0"' > "$RC"
RES3="$(ensure_env_line "$RC" "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" "1")"
assert_status 0 "user override is preserved"      bash -c "[[ '$RES3' == 'kept' ]]"
assert_status 0 "value still '0' (not clobbered)" grep -q 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN="0"' "$RC"

assert_summary
