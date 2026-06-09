// signal-handoff.mjs — the single source of truth for writing a bridge handoff
// signal into a project's .ai/signal.json (interactive-bridge.md §API).
//
// WHY THIS EXISTS (E-158, cli-agnostic-handoff):
//   The handoff was previously reachable ONLY via task-synchronizer-mcp::handoff_control.
//   That works for Claude (which reliably calls custom MCP tools) but NOT for the agy
//   (Antigravity) Architect runtime, which — especially when its Antigravity auth has
//   lapsed — does not dependably expose/invoke project MCP servers to the model. agy
//   DOES reliably run shell commands via its `run_command` built-in, so this helper is
//   the deterministic primitive behind a provider-agnostic `ai handoff` CLI. Both the
//   MCP tool and the CLI route through emitHandoff() so the queue/lock semantics can
//   never drift between the two callers (engineering-standards.md §src/shared reuse).
//
// SEMANTICS (must stay byte-for-byte compatible with the historical handoff_control):
//   - signal.json is a FIFO QUEUE (array). The entry is APPENDED, never overwritten,
//     so a busy agent never loses a pending handoff (E-118).
//   - The entry shape is { timestamp, target, message, delivered:false }. ai-watch keys
//     delivery on the immutable `timestamp` and treats absent/false `delivered`
//     identically as undelivered (E-124).
//   - A short-lived mkdir lock (".lock", SHARED with ai-watch's _signal_lock) serialises
//     this append against the watcher's delivered-flag write so neither clobbers the
//     other (interactive-bridge.md §Execution Constraints).
//   - MAX_QUEUE growth is bounded by evicting only the OLDEST *delivered* entries; an
//     undelivered handoff is never dropped.

import { readFileSync, writeFileSync, existsSync, mkdirSync, rmdirSync } from "node:fs";
import { resolve, dirname } from "node:path";

// Semantic roles (architect/engineer) AND legacy provider names (claude/gemini).
// ai-watch resolves either to a tmux pane via .ai/roles.json (E-136/E-137).
export const VALID_TARGETS = new Set(["architect", "engineer", "claude", "gemini"]);

const MAX_QUEUE = 50; // bound growth — `ai watch` consumes via per-entry delivered flags.

// Synchronous sleep without busy-spinning (matches handoff_control). Atomics.wait on a
// throwaway SharedArrayBuffer; degrades to no-wait if SAB is unavailable.
const _sleepMs = (ms) => {
  try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); } catch { /* SAB unavailable → no wait */ }
};

/**
 * Append a handoff signal to <aiDir>/signal.json under the shared write lock.
 * Pure of process state — caller supplies aiDir — so it is unit-testable and reusable.
 *
 * @param {{aiDir:string, target:string, message:string}} opts
 * @returns {{ok:true, target:string, message:string, queueLength:number, signalPath:string}
 *          | {ok:false, code:string, error:string}}
 */
export function emitHandoff({ aiDir, target, message } = {}) {
  if (!VALID_TARGETS.has(target)) {
    return { ok: false, code: "INVALID_TARGET", error: "target must be a semantic role ('architect'|'engineer') or a provider name ('claude'|'gemini')." };
  }
  const msg = typeof message === "string" ? message.trim() : "";
  if (!msg) {
    return { ok: false, code: "EMPTY_MESSAGE", error: "a non-empty message is required." };
  }

  const entry = { timestamp: new Date().toISOString(), target, message: msg, delivered: false };
  const signalPath = resolve(aiDir, "signal.json");
  const lockPath = signalPath + ".lock";

  let lockHeld = false;
  for (let i = 0; i < 25; i++) {
    try { mkdirSync(lockPath); lockHeld = true; break; } catch { _sleepMs(20); }
  }
  try {
    let queue = [];
    if (existsSync(signalPath)) {
      try {
        const parsed = JSON.parse(readFileSync(signalPath, "utf8"));
        if (Array.isArray(parsed)) queue = parsed;
        else if (parsed && typeof parsed === "object") queue = [parsed]; // legacy flat → queue
      } catch { queue = []; } // corrupt → safely reset rather than throw
    }
    queue.push(entry);
    // Evict only the OLDEST *delivered* entries; never drop an undelivered handoff.
    if (queue.length > MAX_QUEUE) {
      const deliveredOverflow = queue.filter((e) => e && e.delivered === true).length;
      let toDrop = Math.min(queue.length - MAX_QUEUE, deliveredOverflow);
      if (toDrop > 0) {
        queue = queue.filter((e) => {
          if (toDrop > 0 && e && e.delivered === true) { toDrop--; return false; }
          return true;
        });
      }
    }
    try {
      writeFileSync(signalPath, JSON.stringify(queue, null, 2) + "\n", "utf8");
    } catch (e) {
      return { ok: false, code: "SIGNAL_WRITE_FAILED", error: e.message };
    }
    return { ok: true, target, message: msg, queueLength: queue.length, signalPath };
  } finally {
    if (lockHeld) { try { rmdirSync(lockPath); } catch { /* already gone */ } }
  }
}

// Walk up from `start` to find the nearest ancestor containing a `.ai/` directory,
// so `ai handoff` works from any subdirectory of a project (git-style discovery).
// Falls back to <start>/.ai when no ancestor has one.
export function findAiDir(start) {
  let dir = resolve(start || ".");
  for (let i = 0; i < 40; i++) {
    if (existsSync(resolve(dir, ".ai"))) return resolve(dir, ".ai");
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return resolve(start || ".", ".ai");
}

// Sensible role-based default when the caller omits a message — keeps `ai handoff <role>`
// a one-word command. The two skills (task-planner / ai-task) normally pass a real summary.
export function defaultMessage(target) {
  return (target === "engineer" || target === "claude")
    ? "Architect: new/updated tasks are ready — review TASKS.md and execute the open Engineer queue."
    : "Engineer: queue exhausted — please review COMM.md and plan the next sprint.";
}

// ── CLI entry: `node signal-handoff.mjs <target> [message...]` ────────────────
// Used by `ai handoff` (src/bin/ai). Resolves the project's .ai dir from $AI_OS_AIDIR
// or by walking up from cwd. Prints the same ✓/✗ lines as handoff_control for parity.
const _isMain = (() => {
  try { return process.argv[1] && resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname); }
  catch { return false; }
})();

if (_isMain) {
  const target = process.argv[2];
  const rest = process.argv.slice(3).join(" ").trim();
  if (!target) {
    console.error("usage: ai handoff <architect|engineer|claude|gemini> [message]");
    process.exit(2);
  }
  const message = rest || defaultMessage(target);
  const aiDir = process.env.AI_OS_AIDIR ? resolve(process.env.AI_OS_AIDIR) : findAiDir(process.cwd());
  const r = emitHandoff({ aiDir, target, message });
  if (!r.ok) {
    console.error(`✗ [${r.code}] ${r.error}`);
    process.exit(1);
  }
  console.log(`✓ [HANDOFF] → ${r.target} (queued #${r.queueLength}): ${r.message}`);
  console.log(`  signal: ${r.signalPath}`);
  process.exit(0);
}
