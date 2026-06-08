#!/usr/bin/env bash
# meta_analyst_test.sh — Tests for E-85 meta_analyst agent + ai-insights skill.
#
# Verifies the contract demanded by .ai/blueprints/meta-cognition.md §Components
# 2 + 3:
#
#   • src/gemini/agents/meta_analyst.md — restricted toolset, read-only over
#     telemetry, write-only over INSIGHTS.md, SQL-aggregates-only contract.
#   • Anti-drift: no source-code edits, no add_task, no proxy_call.
#   • Cross-reference with E-84 telemetry helper (locator chain).
#   • src/shared/skills/ai-insights/SKILL.md — single trigger surface,
#     delegates to meta_analyst, never queries the DB directly.
#   • Frontmatter parses cleanly (description quoted — colon-parse guard
#     mirrors E-49 / E-65 / E-77 / E-78).
#   • Mirrors byte-identical to .gemini/ + .claude/ + ~/.ai-os/.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGENT_SRC="${REPO_ROOT}/src/gemini/agents/meta_analyst.md"
AGENT_GEM="${REPO_ROOT}/.gemini/agents/meta_analyst.md"
AGENT_MIRROR="${HOME}/.ai-os/gemini/agents/meta_analyst.md"
SKILL_SRC="${REPO_ROOT}/src/shared/skills/ai-insights/SKILL.md"
SKILL_CLAUDE="${REPO_ROOT}/.claude/skills/ai-insights/SKILL.md"
SKILL_GEMINI="${REPO_ROOT}/.agents/skills/ai-insights/SKILL.md"
SKILL_MIRROR="${HOME}/.ai-os/shared/skills/ai-insights/SKILL.md"
BLUEPRINT="${REPO_ROOT}/.ai/blueprints/meta-cognition.md"
TELEMETRY="${REPO_ROOT}/src/shared/telemetry.mjs"

echo "===== meta_analyst_test.sh ====="

# ── T-META-S01: meta_analyst frontmatter ──────────────────────────────────────
echo ""
echo "  [T-META-S01] meta_analyst.md frontmatter parses cleanly"

assert_status 0 "src/ agent file exists"             test -f "$AGENT_SRC"
assert_status 0 "frontmatter opens on line 1"        bash -c "head -1 '$AGENT_SRC' | grep -q '^---$'"
assert_status 0 "name: meta_analyst"                 grep -q '^name: meta_analyst$' "$AGENT_SRC"
assert_status 0 "description double-quoted (no colon-parse trap)" \
  bash -c "head -10 '$AGENT_SRC' | grep -q '^description: \"'"
assert_status 0 "description names blueprint"        \
  grep -q 'meta-cognition\.md' "$AGENT_SRC"
assert_status 0 "description names E-85"             \
  grep -q 'E-85' "$AGENT_SRC"

# YAML closes on second --- (between line 2 and 12).
assert_status 0 "frontmatter terminates within first 10 lines" \
  bash -c "head -10 '$AGENT_SRC' | awk '/^---$/{c++} END{exit c<2}'"

# ── T-META-S02: anti-drift Forbidden block ────────────────────────────────────
echo ""
echo "  [T-META-S02] anti-drift forbidden block names code/aggregate/scope rules"

assert_status 0 "Forbidden section present"          grep -q '^## Forbidden' "$AGENT_SRC"
assert_status 0 "forbids source-code generation"     \
  grep -qiE 'do NOT write source code' "$AGENT_SRC"
assert_status 0 "forbids SELECT * — aggregates only" \
  grep -qE 'SELECT \*' "$AGENT_SRC"
assert_status 0 "writes only ~/.ai-os/INSIGHTS.md"   \
  grep -qE '~/\.ai-os/INSIGHTS\.md' "$AGENT_SRC"
assert_status 0 "names blueprint §Execution Constraints contract" \
  grep -qE 'Execution Constraints' "$AGENT_SRC"

# Defence-in-depth: no add_task / no proxy_call statements
assert_status 0 "no add_task surface in agent contract" \
  bash -c "! grep -qE '\\<add_task\\>' '$AGENT_SRC' || grep -qE 'Not a task planner|does NOT call .add_task.' '$AGENT_SRC'"

