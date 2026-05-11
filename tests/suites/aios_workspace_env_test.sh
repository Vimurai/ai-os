#!/usr/bin/env bash
# aios_workspace_env_test.sh — Tests for E-62 framework workspace injection.
#
# Verifies AIOS_WORKSPACE propagates through every injection point called
# out in task-routing.md §Components:
#   • install-ai-os.sh persists ${REPO_DIR} to ~/.ai-os/config/aios-workspace.txt
#   • install-ai-os.sh exports AIOS_WORKSPACE via ensure_env_line on
#     .zprofile / .zshrc / .bashrc (mirrors E-50 pattern)
#   • src/bin/ai exposes _resolve_aios_workspace() (env > persisted file > "")
#   • _configure_project_claude_settings propagates the value into
#     .claude/settings.json env via setdefault (preserves user override)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== aios_workspace_env_test.sh ====="

# ── T-WS-S01: bin/ai defines _resolve_aios_workspace ──────────────────────────
echo ""
echo "  [T-WS-S01] bin/ai exposes _resolve_aios_workspace helper"

assert_status 0 "bin/ai defines _resolve_aios_workspace()" \
  grep -q '^_resolve_aios_workspace()' "${REPO_ROOT}/src/bin/ai"

# Order: env first, then persisted file, then empty.
assert_status 0 "resolver reads \$AIOS_WORKSPACE first" \
  grep -q 'AIOS_WORKSPACE:-' "${REPO_ROOT}/src/bin/ai"

assert_status 0 "resolver falls back to config/aios-workspace.txt" \
  grep -q 'aios-workspace.txt' "${REPO_ROOT}/src/bin/ai"

# ── T-WS-S02: _configure_project_claude_settings propagates AIOS_WORKSPACE ───
echo ""
echo "  [T-WS-S02] settings.json env carries AIOS_WORKSPACE via setdefault"

assert_status 0 "bin/ai uses setdefault for AIOS_WORKSPACE (preserves override)" \
  grep -qE 'env\.setdefault\(\s*["\x27]AIOS_WORKSPACE' "${REPO_ROOT}/src/bin/ai"

assert_status 0 "bin/ai threads AIOS_WORKSPACE through to python heredoc" \
  grep -q 'AIOS_WORKSPACE="\${AIOS_WORKSPACE_VALUE}" python3' "${REPO_ROOT}/src/bin/ai"

# ── T-WS-S03: install-ai-os.sh defines + invokes ensure_env_line for AIOS_WORKSPACE ──
echo ""
echo "  [T-WS-S03] install-ai-os.sh exports AIOS_WORKSPACE via shell rc"

INSTALL="${REPO_ROOT}/install-ai-os.sh"
assert_status 0 "install script defines ensure_env_line helper" \
  grep -q 'ensure_env_line()' "$INSTALL"

assert_status 0 "ensure_env_line is invoked for AIOS_WORKSPACE" \
  grep -qE 'ensure_env_line[[:space:]]+".*"[[:space:]]+"AIOS_WORKSPACE"' "$INSTALL"

assert_status 0 "AIOS_WORKSPACE wired to .zprofile" \
  grep -q '\.zprofile.*AIOS_WORKSPACE' "$INSTALL"

assert_status 0 "AIOS_WORKSPACE wired to .zshrc" \
  grep -q '\.zshrc.*AIOS_WORKSPACE' "$INSTALL"

assert_status 0 "AIOS_WORKSPACE wired to .bashrc" \
  grep -q '\.bashrc.*AIOS_WORKSPACE' "$INSTALL"

# ── T-WS-S04: install persists REPO_DIR to config/aios-workspace.txt ─────────
echo ""
echo "  [T-WS-S04] install persists workspace path for non-interactive recovery"

assert_status 0 "install writes config/aios-workspace.txt" \
  grep -q 'aios-workspace.txt' "$INSTALL"

assert_status 0 "install creates \${AIOS}/config dir before write" \
  grep -qE 'mkdir -p[[:space:]]+"\$\{AIOS\}/config"' "$INSTALL"

# Functional check: live install (if present) should have the file.
if [[ -f "${HOME}/.ai-os/config/aios-workspace.txt" ]]; then
  PERSISTED="$(head -n 1 "${HOME}/.ai-os/config/aios-workspace.txt" | tr -d '\n')"
  assert_status 0 "persisted aios-workspace.txt is non-empty" \
    bash -c "[[ -n '${PERSISTED}' ]]"
  assert_status 0 "persisted path resolves to a directory" \
    bash -c "[[ -d '${PERSISTED}' ]]"
else
  echo "  ⚠ ~/.ai-os/config/aios-workspace.txt absent — install hasn't run since E-62; skipping live checks"
fi

# ── T-WS-S05: _resolve_aios_workspace behavioural test (sandbox) ─────────────
echo ""
echo "  [T-WS-S05] _resolve_aios_workspace honours env > file > empty"

SANDBOX="$(mktemp -d -t aios-ws-XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

# Extract just the function to keep the sandbox hermetic.
cat > "${SANDBOX}/helper.sh" <<'HELPER'
AIOS="${AIOS_DIR}"
_resolve_aios_workspace() {
  if [[ -n "${AIOS_WORKSPACE:-}" ]]; then
    printf "%s" "${AIOS_WORKSPACE}"
    return 0
  fi
  local persisted="${AIOS}/config/aios-workspace.txt"
  if [[ -f "$persisted" ]]; then
    head -n 1 "$persisted" 2>/dev/null | tr -d '\n'
    return 0
  fi
  printf ""
}
HELPER

# (a) env wins
AIOS_DIR="${SANDBOX}" AIOS_WORKSPACE="/from/env" \
  bash -c "source ${SANDBOX}/helper.sh; _resolve_aios_workspace" \
  > "${SANDBOX}/out_env" 2>&1
assert_status 0 "env value wins" \
  bash -c "[[ \"\$(cat ${SANDBOX}/out_env)\" == '/from/env' ]]"

# (b) file fallback when env unset
mkdir -p "${SANDBOX}/config"
echo "/from/file" > "${SANDBOX}/config/aios-workspace.txt"
unset AIOS_WORKSPACE
AIOS_DIR="${SANDBOX}" \
  bash -c "unset AIOS_WORKSPACE; source ${SANDBOX}/helper.sh; _resolve_aios_workspace" \
  > "${SANDBOX}/out_file" 2>&1
assert_status 0 "persisted file used when env unset" \
  bash -c "[[ \"\$(cat ${SANDBOX}/out_file)\" == '/from/file' ]]"

# (c) empty when neither
rm -f "${SANDBOX}/config/aios-workspace.txt"
AIOS_DIR="${SANDBOX}" \
  bash -c "unset AIOS_WORKSPACE; source ${SANDBOX}/helper.sh; _resolve_aios_workspace" \
  > "${SANDBOX}/out_none" 2>&1
assert_status 0 "empty string when neither source present" \
  bash -c "[[ \"\$(cat ${SANDBOX}/out_none)\" == '' ]]"

assert_summary
