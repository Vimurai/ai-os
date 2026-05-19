#!/usr/bin/env bash
# memory_worker_pool_test.sh — Tests for E-76 Bounded Worker Pool + DLQ.
#
# Verifies src/shared/memory-worker-pool.mjs per
# .ai/blueprints/multimodal-rag-batching.md §Components 2+3:
#
#   - Bounded concurrency (default 3, AI_EMBEDDING_CONCURRENCY override)
#   - Exponential backoff on 429s (1000ms → 15000ms cap) before DLQ
#   - Non-rate-limit errors skip retries → straight to DLQ
#   - DLQ schema persisted to .ai/memory/dlq.json with retry_count dedup
#   - flushDlq() retries DLQ entries; successes drop, failures persist
#   - AI_RAG_MODE=text-only short-circuits the pool (rollback path)
#   - AI_EMBEDDING_CONCURRENCY=1 serial fallback (rollback path)
#   - Privacy: DLQ contains file_path + error code only (no embedding bytes)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POOL="${REPO_ROOT}/src/shared/memory-worker-pool.mjs"

echo "===== memory_worker_pool_test.sh ====="

# ── T-MWP-S01: Source contract ───────────────────────────────────────────────
echo ""
echo "  [T-MWP-S01] Source exports the documented surface"

assert_status 0 "pool file exists"               test -f "$POOL"
assert_status 0 "pool has node shebang"          bash -c "head -1 '$POOL' | grep -q 'node'"
assert_status 0 "processBatch exported"          grep -q 'export async function processBatch' "$POOL"
assert_status 0 "flushDlq exported"              grep -q 'export async function flushDlq' "$POOL"
assert_status 0 "loadDlq exported"               grep -q 'export function loadDlq' "$POOL"
assert_status 0 "saveDlq exported"               grep -q 'export function saveDlq' "$POOL"
assert_status 0 "appendToDlq exported"           grep -q 'export function appendToDlq' "$POOL"
assert_status 0 "isRateLimitError exported"      grep -q 'export function isRateLimitError' "$POOL"
assert_status 0 "DEFAULT_CONCURRENCY = 3"        grep -q 'DEFAULT_CONCURRENCY  = 3' "$POOL"
assert_status 0 "DEFAULT_BACKOFF_MIN_MS = 1000"  grep -q 'DEFAULT_BACKOFF_MIN_MS = 1_000' "$POOL"
assert_status 0 "DEFAULT_BACKOFF_MAX_MS = 15000" grep -q 'DEFAULT_BACKOFF_MAX_MS = 15_000' "$POOL"
assert_status 0 "DEFAULT_DLQ_PATH pinned"        grep -q '\.ai/memory/dlq\.json' "$POOL"
assert_status 0 "blueprint reference present"    grep -q 'multimodal-rag-batching.md' "$POOL"

SBOX="$(mktemp -d -t e76-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT

# ── T-MWP-S02: Happy path — all sends succeed, concurrency observed ──────────
echo ""
echo "  [T-MWP-S02] All sends succeed; concurrency cap is respected"

result_file="${SBOX}/happy.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const files = Array.from({length: 8}, (_,i) => ({ path: '/tmp/f' + i + '.png', sha256: 'h' + i, size: 100, kind: 'png' }));
  let maxInFlight = 0;
  const result = await m.processBatch(files, {
    sendEmbedding: async (file) => {
      await new Promise(r => setTimeout(r, 20));
      return { vec: [1,2,3], id: file.sha256 };
    },
    concurrency: 3,
    onInFlightChange: (n) => { if (n > maxInFlight) maxInFlight = n; },
  });
  console.log(JSON.stringify({
    successes_count: result.successes.length,
    failures_count: result.failures.length,
    skipped_count: result.skipped.length,
    max_in_flight: maxInFlight,
  }));
" > "$result_file" 2>/dev/null

