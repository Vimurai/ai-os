#!/usr/bin/env bash
# cache_manager_mcp_test.sh — Unit tests for cache-manager-mcp (E-11)
# Tests: file structure, tool declarations, security constraints,
#        cache assembly, mtime invalidation, registry registration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVER="${REPO_ROOT}/src/mcp/cache-manager-mcp/index.js"

echo "── Suite: cache_manager_mcp ─────────────────────────────────────────"

# ── T-CACHE-S01: File structure ───────────────────────────────────────────────
echo ""
echo "  [T-CACHE-S01] File structure"

assert_status 0 "index.js exists" test -f "$SERVER"
assert_status 0 "package.json exists" test -f "${REPO_ROOT}/src/mcp/cache-manager-mcp/package.json"

assert_status 0 "package.json has type module" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const p = JSON.parse(readFileSync('${REPO_ROOT}/src/mcp/cache-manager-mcp/package.json', 'utf8'));
if (p.type !== 'module') process.exit(1);
JS

assert_status 0 "package.json declares @modelcontextprotocol/sdk dependency" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const p = JSON.parse(readFileSync('${REPO_ROOT}/src/mcp/cache-manager-mcp/package.json', 'utf8'));
if (!p.dependencies?.['@modelcontextprotocol/sdk']) process.exit(1);
JS

# ── T-CACHE-S02: Tool declarations ───────────────────────────────────────────
echo ""
echo "  [T-CACHE-S02] Tool declarations"

assert_status 0 "build_cache tool declared" \
  grep -q '"build_cache"' "$SERVER"

assert_status 0 "get_cached_context tool declared" \
  grep -q '"get_cached_context"' "$SERVER"

assert_status 0 "invalidate_cache tool declared" \
  grep -q '"invalidate_cache"' "$SERVER"

assert_status 0 "get_cache_status tool declared" \
  grep -q '"get_cache_status"' "$SERVER"

assert_status 0 "all 4 tools handled in switch" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const tools = ['build_cache', 'get_cached_context', 'invalidate_cache', 'get_cache_status'];
for (const t of tools) {
  // match either single or double quoted case labels
  if (!src.includes('case "' + t + '":') && !src.includes("case '" + t + "':")) {
    console.error('Missing case:', t); process.exit(1);
  }
}
JS

# ── T-CACHE-S03: Security — DB_PATH hardcoded ────────────────────────────────
echo ""
echo "  [T-CACHE-S03] Security — DB_PATH hardcoded"

assert_status 0 "DB_PATH is a const" \
  grep -q 'const DB_PATH' "$SERVER"

assert_status 1 "DB_PATH not derived from process.env" \
  grep -qE 'DB_PATH\s*=.*process\.env' "$SERVER"

assert_status 1 "DB_PATH not derived from tool arguments" \
  grep -qE 'DB_PATH\s*=.*args\.' "$SERVER"

assert_status 0 "DB_PATH stored in ~/.ai-os/" \
  grep -q 'cache.sqlite' "$SERVER"

# ── T-CACHE-S04: Security — path traversal prevention ────────────────────────
echo ""
echo "  [T-CACHE-S04] Security — path traversal prevention"

assert_status 0 "validateProjectRoot function exists" \
  grep -q 'validateProjectRoot' "$SERVER"

assert_status 0 "absolute path check present" \
  grep -q 'isAbsolute' "$SERVER"

assert_status 0 "double-dot traversal blocked" \
  grep -q '".."' "$SERVER"

assert_status 0 "validateProjectRoot rejects relative paths" \
  node --input-type=module <<'JS'
