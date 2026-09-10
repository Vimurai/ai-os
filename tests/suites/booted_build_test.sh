#!/usr/bin/env bash
# booted_build_test.sh — E-249 (D-067 §3): booted-build staleness is ANNOUNCED.
#
# THE DEFECT. ESM caches a module for the lifetime of the process, and an MCP server is a
# long-lived process. `bash install-ai-os.sh` rewrites ~/.ai-os and `git pull` rewrites
# src/; neither reaches a server that is already running. The task synchroniser served the
# pre-E-245 projector and stripped the archive pointer on every write; run_review reported
# a P0 the shipped checker no longer emitted. Both times the gate was reporting on code
# that was no longer on disk, and nothing said so.
#
# THE HARD PART IS PROVING IT LIVE. Every other MCP assertion in this suite spawns a fresh
# server per call, which is precisely the condition under which this bug cannot occur — a
# fresh process always has fresh modules. So §1 below holds ONE server open across a source
# rewrite, which is the only shape in which the defect exists at all. A per-call client
# would report green forever.
#
# The unit layer (tests/unit/build-stamp.test.mjs) owns the scan's own logic — hashing,
# reaping, the gate's decision table. This suite owns the WIRING: that a real server stamps
# real results, that the five consumers actually call the scan, and that the completion
# gate refuses and allows through the real tool.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
source "${SCRIPT_DIR}/../lib/mcp-client.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
INSTALLER="${REPO_ROOT}/install-ai-os.sh"
STAMP="${REPO_ROOT}/src/shared/build-stamp.mjs"
SYNCHRONIZER="${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"

echo "── Suite: booted_build_test (E-249) ─────────────────────────────────"

export AI_OS_DISABLE_REPO_MAP=1

# ── §1: LIVE — one server, held open across a source rewrite ─────────────────
#
# A copy of the framework's server-side tree, so the rewrite below touches a throwaway file
# and never the repo. node_modules is SYMLINKED rather than copied: the vendored SDK is the
# bulk of src/mcp, and module resolution follows the link.
_live_root=""
_prepare_live_tree() {
  local d; d="$(test_tmpdir e249-live)"
  mkdir -p "$d/mcp"
  cp -R "${REPO_ROOT}/src/shared"  "$d/shared"
  cp -R "${REPO_ROOT}/src/mcp/shared" "$d/mcp/shared"
  cp -R "${REPO_ROOT}/src/mcp/task-synchronizer-mcp" "$d/mcp/task-synchronizer-mcp"
  rm -rf "$d/mcp/task-synchronizer-mcp/node_modules"
  # The SDK is hoisted to the workspace root (npm workspaces), so the copy needs a
  # node_modules at ITS root — Node walks up from the importing file, and a per-server link
  # is never reached. Symlinked rather than copied: the vendored SDK is the bulk of the tree.
  ln -sfn "${REPO_ROOT}/node_modules" "$d/node_modules" 2>/dev/null || true
  printf '%s' "$d"
}

if skip_unless_cmd node "live MCP server layer"; then
  _live_root="$(_prepare_live_tree)"
  _live_entry="${_live_root}/mcp/task-synchronizer-mcp/index.js"
  _live_home="$(test_tmpdir e249-home)"          # HOME is redirected: the boot record must
  _live_proj="$(test_tmpdir e249-proj)"          # never land in (or reap from) the real run dir
  mkdir -p "${_live_proj}/.ai"
  printf '# TASKS (Generated from state.json)\n' > "${_live_proj}/.ai/TASKS.md"

  # The driver. One child process, two tool calls, a source rewrite in between — expressed
  # in node because a persistent JSON-RPC session is not something the per-call bash client
  # can express, and expressing it here keeps the shared client unchanged.
  cat > "${_live_root}/driver.mjs" <<'DRIVER'
import { spawn } from "node:child_process";
import { appendFileSync } from "node:fs";

const [entry, cwd, touchFile] = process.argv.slice(2);
const srv = spawn(process.execPath, ["--no-warnings", entry], {
  cwd, stdio: ["pipe", "pipe", "pipe"], env: { ...process.env },
});

