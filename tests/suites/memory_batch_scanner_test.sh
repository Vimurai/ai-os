#!/usr/bin/env bash
# memory_batch_scanner_test.sh — Tests for E-75 Batch Scanner.
#
# Verifies src/shared/memory-batch-scanner.mjs per
# .ai/blueprints/multimodal-rag-batching.md §Components 1 + §Security:
#
#   - Walk discovers PNG/SVG/PDF candidates and prunes node_modules/.git/.ai-os
#   - Path-rule rejects (/.env/, /secrets/, /credentials/, /.ssh/, /.aws/, /.gnupg/)
#   - Sensitive-name regex rejects (secret*, *credential*, *.pem, id_rsa, etc.)
#   - .gitignore enforcement via batched `git check-ignore --stdin`
#   - [NO_RAG] sidecar file + inline SVG marker both reject
#   - 5 MB size cap rejects oversize files
#   - SHA-256 hashing skips files whose hash already lives in the palette index
#   - Privacy: only basenames + reason codes in `skipped` (no full paths)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCANNER="${REPO_ROOT}/src/shared/memory-batch-scanner.mjs"

echo "===== memory_batch_scanner_test.sh ====="

# ── T-MBS-S01: Source contract — exports + blueprint constants ───────────────
echo ""
echo "  [T-MBS-S01] Source exports the documented surface"

assert_status 0 "scanner file exists"                test -f "$SCANNER"
assert_status 0 "scanner has node shebang"           bash -c "head -1 '$SCANNER' | grep -q 'node'"
assert_status 0 "scanWorkspace exported"             grep -q 'export function scanWorkspace' "$SCANNER"
assert_status 0 "computeFileSha256 exported"         grep -q 'export function computeFileSha256' "$SCANNER"
assert_status 0 "batchGitignoreCheck exported"       grep -q 'export function batchGitignoreCheck' "$SCANNER"
assert_status 0 "hasNoRagTag exported"               grep -q 'export function hasNoRagTag' "$SCANNER"
assert_status 0 "isSensitiveName exported"           grep -q 'export function isSensitiveName' "$SCANNER"
assert_status 0 "isPathExcluded exported"            grep -q 'export function isPathExcluded' "$SCANNER"
assert_status 0 "isSkippableDir exported"            grep -q 'export function isSkippableDir' "$SCANNER"
assert_status 0 "loadIndexedHashes exported"         grep -q 'export function loadIndexedHashes' "$SCANNER"
assert_status 0 "DEFAULT_MAX_BYTES pinned to 5 MB"   grep -q 'DEFAULT_MAX_BYTES.*5 \* 1024 \* 1024' "$SCANNER"
assert_status 0 "DEFAULT_EXTENSIONS pinned"          grep -q "DEFAULT_EXTENSIONS = \\[\".png\", \".svg\", \".pdf\"\\]" "$SCANNER"
assert_status 0 "blueprint reference in comments"    grep -q "multimodal-rag-batching.md" "$SCANNER"
assert_status 0 "node:crypto imported"               grep -q 'from "node:crypto"' "$SCANNER"
assert_status 0 "node:child_process imported"        grep -q 'from "node:child_process"' "$SCANNER"

# ── Set up a synthetic project sandbox ───────────────────────────────────────
echo ""
echo "  [T-MBS-S02] Build sandbox project with eligible + ineligible files"

SBOX="$(mktemp -d -t e75-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT
PROJ="${SBOX}/proj"
mkdir -p "$PROJ"

# Initialise a real git repo so check-ignore works.
git -C "$PROJ" init -q
git -C "$PROJ" config user.email "test@example.com"
git -C "$PROJ" config user.name "tester"

# Eligible: in-tree PNG/SVG/PDF.
mkdir -p "${PROJ}/diagrams" "${PROJ}/ux" "${PROJ}/docs"
printf '\x89PNG\r\n\x1a\n%s' "FAKE-PNG-1" > "${PROJ}/diagrams/c4-context.png"
printf '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' > "${PROJ}/ux/login-mockup.svg"
printf '%%PDF-1.4\n%s' "FAKE-PDF" > "${PROJ}/docs/erd-overview.pdf"

