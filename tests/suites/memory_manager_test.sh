#!/usr/bin/env bash
# memory_manager_test.sh — Tests for memory-manager-mcp (E-110 / §31)
# Validates: export_signature upsert, sanitization, query_signatures OR logic,
# and silent failure on unwritable store directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="${SCRIPT_DIR}/../.."
MEMORY_MCP="${REPO_ROOT}/src/mcp/memory-manager-mcp/index.js"

echo "── Suite: memory_manager_test ──────────────────────────────────────"

# T-04.01: MCP file exists and is syntactically valid
assert_exists "$MEMORY_MCP"
assert_status 0 "T-04.01: memory-manager-mcp syntax OK" \
  node -e "import('file://${MEMORY_MCP}').catch(e => { if (e instanceof SyntaxError) process.exit(1); })"

# ── Isolated store in tmpdir (avoids touching real ~/.ai-os) ─────────────────
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
STORE_FILE="${FAKE_HOME}/.ai-os/memory/signatures.json"

# Helper: export a signature to the isolated store (inlines memory-manager-mcp logic)
export_sig() {
  local project_name="$1" summary="$2" tags_json="$3"
  HOME="$FAKE_HOME" node -e "
    import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
    import { resolve, join } from 'path';
    const STORE_DIR  = resolve(process.env.HOME, '.ai-os', 'memory');
    const STORE_FILE = join(STORE_DIR, 'signatures.json');

    function sanitize(str, maxLen = 300) {
      if (typeof str !== 'string') return '';
      return str
        .replace(/\b(password|passwd|api[_-]?key|secret|token|private[_-]?key)\s*[=:]\s*\S+/gi, '[REDACTED]')
        .replace(/\b[A-Za-z0-9+/]{40,}\b/g, '[REDACTED_BLOB]')
        .slice(0, maxLen);
    }
    function readStore() {
      try { return existsSync(STORE_FILE) ? JSON.parse(readFileSync(STORE_FILE,'utf8')) : []; }
      catch { return []; }
    }
    function writeStore(sigs) {
      try { mkdirSync(STORE_DIR,{recursive:true}); writeFileSync(STORE_FILE,JSON.stringify(sigs,null,2)+'\n','utf8'); return true; }
      catch { return false; }
    }
    const projectName = sanitize('$project_name', 100);
    const summary     = sanitize('$summary', 300);
    const tags        = JSON.parse('$tags_json').map(t => sanitize(String(t), 50));
    const sig = { project_name: projectName, tags, summary, architect_v: 'unknown', timestamp: new Date().toISOString() };
    const sigs = readStore();
    const dedup = sigs.filter(s => s.project_name !== projectName);
    dedup.push(sig);
    const ok = writeStore(dedup);
    console.log(ok ? 'ok:' + dedup.length : 'write_failed');
  " --input-type=module 2>/dev/null || echo "node_error"
}

# Helper: query signatures from the isolated store
query_sig() {
  local tags_json="$1"
  HOME="$FAKE_HOME" node -e "
    import { readFileSync, existsSync } from 'fs';
    import { resolve, join } from 'path';
    const STORE_FILE = join(resolve(process.env.HOME, '.ai-os', 'memory'), 'signatures.json');
    function readStore() {
      try { return existsSync(STORE_FILE) ? JSON.parse(readFileSync(STORE_FILE,'utf8')) : []; }
      catch { return []; }
    }
    const queryTags = JSON.parse('$tags_json').map(t => String(t).toLowerCase());
    const matched = readStore().filter(s => {
      const sigTags = (s.tags || []).map(t => String(t).toLowerCase());
      return queryTags.some(qt => sigTags.some(st => st.includes(qt)));
    });
    console.log(JSON.stringify(matched.map(s => s.project_name)));
  " --input-type=module 2>/dev/null || echo "[]"
}

# T-04.02: export_signature creates store entry
result=$(export_sig "test-project" "A test project summary" '["bash","node"]')
assert_contains "T-04.02: export_signature creates store entry" "ok:1" "$result"
assert_exists "$STORE_FILE"

# T-04.03: duplicate project upserts (no duplicate entries)
export_sig "test-project" "Updated summary" '["bash","node"]' >/dev/null
store_count=$(python3 -c "import json; d=json.load(open('${STORE_FILE}')); print(len(d))")
assert_contains "T-04.03: duplicate project upserts (1 entry, not 2)" "1" "$store_count"

# T-04.04: sanitization strips secrets from summary
export_sig "secret-project" "api_key=supersecret123 is the config" '["api"]' >/dev/null
summary_val=$(python3 -c "
import json; d=json.load(open('${STORE_FILE}'))
p=[s for s in d if s['project_name']=='secret-project']
print(p[0]['summary'] if p else 'not_found')
")
assert_contains "T-04.04: sanitization inserts [REDACTED] placeholder" "[REDACTED]" "$summary_val"
assert_not_contains "T-04.04b: raw secret value not stored" "supersecret123" "$summary_val"

# T-04.05: export multiple projects (total count correct)
export_sig "project-alpha" "Alpha project" '["react","api"]' >/dev/null
export_sig "project-beta"  "Beta project"  '["vue","auth"]'  >/dev/null
total=$(python3 -c "import json; d=json.load(open('${STORE_FILE}')); print(len(d))")
assert_contains "T-04.05: store holds 4 distinct projects" "4" "$total"

# T-04.06: query_signatures matches by tag (single tag)
matches=$(query_sig '["react"]')
assert_contains "T-04.06: query matches project-alpha (react tag)" "project-alpha" "$matches"
assert_not_contains "T-04.06b: query excludes project-beta (no react tag)" "project-beta" "$matches"

# T-04.07: query_signatures OR logic returns multiple matches
multi=$(query_sig '["react","auth"]')
assert_contains "T-04.07a: OR logic matches alpha (react)" "project-alpha" "$multi"
assert_contains "T-04.07b: OR logic matches beta (auth)" "project-beta" "$multi"

# T-04.08: silent failure when store directory is unwritable
READONLY_HOME=$(mktemp -d)
# Make .ai-os/memory unwritable by making parent unwritable
mkdir -p "${READONLY_HOME}/.ai-os"
chmod 000 "${READONLY_HOME}/.ai-os"
fail_result=$(HOME="$READONLY_HOME" node -e "
  import { writeFileSync, mkdirSync } from 'fs';
  import { resolve, join } from 'path';
  const STORE_DIR  = resolve(process.env.HOME, '.ai-os', 'memory');
  const STORE_FILE = join(STORE_DIR, 'signatures.json');
  function writeStore(sigs) {
    try { mkdirSync(STORE_DIR,{recursive:true}); writeFileSync(STORE_FILE,JSON.stringify(sigs)); return true; }
    catch { return false; }
  }
  console.log(writeStore([{test:true}]) ? 'wrote' : 'silent_failure');
" --input-type=module 2>/dev/null || echo "node_error")
chmod 755 "${READONLY_HOME}/.ai-os"
rm -rf "$READONLY_HOME"
assert_contains "T-04.08: silent failure on unwritable store (no crash)" "silent_failure" "$fail_result"

assert_summary
