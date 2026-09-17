#!/usr/bin/env bash
# actions_decommission_test.sh — E-268 (D-072, local-ci.md §Component 6b).
#
# GitHub Actions is retired: the workflow is deleted and every surface that told an operator
# (or an agent) to look at a hosted run now points at `ai ci`. The assertions are the
# acceptance grep, kept executable — a future edit that reintroduces a hosted-CI instruction
# fails here rather than sending someone to a pipeline that no longer runs.
#
# The workflow file stays in git history; that is the rollback (D-072).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: actions_decommission_test (E-268) ────────────────────────"

# ── E-268.1: the workflow is gone, history keeps it ───────────────────────
assert_status 1 "E-268.01a: .github/workflows no longer exists" test -e "${REPO_ROOT}/.github/workflows"
assert_status 1 "E-268.01b: and neither does the workflow file" test -e "${REPO_ROOT}/.github/workflows/test.yml"
assert_status 0 "E-268.01c: .github survives (copilot-instructions.md lives there)" \
  test -f "${REPO_ROOT}/.github/copilot-instructions.md"
assert_status 0 "E-268.01d: the workflow is still in git history — that is the rollback" \
  bash -c "cd '$REPO_ROOT' && git log --oneline -1 -- .github/workflows/test.yml | grep -q ."

# ── E-268.2: nothing instructs anyone to read a hosted run ───────────────
# One grep, the acceptance one. Written as regexes so this suite does not trip itself.
# --exclude-dir=node_modules: `ai ci run` installs dependencies INSIDE the worktree it
# tests, and half of npm advertises its own GitHub Actions badge. Without this the assertion
# measured what the machine happened to have installed (E-236) — it passed on a tree with no
# vendored deps and failed under the runner, which is the wrong way round.
_hits="$(cd "$REPO_ROOT" && grep -rnE --exclude-dir=node_modules --exclude-dir=.git \
  'gh +run|GITHUB_ACTIONS|actions/workflow|workflows/test\.yml|ubuntu-latest' \
  src tests hooks .claude README.md CONTRIBUTING.md ENGINEER.md ARCHITECT.md install-ai-os.sh 2>/dev/null \
  | grep -vE '^tests/suites/actions_decommission_test\.sh:' || true)"
assert_status 0 "E-268.02a: no hosted-CI instruction remains under src/tests/hooks/.claude/docs" \
  bash -c "[[ -z \"\$1\" ]]" _ "$_hits"
[[ -n "$_hits" ]] && printf '  ⓘ remaining hits:\n%s\n' "$_hits"
# The permitted mentions: CHANGELOG history, DECISIONS, the archive.
assert_status 0 "E-268.02b: the CHANGELOG records the removal for the release notes" \
  grep -q 'GitHub Actions workflow removed; CI runs locally via `ai ci`' "${REPO_ROOT}/CHANGELOG.md"
assert_status 0 "E-268.02c: under an Unreleased BREAKING heading, where E-263 will find it" \
  bash -c "sed -n '/^## \[Unreleased\]/,/^## \[3/p' '${REPO_ROOT}/CHANGELOG.md' | grep -q 'Changed — BREAKING'"

# ── E-268.3: README ──────────────────────────────────────────────────────
assert_status 1 "E-268.03a: the Tests badge is gone" grep -q 'badge.svg' "${REPO_ROOT}/README.md"
assert_status 0 "E-268.03b: a Local CI section documents the runner" \
  grep -q '^## Local CI — `ai ci`' "${REPO_ROOT}/README.md"
for needle in 'ai ci run' 'ai ci status' 'ai ci log --failed' 'AI_OS_CI_SKIP_REASON' 'pre-push'; do
  assert_status 0 "E-268.03c: README documents ${needle}" \
    bash -c "sed -n '/^## Local CI/,/^## Troubleshooting/p' '${REPO_ROOT}/README.md' | grep -qF '$needle'"
done

# ── E-268.4: CONTRIBUTING ────────────────────────────────────────────────
assert_status 0 "E-268.04a: CONTRIBUTING has the Local CI section" \
  grep -q 'Local CI (`ai ci`)' "${REPO_ROOT}/CONTRIBUTING.md"
assert_status 0 "E-268.04b: and says what green means for a PR" \
  grep -q 'non-dirty' "${REPO_ROOT}/CONTRIBUTING.md"
assert_status 0 "E-268.04c: and names the recorded bypass" \
  grep -q 'AI_OS_CI_SKIP=1' "${REPO_ROOT}/CONTRIBUTING.md"

# ── E-268.5: the agent-facing surfaces ───────────────────────────────────
CG="${REPO_ROOT}/src/claude/skills/ci_gate/SKILL.md"
assert_status 0 "E-268.05a: ci_gate names the local config files it protects" \
  grep -q 'hooks/pre-push.sh' "$CG"
assert_status 0 "E-268.05b: ci_gate injects the local CI verdict, not a workflow find" \
  grep -q 'ai ci status --ref HEAD --short' "$CG"
assert_status 0 "E-268.05c: ci_gate enforces the step order of the runner" \
  grep -q 'worktree → env → deps' "$CG"
assert_status 0 "E-268.05d: the DevOps contract says what CI means here" \
  grep -q 'ai ci run` on the machine' "${REPO_ROOT}/src/contracts/40_DEVOPS.md"
assert_status 0 "E-268.05e: devops_engineer knows CI is local" \
  grep -q 'AI-OS itself runs CI locally' "${REPO_ROOT}/src/claude/agents/devops_engineer.md"
assert_status 0 "E-268.05f: the copilot brief no longer offers CI triggers" \
  bash -c "! grep -q 'CI triggers' '${REPO_ROOT}/src/copilot/COPILOT.md'"

# ── E-268.6: mirrors carry the same text ─────────────────────────────────
assert_mirror_if_present "E-268.06a: .claude/skills/ci_gate mirrors src/" \
  "$CG" "${REPO_ROOT}/.claude/skills/ci_gate/SKILL.md"
assert_mirror_if_present "E-268.06b: .claude/agents/devops_engineer mirrors src/" \
  "${REPO_ROOT}/src/claude/agents/devops_engineer.md" "${REPO_ROOT}/.claude/agents/devops_engineer.md"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== actions_decommission_test.sh PASS ====="
else
  echo "===== actions_decommission_test.sh FAIL (${FAIL_COUNT}) ====="
fi