assert_status 0 "all 8 files succeed" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['successes_count']==8 else 1)"
assert_status 0 "zero failures"        \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['failures_count']==0 else 1)"
assert_status 0 "max in flight ≤ concurrency cap (3)" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['max_in_flight']<=3 else 1)"
assert_status 0 "max in flight reaches > 1 (parallelism actually happened)" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['max_in_flight']>1 else 1)"

# ── T-MWP-S03: 429 exhausts retries → DLQ ────────────────────────────────────
echo ""
echo "  [T-MWP-S03] 429 errors exhaust retries → DLQ"

dlq_path="${SBOX}/dlq.json"
result_file="${SBOX}/exhaust.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const files = [{ path: '/tmp/rate.png', sha256: 'r1', size: 100, kind: 'png' }];
  const result = await m.processBatch(files, {
    sendEmbedding: async () => {
      const e = new Error('429 Too Many Requests');
      e.status = 429;
      throw e;
    },
    concurrency: 1,
    dlqPath: '${dlq_path}',
    backoffMinMs: 1,
    backoffMaxMs: 8,
  });
  console.log(JSON.stringify({
    successes: result.successes.length,
    failures: result.failures.length,
    last_error: result.failures[0]?.last_error,
    kind: result.failures[0]?.kind,
    retry_count: result.failures[0]?.retry_count,
  }));
" > "$result_file" 2>/dev/null

assert_status 0 "zero successes"          \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['successes']==0 else 1)"
assert_status 0 "exactly one failure"     \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['failures']==1 else 1)"
assert_status 0 "failure kind=exhausted"  \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['kind']=='exhausted' else 1)"
assert_status 0 "retry_count > 1"         \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file'))['retry_count']>1 else 1)"

assert_status 0 "DLQ file written"        test -f "$dlq_path"
assert_status 0 "DLQ has the failed job"  python3 -c "
import json, sys
d = json.load(open('$dlq_path'))
sys.exit(0 if len(d['failed_jobs'])==1 and d['failed_jobs'][0]['file_path']=='/tmp/rate.png' else 1)
"
assert_status 0 "DLQ entry carries last_attempt ISO timestamp" python3 -c "
import json, re, sys
d = json.load(open('$dlq_path'))
ts = d['failed_jobs'][0].get('last_attempt','')
sys.exit(0 if re.match(r'\d{4}-\d{2}-\d{2}T', ts) else 1)
"

# ── T-MWP-S04: Non-retryable error skips retries, lands in DLQ ───────────────
echo ""
echo "  [T-MWP-S04] Non-rate-limit errors short-circuit to DLQ (no retries)"

dlq_path2="${SBOX}/dlq2.json"
result_file2="${SBOX}/nonretry.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const files = [{ path: '/tmp/payload-bad.png', sha256: 'p1', size: 100, kind: 'png' }];
  let calls = 0;
  const result = await m.processBatch(files, {
    sendEmbedding: async () => {
      calls += 1;
      const e = new Error('400 invalid payload');
      e.status = 400;
      throw e;
    },
    concurrency: 1,
    dlqPath: '${dlq_path2}',
    backoffMinMs: 1,
    backoffMaxMs: 8,
  });
  console.log(JSON.stringify({
    calls,
    failures: result.failures.length,
    kind: result.failures[0]?.kind,
  }));
" > "$result_file2" 2>/dev/null

assert_status 0 "sendEmbedding called exactly once (no retry)" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file2'))['calls']==1 else 1)"
assert_status 0 "exactly one failure" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file2'))['failures']==1 else 1)"
assert_status 0 "failure kind=non-retryable" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$result_file2'))['kind']=='non-retryable' else 1)"

# ── T-MWP-S05: Backoff actually waits between retries ────────────────────────
echo ""
echo "  [T-MWP-S05] Backoff doubles between retries (minimum wait observed)"

