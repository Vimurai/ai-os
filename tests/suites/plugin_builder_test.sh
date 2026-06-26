#!/usr/bin/env bash
# plugin_builder_test.sh — E-144 (native-subagents.md, reconciled): src/shared/
# plugin-builder.mjs packages AI-OS personas into an Antigravity (`agy`) PLUGIN
# (plugin.json + agents/<name>/agent.json in agy's config.customAgent schema). agy
# registers custom subagents ONLY via installed plugins; the retired loose-file
# mapper (E-140) is gone. These tests exercise the builder against seeded fixtures
# in a temp repo — no live `agy` binary required (CI has none).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILDER="${REPO_ROOT}/src/shared/plugin-builder.mjs"
IMPORT="import {buildPlugin,listAgents} from 'file://${BUILDER}'; import {resolve} from 'node:path';"

echo "── Suite: plugin_builder_test (E-144) ──────────────────────────────"

# ── T-1: builder is valid JS ─────────────────────────────────────────────────
assert_exists "$BUILDER"
assert_status 0 "T-1: plugin-builder.mjs valid JS" node --check "$BUILDER"

# ── Seed an isolated fake repo with persona + skill fixtures ─────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/claude/agents" "$TMP/src/gemini/agents"

# persona (claude side)
cat > "$TMP/src/claude/agents/critic_arch.md" <<'EOF'
---
name: critic_arch
description: Architecture reviewer
allowed-tools: Read, Grep
---
You are the architecture critic. Review the diff against the blueprint.
EOF
# persona present in BOTH sides → must dedup to one
cat > "$TMP/src/gemini/agents/critic_arch.md" <<'EOF'
---
name: critic_arch
description: Architecture reviewer (gemini copy)
---
Duplicate — should be skipped (claude wins, first dir scanned).
EOF
# persona (gemini side, write-capable)
cat > "$TMP/src/gemini/agents/devops_engineer.md" <<'EOF'
---
name: devops_engineer
description: CI/CD engineer
allowed-tools: Read, Write, Edit
---
You set up pipelines.
EOF
# skill by type → filtered
cat > "$TMP/src/claude/agents/proc_skill.md" <<'EOF'
---
name: proc_skill
type: skill
description: a procedural skill, not a persona
---
skill body
EOF
# skill by context:default → filtered
cat > "$TMP/src/gemini/agents/proc_default.md" <<'EOF'
---
name: proc_default
context: default
description: default-context, not a persona
---
default body
EOF

# ── T-2: build produces a valid plugin.json manifest ─────────────────────────
OUT="$TMP/out"
( node --input-type=module -e "${IMPORT} buildPlugin(resolve('$TMP'), resolve('$OUT'))" ) >/dev/null 2>&1
assert_status 0 "T-2: plugin.json exists" test -f "$OUT/plugin.json"
manifest=$(node -e "const p=require('$OUT/plugin.json'); process.stdout.write(p.name+'|'+(p.version?'v':'-'))" 2>/dev/null)
assert_contains "T-2b: plugin.json name=ai-os + has version" "ai-os|v" "$manifest"

# ── T-3: persona → bare-name subdir; skills filtered; dedup ──────────────────
assert_status 0 "T-3a: persona → agents/critic_arch/agent.json (bare name, no ai-os- prefix)" \
  test -f "$OUT/agents/critic_arch/agent.json"
assert_status 0 "T-3b: write-capable persona devops_engineer present" \
  test -f "$OUT/agents/devops_engineer/agent.json"
assert_status 1 "T-3c: type:skill FILTERED (no proc_skill)" \
  test -e "$OUT/agents/proc_skill"
assert_status 1 "T-3d: context:default FILTERED (no proc_default)" \
  test -e "$OUT/agents/proc_default"
