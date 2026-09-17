#!/usr/bin/env bash
# AI-OS pre-push — Local CI gate (E-267, D-072, local-ci.md §Components 5b)
# Logic: every pushed tip needs a green, non-dirty `ai ci run` row in the project's
#        .ai/state.sqlite — or a green row for an ancestor that differs from the tip only
#        under .ai/ (the bookkeeping commits ai-task makes after a DONE).
# Bypass: AI_OS_CI_SKIP=1 AI_OS_CI_SKIP_REASON="<why>" git push — ONE push; the skip is
#         written to ci_runs as a SKIPPED row with the reason. No reason, no skip.
# Install: `ai init` / `ai sync` write a stub to .git/hooks/pre-push that execs this file.
# stdin (git): "<local ref> <local sha> <remote ref> <remote sha>" per pushed ref.

# Install-mirror-only helper resolution (E-223): the visited repo never supplies the code
# that decides whether its own push may leave the machine. Unlike pre-commit.sh there is no
# script-relative fallback — a missing mirror fails this gate closed below anyway.
export AI_OS_LOCATE_UNTRUSTED_ENV=1
_AI_OS_HOME_DIR="${HOME}/.ai-os"
unset -f ai_os_locate ai_os_locate_enable_dev_tree ai_os_is_framework_clone 2>/dev/null || true
[[ -f "${_AI_OS_HOME_DIR}/shared/locate.sh" ]] && . "${_AI_OS_HOME_DIR}/shared/locate.sh"
if ! declare -f ai_os_locate >/dev/null 2>&1; then
  ai_os_locate() { local _c="${_AI_OS_HOME_DIR}/${1}"; [[ -f "$_c" ]] && { printf '%s' "$_c"; return 0; }; return 1; }
fi

ZERO_SHA="0000000000000000000000000000000000000000"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
AI_DIR="${ROOT}/.ai"

# Not an AI-OS project: nothing to enforce.
[[ -d "$AI_DIR" ]] || exit 0

# Fail CLOSED from here on: a gate that silently lets everything through when its helper
# is missing is the pre-D-060 state with a hook that looks authoritative.
HELPER="$(ai_os_locate shared/ci-record.mjs 2>/dev/null || true)"
if [[ -z "$HELPER" ]] || ! command -v node >/dev/null 2>&1; then
  echo "[CI_GATE] pre-push: ci-record.mjs or node unavailable — run: bash install-ai-os.sh" >&2
  exit 1
fi
NODE_FLAGS=(--disable-warning=MODULE_TYPELESS_PACKAGE_JSON --disable-warning=ExperimentalWarning)

skip="${AI_OS_CI_SKIP:-0}"
reason="${AI_OS_CI_SKIP_REASON:-}"
rc=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "${local_ref:-}" ]] && continue
  # A deletion pushes no content.
  [[ "$local_sha" == "$ZERO_SHA" ]] && continue
  if [[ "$skip" == "1" ]]; then
    node "${NODE_FLAGS[@]}" "$HELPER" skip --ai-dir "$AI_DIR" --sha "$local_sha" \
      --ref "$remote_ref" --reason "$reason" || rc=1
  else
    node "${NODE_FLAGS[@]}" "$HELPER" gate --ai-dir "$AI_DIR" --sha "$local_sha" \
      --ref "$remote_ref" || rc=1
  fi
done
exit "$rc"