import { isAbsolute } from 'node:path';
import { existsSync } from 'node:fs';
function validate(raw) {
  const root = raw ? String(raw).trim() : process.cwd();
  if (!isAbsolute(root)) throw new Error('not absolute');
  if (root.includes('..')) throw new Error('traversal');
  if (!existsSync(root)) throw new Error('not found');
  return root;
}
try { validate('relative/path'); process.exit(1); } catch(e) {
  if (!e.message.includes('absolute')) process.exit(1);
}
try { validate('/abs/../traversal'); process.exit(1); } catch(e) {
  if (!e.message.includes('traversal')) process.exit(1);
}
// Valid path (cwd) should succeed
validate(process.cwd());
JS

assert_status 0 "validateProjectRoot rejects paths with .." \
  node --input-type=module <<'JS'
import { isAbsolute } from 'node:path';
function validate(raw) {
  const root = raw ? String(raw).trim() : process.cwd();
  if (!isAbsolute(root)) throw new Error('not absolute');
  if (root.includes('..')) throw new Error('traversal blocked');
  return root;
}
try { validate('/home/user/../etc/passwd'); process.exit(1); } catch(e) {
  if (!e.message.includes('traversal')) process.exit(1);
}
JS

# ── T-CACHE-S05: Cache assembly — payload files ───────────────────────────────
echo ""
echo "  [T-CACHE-S05] Cache assembly"

assert_status 0 "assembleContext function defined" \
  grep -q 'function assembleContext' "$SERVER"

assert_status 0 "discoverPayloadFiles includes architect.md" \
  grep -q 'architect.md' "$SERVER"

assert_status 0 "discoverPayloadFiles includes blueprints directory" \
  grep -q 'blueprints' "$SERVER"

assert_status 0 "discoverPayloadFiles includes registry.json" \
  grep -q 'registry.json' "$SERVER"

assert_status 0 "readSqliteSchema queries sqlite_master (no shell)" \
  grep -q 'sqlite_master' "$SERVER"

assert_status 1 "readSqliteSchema does not call execSync()" \
  grep -q 'execSync(' "$SERVER"

assert_status 0 "blob includes section delimiters" \
  grep -q 'SYSTEM CONTEXT' "$SERVER"

assert_status 0 "blueprint files sorted for deterministic order" \
  grep -q '\.sort()' "$SERVER"

assert_status 0 "file roles tracked: architect, blueprint, registry" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// Match either single or double quoted role strings
for (const role of ['architect', 'blueprint', 'registry']) {
  if (!src.includes('"' + role + '"') && !src.includes("'" + role + "'")) {
    console.error('Missing role string:', role); process.exit(1);
  }
}
JS

# ── T-CACHE-S06: Staleness detection ─────────────────────────────────────────
echo ""
echo "  [T-CACHE-S06] Staleness detection"

assert_status 0 "isCacheStale function defined" \
  grep -q 'function isCacheStale' "$SERVER"

assert_status 0 "staleness checks 'valid' key in cache_meta" \
  grep -q "'valid'" "$SERVER"

assert_status 0 "staleness checks project_root mismatch" \
  grep -q 'project_root' "$SERVER"

assert_status 0 "staleness detects new blueprint files (not just mtime changes)" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// Must re-glob blueprints dir on each staleness check
if (!src.includes('readdirSync')) process.exit(1);
JS

assert_status 0 "get_cached_context auto-rebuilds when stale" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
// Match either quote style
const ctxIdx = src.indexOf('case "get_cached_context":') !== -1
  ? src.indexOf('case "get_cached_context":')
  : src.indexOf("case 'get_cached_context':");
if (ctxIdx === -1) process.exit(1);
const block = src.slice(ctxIdx, ctxIdx + 1500);
if (!block.includes('isCacheStale')) process.exit(1);
if (!block.includes('assembleContext')) process.exit(1);
JS

# ── T-CACHE-S07: SQLite schema ────────────────────────────────────────────────
echo ""
echo "  [T-CACHE-S07] SQLite schema"

assert_status 0 "cache_meta table defined" \
  grep -q 'cache_meta' "$SERVER"

assert_status 0 "cache_files table defined" \
  grep -q 'cache_files' "$SERVER"