let buf = "";
const waiters = new Map();
srv.stdout.on("data", (c) => {
  buf += c.toString();
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg; try { msg = JSON.parse(line); } catch { continue; }
    const w = waiters.get(msg.id);
    if (w) { waiters.delete(msg.id); w(msg); }
  }
});

let id = 0;
function rpc(method, params) {
  const myId = ++id;
  return new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error(`timeout on ${method}`)), 20000);
    waiters.set(myId, (m) => { clearTimeout(t); res(m); });
    srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: myId, method, params }) + "\n");
  });
}

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

try {
  await rpc("initialize", {
    protocolVersion: "2024-11-05", capabilities: {},
    clientInfo: { name: "e249-driver", version: "1.0" },
  });
  srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

  const first = await rpc("tools/call", { name: "verify_markdown_sync", arguments: {} });
  console.log("__FIRST__ " + JSON.stringify(first.result ?? first));

  // The rewrite. Appending keeps the module valid — the point is that its BYTES changed
  // while a process that already imported it keeps serving the old copy.
  appendFileSync(touchFile, "\n// E-249 live rewrite\n");
  await sleep(50);

  const second = await rpc("tools/call", { name: "verify_markdown_sync", arguments: {} });
  console.log("__SECOND__ " + JSON.stringify(second.result ?? second));
} catch (e) {
  console.log("__ERROR__ " + e.message);
} finally {
  srv.kill("SIGKILL");
}
DRIVER

  _live_out="$(HOME="${_live_home}" node --no-warnings "${_live_root}/driver.mjs" \
                 "${_live_entry}" "${_live_proj}" "${_live_root}/mcp/shared/state-db.js" 2>/dev/null || true)"
  _first="$(printf '%s\n'  "$_live_out" | grep -m1 '^__FIRST__ '  | cut -c11-)"
  _second="$(printf '%s\n' "$_live_out" | grep -m1 '^__SECOND__ ' | cut -c12-)"

  assert_status 0 "E-249.01a: the live server answered both calls" \
    bash -c "[[ -n '${_first:-}' && -n '${_second:-}' ]]"

  # Every tool result carries the build the SERVER PROCESS booted with.
  assert_contains "E-249.01b: the first result carries _meta.booted_build" "booted_build" "${_first:-}"
  assert_contains "E-249.01c: so does the result after the rewrite" "booted_build" "${_second:-}"

  # The stamp reports what the process BOOTED with, not what is on disk now. If it tracked
  # disk it would always agree with disk, and could never report a stale server.
  _h1="$(printf '%s' "${_first:-}"  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("_meta",{}).get("booted_build",{}).get("hash",""))' 2>/dev/null || true)"
  _h2="$(printf '%s' "${_second:-}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("_meta",{}).get("booted_build",{}).get("hash",""))' 2>/dev/null || true)"
  assert_status 0 "E-249.01d: booted_build is UNCHANGED by the rewrite (it reports the boot, not disk)" \
    bash -c "[[ -n '${_h1}' && '${_h1}' == '${_h2}' ]]"

  # ACCEPTANCE: the same tool, on the same process, reports the staleness the rewrite created.
  assert_status 1 "E-249.01e: verify_markdown_sync was CLEAN before the rewrite" \
    bash -c "printf '%s' \"\${_first}\" | grep -q STALE_SERVER"
  assert_contains "E-249.01f: and reports [STALE_SERVER] after it" "STALE_SERVER" "${_second:-}"
  assert_contains "E-249.01g: the notice names the restart requirement" "restart required" "${_second:-}"
  # The structured tail carries it too, for the skills and hooks that parse rather than read.
  assert_contains "E-249.01h: __SYNC_RESULT__ carries stale_servers" "stale_servers" "${_second:-}"
  # Staleness is an operational notice, NOT a sync verdict: folding it into SYNC_FAIL would
  # make that verdict mean two different things.
  _verdict="$(printf '%s' "${_second:-}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(json.loads(d["content"][0]["text"].split("__SYNC_RESULT__ ")[1])["status"])
