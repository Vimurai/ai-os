#!/usr/bin/env bash
# seo_engineer_test.sh — Tests for E-90 SEO-Engineer Claude persona.
#
# Verifies src/claude/agents/seo_engineer.md against the contract in
# .ai/blueprints/seo-keyword-multiplier.md §Components 4:
#
#   - Technical SEO persona: meta tags, JSON-LD structured data,
#     canonical URLs, pillar↔cluster internal linking
#   - Anti-drift: NOT content generation (generator), NOT orchestration
#     (E-87), NOT state tracking
#   - Treats the topic term as untrusted input (escape before emit)
#   - YAML frontmatter parses cleanly (description double-quoted —
#     colon-parse guard, same regression mode as E-49 / E-65)
#   - Mirrored byte-identical to .claude/ + ~/.ai-os/claude/

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGENT_SRC="${REPO_ROOT}/src/claude/agents/seo_engineer.md"
AGENT_CLAUDE="${REPO_ROOT}/.claude/agents/seo_engineer.md"
AGENT_MIRROR="${HOME}/.ai-os/claude/agents/seo_engineer.md"
BLUEPRINT="${REPO_ROOT}/.ai/blueprints/seo-keyword-multiplier.md"

echo "===== seo_engineer_test.sh ====="

# ── T-SENG-S01: File presence + frontmatter ──────────────────────────────────
echo ""
echo "  [T-SENG-S01] Persona file exists with parseable YAML frontmatter"

assert_status 0 "src/ persona file exists"           test -f "$AGENT_SRC"
assert_status 0 ".claude/ mirror exists"             test -f "$AGENT_CLAUDE"
assert_status 0 "frontmatter opens on line 1"        bash -c "head -1 '$AGENT_SRC' | grep -q '^---$'"
assert_status 0 "name: seo_engineer"                 grep -q '^name: seo_engineer$' "$AGENT_SRC"
assert_status 0 "description present"                grep -q '^description: ' "$AGENT_SRC"
assert_status 0 "description is double-quoted (no colon-parse trap)" \
  bash -c "head -10 '$AGENT_SRC' | grep -q '^description: \"'"
assert_status 0 "allowed-tools declared"             grep -q '^allowed-tools:' "$AGENT_SRC"
assert_status 0 "allowed-tools permit Write/Edit (implements code)" \
  bash -c "grep '^allowed-tools:' '$AGENT_SRC' | grep -qE 'Write|Edit'"
assert_status 0 "blueprint reference present"        grep -q "seo-keyword-multiplier.md" "$AGENT_SRC"
assert_status 0 "frontmatter has a closing --- delimiter" \
  bash -c "awk 'NR>1 && /^---$/{print NR; exit}' '$AGENT_SRC' | grep -qE '^[2-9]$|^[12][0-9]$|^30$'"
assert_status 0 "description value is properly quoted (no colon-parse trap)" \
  python3 -c "
import re, sys
with open('$AGENT_SRC') as f:
    head = ''.join(f.readlines()[:20])
m = re.search(r'^description:\s*(.+?)\$', head, flags=re.M)
if not m:
    sys.exit(1)
val = m.group(1).strip()
sys.exit(0 if (val.startswith('\"') and val.endswith('\"')) or val.startswith('>') or val.startswith('|') else 2)
"

# ── T-SENG-S02: Required contract sections ───────────────────────────────────
echo ""
echo "  [T-SENG-S02] Persona body covers every required section"

assert_status 0 "ROLE declaration"                   grep -q '^ROLE: SEO_ENGINEER' "$AGENT_SRC"
assert_status 0 "Forbidden section"                  grep -q '^## Forbidden' "$AGENT_SRC"
assert_status 0 "Preflight section"                  grep -q '^## Preflight' "$AGENT_SRC"
assert_status 0 "Technical SEO Standards section"    grep -q '^## Technical SEO Standards' "$AGENT_SRC"
assert_status 0 "Execution Constraints section"      grep -q '^## Execution Constraints' "$AGENT_SRC"
assert_status 0 "Rollback section"                   grep -q '^## Rollback' "$AGENT_SRC"
assert_status 0 "What this agent is NOT (anti-drift)" grep -q '^## What this agent is NOT' "$AGENT_SRC"

# ── T-SENG-S03: Technical SEO standards enforced ─────────────────────────────
echo ""
echo "  [T-SENG-S03] Persona enforces meta tags, JSON-LD, canonicals, linking"

