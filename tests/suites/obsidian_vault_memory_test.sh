#!/usr/bin/env bash
# obsidian_vault_memory_test.sh — Tests for E-51 Obsidian Vault Memory.
#
# Verifies the contract demanded by claude-obsidian-optimizations.md
# §"Obsidian Memory Standard": every documentation skill that emits content
# into .ai/ must specify YAML frontmatter on new files and use [[wikilinks]]
# for cross-references to other .ai/ files / D-### / E-## / P-## IDs.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== obsidian_vault_memory_test.sh ====="

# Three skill source-of-truth paths and their expected mirrors.
SKILLS=(
  "blueprint-writer:gemini"
  "decision-recorder:gemini"
  "ai-log:shared"
)

# Resolve the source-of-truth path for a skill.
src_path() {
  local skill="$1" namespace="$2"
  case "$namespace" in
    gemini) echo "${REPO_ROOT}/src/gemini/skills/${skill}/SKILL.md" ;;
    shared) echo "${REPO_ROOT}/src/shared/skills/${skill}/SKILL.md" ;;
    *) return 1 ;;
  esac
}

# Resolve the mirrors a skill is expected to ship to.
mirrors_for() {
  local skill="$1" namespace="$2"
  case "$namespace" in
    gemini)
      printf '%s\n%s\n' \
        "${REPO_ROOT}/.gemini/skills/${skill}/SKILL.md" \
        "${REPO_ROOT}/.gemini/skills/${skill}/SKILL.md"
      ;;
    shared)
      printf '%s\n%s\n' \
        "${REPO_ROOT}/.claude/skills/${skill}/SKILL.md" \
        "${REPO_ROOT}/.gemini/skills/${skill}/SKILL.md"
      ;;
  esac
}

# ── T-OBS-S01: Frontmatter description references E-51 / Obsidian ────────────
echo ""
echo "  [T-OBS-S01] Description references E-51 / Obsidian"

for entry in "${SKILLS[@]}"; do
  skill="${entry%%:*}"
  namespace="${entry##*:}"
  src="$(src_path "$skill" "$namespace")"

  assert_status 0 "${skill} → src exists" test -f "$src"
  assert_status 0 "${skill} → description names E-51 or Obsidian" \
    grep -qE '^description:.*(E-51|Obsidian|wikilink|YAML frontmatter)' "$src"
done

# ── T-OBS-S02: blueprint-writer body teaches frontmatter + wikilinks ─────────
echo ""
echo "  [T-OBS-S02] blueprint-writer body"

BPW="${REPO_ROOT}/src/gemini/skills/blueprint-writer/SKILL.md"

assert_status 0 "blueprint-writer mandates YAML frontmatter on new blueprints" \
  grep -q 'YAML frontmatter' "$BPW"
assert_status 0 "blueprint-writer documents type/tier/tags fields" \
  bash -c "grep -q 'type:[[:space:]]*blueprint' '$BPW' && grep -q 'tier:' '$BPW' && grep -q 'tags:' '$BPW'"
assert_status 0 "blueprint-writer documents [[wikilinks]] for cross-refs" \
  grep -qE '\[\[[a-z0-9._-]+\.md\]\]|\[\[D-[0-9]+\]\]|\[\[E-[0-9]+\]\]|\[\[P-[0-9]+\]\]' "$BPW"
assert_status 0 "blueprint-writer forbids bare markdown links for .ai cross-refs" \
  grep -qE 'bare markdown links|do not use bare' "$BPW"
assert_status 0 "blueprint-writer references memory_curator integration" \
  grep -q 'memory_curator' "$BPW"

# ── T-OBS-S03: decision-recorder body teaches frontmatter + wikilinks ────────
echo ""
echo "  [T-OBS-S03] decision-recorder body"

DR="${REPO_ROOT}/src/gemini/skills/decision-recorder/SKILL.md"

assert_status 0 "decision-recorder mandates DECISIONS.md-level frontmatter" \
  grep -qE 'type:[[:space:]]*decisions' "$DR"
assert_status 0 "decision-recorder D-### template uses [[P-##]] wikilink" \
  grep -qE '\[\[P-##\]\]|\[\[E-##\]\]' "$DR"
assert_status 0 "decision-recorder template uses [[Blueprint]] wikilink" \
  grep -qE '\[\[<filename>\.md\]\]|\[\[blueprint\.md\]\]|\[\[<.+>\.md\]\]' "$DR"