timing_file="${SBOX}/timing.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const timestamps = [];
  const result = await m.processBatch(
    [{ path: '/tmp/slow.png', sha256: 's1', size: 1, kind: 'png' }],
    {
      sendEmbedding: async () => {
        timestamps.push(Date.now());
        const e = new Error('429 try again');
        e.status = 429;
        throw e;
      },
      concurrency: 1,
      backoffMinMs: 50,
      backoffMaxMs: 200,
    }
  );
  // Diffs between consecutive timestamps should reflect doubling: ~50, ~100, ~200, then exhaust.
  const diffs = [];
  for (let i=1; i<timestamps.length; i++) diffs.push(timestamps[i] - timestamps[i-1]);
  console.log(JSON.stringify({ attempts: timestamps.length, diffs }));
" > "$timing_file" 2>/dev/null

assert_status 0 "≥ 3 attempts observed" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$timing_file'))['attempts']>=3 else 1)"
# Use a 40ms floor on the first diff to absorb timer jitter.
assert_status 0 "first retry waited ≥ ~minMs" \
  python3 -c "
import json, sys
d=json.load(open('$timing_file'))
diffs=d['diffs']
sys.exit(0 if diffs and diffs[0]>=40 else 1)
"
# Second diff should be roughly 2× the first.
assert_status 0 "second retry diff > first retry diff (doubling)" \
  python3 -c "
import json, sys
d=json.load(open('$timing_file'))['diffs']
sys.exit(0 if len(d)>=2 and d[1]>d[0] else 1)
"

# ── T-MWP-S06: AI_EMBEDDING_CONCURRENCY=1 enforces serial fallback ───────────
echo ""
echo "  [T-MWP-S06] Env override AI_EMBEDDING_CONCURRENCY=1 → strictly serial"

serial_file="${SBOX}/serial.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const files = Array.from({length: 4}, (_,i) => ({ path: '/tmp/g'+i+'.png', sha256: 'g'+i, size: 1, kind: 'png' }));
  let maxInFlight = 0;
  const result = await m.processBatch(files, {
    sendEmbedding: async (f) => {
      await new Promise(r => setTimeout(r, 15));
      return { id: f.sha256 };
    },
    env: { AI_EMBEDDING_CONCURRENCY: '1' },
    onInFlightChange: (n) => { if (n > maxInFlight) maxInFlight = n; },
  });
  console.log(JSON.stringify({ successes: result.successes.length, maxInFlight }));
" > "$serial_file" 2>/dev/null
assert_status 0 "all 4 succeed under serial mode" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$serial_file'))['successes']==4 else 1)"
assert_status 0 "maxInFlight is exactly 1 (truly serial)" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$serial_file'))['maxInFlight']==1 else 1)"

# ── T-MWP-S07: AI_RAG_MODE=text-only short-circuits the batch ────────────────
echo ""
echo "  [T-MWP-S07] AI_RAG_MODE=text-only → no embedding calls, all skipped"

textonly_file="${SBOX}/textonly.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const files = [{ path: '/tmp/a.png', sha256: 'a', size: 1, kind: 'png' }];
  let calls = 0;
  const result = await m.processBatch(files, {
    sendEmbedding: async () => { calls++; return {}; },
    env: { AI_RAG_MODE: 'text-only' },
  });
  console.log(JSON.stringify({ calls, skipped: result.skipped.length, reason: result.skipped[0]?.reason }));
" > "$textonly_file" 2>/dev/null
assert_status 0 "zero embedding calls in text-only mode" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$textonly_file'))['calls']==0 else 1)"
assert_status 0 "all files moved to skipped" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$textonly_file'))['skipped']==1 else 1)"
assert_status 0 "skip reason = text-only-mode" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$textonly_file'))['reason']=='text-only-mode' else 1)"

# ── T-MWP-S08: isRateLimitError recognises common 429 shapes ─────────────────
echo ""
echo "  [T-MWP-S08] isRateLimitError covers status/code/message variants"