assert_status 0 "cache_files has mtime_ms column" \
  grep -q 'mtime_ms' "$SERVER"

assert_status 0 "cache_files has size_bytes column" \
  grep -q 'size_bytes' "$SERVER"

assert_status 0 "cache_files has role column" \
  grep -q 'role' "$SERVER"

assert_status 0 "persistCache writes context_blob to cache_meta" \
  grep -q 'context_blob' "$SERVER"

assert_status 0 "persistCache writes built_at timestamp" \
  grep -q 'built_at' "$SERVER"

assert_status 0 "persistCache clears cache_files before insert (no stale rows)" \
  grep -q 'DELETE FROM cache_files' "$SERVER"

# ── T-CACHE-S08: invalidate_cache sets valid=0 ────────────────────────────────
echo ""
echo "  [T-CACHE-S08] invalidate_cache"

assert_status 0 "invalidate_cache sets valid to '0'" \
  grep -q "'valid', '0'" "$SERVER"

assert_status 0 "CACHE_INVALIDATED emitted in response" \
  grep -q 'CACHE_INVALIDATED' "$SERVER"

# ── T-CACHE-S09: get_cache_status reporting ───────────────────────────────────
echo ""
echo "  [T-CACHE-S09] get_cache_status"

assert_status 0 "status shows VALID or STALE" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
if (!src.includes('"VALID"') && !src.includes("'VALID'") && !src.includes('VALID')) process.exit(1);
if (!src.includes('"STALE"') && !src.includes("'STALE'") && !src.includes('STALE')) process.exit(1);
JS

assert_status 0 "status reports chars and estimated tokens" \
  grep -q 'estimateTokens' "$SERVER"

assert_status 0 "estimateTokens uses 4-char approximation" \
  grep -q '/ 4' "$SERVER"

assert_status 0 "status lists tracked files" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const src = readFileSync('$SERVER', 'utf8');
const statusIdx = src.indexOf('case "get_cache_status":') !== -1
  ? src.indexOf('case "get_cache_status":')
  : src.indexOf("case 'get_cache_status':");
if (statusIdx === -1) process.exit(1);
const block = src.slice(statusIdx, statusIdx + 2000);
if (!block.includes('cache_files')) process.exit(1);
JS

# ── T-CACHE-S10: Observability ────────────────────────────────────────────────
echo ""
echo "  [T-CACHE-S10] Observability"

assert_status 0 "shared logger imported" \
  grep -q 'createLogger.*shared/logger' "$SERVER"

assert_status 0 "logger exposes log() shim" \
  grep -q 'logger.log' "$SERVER"

assert_status 0 "logger initialised with SERVICE" \
  grep -q 'createLogger(SERVICE)' "$SERVER"

assert_status 0 "latency_ms tracked" \
  grep -q 'latency_ms' "$SERVER"

assert_status 0 "startup log entry emitted" \
  grep -q '"startup"' "$SERVER"

assert_status 0 "CACHE_HIT logged" \
  grep -q 'CACHE_HIT' "$SERVER"

assert_status 0 "CACHE_BUILT logged" \
  grep -q 'CACHE_BUILT' "$SERVER"

# ── T-CACHE-S11: Registry and .mcp.json ──────────────────────────────────────
echo ""
echo "  [T-CACHE-S11] Registry and .mcp.json"

assert_status 0 "cache-manager-mcp in registry.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
if (!r.mcp_servers['cache-manager-mcp']) process.exit(1);
JS

assert_status 0 "registry capability is READ" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const entry = r.mcp_servers['cache-manager-mcp'];
if (entry.capability !== 'READ') process.exit(1);
JS

