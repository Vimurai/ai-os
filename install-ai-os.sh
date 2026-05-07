#!/usr/bin/env bash
# AI-OS v3.2 Installer — thin copier
# Source files live in src/; this script copies them to ~/.ai-os/ and sets up PATH.

# Guard: require bash (process substitution is bash-only; sh/dash will fail)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Error: This script requires bash." >&2
  echo "Run:   bash install-ai-os.sh" >&2
  exit 1
fi

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

# ── 2) Remove orphaned files from installed dirs (dynamic — no hardcoded list) ─

purge_orphans() {
  local src_dir="$1"
  local dst_dir="$2"
  [[ -d "$dst_dir" ]] || return 0
  local removed=0
  while IFS= read -r -d '' dst_file; do
    local rel="${dst_file#${dst_dir}/}"
    if [[ ! -f "${src_dir}/${rel}" ]]; then
      rm -f "$dst_file"
      echo "✓ Removed orphaned file: ${dst_dir}/${rel}"
      removed=1
    fi
  done < <(find "$dst_dir" -maxdepth 1 -type f -print0 2>/dev/null)
  [[ $removed -eq 0 ]] && echo "✓ ${dst_dir##*/}/ clean (no orphans)"
}

# Always run dynamic orphan cleanup (rsync --delete handles this for rsync path;
# purge_orphans covers the cp fallback path and any gap files)
purge_orphans "${REPO_DIR}/src/contracts" "${AIOS}/contracts"
purge_orphans "${REPO_DIR}/src/claude"    "${AIOS}/claude"
purge_orphans "${REPO_DIR}/src/gemini"    "${AIOS}/gemini"
purge_orphans "${REPO_DIR}/src/shared"    "${AIOS}/shared"

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

# E-50: restore native terminal scrollback for tmux users by disabling
# Claude Code's TUI alternate-screen mode at the shell level. This ensures
# `claude` invoked outside an AI-OS project still inherits the flag. Per
# claude-obsidian-optimizations §Rollback: comment the export out if a
# specific OS shows rendering bugs.
ensure_env_line() {
  local rc="$1" var="$2" value="$3"
  local line="export ${var}=\"${value}\""
  [[ -f "$rc" ]] || touch "$rc"
  # Match on the variable name so re-runs don't append duplicates even if
  # the value has been edited.
  if ! grep -qE "^export[[:space:]]+${var}=" "$rc" 2>/dev/null; then
    printf "%s\n" "$line" >> "$rc"
    echo "✓ Added ${var} to ${rc}"
  fi
}

ensure_path_line "${HOME}/.zprofile"
ensure_path_line "${HOME}/.zshrc"
ensure_path_line "${HOME}/.bashrc"

ensure_env_line "${HOME}/.zprofile" "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" "1"
ensure_env_line "${HOME}/.zshrc"    "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" "1"
ensure_env_line "${HOME}/.bashrc"   "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN" "1"

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