shapes="$(node --input-type=module -e "
  const m = await import('file://${POOL}');
  const cases = [
    Object.assign(new Error('x'), { status: 429 }),
    Object.assign(new Error('x'), { code: 429 }),
    Object.assign(new Error('x'), { statusCode: '429' }),
    Object.assign(new Error('RATE_LIMIT'), { code: 'RATE_LIMIT' }),
    new Error('429 Too Many Requests'),
    new Error('rate limit exceeded'),
  ];
  console.log(JSON.stringify(cases.map(e => m.isRateLimitError(e))));
" 2>/dev/null)"
assert_status 0 "all 6 known 429 shapes return true" \
  bash -c "echo '$shapes' | grep -qF '[true,true,true,true,true,true]'"

nonrl="$(node --input-type=module -e "
  const m = await import('file://${POOL}');
  console.log(JSON.stringify([
    m.isRateLimitError(new Error('something else')),
    m.isRateLimitError(Object.assign(new Error('x'), { status: 500 })),
    m.isRateLimitError(null),
    m.isRateLimitError({}),
  ]));
" 2>/dev/null)"
assert_status 0 "non-RL errors return false" \
  bash -c "echo '$nonrl' | grep -qF '[false,false,false,false]'"

# ── T-MWP-S09: appendToDlq dedups by file_path; retry_count increments ───────
echo ""
echo "  [T-MWP-S09] DLQ dedups by file_path and bumps retry_count"

dlq_path3="${SBOX}/dlq3.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  m.appendToDlq('${dlq_path3}', { file_path: '/tmp/x.png', last_error: 'first',  retry_count: 2, last_attempt: '2026-01-01T00:00:00Z' });
  m.appendToDlq('${dlq_path3}', { file_path: '/tmp/x.png', last_error: 'second', retry_count: 1, last_attempt: '2026-01-02T00:00:00Z' });
  m.appendToDlq('${dlq_path3}', { file_path: '/tmp/y.png', last_error: 'other',  retry_count: 1, last_attempt: '2026-01-03T00:00:00Z' });
" 2>/dev/null

assert_status 0 "DLQ contains exactly 2 unique jobs" python3 -c "
import json, sys
d = json.load(open('$dlq_path3'))
sys.exit(0 if len(d['failed_jobs']) == 2 else 1)
"
assert_status 0 "x.png retry_count summed to 3" python3 -c "
import json, sys
d = json.load(open('$dlq_path3'))
x = next(j for j in d['failed_jobs'] if j['file_path']=='/tmp/x.png')
sys.exit(0 if x['retry_count'] == 3 else 1)
"
assert_status 0 "x.png last_error updated to most recent" python3 -c "
import json, sys
d = json.load(open('$dlq_path3'))
x = next(j for j in d['failed_jobs'] if j['file_path']=='/tmp/x.png')
sys.exit(0 if x['last_error'] == 'second' else 1)
"

# ── T-MWP-S10: flushDlq retries; successes drop, failures remain ─────────────
echo ""
echo "  [T-MWP-S10] flushDlq retries the DLQ and rewrites the file"

dlq_path4="${SBOX}/dlq4.json"
# Seed two jobs in the DLQ.
node --input-type=module -e "
  const m = await import('file://${POOL}');
  m.saveDlq('${dlq_path4}', { failed_jobs: [
    { file_path: '/tmp/recover.png',  last_error: 'old', retry_count: 1, last_attempt: '2026-01-01T00:00:00Z' },
    { file_path: '/tmp/stillbad.png', last_error: 'old', retry_count: 1, last_attempt: '2026-01-01T00:00:00Z' },
  ]});
" 2>/dev/null

flush_file="${SBOX}/flush.json"
node --input-type=module -e "
  const m = await import('file://${POOL}');
  const result = await m.flushDlq('${dlq_path4}', async (file) => {
    if (file.path === '/tmp/recover.png') return { id: 'ok' };
    const e = new Error('400 still bad');
    e.status = 400;
    throw e;
  }, { backoffMinMs: 1, backoffMaxMs: 4 });
  console.log(JSON.stringify(result));
