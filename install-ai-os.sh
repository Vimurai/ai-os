#!/usr/bin/env bash
# AI-OS v3.2 Installer — thin copier
# Source files live in src/; this script copies them to ~/.ai-os/ and sets up PATH.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIOS="${HOME}/.ai-os"

echo "AI-OS v3.2 installer"
echo "Source: ${REPO_DIR}/src"
echo "Target: ${AIOS}"
echo ""

# ── 1) Copy src tree to ~/.ai-os ─────────────────────────────────────────────

mkdir -p "${AIOS}"

# Use rsync if available (preserves permissions, faster); fall back to cp
if command -v rsync &>/dev/null; then
  rsync -a --delete "${REPO_DIR}/src/contracts/"  "${AIOS}/contracts/"
  rsync -a --delete "${REPO_DIR}/src/templates/"  "${AIOS}/templates/"
  rsync -a --delete "${REPO_DIR}/src/shared/"     "${AIOS}/shared/"
  rsync -a --delete "${REPO_DIR}/src/claude/"     "${AIOS}/claude/"
  rsync -a --delete "${REPO_DIR}/src/gemini/"     "${AIOS}/gemini/"
  rsync -a --delete "${REPO_DIR}/src/copilot/"    "${AIOS}/copilot/"
  rsync -a --delete "${REPO_DIR}/src/bin/"        "${AIOS}/bin/"
  rsync -a --delete "${REPO_DIR}/src/config/"     "${AIOS}/config/"
  rsync -a          "${REPO_DIR}/src/mcp/"        "${AIOS}/mcp/"
  rsync -a          "${REPO_DIR}/hooks/"           "${AIOS}/hooks/"
else
  cp -rf "${REPO_DIR}/src/contracts/"  "${AIOS}/contracts/"
  cp -rf "${REPO_DIR}/src/templates/"  "${AIOS}/templates/"
  cp -rf "${REPO_DIR}/src/shared/"     "${AIOS}/shared/"
  cp -rf "${REPO_DIR}/src/claude/"     "${AIOS}/claude/"
  cp -rf "${REPO_DIR}/src/gemini/"     "${AIOS}/gemini/"
  cp -rf "${REPO_DIR}/src/copilot/"    "${AIOS}/copilot/"
  cp -rf "${REPO_DIR}/src/bin/"        "${AIOS}/bin/"
  cp -rf "${REPO_DIR}/src/config/"     "${AIOS}/config/"
  cp -rf "${REPO_DIR}/src/mcp/"        "${AIOS}/mcp/"
  cp -rf "${REPO_DIR}/hooks/"          "${AIOS}/hooks/"
fi

chmod +x "${AIOS}/bin/ai"
chmod +x "${AIOS}/hooks/"*.sh 2>/dev/null || true

echo "✓ Files copied to ${AIOS}"

# ── 2) Remove orphaned v2 contracts (left over from previous installs) ────────

ORPHANS=(10_WORKFLOW.md 20_OWNERSHIP.md 30_TOKEN_DISCIPLINE.md 40_SECURITY.md 50_DEVOPS.md 60_SEO_COMPLIANCE.md)
REMOVED=0
for f in "${ORPHANS[@]}"; do
  if [[ -f "${AIOS}/contracts/$f" ]]; then
    rm -f "${AIOS}/contracts/$f"
    echo "✓ Removed orphaned contract: $f"
    REMOVED=1
  fi
done
[[ $REMOVED -eq 0 ]] && echo "✓ Contracts clean (no orphans)"

# ── 3) PATH setup ─────────────────────────────────────────────────────────────

ensure_path_line() {
  local rc="$1"
  local line='export PATH="$HOME/.ai-os/bin:$PATH"'
  [[ -f "$rc" ]] || touch "$rc"
  if ! grep -qF "$line" "$rc" 2>/dev/null; then
    printf "\n# AI-OS\n%s\n" "$line" >> "$rc"
    echo "✓ Added PATH to ${rc}"
  fi
}

ensure_path_line "${HOME}/.zprofile"
ensure_path_line "${HOME}/.zshrc"
ensure_path_line "${HOME}/.bashrc"

# ── 4) Install global configs + hooks + fix settings.json ────────────────────

echo ""
echo "Running: ai install (global configs + hooks + settings.json) ..."
"${AIOS}/bin/ai" install

# ── Done ──────────────────────────────────────────────────────────────────────

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AI-OS v3.2 installed at: ${AIOS}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Next steps:

1) Reload shell:
   source ~/.zprofile && source ~/.zshrc

2) Verify everything:
   ai doctor

3) In any project repo:
   ai init       — scaffold .ai/ directory
   ai preflight  — see the read order
   ai update     — start a Claude session

4) Gemini: use /gemini skill from Claude — no separate session needed.

5) MCP servers (auto-configured — requires Node.js):
   ai mcp-setup   ← installs deps + regenerates .mcp.json with absolute paths
   ai doctor      ← verify per-server health

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