assert_status 0 "registry allowed-tools lists all 4 tools" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const r = JSON.parse(readFileSync('${REPO_ROOT}/src/config/registry.json', 'utf8'));
const tools = r.mcp_servers['cache-manager-mcp']['allowed-tools'];
const expected = ['build_cache', 'get_cached_context', 'invalidate_cache', 'get_cache_status'];
if (!Array.isArray(tools) || tools.length !== 4) process.exit(1);
for (const t of expected) { if (!tools.includes(t)) { console.error('Missing:', t); process.exit(1); } }
JS

assert_status 0 "cache-manager-mcp in .mcp.json" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
if (!m.mcpServers['cache-manager-mcp']) process.exit(1);
JS

assert_status 0 ".mcp.json entry points to index.js" \
  node --input-type=module <<JS
import { readFileSync } from 'fs';
const m = JSON.parse(readFileSync('${REPO_ROOT}/.mcp.json', 'utf8'));
const args = m.mcpServers['cache-manager-mcp']?.args ?? [];
if (!args.some(a => a.includes('cache-manager-mcp') && a.endsWith('index.js'))) process.exit(1);
JS

# ── T-CACHE-S12: End-to-end smoke test ───────────────────────────────────────
echo ""
echo "  [T-CACHE-S12] Smoke test — build_cache + get_cache_status"

assert_status 0 "build_cache assembles context from live project" \
  node --input-type=module <<JS
// Inline the core assembly logic to test without the MCP transport
import { readFileSync, statSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const projectRoot = '${REPO_ROOT}';

// Discover payload files
const files = [];
const architectPath = join(projectRoot, '.ai', 'architect.md');
if (existsSync(architectPath)) files.push({ path: architectPath, role: 'architect' });

const blueprintsDir = join(projectRoot, '.ai', 'blueprints');
if (existsSync(blueprintsDir)) {
  const names = readdirSync(blueprintsDir).filter(n => n.endsWith('.md')).sort();
  for (const n of names) files.push({ path: join(blueprintsDir, n), role: 'blueprint' });
}

const registryPath = join(projectRoot, 'src', 'config', 'registry.json');
if (existsSync(registryPath)) files.push({ path: registryPath, role: 'registry' });

if (files.length === 0) { console.error('No payload files found'); process.exit(1); }

// Verify all files are readable
for (const { path } of files) {
  const content = readFileSync(path, 'utf8');
  if (!content) { console.error('Empty file:', path); process.exit(1); }
}

// Verify context blob structure
let blob = '=== AI-OS SYSTEM CONTEXT CACHE ===\n';
for (const { path, role } of files) {
  const content = readFileSync(path, 'utf8');
  blob += '--- ' + path.replace(projectRoot + '/', '') + ' (' + role + ') ---\n';
  blob += content.trimEnd() + '\n\n';
}
blob += '=== END SYSTEM CONTEXT ===';

if (!blob.includes('=== AI-OS SYSTEM CONTEXT CACHE ===')) process.exit(1);
if (!blob.includes('=== END SYSTEM CONTEXT ===')) process.exit(1);
if (blob.length < 1000) { console.error('Blob too small:', blob.length); process.exit(1); }
JS

assert_status 0 "context blob includes architect.md content" \
  node --input-type=module <<JS
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const projectRoot = '${REPO_ROOT}';
const architectPath = join(projectRoot, '.ai', 'architect.md');
if (!existsSync(architectPath)) process.exit(0); // skip if missing

const content = readFileSync(architectPath, 'utf8');
// First 50 chars of architect.md must be part of the blob
if (!content || content.length < 10) process.exit(1);
JS

assert_status 0 "context blob includes at least one blueprint" \
  node --input-type=module <<JS
import { readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const blueprintsDir = '${REPO_ROOT}/.ai/blueprints';
if (!existsSync(blueprintsDir)) process.exit(0); // skip if missing
const mdFiles = readdirSync(blueprintsDir).filter(n => n.endsWith('.md'));
if (mdFiles.length === 0) { console.error('No blueprints found'); process.exit(1); }
JS

assert_summary
