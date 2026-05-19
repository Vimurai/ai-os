#!/usr/bin/env bash
# critic_clean_code_test.sh — Tests for E-81 critic_clean_code persona.
#
# Verifies src/claude/agents/critic_clean_code.md against the contract in
# .ai/blueprints/engineering-standards.md §Components 2 and the integration
# pattern documented in src/claude/skills/ai-review/SKILL.md:
#
#   - Persona file exists with parseable YAML frontmatter
#   - Persona invokes scripts/standards.mjs (the E-80 CLI) — single source
#     of truth, never re-implements the rule logic
#   - Persona stamps via task-synchronizer-mcp::add_stamp (never writes
#     REVIEWS.md directly) using CLEAN_PASS / CLEAN_WARN / CLEAN_FAIL types
#   - ai-review SKILL.md Tier 2 + Tier 3 sections wire the persona in
#   - AI_OS_SKIP_STANDARDS=1 rollback path documented in the persona
#   - Severity ladder + verdict table match the E-80 envelope schema
#   - Mirrors byte-identical to .claude/ + ~/.ai-os/claude/

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PERSONA_SRC="${REPO_ROOT}/src/claude/agents/critic_clean_code.md"
PERSONA_CLD="${REPO_ROOT}/.claude/agents/critic_clean_code.md"
PERSONA_MIRROR="${HOME}/.ai-os/claude/agents/critic_clean_code.md"
REVIEW_SRC="${REPO_ROOT}/src/claude/skills/ai-review/SKILL.md"
REVIEW_CLD="${REPO_ROOT}/.claude/skills/ai-review/SKILL.md"
REVIEW_MIRROR="${HOME}/.ai-os/claude/skills/ai-review/SKILL.md"

echo "===== critic_clean_code_test.sh ====="

# ── T-CCC-S01: Persona file presence + frontmatter integrity ────────────────
echo ""
echo "  [T-CCC-S01] Persona file exists with parseable frontmatter"

assert_status 0 "src/ persona exists"                test -f "$PERSONA_SRC"
assert_status 0 ".claude/ mirror exists"             test -f "$PERSONA_CLD"
assert_status 0 "frontmatter opens on line 1"        bash -c "head -1 '$PERSONA_SRC' | grep -q '^---$'"
assert_status 0 "name: critic_clean_code"            grep -q '^name: critic_clean_code$' "$PERSONA_SRC"
assert_status 0 "description present"                grep -q '^description: ' "$PERSONA_SRC"
assert_status 0 "description double-quoted (colon-parse guard)" \
  bash -c "head -10 '$PERSONA_SRC' | grep -q '^description: \"'"
assert_status 0 "frontmatter has closing delimiter within 30 lines" \
  bash -c "awk 'NR>1 && /^---$/{print NR; exit}' '$PERSONA_SRC' | grep -qE '^[2-9]$|^[12][0-9]$|^30$'"
assert_status 0 "allowed-tools include Bash (for shell + git diff)" \
  grep -q 'allowed-tools:.*Bash' "$PERSONA_SRC"
assert_status 0 "context: fork (parallel-spawnable)"  grep -q '^context: fork' "$PERSONA_SRC"

# ── T-CCC-S02: Persona invokes the E-80 standards-checker CLI ───────────────
echo ""
echo "  [T-CCC-S02] Persona uses scripts/standards.mjs (single source of truth)"

assert_status 0 "persona references scripts/standards.mjs" \
  grep -q 'scripts/standards.mjs' "$PERSONA_SRC"
assert_status 0 "persona uses --staged + --json envelope" \
  grep -q 'check --staged --json' "$PERSONA_SRC"
assert_status 0 "persona documents the locator chain (in-tree + ~/.ai-os fallback)" \
  grep -qE '\$\{HOME\}/.ai-os/scripts/standards.mjs|HOME.*ai-os' "$PERSONA_SRC"
assert_status 0 "persona references standards.json (rule registry)" \
  grep -q 'standards.json' "$PERSONA_SRC"
assert_status 0 "persona reads the engineering-standards blueprint" \
  grep -q 'engineering-standards.md' "$PERSONA_SRC"

# ── T-CCC-S03: Stamp contract — uses MCP, never writes REVIEWS.md ───────────
echo ""
echo "  [T-CCC-S03] Persona stamps via task-synchronizer-mcp::add_stamp"

assert_status 0 "persona invokes add_stamp"           grep -q 'mcp__task-synchronizer-mcp__add_stamp' "$PERSONA_SRC"
assert_status 0 "persona explicitly forbids writing REVIEWS.md" \
  grep -qE 'never write[s]? .*REVIEWS.md|do NOT write.*REVIEWS.md|never writes? \`.ai/REVIEWS.md\`' "$PERSONA_SRC"
for stamp in CLEAN_PASS CLEAN_WARN CLEAN_FAIL; do
  assert_status 0 "stamp type ${stamp} documented" \
    grep -q "${stamp}" "$PERSONA_SRC"
done
assert_status 0 "agent string in stamp = critic_clean_code" \
  grep -qE 'agent: *.*critic_clean_code' "$PERSONA_SRC"

# ── T-CCC-S04: Verdict table follows the E-80 envelope semantics ────────────
echo ""
echo "  [T-CCC-S04] Verdict ladder matches summary{error_count,warning_count}"

assert_status 0 "persona references summary.error_count semantic" \
  grep -q 'error_count' "$PERSONA_SRC"
assert_status 0 "persona references warning_count semantic" \
  grep -qE 'warning_count|warn_count' "$PERSONA_SRC"
assert_status 0 "CLEAN_WARN is non-blocking for Tier 2" \
  grep -qiE 'CLEAN_WARN does NOT block|does not block' "$PERSONA_SRC"
