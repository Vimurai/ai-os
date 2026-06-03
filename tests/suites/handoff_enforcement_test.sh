#!/usr/bin/env bash
# handoff_enforcement_test.sh — E-119 (interactive-bridge.md §Automated Handoff
# Enforcement): the ai-handoff and ai-task skills (Claude + Gemini) strictly
# mandate calling handoff_control at session completion so the `ai watch` bridge
# wakes the other agent's pane without a human keypress.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

HANDOFF="${REPO_ROOT}/src/shared/skills/ai-handoff/SKILL.md"
TASK_CLAUDE="${REPO_ROOT}/src/shared/skills/ai-task/SKILL.md"
TASK_GEMINI="${REPO_ROOT}/src/gemini/skills/ai-task/SKILL.md"

echo "===== handoff_enforcement_test.sh (E-119) ====="

# ── S01: ai-handoff emits the bridge signal (the actual wake mechanism) ───────
assert_status 0 "E-119.S01: ai-handoff calls handoff_control" \
  grep -qF 'handoff_control' "$HANDOFF"
assert_status 0 "E-119.S01: ai-handoff signal step is MANDATORY" \
  grep -qE 'Emit the Bridge Signal \(MANDATORY' "$HANDOFF"
assert_status 0 "E-119.S01: handoff_control in ai-handoff allowed-tools" \
  grep -qE '^allowed-tools:.*handoff_control' "$HANDOFF"
assert_status 0 "E-119.S01: ai-handoff forbids skipping the signal" \
  grep -qE 'Do NOT skip the .?handoff_control' "$HANDOFF"

# ── S02: ai-task (Claude) mandates handoff when the E-## queue is exhausted ───
assert_status 0 "E-119.S02: claude ai-task references handoff_control" \
  grep -qF 'handoff_control' "$TASK_CLAUDE"
assert_status 0 "E-119.S02: claude ai-task hand-back step is MANDATORY" \
  grep -qE 'Hand Control Back \(MANDATORY\)' "$TASK_CLAUDE"
assert_status 0 "E-119.S02: claude ai-task ties handoff to queue exhaustion" \
  grep -qiE 'queue exhausted' "$TASK_CLAUDE"
assert_status 0 "E-119.S02: claude ai-task cites E-119" \
  grep -qF 'E-119' "$TASK_CLAUDE"
assert_status 0 "E-119.S02: handoff_control in claude ai-task allowed-tools" \
  grep -qE '^allowed-tools:.*handoff_control' "$TASK_CLAUDE"
assert_status 0 "E-119.S02: claude ai-task targets gemini on hand-back" \
  grep -qE 'target:[[:space:]]*"gemini"' "$TASK_CLAUDE"

# ── S03: ai-task (Gemini) mandates handoff to Claude at session completion ────
assert_status 0 "E-119.S03: gemini ai-task hand-off step is MANDATORY" \
  grep -qE 'Trigger Handoff to Claude \(MANDATORY' "$TASK_GEMINI"
assert_status 0 "E-119.S03: gemini ai-task triggers ai-handoff (emits signal)" \
  grep -qF 'ai-handoff' "$TASK_GEMINI"
assert_status 0 "E-119.S03: gemini ai-task notes the bridge signal" \
  grep -qF 'handoff_control' "$TASK_GEMINI"
assert_status 0 "E-119.S03: gemini ai-task cites E-119" \
  grep -qF 'E-119' "$TASK_GEMINI"

# ── S04: frontmatter integrity (name present, single opening fence) ──────────
for f in "$HANDOFF" "$TASK_CLAUDE" "$TASK_GEMINI"; do
  assert_status 0 "E-119.S04: $(basename "$(dirname "$(dirname "$f")")")/$(basename "$(dirname "$f")") has name:" \
    bash -c "head -10 '$f' | grep -qE '^name:'"
done

# ── S05: enforcement is DEPLOYED to every mirror (not just src/) ──────────────
chk_mirror() { # chk_mirror <canonical> <mirror>
  if [[ -f "$2" ]]; then
    assert_status 0 "E-119.S05: mirror identical → $2" diff -q "$1" "$2"
  else
    _fail "E-119.S05: mirror MISSING → $2"
  fi
}
chk_mirror "$HANDOFF" "${REPO_ROOT}/.claude/skills/ai-handoff/SKILL.md"
chk_mirror "$HANDOFF" "${REPO_ROOT}/.gemini/skills/ai-handoff/SKILL.md"
chk_mirror "$HANDOFF" "${HOME}/.ai-os/shared/skills/ai-handoff/SKILL.md"
chk_mirror "$TASK_CLAUDE" "${REPO_ROOT}/.claude/skills/ai-task/SKILL.md"
chk_mirror "$TASK_CLAUDE" "${HOME}/.ai-os/shared/skills/ai-task/SKILL.md"
chk_mirror "$TASK_GEMINI" "${REPO_ROOT}/.gemini/skills/ai-task/SKILL.md"
chk_mirror "$TASK_GEMINI" "${HOME}/.ai-os/gemini/skills/ai-task/SKILL.md"

assert_summary