assert_status 0 "decision-recorder template wikilinks supersedes" \
  grep -qE 'Supersedes:[[:space:]]*\[\[D-' "$DR"
assert_status 0 "decision-recorder forbids bare links in NOT-to-do" \
  grep -qE 'bare links|bare markdown' "$DR"

# ── T-OBS-S04: ai-log body teaches wikilinks for task IDs ────────────────────
echo ""
echo "  [T-OBS-S04] ai-log body"

ALOG="${REPO_ROOT}/src/shared/skills/ai-log/SKILL.md"

# E-49 contract still holds.
assert_status 0 "ai-log keeps the session= contract"            grep -q 'CLAUDE_CODE_SESSION_ID' "$ALOG"
# E-51 additions.
assert_status 0 "ai-log examples wrap Task-IDs in [[wikilinks]]" \
  grep -qE '\[\[E-[0-9]+\]\]|\[\[P-[0-9]+\]\]' "$ALOG"
assert_status 0 "ai-log instructs to wikilink related notes"   \
  grep -qE 'wikilink|\[\[blueprint-name\.md\]\]' "$ALOG"

# ── T-OBS-S05: Mirrors are byte-identical for each skill ────────────────────
echo ""
echo "  [T-OBS-S05] Source-of-truth ⇄ mirrors byte-identical"

# blueprint-writer + decision-recorder ship to .gemini only.
for skill in blueprint-writer decision-recorder; do
  src="${REPO_ROOT}/src/gemini/skills/${skill}/SKILL.md"
  mir="${REPO_ROOT}/.gemini/skills/${skill}/SKILL.md"
  SRC_HASH="$(md5sum "$src" | awk '{print $1}')"
  MIR_HASH="$(md5sum "$mir" | awk '{print $1}')"
  assert_status 0 "${skill}: .gemini mirror = src" \
    bash -c "[[ '$SRC_HASH' == '$MIR_HASH' ]]"
done

# ai-log ships to both mirrors.
SRC_HASH="$(md5sum "${REPO_ROOT}/src/shared/skills/ai-log/SKILL.md" | awk '{print $1}')"
CLA_HASH="$(md5sum "${REPO_ROOT}/.claude/skills/ai-log/SKILL.md"     | awk '{print $1}')"
GEM_HASH="$(md5sum "${REPO_ROOT}/.gemini/skills/ai-log/SKILL.md"     | awk '{print $1}')"
assert_status 0 "ai-log: .claude mirror = src" \
  bash -c "[[ '$SRC_HASH' == '$CLA_HASH' ]]"
assert_status 0 "ai-log: .gemini mirror = src" \
  bash -c "[[ '$SRC_HASH' == '$GEM_HASH' ]]"

# ── T-OBS-S06: Frontmatter loads as valid YAML on every file ────────────────
echo ""
echo "  [T-OBS-S06] All updated SKILL.md files parse as valid YAML frontmatter"

for skill_path in \
  "${REPO_ROOT}/src/gemini/skills/blueprint-writer/SKILL.md" \
  "${REPO_ROOT}/src/gemini/skills/decision-recorder/SKILL.md" \
  "${REPO_ROOT}/src/shared/skills/ai-log/SKILL.md" \
  "${REPO_ROOT}/.gemini/skills/blueprint-writer/SKILL.md" \
  "${REPO_ROOT}/.gemini/skills/decision-recorder/SKILL.md" \
  "${REPO_ROOT}/.gemini/skills/ai-log/SKILL.md" \
  "${REPO_ROOT}/.claude/skills/ai-log/SKILL.md"; do

  # Detect any bare-scalar value that contains an unquoted colon-space, the
  # exact failure that broke ux_reviewer (84288ce).
  assert_status 0 "${skill_path#${REPO_ROOT}/} → frontmatter loads cleanly" \
    python3 -c "
import re, sys
src = open('$skill_path').read()
m = re.match(r'---\n(.*?)\n---', src, re.S)
if not m: sys.exit(1)
body = m.group(1)
for line in body.split('\n'):
    if ':' not in line: continue
    key, _, value = line.partition(':')
    value = value.strip()
    if not value: continue
    if value.startswith('\"') or value.startswith(\"'\"): continue
    if ': ' in value:
        sys.stderr.write(f'unquoted colon-space in {key.strip()!r}: {value[:60]}\n')
        sys.exit(1)
"
done

assert_summary