assert_status 0 "CLEAN_FAIL is the COMMIT BLOCKED signal" \
  grep -q 'COMMIT BLOCKED' "$PERSONA_SRC"

# ── T-CCC-S05: Rollback path documented per blueprint §Rollback Plan ───────
echo ""
echo "  [T-CCC-S05] AI_OS_SKIP_STANDARDS=1 escape hatch documented"

assert_status 0 "rollback flag named verbatim"       grep -q 'AI_OS_SKIP_STANDARDS=1' "$PERSONA_SRC"
assert_status 0 "STANDARDS_SKIPPED marker referenced" grep -q 'STANDARDS_SKIPPED' "$PERSONA_SRC"
assert_status 0 "skip-path still emits a stamp"      \
  bash -c "awk '/^## Rollback/{f=1; next} /^## /{f=0} f' '$PERSONA_SRC' | grep -q 'add_stamp'"

# ── T-CCC-S06: Pre-flight reads documented (blueprint + standards.json) ─────
echo ""
echo "  [T-CCC-S06] Persona reads the contract files before reviewing"

assert_status 0 "preflight section present"          grep -q '^## Pre-flight' "$PERSONA_SRC"
assert_status 0 "preflight reads engineering-standards.md blueprint" \
  bash -c "awk '/^## Pre-flight/,/^## Step 1/' '$PERSONA_SRC' | grep -q 'engineering-standards.md'"
assert_status 0 "preflight reads standards.json registry" \
  bash -c "awk '/^## Pre-flight/,/^## Step 1/' '$PERSONA_SRC' | grep -q 'standards.json'"
assert_status 0 "no-staged-surface short-circuit documented" \
  grep -qE 'no staged surface|no staged changes' "$PERSONA_SRC"

# ── T-CCC-S07: ai-review SKILL.md wires critic_clean_code at Tier 2 + Tier 3 ─
echo ""
echo "  [T-CCC-S07] ai-review skill invokes critic_clean_code in Tier 2 + Tier 3"

# Tier 2 block — between '## Tier 2' and '## Tier 3'.
assert_status 0 "Tier 2 section spawns critic_clean_code" \
  bash -c "awk '/^## Tier 2/,/^## Tier 3/' '$REVIEW_SRC' | grep -q 'critic_clean_code'"
assert_status 0 "Tier 2 section names CLEAN_PASS|CLEAN_WARN|CLEAN_FAIL" \
  bash -c "awk '/^## Tier 2/,/^## Tier 3/' '$REVIEW_SRC' | grep -qE 'CLEAN_PASS|CLEAN_WARN|CLEAN_FAIL'"
assert_status 0 "Tier 2 documents the pass-gate condition" \
  bash -c "awk '/^## Tier 2/,/^## Tier 3/' '$REVIEW_SRC' | grep -qE 'CLEAN must NOT be .FAIL|CLEAN_FAIL'"

# Tier 3 block — from '## Tier 3' to EOF.
assert_status 0 "Tier 3 spawns critic_clean_code" \
  bash -c "awk '/^## Tier 3/{f=1} f' '$REVIEW_SRC' | grep -q 'critic_clean_code'"
assert_status 0 "Tier 3 expected-stamps list mentions CLEAN_*" \
  bash -c "awk '/^## Tier 3/{f=1} f' '$REVIEW_SRC' | grep -qE 'CLEAN_PASS/WARN/FAIL'"

# ── T-CCC-S08: ~/.ai-os mirrors byte-identical ──────────────────────────────
echo ""
echo "  [T-CCC-S08] Mirrors match src/"

assert_status 0 "persona .claude/ mirror"      diff -q "$PERSONA_SRC" "$PERSONA_CLD"
if [[ -f "$PERSONA_MIRROR" ]]; then
  assert_status 0 "persona ~/.ai-os/ mirror"   diff -q "$PERSONA_SRC" "$PERSONA_MIRROR"
else
  echo "    ⚠  persona ~/.ai-os/ mirror absent — skipping"
fi
assert_status 0 "ai-review .claude/ mirror"   diff -q "$REVIEW_SRC" "$REVIEW_CLD"
if [[ -f "$REVIEW_MIRROR" ]]; then
  assert_status 0 "ai-review ~/.ai-os/ mirror" diff -q "$REVIEW_SRC" "$REVIEW_MIRROR"
else
  echo "    ⚠  ai-review ~/.ai-os/ mirror absent — skipping"
fi

# ── T-CCC-S09: Reference resolution — critic_clean_code points to E-80 files ─
echo ""
echo "  [T-CCC-S09] Persona's referenced files actually exist in the repo"

assert_status 0 "scripts/standards.mjs exists" test -f "${REPO_ROOT}/scripts/standards.mjs"
assert_status 0 "src/shared/standards.json exists" test -f "${REPO_ROOT}/src/shared/standards.json"
assert_status 0 "blueprint exists"             test -f "${REPO_ROOT}/.ai/blueprints/engineering-standards.md"

# ── T-CCC-S10: Anti-drift — persona does not re-implement checks ────────────
echo ""
echo "  [T-CCC-S10] Persona declares it does NOT bypass the CLI"

assert_status 0 "explicit 'do NOT bypass the CLI' guard" \
  grep -qE 'NOT bypass the CLI|reimplement|single source of truth' "$PERSONA_SRC"
assert_status 0 "explicit read-only review constraint" \
  grep -qE 'read-only|Read-only|MUST NOT modify any source file|Do NOT modify any source' "$PERSONA_SRC"

echo ""
assert_summary
echo "===== critic_clean_code_test.sh PASS ====="
