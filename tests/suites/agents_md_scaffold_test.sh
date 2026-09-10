#!/usr/bin/env bash
# agents_md_scaffold_test.sh — E-195: scaffold .agents/AGENTS.md (→ @ARCHITECT.md)
# so Antigravity (agy) auto-loads the Architect persona and does not drift out of
# role. Mirrors the GEMINI.md → ARCHITECT.md shim pattern (D-050/E-183) into the
# agy workspace dir. Sources src/bin/ai (guarded) for the E2E scaffold check.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
TEMPLATE="${REPO_ROOT}/src/templates/AGENTS.md"
WS_FILE="${REPO_ROOT}/.agents/AGENTS.md"
export AIOS="${HOME}/.ai-os"

echo "── Suite: agents_md_scaffold_test (E-195) ──────────────────────────"

# ── T-1: template exists and is an ARCHITECT.md @import shim ──────────────────
assert_exists "$TEMPLATE"
assert_status 0 "T-1: AGENTS.md template @imports ARCHITECT.md" \
  grep -qx '@ARCHITECT.md' "$TEMPLATE"
assert_status 0 "T-1b: AGENTS.md template is a documented shim (E-195)" \
  grep -q 'E-195' "$TEMPLATE"
assert_status 0 "T-1c: shim names ARCHITECT.md as canonical, not itself" \
  grep -q 'Edit `ARCHITECT.md`, never this shim' "$TEMPLATE"

# ── T-2: _sync_workspace_dirs wires the scaffold (init + sync) ────────────────
BIN_CONTENT="$(cat "$AI_BIN")"
assert_contains "T-2: scaffolds .agents/AGENTS.md from the installed template" \
  'cp -f "${AIOS}/templates/AGENTS.md" ".agents/AGENTS.md"' "$BIN_CONTENT"
assert_contains "T-2b: scaffold lives in the shared _sync_workspace_dirs helper" \
  "_sync_workspace_dirs()" "$BIN_CONTENT"

# ── T-3: the workspace copy, WHEN THE WORKSPACE EXISTS ────────────────────────
# E-244 (D-066 §4): this repository no longer carries a tracked .agents/ — `ai sync`
# provisions it only for a project with a role bound to agy. The property T-3 cared about
# (the scaffolded file imports ARCHITECT.md and matches the template) is still proved
# END-TO-END by T-4 below, which provisions its own project and reads the file sync
# actually wrote. That is the stronger test: it exercises the scaffolder rather than
# checking that someone remembered to commit its output.
assert_file_if_present "T-3: .agents/AGENTS.md @imports ARCHITECT.md" "$WS_FILE" \
  grep -qx '@ARCHITECT.md' "$WS_FILE"
assert_mirror_if_present "T-3b: .agents/AGENTS.md byte-identical to src/templates/AGENTS.md" \
  "$TEMPLATE" "$WS_FILE"

# ── T-4 (E2E): a real _sync_workspace_dirs run scaffolds .agents/AGENTS.md ────
# Source the CLI (guarded: sourcing returns before dispatch) and invoke the
# scaffolder in an isolated temp project. Requires the installed template mirror.
if [[ -f "${AIOS}/templates/AGENTS.md" ]]; then
  PROJ="$(mktemp -d)"
  # E-244: the scaffolder only touches .agents/ for a project some role binds to agy.
  # Without this the E2E case would assert on a workspace sync correctly declined to
  # create, and "the scaffold is gone" would look identical to "the scaffold is broken".
  mkdir -p "$PROJ/.ai"
  cat > "$PROJ/.ai/roles.json" <<'JSON'
{ "roles": { "architect": {"provider":"agy","pane_identifier":"1"},
             "engineer":  {"provider":"claude","pane_identifier":"0"} } }
JSON
  (
    cd "$PROJ" || exit 1
    # shellcheck disable=SC1090
    source "$AI_BIN" >/dev/null 2>&1 || true
    _sync_workspace_dirs init >/dev/null 2>&1 || true
  )
  assert_status 0 "T-4: ai sync/init scaffolds .agents/AGENTS.md" \
    test -f "${PROJ}/.agents/AGENTS.md"
  assert_status 0 "T-4b: scaffolded file @imports ARCHITECT.md" \
    grep -qx '@ARCHITECT.md' "${PROJ}/.agents/AGENTS.md"
  rm -rf "$PROJ"
else
  echo "  [SKIP] T-4 E2E — ${AIOS}/templates/AGENTS.md not installed (run: bash install-ai-os.sh)"
fi

assert_summary
