#!/usr/bin/env bash
# mcp_telemetry_test.sh — E-153 (telemetry-hardening.md §Components 1): the global
# telemetry interceptor `withTelemetry()` that wraps every MCP server's CallTool handler.
#
# Proves: canonical mcp__<server>__<tool> naming, accurate SUCCESS/ERROR classification
# (E-154: a thrown exception OR an `{isError:true}` result both record ERROR), result
# pass-through, exception propagation, non-negative latency, and the hard invariant that a
# telemetry failure NEVER breaks or alters the wrapped tool's result.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "── Suite: mcp_telemetry_test (E-153 / E-154) ───────────────────────"

# Run all behavioural scenarios in one node process with an INJECTED recorder (no real
# telemetry DB is touched). Emits one `key=value` token per line for assert_contains.
OUT="$(HELPER_URL="file://${REPO_ROOT}/src/shared/mcp-telemetry.mjs" node --input-type=module <<'NODE'
const { withTelemetry, toolNameFor, statusForResult, rejection, markRejection } = await import(process.env.HELPER_URL);

const reqFor = (name) => ({ params: { name } });
let captured = null;
const rec = (p) => { captured = p; };

// 1. SUCCESS path — normal result, recorder sees SUCCESS + canonical name + latency.
captured = null;
const okHandler = withTelemetry("task-synchronizer-mcp", async () => ({ content: [{ type: "text", text: "ok" }] }), { record: rec });
const okRes = await okHandler(reqFor("add_task"));
console.log("name=" + captured.tool_name);
console.log("ok_status=" + captured.status);
console.log("ok_returned=" + (okRes && okRes.content ? "true" : "false"));
console.log("latency_int=" + (Number.isInteger(captured.execution_time_ms) && captured.execution_time_ms >= 0 ? "true" : "false"));

// 2. Tool-level error result ({isError:true}) → ERROR, but result still returned.
captured = null;
const errResHandler = withTelemetry("safe-exec-mcp", async () => ({ content: [], isError: true }), { record: rec });
const errRes = await errResHandler(reqFor("analyze_command"));
console.log("errresult_status=" + captured.status);
console.log("errresult_returned=" + (errRes && errRes.isError ? "true" : "false"));

// 3. Thrown exception → ERROR recorded AND the exception propagates unchanged.
captured = null;
let threw = false, propagated = false;
const throwHandler = withTelemetry("db-architect-mcp", async () => { throw new Error("boom"); }, { record: rec });
try { await throwHandler(reqFor("migrate")); } catch (e) { propagated = (e.message === "boom"); }
console.log("throw_status=" + (captured ? captured.status : "NONE"));
console.log("throw_propagated=" + propagated);

// 4. Telemetry failure must NEVER break the tool — recorder throws, result still returns.
const badRec = () => { throw new Error("telemetry down"); };
const robustHandler = withTelemetry("orchestrator-mcp", async () => ({ content: [{ type: "text", text: "fine" }] }), { record: badRec });
let robustOk = false;
try { const r = await robustHandler(reqFor("run_review")); robustOk = !!(r && r.content); } catch { robustOk = false; }
console.log("telemetry_fail_safe=" + robustOk);

// 5. Pure helpers: missing tool name → ...__unknown; statusForResult mapping.
console.log("name_missing=" + toolNameFor("x-mcp", {}));
console.log("status_ok=" + statusForResult({ content: [] }));
console.log("status_err=" + statusForResult({ isError: true }));

// 6. instrument(): the rollout mechanism. A fake Server whose setRequestHandler is patched;
//    CallTool handlers get wrapped (recorder fires), non-CallTool handlers pass through.
const { instrument } = await import(process.env.HELPER_URL);
const calls = [];
const fakeServer = { _h: new Map(), setRequestHandler(schema, h) { this._h.set(schema, h); } };
const CALLTOOL = { kind: "CallTool" };
const LISTTOOLS = { kind: "ListTools" };
instrument(fakeServer, "demo-mcp", CALLTOOL, { record: (p) => calls.push(p) });
fakeServer.setRequestHandler(CALLTOOL, async (req) => ({ content: [], isError: req.params.name === "boom" }));
fakeServer.setRequestHandler(LISTTOOLS, async () => ({ tools: ["passthrough"] }));
await fakeServer._h.get(CALLTOOL)({ params: { name: "ok" } });
await fakeServer._h.get(CALLTOOL)({ params: { name: "boom" } });
const listRes = await fakeServer._h.get(LISTTOOLS)();
console.log("instrument_calltool_count=" + calls.length);
console.log("instrument_names=" + calls.map((c) => c.tool_name).join(","));
console.log("instrument_statuses=" + calls.map((c) => c.status).join(","));
console.log("instrument_listtools_untouched=" + (listRes.tools[0] === "passthrough" ? "true" : "false"));