# ── T-META-S03: five canonical SQL aggregates present ─────────────────────────
echo ""
echo "  [T-META-S03] five canonical aggregates per blueprint §API/Read"

assert_status 0 "Aggregate A — error hotspots"       grep -qE -e '-- A\. Tool-error hotspots' "$AGENT_SRC"
assert_status 0 "Aggregate B — latency outliers"     grep -qE -e '-- B\. Latency outliers'    "$AGENT_SRC"
assert_status 0 "Aggregate C — frequency cohort"     grep -qE -e '-- C\. Tool-frequency'      "$AGENT_SRC"
assert_status 0 "Aggregate D — cross-project breadth" grep -qE -e '-- D\. Cross-project'       "$AGENT_SRC"
assert_status 0 "Aggregate E — task velocity"        grep -qE -e '-- E\. Task velocity'       "$AGENT_SRC"

# Each query has a hard LIMIT — bounded result set per blueprint §Token Limits.
LIMIT_COUNT="$(grep -cE '^LIMIT [0-9]+;' "$AGENT_SRC")"
assert_status 0 "every aggregate carries a LIMIT clause (5+)" \
  bash -c "[[ $LIMIT_COUNT -ge 5 ]]"

# 30-day window per Step 2 default.
assert_status 0 "30-day window in queries" \
  grep -qE "datetime\('now', '-30 days'\)" "$AGENT_SRC"

# Three recommendation classes per Step 3.
assert_status 0 "CLI automation candidate class"     grep -qE 'CLI automation candidate'    "$AGENT_SRC"
assert_status 0 "Tool deprecation candidate class"   grep -qE 'Tool deprecation candidate'  "$AGENT_SRC"
assert_status 0 "Latency hardening candidate class"  grep -qE 'Latency hardening candidate' "$AGENT_SRC"

# Empty / steady fast-path sentinel.
assert_status 0 "[INSIGHTS_EMPTY] sentinel"          grep -qE '\[INSIGHTS_EMPTY\]'   "$AGENT_SRC"
assert_status 0 "[INSIGHTS_STABLE] sentinel"         grep -qE '\[INSIGHTS_STABLE\]'  "$AGENT_SRC"
assert_status 0 "[INSIGHTS_PAUSED] sentinel"         grep -qE '\[INSIGHTS_PAUSED\]'  "$AGENT_SRC"

# ── T-META-S04: stamp wiring + restricted toolset ─────────────────────────────
echo ""
echo "  [T-META-S04] agent stamps via task-synchronizer-mcp::add_stamp"

assert_status 0 "names INSIGHTS_GENERATED stamp type" grep -q 'INSIGHTS_GENERATED' "$AGENT_SRC"
assert_status 0 "stamps via task-synchronizer-mcp::add_stamp" \
  grep -qE 'task-synchronizer-mcp::add_stamp' "$AGENT_SRC"
assert_status 0 "restricted toolset declared"        grep -qE 'restricted toolset' "$AGENT_SRC"
assert_status 0 "no proxy_call surface in agent"     \
  bash -c "! grep -qE 'proxy_call' '$AGENT_SRC' || grep -qE 'No proxy_call' '$AGENT_SRC'"

# ── T-META-S05: locator chain references E-84 telemetry helper ────────────────
echo ""
echo "  [T-META-S05] meta_analyst references telemetry.mjs locator chain"

assert_status 0 "names telemetry.mjs by path"        grep -qE 'src/shared/telemetry\.mjs' "$AGENT_SRC"
assert_status 0 "installed mirror in locator chain"  \
  grep -qE '~/\.ai-os/shared/telemetry\.mjs' "$AGENT_SRC"
assert_status 0 "uses getTelemetryStats helper"      grep -qE 'getTelemetryStats' "$AGENT_SRC"

# ── T-META-S06: ai-insights skill frontmatter ─────────────────────────────────
echo ""
echo "  [T-META-S06] ai-insights skill frontmatter parses cleanly"

assert_status 0 "src/ skill file exists"             test -f "$SKILL_SRC"
assert_status 0 "name: ai-insights"                  grep -q '^name: ai-insights$' "$SKILL_SRC"
assert_status 0 "description double-quoted"          \
  bash -c "head -10 '$SKILL_SRC' | grep -q '^description: \"'"