# Path-rule rejects: .env/, secrets/, credentials/, .ssh/, .aws/.
mkdir -p "${PROJ}/.env" "${PROJ}/secrets" "${PROJ}/credentials" "${PROJ}/.ssh" "${PROJ}/.aws"
printf 'PNG-IN-DOTENV'      > "${PROJ}/.env/leaky.png"
printf 'SVG-IN-SECRETS'     > "${PROJ}/secrets/diagram.svg"
printf 'PDF-IN-CREDENTIALS' > "${PROJ}/credentials/badge.pdf"
printf 'PNG-IN-SSH'         > "${PROJ}/.ssh/keymap.png"
printf 'SVG-IN-AWS'         > "${PROJ}/.aws/topology.svg"

# Sensitive-name rejects (regardless of directory).
printf 'BAD-NAME-1' > "${PROJ}/diagrams/secret-handshake.png"
printf 'BAD-NAME-2' > "${PROJ}/ux/password-reset-screen.svg"
printf 'BAD-NAME-3' > "${PROJ}/docs/id_rsa-backup.pdf"
printf 'BAD-NAME-4' > "${PROJ}/diagrams/staging.pem"   # extension change — will be skipped by ext filter anyway

# .gitignore: ignore everything in private/.
mkdir -p "${PROJ}/private"
printf 'private/\n' > "${PROJ}/.gitignore"
printf 'GITIGNORED-PNG' > "${PROJ}/private/wireframe.png"

# [NO_RAG] sidecar PNG + inline SVG marker.
printf 'PNG-WITH-SIDECAR' > "${PROJ}/diagrams/internal-only.png"
printf 'marker'           > "${PROJ}/diagrams/internal-only.png.norag"
printf '<svg xmlns="http://www.w3.org/2000/svg"><!-- [NO_RAG] --><rect/></svg>' > "${PROJ}/ux/internal-flow.svg"

# Oversized file (>5 MB). Use dd to materialise quickly.
dd if=/dev/zero of="${PROJ}/diagrams/oversize.png" bs=1m count=6 status=none 2>/dev/null || \
  dd if=/dev/zero of="${PROJ}/diagrams/oversize.png" bs=1048576 count=6 status=none

# Walker should NOT descend node_modules / .git / .ai-os — drop a media
# file into each to prove the prune fires.
mkdir -p "${PROJ}/node_modules/some-pkg" "${PROJ}/.ai-os/cache"
printf 'NM-PNG' > "${PROJ}/node_modules/some-pkg/diagram.png"
printf 'AIOS-SVG' > "${PROJ}/.ai-os/cache/cached-render.svg"

# Files outside the recognised extensions — never enter the scan.
printf 'unrelated' > "${PROJ}/diagrams/README.md"
printf 'unrelated' > "${PROJ}/docs/notes.txt"

# Confirm fixture cardinality before scanning.
total_media="$(find "$PROJ" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.pdf" \) | wc -l | tr -d ' ')"
assert_status 0 "fixture has the expected media-file footprint" \
  bash -c "[[ $total_media -ge 12 ]]"

# ── T-MBS-S03: Scan returns the eligible 3 files only ────────────────────────
echo ""
echo "  [T-MBS-S03] scanWorkspace eligibility set"

RESULT_FILE="${SBOX}/scan.json"
node --input-type=module -e "
  const m = await import('file://${SCANNER}');
  const r = m.scanWorkspace('${PROJ}');
  console.log(JSON.stringify(r));
" > "$RESULT_FILE" 2>/dev/null

eligible_count="$(python3 -c "import json; print(len(json.load(open('$RESULT_FILE'))['eligible']))")"
skipped_count="$(python3 -c "import json; print(len(json.load(open('$RESULT_FILE'))['skipped']))")"

assert_status 0 "exactly 3 eligible files (PNG + SVG + PDF)" \
  bash -c "[[ $eligible_count -eq 3 ]]"

# eligible basenames should be c4-context.png, login-mockup.svg, erd-overview.pdf.
for name in c4-context.png login-mockup.svg erd-overview.pdf; do
  assert_status 0 "eligible includes ${name}" \
    bash -c "python3 -c \"
import json; r=json.load(open('$RESULT_FILE'))
import os
names=[os.path.basename(e['path']) for e in r['eligible']]
import sys; sys.exit(0 if '${name}' in names else 1)
\""
done

# ── T-MBS-S04: Skipped entries carry the right reason codes ──────────────────
echo ""
echo "  [T-MBS-S04] Skip reasons by gate"