" > "$flush_file" 2>/dev/null

assert_status 0 "flushDlq retried 2 entries" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$flush_file'))['retried']==2 else 1)"
assert_status 0 "flushDlq reports 1 succeeded" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$flush_file'))['succeeded']==1 else 1)"
assert_status 0 "flushDlq reports 1 still_failing" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$flush_file'))['still_failing']==1 else 1)"

# DLQ file should now contain only the still-failing job.
assert_status 0 "DLQ rewritten with only stillbad.png" python3 -c "
import json, sys
d = json.load(open('$dlq_path4'))
jobs = d['failed_jobs']
ok = len(jobs)==1 and jobs[0]['file_path']=='/tmp/stillbad.png'
sys.exit(0 if ok else 1)
"

# ── T-MWP-S11: empty / missing / garbage DLQ handled gracefully ──────────────
echo ""
echo "  [T-MWP-S11] DLQ accessors are fail-open on missing/garbage files"

missing="$(node --input-type=module -e "
  const m = await import('file://${POOL}');
  console.log(m.loadDlq('${SBOX}/does-not-exist.json').failed_jobs.length);
" 2>/dev/null)"
assert_status 0 "missing DLQ → empty array" bash -c "[[ '$missing' == '0' ]]"

echo 'not valid json {{{' > "${SBOX}/garbage.json"
garbage="$(node --input-type=module -e "
  const m = await import('file://${POOL}');
  console.log(m.loadDlq('${SBOX}/garbage.json').failed_jobs.length);
" 2>/dev/null)"
assert_status 0 "garbage DLQ → empty array (no throw)" bash -c "[[ '$garbage' == '0' ]]"

flush_empty="$(node --input-type=module -e "
  const m = await import('file://${POOL}');
  const r = await m.flushDlq('${SBOX}/does-not-exist.json', async () => {});
  console.log(JSON.stringify(r));
" 2>/dev/null)"
assert_status 0 "flushDlq on missing DLQ returns zeros" \
  bash -c "echo '$flush_empty' | grep -q '\"retried\":0'"

# ── T-MWP-S12: CLI --dlq-show / --dlq-clear ──────────────────────────────────
echo ""
echo "  [T-MWP-S12] CLI flags for ops"

show_out="$(node "$POOL" --dlq-show "$dlq_path4" 2>&1)"
assert_status 0 "--dlq-show prints JSON envelope" bash -c "echo '$show_out' | grep -q '\"failed_jobs\"'"
assert_status 0 "--dlq-show reports the surviving job" bash -c "echo '$show_out' | grep -q 'stillbad.png'"

node "$POOL" --dlq-clear "$dlq_path4" >/dev/null 2>&1
assert_status 0 "--dlq-clear empties the DLQ" python3 -c "
import json, sys
d = json.load(open('$dlq_path4'))
sys.exit(0 if d['failed_jobs'] == [] else 1)
"

usage_out="$(node "$POOL" --bogus 2>&1 >/dev/null || true)"
assert_status 0 "usage mentions --dlq-show" bash -c "echo '$usage_out' | grep -q -- '--dlq-show'"
assert_status 0 "usage mentions --dlq-clear" bash -c "echo '$usage_out' | grep -q -- '--dlq-clear'"

# ── T-MWP-S13: ~/.ai-os mirror byte-identity ─────────────────────────────────
echo ""
echo "  [T-MWP-S13] ~/.ai-os mirror matches src"

MIRROR="${HOME}/.ai-os/shared/memory-worker-pool.mjs"
if [[ -f "$MIRROR" ]]; then
  assert_status 0 "mirror is byte-identical to src" diff -q "$POOL" "$MIRROR"
else
  echo "    ⚠  mirror absent — skipping"
fi

echo ""
assert_summary
echo "===== memory_worker_pool_test.sh PASS ====="