' 2>/dev/null || echo "PARSE_FAILED")"
  assert_contains "E-249.01i: the SYNC verdict itself is unaffected by staleness" "PASS" "${_verdict}"
fi

# ── §2: the rollback ─────────────────────────────────────────────────────────
_stale_fixture() {   # → a run dir holding one stale record for a throwaway "server"
  local d; d="$(test_tmpdir e249-run)"
  mkdir -p "$d/run" "$d/srv"
  printf '// v1\n' > "$d/srv/index.js"
  # The record must name a LIVE pid. writeBootRecord() stamps process.pid, and a helper
  # invoked with `node -e` is gone by the time the scan runs — so the scan would (correctly)
  # reap it as dead and report nothing, and the assertion below would pass for the wrong
  # reason in one direction and fail in the other. `$$` is this suite's own shell: alive for
  # as long as the assertions are.
  local hash
  hash="$(node --no-warnings "$STAMP" --stamp "$d/srv/index.js" \
          | python3 -c 'import json,sys; print(json.load(sys.stdin)["hash"])' 2>/dev/null || echo "")"
  printf '{"server":"rollback-mcp","pid":%s,"entry":"%s","hash":"%s","booted_at":"%s"}\n' \
    "$$" "$d/srv/index.js" "$hash" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$d/run/build-rollback-mcp.json"
  printf '// v2\n' >> "$d/srv/index.js"
  printf '%s' "$d"
}
_rb="$(_stale_fixture)"
assert_contains "E-249.02a: the fixture is stale while the stamp is enabled" "STALE_SERVER" \
  "$(E249_MOD="$STAMP" E249_RUN="${_rb}/run" node --no-warnings -e '
      import(process.env.E249_MOD).then(m => console.log(m.staleServerReport({ runDir: process.env.E249_RUN }).join("\n")));
    ' 2>/dev/null || true)"