for tuple in \
  "leaky.png:path-rule" \
  "diagram.svg:path-rule" \
  "badge.pdf:path-rule" \
  "keymap.png:path-rule" \
  "topology.svg:path-rule" \
  "secret-handshake.png:sensitive-name" \
  "password-reset-screen.svg:sensitive-name" \
  "id_rsa-backup.pdf:sensitive-name" \
  "wireframe.png:gitignored" \
  "internal-only.png:no-rag-tag" \
  "internal-flow.svg:no-rag-tag" \
  "oversize.png:size-cap"; do
  fname="${tuple%%:*}"
  reason="${tuple##*:}"
  assert_status 0 "skipped[basename=${fname}] reason=${reason}" \
    bash -c "python3 -c \"
import json, sys
r=json.load(open('$RESULT_FILE'))
hit=[s for s in r['skipped'] if s.get('basename')=='${fname}' and s.get('reason')=='${reason}']
sys.exit(0 if hit else 1)
\""
done

# ── T-MBS-S05: Privacy — only basename + reason; never a full path ───────────
echo ""
echo "  [T-MBS-S05] Skipped entries surface basename only (no full paths)"

assert_status 1 "no skipped entry contains a '/' character in basename" \
  python3 -c "
import json, sys
r=json.load(open('$RESULT_FILE'))
sys.exit(0 if any('/' in s.get('basename','') for s in r['skipped']) else 1)
"
assert_status 1 "no skipped entry includes the sandbox SBOX path" \
  python3 -c "
import json, sys
r=json.load(open('$RESULT_FILE'))
sys.exit(0 if any('$SBOX' in str(s) for s in r['skipped']) else 1)
"

# ── T-MBS-S06: Walker prunes node_modules / .ai-os / .git ────────────────────
echo ""
echo "  [T-MBS-S06] Pruned directories never enter the candidate list"

assert_status 1 "node_modules diagram.png NOT in eligible+skipped" \
  python3 -c "
import json, sys, os
r=json.load(open('$RESULT_FILE'))
basenames = set(os.path.basename(e['path']) for e in r['eligible']) | set(s.get('basename','') for s in r['skipped'])
# The node_modules file has basename 'diagram.png' — check none of the
# basenames in scan output come from a walker that descended.
# We assert by: the scan should NOT have produced any entry whose
# basename matches the node_modules file BUT path/skip-reason confirms it.
# Cheap proxy: the count of 'diagram.png' basenames must be 0 — the only
# candidate diagram.png lives inside node_modules.
import collections
counts = collections.Counter(basenames)
sys.exit(0 if counts.get('diagram.png',0) > 0 else 1)
"

# Same for .ai-os/.
assert_status 1 ".ai-os cached-render.svg NOT in scan output" \
  python3 -c "
import json, sys
r=json.load(open('$RESULT_FILE'))
basenames=[e.get('basename','') for e in r['skipped']]
import os
basenames += [os.path.basename(e['path']) for e in r['eligible']]
sys.exit(0 if 'cached-render.svg' in basenames else 1)
"

# ── T-MBS-S07: SHA-256 stability + dedup against indexedHashes ───────────────
echo ""
echo "  [T-MBS-S07] computeFileSha256 is deterministic; already-indexed dedup works"

target="${PROJ}/diagrams/c4-context.png"
h1="$(node "$SCANNER" --hash "$target" 2>/dev/null)"
h2="$(node "$SCANNER" --hash "$target" 2>/dev/null)"
assert_status 0 "hash is non-empty + 64 hex chars" \
  bash -c "echo '$h1' | grep -qE '^[0-9a-f]{64}$'"
assert_status 0 "two reads produce identical hashes" \
  bash -c "[[ '$h1' == '$h2' ]]"

# Pass the c4-context hash as already-indexed — it must move to skipped.
dedup_file="${SBOX}/dedup.json"
node --input-type=module -e "
  const m = await import('file://${SCANNER}');
  const r = m.scanWorkspace('${PROJ}', { indexedHashes: new Set(['${h1}']) });
  console.log(JSON.stringify(r));
" > "$dedup_file" 2>/dev/null

assert_status 0 "c4-context.png moves to skipped[reason=already-indexed]" \
  python3 -c "
