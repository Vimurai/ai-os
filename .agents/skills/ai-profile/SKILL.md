---
name: ai-profile
description: In-context profiling workflow for Node.js performance measurement. Initiates CPU/memory analysis inside code-execution-mcp sandbox and returns structured profiling data to the performance_engineer agent. [DEFERRED: performance-mcp not built — using code-execution-mcp process.cpuUsage/heapUsed proxy; NO true flamegraph]
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash, Glob, mcp__code-execution-mcp__execute_code
context: default
agent: default
---

# AI-Profile — Node.js Performance Profiling Workflow

## Dynamic Context Injection
Target module/command: !echo "${TARGET:-(not set)}"
Profiling metric: !echo "${METRIC:-cpu}"
Baseline SHA (optional): !echo "${BASELINE_SHA:-(none)}"
Sandbox status: !grep -i "code-execution-mcp" .mcp.json 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/' || echo "(checking...)"

## Role

You are the **Profiling Workflow Engine**. Your job is to safely measure CPU, memory, and bundle-size performance of a target module or command. For CPU and memory, run measurements inside the `code-execution-mcp` Docker sandbox. For bundle size and Web Vitals, use the Bash tool (which has network access and can invoke build tools). Parse the results and hand structured data back to the `performance_engineer` agent.

You do **NOT** write OPTIMIZATION_REPORT.md or make code changes. You **ONLY** profile and return data.

## When to Invoke

- When `performance_engineer` agent calls `activate_skill("ai-profile", {target, metric, baseline_sha})`
- From user CLI: `skill: ai-profile --target src/index.js --metric cpu`
- As part of a pre-deployment gate (Tier 3 tasks)

## Input Arguments

- **target** (required): A file path (`src/core/scheduler.js`), or command (`npm run build`)
- **metric** (required): One of `cpu`, `memory`, `bundle`, `vitals`
- **baseline_sha** (optional): A prior git commit hash to fetch baseline for delta calculation

## Step 1 — Preflight Validation

1. Verify `code-execution-mcp` is available in `.mcp.json`:
   ```bash
   grep -q "code-execution-mcp" .mcp.json || exit 1 "[SANDBOX_UNAVAILABLE]"
   ```
2. If target is a file, verify it exists:
   ```bash
   [ -f "<target>" ] || [ -f "src/<target>" ] || exit 1 "[TARGET_NOT_FOUND]"
   ```
3. If metric is `vitals` or `bundle`, prepare to invoke via Bash tool (external tools like Lighthouse and npm require network access)

## Step 2 — Prepare Test Fixture

### For **cpu** metric (Node.js `process.cpuUsage()`):
Generate a minimal test harness inside the sandbox:

```typescript
// Paste the target module and exercise the hot path
const target = require('./src/core/scheduler.js');

// Measure 10k iterations
const start = process.cpuUsage();
for (let i = 0; i < 10000; i++) {
  target.schedule({ id: `task-${i}`, delay: i % 1000 });
}
const delta = process.cpuUsage(start);
console.log(JSON.stringify({
  metric: 'cpu_micros',
  user: delta.user,
  system: delta.system
}));
```

### For **memory** metric (heap measurement with settling loop):
Use `process.memoryUsage().heapUsed` deltas with minimal forced collection:

```typescript
const target = require('./src/db/connection.js');
let allocations = [];

// Small settling loop (no forced gc() call)
let before = 0;
for (let settle = 0; settle < 3; settle++) {
  before = process.memoryUsage().heapUsed;
}

// Exercise the module under test
for (let i = 0; i < 1000; i++) {
  const conn = target.getConnection();
  allocations.push(conn);
}

// Measure after, with settling
let after = 0;
for (let settle = 0; settle < 3; settle++) {
  after = process.memoryUsage().heapUsed;
}

console.log(JSON.stringify({
  metric: 'heap_delta_bytes',
  before,
  after,
  delta: after - before
}));
```

### For **bundle** metric (webpack/esbuild):
Use the **Bash tool** to run the build command with size reporting:

```bash
# Run the build command with size reporting
npm run build -- --analyze 2>&1 | grep -E "chunk|bundle|size" || du -sh dist/
```

### For **vitals** metric (Lighthouse via headless):
Use the **Bash tool** to invoke Lighthouse and parse results:

```bash
# Requires a running dev server on $PORT (default 3000)
npx lighthouse http://localhost:3000 --chrome-flags="--headless" --output-path=/tmp/lh.json 2>&1
cat /tmp/lh.json | jq '.audits | {fcp: .first-contentful-paint, lcp: .largest-contentful-paint, cls: .cumulative-layout-shift}'
```

## Step 3 — Execute in Sandbox (CPU/Memory Only)

For `cpu` and `memory` metrics, invoke the sandbox once per metric:
```
mcp__code-execution-mcp__execute_code({
  language: "typescript",
  code: "<fixture from Step 2>",
  timeout_ms: 5000
})
```

For `bundle` and `vitals` metrics, use the **Bash tool** instead (they require network access and external tools unavailable in the sandbox).

Capture the JSON response. If `exit_code` is non-zero or contains `TIMEOUT`, mark as `[INCONCLUSIVE]` and document the reason.

## Step 4 — Parse & Structurize Results

Return a JSON envelope:
```json
{
  "status": "OK" | "TIMEOUT" | "SANDBOX_UNAVAILABLE",
  "target": "<input target>",
  "metric": "<input metric>",
  "measurement": {
    "value": <numeric>,
    "unit": "micros|bytes|KB|Mbps",
    "timestamp": "ISO8601"
  },
  "baseline": {
    "value": <numeric>,
    "sha": "<baseline_sha if provided>",
    "delta_percent": <((new - old) / old) * 100>
  },
  "raw_output": "<stdout from sandbox or Bash>"
}
```

## Step 5 — Return to Caller

Report the envelope back to the caller (typically `performance_engineer` agent):
- If called via `activate_skill`, the JSON is captured in the agent's context
- If called via CLI, print the JSON to stdout
- Do NOT write to OPTIMIZATION_REPORT.md (that is the agent's responsibility)

## Safety Constraints

- **Timeout**: Always use `timeout_ms: 5000` (5 seconds max) for execute_code
- **Memory cap**: code-execution-mcp enforces `--memory=512m`; if target exhausts this, mark as `[OOM]` (out-of-memory)
- **No network in sandbox**: `--network=none` — Lighthouse and external HTTP requests will fail in code-execution-mcp; use Bash tool for `bundle` and `vitals` metrics
- **No host side-effects**: Profiling is read-only; do not modify source code, environment, or host files
- **Sequential only**: Do not spawn parallel profiles; wait for one to complete before starting the next
- **No forced gc()**: Avoid `gc()` calls (require --expose-gc flag not available in sandbox); use `process.memoryUsage().heapUsed` deltas with a short settling loop instead

## Output

Upon completion, emit:
```
[PROFILE_COMPLETE] <target> | <metric> = <value> <unit> | status=<OK|TIMEOUT|OOM>
```

If the `performance_engineer` agent is listening, it will parse the JSON and synthesize OPTIMIZATION_REPORT.md. If called standalone (CLI), the user receives the raw data for manual analysis.

## Rollback & Recovery

- If sandbox unavailable: gracefully degrade to local profiling via Bash tool (marked `[SANDBOX_FALLBACK]`) — results are less isolated but still useful
- If target not found: emit `[TARGET_NOT_FOUND]` and suggest alternative paths to search
- If metric is unsupported: emit `[UNSUPPORTED_METRIC]` and list available metrics (cpu, memory, bundle, vitals)

## Deferred Capabilities

**[DEFERRED: performance-mcp not built]** The following advanced features require performance-mcp MCP server, currently unavailable:
- True flamegraph generation (currently using process.cpuUsage proxy only)
- Deep heap allocation tree analysis
- V8 code cache visualization
- Per-function flame stacks

When performance-mcp becomes available, upgrade this skill to use real flamegraph analysis instead of proxy measurements.