assert_status 0 "user-invocable: true"               grep -q '^user-invocable: true$' "$SKILL_SRC"
assert_status 0 "agent: meta_analyst declared"       grep -q '^agent: meta_analyst$' "$SKILL_SRC"
assert_status 0 "allowed-tools includes Bash"        grep -qE '^allowed-tools:.*Bash' "$SKILL_SRC"
assert_status 0 "allowed-tools includes add_stamp"   grep -qE 'add_stamp' "$SKILL_SRC"

# Frontmatter closes within first 12 lines.
assert_status 0 "frontmatter terminates within first 12 lines" \
  bash -c "head -12 '$SKILL_SRC' | awk '/^---$/{c++} END{exit c<2}'"

# ── T-META-S07: skill delegates to meta_analyst, does NOT query DB itself ─────
echo ""
echo "  [T-META-S07] skill delegates to meta_analyst (no direct DB queries)"

assert_status 0 "skill invokes activate_agent(meta_analyst)" \
  grep -qE 'activate_agent\(.*meta_analyst' "$SKILL_SRC"

# Skill must NOT contain raw SQL — that is the agent's job.
assert_status 1 "skill carries no raw SELECT statements" \
  grep -qE 'SELECT ' "$SKILL_SRC"

# Locator chain for the telemetry helper smoke check.
assert_status 0 "skill references telemetry.mjs locator chain" \
  grep -qE 'src/shared/telemetry\.mjs' "$SKILL_SRC"
assert_status 0 "skill references installed mirror" \
  grep -qE '\.ai-os/shared/telemetry\.mjs' "$SKILL_SRC"

# Skill respects AI_TELEMETRY_DISABLE rollback wiring.
assert_status 0 "skill documents AI_TELEMETRY_DISABLE rollback" \
  grep -qE 'AI_TELEMETRY_DISABLE' "$SKILL_SRC"

# Stamp re-emission rule (skill only re-stamps if agent failed).
assert_status 0 "skill documents add_stamp re-emit rule" \
  grep -qE 're-emit' "$SKILL_SRC"

# ── T-META-S08: blueprint cross-reference ─────────────────────────────────────
echo ""
echo "  [T-META-S08] blueprint exists + meta-cognition.md cross-ref"

assert_status 0 "blueprint exists" test -f "$BLUEPRINT"
assert_status 0 "blueprint names meta_analyst"       grep -qE 'meta_analyst' "$BLUEPRINT"
assert_status 0 "blueprint names ai insights / ai-insights" \
  bash -c "grep -qE 'ai-insights|ai insights' '$BLUEPRINT'"
assert_status 0 "blueprint names INSIGHTS.md"        grep -qE 'INSIGHTS\.md' "$BLUEPRINT"

# Telemetry helper must exist (E-84 prereq).
assert_status 0 "E-84 telemetry helper exists"       test -f "$TELEMETRY"

# ── T-META-S09: telemetry tooling smoke ───────────────────────────────────────
echo ""
echo "  [T-META-S09] telemetry --path / --stats smoke (used by skill Step 1)"

PATHOUT="$(node "$TELEMETRY" --path)"
assert_contains "telemetry --path emits expected suffix" ".ai-os/telemetry.sqlite" "$PATHOUT"

STATS="$(node "$TELEMETRY" --stats)"
assert_contains "telemetry --stats emits status key" "\"status\":" "$STATS"

# ── T-META-S10: mirrors byte-identical ────────────────────────────────────────
echo ""
echo "  [T-META-S10] mirrors byte-identical"

assert_status 0 "meta_analyst → .gemini mirror"      diff -q "$AGENT_SRC" "$AGENT_GEM"
assert_status 0 "meta_analyst → ~/.ai-os mirror"     diff -q "$AGENT_SRC" "$AGENT_MIRROR"
assert_status 0 "ai-insights  → .claude mirror"     diff -q "$SKILL_SRC" "$SKILL_CLAUDE"
assert_status 0 "ai-insights  → .gemini mirror"     diff -q "$SKILL_SRC" "$SKILL_GEMINI"
assert_status 0 "ai-insights  → ~/.ai-os mirror"    diff -q "$SKILL_SRC" "$SKILL_MIRROR"

echo ""
assert_summary
echo "===== meta_analyst_test.sh PASS ====="