assert_status 1 "E-249.02b: AI_OS_BUILD_STAMP=0 silences it" \
  bash -c "AI_OS_BUILD_STAMP=0 E249_MOD='$STAMP' E249_RUN='${_rb}/run' node --no-warnings -e '
      import(process.env.E249_MOD).then(m => console.log(m.staleServerReport({ runDir: process.env.E249_RUN }).join(\"\n\")));
    ' 2>/dev/null | grep -q STALE_SERVER"

# The CLI must ALWAYS exit 0. `ai sync` runs under `set -euo pipefail`, and a non-zero exit
# from an advisory probe is the exact class of defect E-247 had just finished removing.
node --no-warnings "$STAMP" --stale >/dev/null 2>&1
assert_contains "E-249.02c: the CLI exits 0 even with nothing to report" "0" "$?"
assert_status 0 "E-249.02d: --stale-json is machine-readable" \
  bash -c "node --no-warnings '$STAMP' --stale-json 2>/dev/null | python3 -c 'import json,sys; json.load(sys.stdin)'"

# ── §3: the five consumers are WIRED ─────────────────────────────────────────
# Source-level, because each consumer's own report is covered where it lives; what these
# assert is that the scan is actually reached from all five surfaces named in D-067 §3.
assert_status 0 "E-249.03a: verify_markdown_sync calls the scan" \
  grep -q 'staleServerReport()' "${REPO_ROOT}/src/mcp/task-synchronizer-mcp/index.js"
assert_status 0 "E-249.03b: run_preflight calls the scan" \
  grep -q 'staleServerReport()' "${REPO_ROOT}/src/mcp/orchestrator-mcp/index.js"
assert_status 0 "E-249.03c: ai sync runs it as a fail-open step" \
  grep -qE '_sync_step +stale_servers +_report_stale_servers' "$AI"
assert_status 0 "E-249.03d: ai doctor reports it" grep -q '_stale_server_lines' "$AI"
assert_status 0 "E-249.03e: install-ai-os.sh reports it at the end" \
  grep -q 'build-stamp.mjs" --stale' "$INSTALLER"
# Doctor prints the CLEAN case too — a diagnostic that is silent when healthy cannot be
# told apart from one that did not run.
assert_status 0 "E-249.03f: doctor names the healthy case explicitly" \
  grep -q 'every running server booted the build that is on disk' "$AI"
# The install notice must not be able to fail the install.
assert_status 0 "E-249.03g: the installer's probe is guarded and non-fatal" \
  bash -c "grep -A1 'build-stamp.mjs\" --stale' '$INSTALLER' | grep -q '|| true'"

# The interceptor stamps every server, not a hand-maintained list of them.
assert_status 0 "E-249.03h: the stamp rides on the shared instrument() interceptor" \
  grep -q 'bootedBuild(serverName)' "${REPO_ROOT}/src/shared/mcp-telemetry.mjs"
_instrumented="$(grep -lE '^\s*instrument\(server' "${REPO_ROOT}"/src/mcp/*/index.js | wc -l | tr -d ' ')"
assert_status 0 "E-249.03i: all ${_instrumented} instrumented servers inherit it (>=20)" \
  bash -c "[[ '${_instrumented}' -ge 20 ]]"

# ── §4: THE REFUSAL (D-067 §3) — state-db and the projectors are not hot-reloaded ──
# E-237 hot-reloads four POLICY modules. The ruling refuses to extend that to state. This
# is asserted because the tempting "fix" for everything above is to hot-reload the lot, and
# nothing else in the tree would object.
assert_status 1 "E-249.04a: state-db is not in the hot-reload set" \
  grep -qE 'loadPolicy\(.*state-db' "${REPO_ROOT}/src/mcp/shared/load-policy.mjs" \
    "${REPO_ROOT}"/src/mcp/*/index.js
assert_status 0 "E-249.04b: the refusal is recorded where the mechanism lives" \
  grep -q 'never patched live' "$STAMP"

# ── §5: the completion gate, BOTH WAYS, through the real tool ────────────────
#
# The gate lives in update_task_status because that is what `skill: ai-task` calls; a
# markdown skill cannot refuse anything. Driving the real tool is what proves the gate is
# reachable from the path the Engineer actually uses.
#
# isFrameworkClone() decides whether a repo is one the mirror is a copy OF. With HOME
# redirected there is no persisted workspace file, so it falls back to package.json's name
# — which is what makes a self-contained fixture possible here.
_gate_fixture() {   # <mirror-matches: yes|no> → project dir, with $HOME/.ai-os as the mirror
  local matches="$1"
  local h; h="$(test_tmpdir e249-gate-home)"
  local d; d="$(test_tmpdir e249-gate-proj)"
  mkdir -p "$d/.ai" "$d/src/mcp/probe" "$d/src/bin" "$h/.ai-os/mcp/probe" "$h/.ai-os/bin"
  printf '{"name":"ai-os-v2"}\n' > "$d/package.json"
  printf '// probe v1\n' > "$d/src/mcp/probe/index.js"
  printf '#!/usr/bin/env bash\n' > "$d/src/bin/ai"
  cp "$d/src/bin/ai" "$h/.ai-os/bin/ai"
  if [[ "$matches" == "yes" ]]; then
    cp "$d/src/mcp/probe/index.js" "$h/.ai-os/mcp/probe/index.js"
  else
    printf '// probe v0 — the mirror is a build behind\n' > "$h/.ai-os/mcp/probe/index.js"
  fi
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  printf '%s' "$d|$h"
}

_gate_verdict() {   # <matches> → the update_task_status result text
  local pair; pair="$(_gate_fixture "$1")"
  local d="${pair%%|*}" h="${pair##*|}"
  # E-236 / the E-248 tail: `AIOS_WORKSPACE` is EXPORTED into an AI-OS shell and points at
  # the real framework clone. isFrameworkClone() consults it before falling back to
  # package.json, so an inherited value makes every fixture below read as "not the
  # framework" and the gate never fires — the assertions would pass only in the direction
  # that proves nothing. Second instance of an inherited launch variable deciding a verdict
  # in two consecutive tasks.
  ( cd "$d" && env -u AIOS_WORKSPACE -u AI_OS_HOME HOME="$h" bash -c "
      source '${SCRIPT_DIR}/../lib/mcp-client.sh'
      mcp_call_tool '$SYNCHRONIZER' add_task '{\"owner\":\"Engineer (Claude)\",\"description\":\"E-249 gate probe\",\"prefix\":\"E\"}' >/dev/null 2>&1
      mcp_call_tool '$SYNCHRONIZER' update_task_status '{\"id\":\"E-1\",\"status\":\"DONE\",\"summary\":\"probe\"}' 2>/dev/null
    " )
}

_gate_dirty="$(_gate_verdict no)"
assert_contains "E-249.05a: DONE is REFUSED while the mirror is a build behind" "BUILD_STALE" "${_gate_dirty}"
assert_contains "E-249.05b: the refusal names the file that was not installed" "src/mcp/probe/index.js" "${_gate_dirty}"
assert_contains "E-249.05c: and says how to fix it" "install-ai-os.sh" "${_gate_dirty}"
assert_contains "E-249.05d: and names its own rollback" "AI_OS_BUILD_STAMP=0" "${_gate_dirty}"

# NON-VACUITY. Without this, deleting the gate entirely, or breaking it so it refuses
# nothing, would leave 05a-05d passing only if they were also deleted — but a gate that
# refuses EVERYTHING passes them all while making the tool unusable.
_gate_clean="$(_gate_verdict yes)"
assert_status 1 "E-249.05e: DONE is ALLOWED when the mirror is current" \
  bash -c "printf '%s' \"\${_gate_clean}\" | grep -q BUILD_STALE"
assert_contains "E-249.05f: and the task really transitions" "DONE" "${_gate_clean}"

# The rollback releases the gate rather than requiring the mirror to be fixed.
_gate_pair="$(_gate_fixture no)"
_gp_d="${_gate_pair%%|*}"; _gp_h="${_gate_pair##*|}"
_gate_off="$( cd "$_gp_d" && env -u AIOS_WORKSPACE -u AI_OS_HOME HOME="$_gp_h" AI_OS_BUILD_STAMP=0 bash -c "
    source '${SCRIPT_DIR}/../lib/mcp-client.sh'
    mcp_call_tool '$SYNCHRONIZER' add_task '{\"owner\":\"Engineer (Claude)\",\"description\":\"probe\",\"prefix\":\"E\"}' >/dev/null 2>&1
    mcp_call_tool '$SYNCHRONIZER' update_task_status '{\"id\":\"E-1\",\"status\":\"DONE\"}' 2>/dev/null
  " )"
assert_status 1 "E-249.05g: AI_OS_BUILD_STAMP=0 releases the gate" \
  bash -c "printf '%s' \"\${_gate_off}\" | grep -q BUILD_STALE"

# A refusal must leave NOTHING behind: the gate runs before the dependency-revision write,
# so a blocked DONE is not a half-applied mutation. This needs its OWN fixture — the
# rollback pair above deliberately let its DONE through, and checking that one would have
# asserted the opposite of what it reads.
_h8="$(_gate_fixture no)"; _h8d="${_h8%%|*}"; _h8h="${_h8##*|}"
( cd "$_h8d" && env -u AIOS_WORKSPACE -u AI_OS_HOME HOME="$_h8h" bash -c "
    source '${SCRIPT_DIR}/../lib/mcp-client.sh'
    mcp_call_tool '$SYNCHRONIZER' add_task '{\"owner\":\"Engineer (Claude)\",\"description\":\"probe\",\"prefix\":\"E\"}' >/dev/null 2>&1
    mcp_call_tool '$SYNCHRONIZER' update_task_status '{\"id\":\"E-1\",\"status\":\"DONE\",\"summary\":\"probe\"}' >/dev/null 2>&1
  " )
assert_status 0 "E-249.05h: the refused task is still listed OPEN in TASKS.md" \
  grep -q '^- \[ \] E-1' "${_h8d}/.ai/TASKS.md"
assert_status 1 "E-249.05i: and is NOT recorded done" \
  grep -q '^- \[x\] E-1' "${_h8d}/.ai/TASKS.md"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== booted_build_test.sh PASS ====="
else
  echo "===== booted_build_test.sh FAIL (${FAIL_COUNT}) ====="
fi