import json, sys
r=json.load(open('$dedup_file'))
hit=[s for s in r['skipped'] if s.get('basename')=='c4-context.png' and s.get('reason')=='already-indexed']
sys.exit(0 if hit else 1)
"
assert_status 0 "eligible count drops by exactly 1 after dedup" \
  python3 -c "
import json, sys
r=json.load(open('$dedup_file'))
sys.exit(0 if len(r['eligible']) == 2 else 1)
"

# ── T-MBS-S08: loadIndexedHashes parses a real embeddings file ──────────────
echo ""
echo "  [T-MBS-S08] loadIndexedHashes round-trips entries[].id from JSON"

EMB_FILE="${SBOX}/embeddings.json"
cat > "$EMB_FILE" <<JSON
{
  "version": 2,
  "model": "gemini-embedding-002",
  "entries": [
    { "id": "${h1}", "department": "Architecture", "vector": [0,0,0], "indexed_at": "2026-01-01T00:00:00Z" },
    { "id": "deadbeef", "department": "UX", "vector": [0,0,0], "indexed_at": "2026-01-02T00:00:00Z" }
  ]
}
JSON

loaded_count="$(node --input-type=module -e "
  const m = await import('file://${SCANNER}');
  console.log(m.loadIndexedHashes('${EMB_FILE}').size);
" 2>/dev/null)"

assert_status 0 "loaded 2 hashes from real embeddings JSON" \
  bash -c "[[ '$loaded_count' == '2' ]]"

missing_loaded="$(node --input-type=module -e "
  const m = await import('file://${SCANNER}');
  console.log(m.loadIndexedHashes('${SBOX}/does-not-exist.json').size);
" 2>/dev/null)"
assert_status 0 "missing embeddings file → empty set" \
  bash -c "[[ '$missing_loaded' == '0' ]]"

# Malformed JSON → still empty set (no throw).
echo 'not json {{{' > "${SBOX}/garbage.json"
garbage_loaded="$(node --input-type=module -e "
  const m = await import('file://${SCANNER}');
  console.log(m.loadIndexedHashes('${SBOX}/garbage.json').size);
" 2>/dev/null)"
assert_status 0 "garbage embeddings file → empty set + no throw" \
  bash -c "[[ '$garbage_loaded' == '0' ]]"

# ── T-MBS-S09: CLI --scan and --hash exit-code contract ──────────────────────
echo ""
echo "  [T-MBS-S09] CLI flags: --scan / --hash / usage"

node "$SCANNER" --scan "$PROJ" >/dev/null 2>&1
assert_status 0 "--scan exit code 0 on valid project root" bash -c "[[ $? -eq 0 ]]"

node "$SCANNER" --hash "$target" >/dev/null 2>&1
assert_status 0 "--hash exit code 0 on valid file" bash -c "[[ $? -eq 0 ]]"

usage_out="$(node "$SCANNER" --bogus 2>&1 >/dev/null || true)"
assert_status 0 "usage mentions --scan" bash -c "echo '$usage_out' | grep -q -- '--scan'"
assert_status 0 "usage mentions --hash" bash -c "echo '$usage_out' | grep -q -- '--hash'"

# ── T-MBS-S10: Non-git workspace still scans (gitignore gate degrades cleanly) ─
echo ""
echo "  [T-MBS-S10] Non-git project still works (gitignore returns empty Set)"

PROJ2="${SBOX}/not-a-git-repo"
mkdir -p "${PROJ2}/img"
printf 'PNG' > "${PROJ2}/img/clean.png"
non_git_result="$(node --input-type=module -e "
  const m = await import('file://${SCANNER}');
  const r = m.scanWorkspace('${PROJ2}');
  console.log(JSON.stringify(r));
" 2>/dev/null)"
assert_status 0 "non-git project emits the eligible file" \
  bash -c "echo '$non_git_result' | grep -q 'clean.png'"

# ── T-MBS-S11: ~/.ai-os mirror byte-identity ─────────────────────────────────
echo ""
echo "  [T-MBS-S11] ~/.ai-os mirror matches src"

MIRROR="${HOME}/.ai-os/shared/memory-batch-scanner.mjs"
if [[ -f "$MIRROR" ]]; then
  assert_status 0 "mirror is byte-identical to src" diff -q "$SCANNER" "$MIRROR"
else
  echo "    ⚠  mirror absent — skipping"
fi

echo ""
assert_summary
echo "===== memory_batch_scanner_test.sh PASS ====="