// 7. E-179/E-180: expected-rejection marker. rejection()/markRejection() flag an isError result
//    as an EXPECTED rejection so the interceptor books REJECTED (a distinct usage-friction
//    status — NOT SUCCESS, which E-179 used, and NOT ERROR) while the model still receives
//    isError:true. Unmarked isError results stay ERROR.
const rej = rejection("✗ [INVALID_X] bad input");
console.log("rej_iserror=" + (rej.isError === true ? "true" : "false"));
console.log("rej_marked=" + (rej._meta && rej._meta.expected_rejection === true ? "true" : "false"));
console.log("rej_status=" + statusForResult(rej));                                   // REJECTED
console.log("markrej_status=" + statusForResult(markRejection({ content: [], isError: true }))); // REJECTED
console.log("unmarked_iserror_status=" + statusForResult({ isError: true, _meta: {} }));          // ERROR
// E-180: REJECTED is distinct from both SUCCESS and ERROR (the whole point of the new status).
console.log("rej_distinct=" + (statusForResult(rej) !== "SUCCESS" && statusForResult(rej) !== "ERROR" ? "true" : "false"));
// end-to-end: a wrapped handler returning a rejection() records REJECTED but still returns isError.
captured = null;
const rejHandler = withTelemetry("task-synchronizer-mcp", async () => rejection("✗ [SEED_NOT_FOUND] TS-9"), { record: rec });
const rejRes = await rejHandler(reqFor("get_topic_cluster"));
console.log("rej_e2e_status=" + captured.status);                                    // REJECTED
console.log("rej_e2e_iserror=" + (rejRes && rejRes.isError === true ? "true" : "false")); // model still sees isError
// E-179 (critic_tests P2): the non-object guard branches.
console.log("status_null=" + statusForResult(null));                                 // ERROR (malformed)
console.log("markrej_null_safe=" + (markRejection(null) === null ? "true" : "false")); // safe no-op, no throw
NODE
)"

echo "$OUT"
echo "── assertions ──"
assert_contains "153.01: canonical mcp__server__tool name"        "name=mcp__task-synchronizer-mcp__add_task" "$OUT"
assert_contains "153.02: normal result records SUCCESS"           "ok_status=SUCCESS"        "$OUT"
assert_contains "153.03: result passed through unchanged"         "ok_returned=true"         "$OUT"
assert_contains "153.04: latency is a non-negative integer"       "latency_int=true"         "$OUT"
assert_contains "154.01: {isError:true} result records ERROR"     "errresult_status=ERROR"   "$OUT"
assert_contains "154.01b: error result still returned to caller"  "errresult_returned=true"  "$OUT"
assert_contains "154.02: thrown handler records ERROR"            "throw_status=ERROR"       "$OUT"
assert_contains "154.02b: thrown exception propagates unchanged"  "throw_propagated=true"    "$OUT"
assert_contains "153.05: telemetry failure never breaks the tool" "telemetry_fail_safe=true" "$OUT"
assert_contains "153.06: missing tool name → __unknown"           "name_missing=mcp__x-mcp__unknown" "$OUT"
assert_contains "153.07: statusForResult(ok)=SUCCESS"             "status_ok=SUCCESS"        "$OUT"
assert_contains "153.07b: statusForResult(isError)=ERROR"         "status_err=ERROR"         "$OUT"
assert_contains "153.08: instrument() wraps both CallTool calls"  "instrument_calltool_count=2" "$OUT"
assert_contains "153.08b: instrument() names both tools"          "instrument_names=mcp__demo-mcp__ok,mcp__demo-mcp__boom" "$OUT"
assert_contains "153.08c: instrument() classifies SUCCESS+ERROR"  "instrument_statuses=SUCCESS,ERROR" "$OUT"
assert_contains "153.08d: instrument() leaves ListTools untouched" "instrument_listtools_untouched=true" "$OUT"
# ── E-179/E-180: expected-rejection marker classification (E-180: books REJECTED, not SUCCESS) ──
assert_contains "179.01: rejection() sets isError:true (model still reacts)"   "rej_iserror=true"           "$OUT"
assert_contains "179.02: rejection() stamps _meta.expected_rejection"          "rej_marked=true"            "$OUT"
assert_contains "180.03: marked isError result classifies REJECTED"            "rej_status=REJECTED"        "$OUT"
assert_contains "180.04: markRejection() also yields REJECTED"                  "markrej_status=REJECTED"    "$OUT"
assert_contains "179.05: UNMARKED isError still classifies ERROR"              "unmarked_iserror_status=ERROR" "$OUT"
assert_contains "180.04b: REJECTED is distinct from SUCCESS and ERROR"         "rej_distinct=true"          "$OUT"
assert_contains "180.06: wrapped rejection() records REJECTED telemetry"       "rej_e2e_status=REJECTED"    "$OUT"
assert_contains "179.07: wrapped rejection() still returns isError to model"   "rej_e2e_iserror=true"       "$OUT"
assert_contains "179.08: statusForResult(null) MALFORMED → ERROR"             "status_null=ERROR"          "$OUT"
assert_contains "179.09: markRejection(null) is a safe no-op (no throw)"       "markrej_null_safe=true"     "$OUT"

assert_summary
