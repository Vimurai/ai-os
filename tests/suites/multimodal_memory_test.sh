#!/usr/bin/env bash
# multimodal_memory_test.sh — Tests for E-46 multimodal Memory Palace.
#
# Verifies the memory_curator + knowledge_architect agent files (and tracked
# mirrors) carry the contract demanded by may-2026-upgrades.md §"Multimodal
# Memory Curator" / §"knowledge_architect":
#   - Gemini Embedding 2 reference
#   - department metadata (Architecture | UX)
#   - sensitive-file exclusion (.env, .ssh, .gitignore)
#   - 5MB visual cap
#   - background-only execution mandate
#   - knowledge_architect page-level + diagram citations
#   - structured answer envelope schema
#   - byte-identical mirrors

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "===== multimodal_memory_test.sh ====="

CURATOR_FILES=(
  "${REPO_ROOT}/src/gemini/agents/memory_curator.md"
  "${REPO_ROOT}/.gemini/agents/memory_curator.md"
)
ARCHITECT_FILES=(
  "${REPO_ROOT}/src/gemini/agents/knowledge_architect.md"
  "${REPO_ROOT}/.gemini/agents/knowledge_architect.md"
)

# ── T-MM-S01: Files exist and frontmatter parses ──────────────────────────────
echo ""
echo "  [T-MM-S01] Agent files exist with valid YAML frontmatter"

for f in "${CURATOR_FILES[@]}" "${ARCHITECT_FILES[@]}"; do
  assert_status 0 "exists: ${f#${REPO_ROOT}/}" test -f "$f"
  # Description containing colons (e.g. "Trigger on ai sync: ...") was the
  # exact failure mode that broke ux_reviewer (commit 84288ce). Detect any
  # unquoted-colon regression by re-parsing the frontmatter via a tiny
  # Python YAML-lite scanner.
  assert_status 0 "${f##*/agents/} → frontmatter loads cleanly" \
    python3 -c "
import re, sys
src = open('$f').read()
m = re.match(r'---\n(.*?)\n---', src, re.S)
assert m, 'no frontmatter'
body = m.group(1)
# Bail if any line has an unquoted colon-space inside a value. Quoted form
# (description: \"...\") is fine; bare scalars with embedded colon-space are not.
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

# ── T-MM-S02: memory_curator — multimodal contract ───────────────────────────
echo ""
echo "  [T-MM-S02] memory_curator multimodal contract"

for f in "${CURATOR_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → cites Gemini Embedding 2" \
    grep -qE 'Gemini Embedding 2|gemini-embedding-002' "$f"
  assert_status 0 "${f##*/agents/} → declares department classifier"   grep -q 'department' "$f"
  assert_status 0 "${f##*/agents/} → covers Architecture department"   grep -q 'Architecture' "$f"
  assert_status 0 "${f##*/agents/} → covers UX department"             grep -q 'UX' "$f"
  assert_status 0 "${f##*/agents/} → enumerates PNG ingestion"         grep -qi 'PNG' "$f"
  assert_status 0 "${f##*/agents/} → enumerates SVG ingestion"         grep -qi 'SVG' "$f"
  assert_status 0 "${f##*/agents/} → enumerates PDF ingestion"         grep -qi 'PDF' "$f"
done

# ── T-MM-S03: memory_curator — sensitive-file exclusion ──────────────────────
echo ""
echo "  [T-MM-S03] Sensitive-file exclusion"

for f in "${CURATOR_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → excludes .env paths"      grep -q '\.env' "$f"
  assert_status 0 "${f##*/agents/} → excludes .ssh paths"      grep -q '\.ssh' "$f"
  assert_status 0 "${f##*/agents/} → honours .gitignore"       grep -qi 'gitignore' "$f"
  assert_status 0 "${f##*/agents/} → blocks credential names"  grep -qi 'credential\|id_rsa\|\\.pem\|\\.p12' "$f"
done

# ── T-MM-S04: memory_curator — execution constraints ────────────────────────
echo ""
echo "  [T-MM-S04] Execution constraints"

for f in "${CURATOR_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → 5MB cap stated"      grep -qE '5[[:space:]]*MB|5242881|5_?MB' "$f"
  assert_status 0 "${f##*/agents/} → background-only"     grep -qiE 'Background only|never on synchronous ai init|background job' "$f"
  assert_status 0 "${f##*/agents/} → handles 429 backoff" grep -q '429' "$f"
done

# ── T-MM-S05: knowledge_architect — multimodal output ────────────────────────
echo ""
echo "  [T-MM-S05] knowledge_architect multimodal output"

for f in "${ARCHITECT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → cites page-level PDF citations" \
    grep -qE 'page-level|#p<page>' "$f"
  assert_status 0 "${f##*/agents/} → cites visual diagrams" \
    grep -qiE 'visual diagrams|retrieved diagrams|diagram references' "$f"
  assert_status 0 "${f##*/agents/} → uses gemini-embedding-002" \
    grep -q 'gemini-embedding-002' "$f"
  assert_status 0 "${f##*/agents/} → applies department metadata filter" \
    grep -q 'department' "$f"
done

# Verify the answer envelope schema is present in both copies.
for f in "${ARCHITECT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → answer envelope has 'kind:pdf'" \
    grep -q '"kind": "pdf"' "$f"
  assert_status 0 "${f##*/agents/} → answer envelope has 'kind:diagram'" \
    grep -q '"kind": "diagram"' "$f"
  assert_status 0 "${f##*/agents/} → envelope carries department metadata" \
    grep -q '"department"' "$f"
done

# ── T-MM-S06: knowledge_architect — RETRIEVAL_QUERY task type ────────────────
echo ""
echo "  [T-MM-S06] RETRIEVAL_QUERY task_type for queries"

for f in "${ARCHITECT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → RETRIEVAL_QUERY task type" \
    grep -q 'RETRIEVAL_QUERY' "$f"
done

# memory_curator embeds with RETRIEVAL_DOCUMENT task_type.
for f in "${CURATOR_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → RETRIEVAL_DOCUMENT task type" \
    grep -q 'RETRIEVAL_DOCUMENT' "$f"
done

# ── T-MM-S07: SEED.md token discipline preserved ─────────────────────────────
echo ""
echo "  [T-MM-S07] SEED.md visual-citation exclusion"

for f in "${ARCHITECT_FILES[@]}"; do
  assert_status 0 "${f##*/agents/} → visual citations excluded from SEED.md" \
    grep -qiE 'excluded from SEED.md|seed token-cheap' "$f"
done

# ── T-MM-S08: Mirrors are byte-identical ────────────────────────────────────
echo ""
echo "  [T-MM-S08] Source-of-truth ⇄ project mirror byte-identical"

CURATOR_SRC="$(md5sum "${REPO_ROOT}/src/gemini/agents/memory_curator.md" | awk '{print $1}')"
CURATOR_MIR="$(md5sum "${REPO_ROOT}/.gemini/agents/memory_curator.md"     | awk '{print $1}')"
assert_status 0 "memory_curator mirror = src" \
  bash -c "[[ '$CURATOR_SRC' == '$CURATOR_MIR' ]]"

ARCH_SRC="$(md5sum "${REPO_ROOT}/src/gemini/agents/knowledge_architect.md" | awk '{print $1}')"
ARCH_MIR="$(md5sum "${REPO_ROOT}/.gemini/agents/knowledge_architect.md"    | awk '{print $1}')"
assert_status 0 "knowledge_architect mirror = src" \
  bash -c "[[ '$ARCH_SRC' == '$ARCH_MIR' ]]"

assert_summary