ndirs=$(find "$OUT/agents" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-3e: exactly 2 personas (dedup critic_arch across both dirs)" "2" "$ndirs"

# ── T-4: agent.json uses agy's config.customAgent schema with the body inlined ─
assert_status 0 "T-4a: agent.json is valid JSON" \
  node -e "JSON.parse(require('fs').readFileSync('$OUT/agents/critic_arch/agent.json','utf8'))"
shape=$(node -e "const a=require('$OUT/agents/critic_arch/agent.json'); const s=a.config&&a.config.customAgent&&a.config.customAgent.systemPromptSections; process.stdout.write(Array.isArray(s)&&/architecture critic/.test(s[0].content)?'OK':'BAD')" 2>/dev/null)
assert_contains "T-4b: config.customAgent.systemPromptSections holds the persona body" "OK" "$shape"
# write-capable persona gets write tools; read-only does not
wt=$(node -e "const a=require('$OUT/agents/devops_engineer/agent.json'); process.stdout.write(a.config.customAgent.toolNames.includes('write_file')?'W':'-')" 2>/dev/null)
assert_contains "T-4c: write-capable persona granted write_file" "W" "$wt"
ro=$(node -e "const a=require('$OUT/agents/critic_arch/agent.json'); process.stdout.write(a.config.customAgent.toolNames.includes('write_file')?'W':'-')" 2>/dev/null)
assert_contains "T-4d: read-only persona NOT granted write_file" "-" "$ro"

# ── T-5: idempotent rebuild + malformed input does not abort the build ───────
# dangling symlink .md → statSync throws → builder must skip it, not crash.
ln -s "$TMP/does-not-exist" "$TMP/src/claude/agents/broken.md" 2>/dev/null || true
( node --input-type=module -e "${IMPORT} buildPlugin(resolve('$TMP'), resolve('$OUT'))" ) >/dev/null 2>&1
assert_status 0 "T-5a: rebuild with a dangling-symlink .md still succeeds (exit 0)" \
  test -f "$OUT/plugin.json"
ndirs2=$(find "$OUT/agents" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_contains "T-5b: idempotent — still exactly 2 personas after rebuild" "2" "$ndirs2"

# ── T-6: builder against the REAL framework source produces the 16 personas ──
real=$(node --input-type=module -e "${IMPORT} const n=listAgents([resolve('${REPO_ROOT}/src/claude/agents'),resolve('${REPO_ROOT}/src/gemini/agents')]); process.stdout.write(String(n.length))" 2>/dev/null)
assert_match "T-6: real src/{claude,gemini}/agents → >=10 personas (got ${real})" "^(1[0-9]|[2-9][0-9])$" "$real"

# ── T-7: committed plugin agent.json is byte-identical to a fresh rebuild (E-186) ────────────
# The generated src/agents/plugin/agents/<name>/agent.json files are committed, but they are
# DERIVED from the persona .md sources. Without this guard an edit to a source .md (or to the
# builder's emit logic) silently drifts the committed artifact until someone notices in agy.
# Rebuild from the REAL framework source into a temp dir and assert byte-identity — for the
# meta_analyst persona this task names explicitly, then for EVERY committed agent.json (so the
# guard covers the whole plugin, not just one persona). cmp -s is an exact byte comparison.
GEN_OUT="$TMP/realbuild"
( node --input-type=module -e "${IMPORT} buildPlugin(resolve('${REPO_ROOT}'), resolve('$GEN_OUT'))" ) >/dev/null 2>&1
COMMITTED_DIR="${REPO_ROOT}/src/agents/plugin/agents"
assert_status 0 "T-7a: rebuilt meta_analyst/agent.json exists" \
  test -f "$GEN_OUT/agents/meta_analyst/agent.json"
assert_status 0 "T-7b: committed meta_analyst/agent.json is byte-identical to rebuild (E-186)" \
  cmp -s "${COMMITTED_DIR}/meta_analyst/agent.json" "$GEN_OUT/agents/meta_analyst/agent.json"

# T-7c: no committed agent.json drifts from its rebuild. Walks the committed tree so a stale
# artifact for ANY persona fails here, not just meta_analyst. Reports the first drifter by name.
drifted=""
if [[ -d "$COMMITTED_DIR" ]]; then
  while IFS= read -r rel; do
    if ! cmp -s "${COMMITTED_DIR}/${rel}" "${GEN_OUT}/agents/${rel}" 2>/dev/null; then
      drifted="${rel}"; break
    fi
  done < <(cd "$COMMITTED_DIR" && find . -name agent.json -type f | sed 's#^\./##' | sort)
fi
assert_status 0 "T-7c: every committed agent.json matches rebuild (drift: '${drifted:-none}')" \
  test -z "$drifted"

assert_summary