assert_status 0 "meta tags (title + meta description)" \
  bash -c "grep -qiE 'meta description|meta tags' '$AGENT_SRC'"
assert_status 0 "Open Graph / Twitter card tags" \
  bash -c "grep -qiE 'Open Graph|og:title|Twitter Card' '$AGENT_SRC'"
assert_status 0 "canonical URL"                      grep -qi 'canonical' "$AGENT_SRC"
assert_status 0 "JSON-LD structured data"            grep -q 'JSON-LD' "$AGENT_SRC"
assert_status 0 "schema.org types (Article/FAQPage/BreadcrumbList)" \
  bash -c "grep -qE 'FAQPage|BreadcrumbList|Article' '$AGENT_SRC'"
assert_status 0 "pillar↔cluster internal linking"   \
  bash -c "grep -qiE 'internal link|Pillar .* Cluster|link graph' '$AGENT_SRC'"

# ── T-SENG-S04: Anti-drift mandates ──────────────────────────────────────────
echo ""
echo "  [T-SENG-S04] Persona forbids content generation + orchestration + tracking"

assert_status 0 "Forbidden: NO article copy" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qiE 'article copy|body content'"
assert_status 0 "Forbidden: NO orchestration (E-87)" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qE 'orchestrate|SEO-Topic-Cluster-Manager'"
assert_status 0 "Forbidden: NO state tracking" \
  bash -c "awk '/^## Forbidden/,/^## Preflight/' '$AGENT_SRC' | grep -qE 'performance|Multi-Variation-State-Tracker'"
assert_status 0 "References the SEO-Content-Generator owner" \
  grep -q 'SEO-Content-Generator' "$AGENT_SRC"
assert_status 0 "References E-87 orchestrator by id" \
  grep -q 'E-87' "$AGENT_SRC"

# ── T-SENG-S05: Security — untrusted input handling ──────────────────────────
echo ""
echo "  [T-SENG-S05] Topic term treated as untrusted (escape before emit)"

assert_status 0 "untrusted-input handling documented" \
  bash -c "grep -qiE 'untrusted|escape|encode' '$AGENT_SRC'"
assert_status 0 "SEO_ENGINEER_BLOCKED finding tag documented" \
  grep -q 'SEO_ENGINEER_BLOCKED' "$AGENT_SRC"

# ── T-SENG-S06: Idempotency constraint ───────────────────────────────────────
echo ""
echo "  [T-SENG-S06] Execution Constraints require idempotent wiring"

assert_status 0 "idempotent re-run constraint" \
  bash -c "awk '/^## Execution Constraints/,/^## Rollback/' '$AGENT_SRC' | grep -qi 'idempotent'"

# ── T-SENG-S07: Rollback section is actionable ───────────────────────────────
echo ""
echo "  [T-SENG-S07] Rollback maps to git restore of modified files"

assert_status 0 "Rollback references git restore" \
  bash -c "awk '/^## Rollback/,/^## What this agent is NOT/' '$AGENT_SRC' | grep -q 'git restore'"

# ── T-SENG-S08: Mirror byte-identity ─────────────────────────────────────────
echo ""
echo "  [T-SENG-S08] .claude/ + ~/.ai-os/claude/ mirrors match src/"

assert_status 0 ".claude/ mirror byte-identical to src/" \
  diff -q "$AGENT_SRC" "$AGENT_CLAUDE"
if [[ -f "$AGENT_MIRROR" ]]; then
  assert_status 0 "~/.ai-os mirror byte-identical to src/" \
    diff -q "$AGENT_SRC" "$AGENT_MIRROR"
else
  echo "    ⚠  ~/.ai-os mirror absent — skipping"
fi

# ── T-SENG-S09: Bidirectional blueprint reference ────────────────────────────
echo ""
echo "  [T-SENG-S09] Blueprint names E-90 + the persona references the blueprint"

assert_status 0 "blueprint file exists"               test -f "$BLUEPRINT"
assert_status 0 "blueprint names E-90 + seo_engineer.md target" \
  grep -q "E-90.*seo_engineer.md" "$BLUEPRINT"
assert_status 0 "persona description references the blueprint path" \
  grep -q "seo-keyword-multiplier.md" "$AGENT_SRC"

echo ""
assert_summary
echo "===== seo_engineer_test.sh PASS ====="
