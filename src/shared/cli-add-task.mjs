// cli-add-task.mjs — the shell-native primitive behind `ai add-task` (E-198,
// Architect Ruling A / pending D-053).
//
// WHY THIS EXISTS (symmetric to signal-handoff.mjs / E-158):
//   State mutation is normally MCP-only (structured-outputs.md §32). That works for
//   Claude (which reliably calls custom MCP tools) but NOT for the agy (Antigravity)
//   Architect runtime, which does not dependably expose/invoke project MCP servers to
//   the model — so when agy authors a blueprint and hand-edits TASKS.md, the next
//   `verify_markdown_sync` regenerates TASKS.md from state.sqlite and DROPS the
//   unpersisted rows (the "orphaned blueprint" incident). agy DOES reliably run shell
//   via its run_command built-in, so this helper is the deterministic primitive behind
//   a provider-agnostic `ai add-task`.
//
//   Both this CLI and task-synchronizer-mcp::add_task route through the SAME
//   state-db::addTask(), so state.sqlite stays the single writer and the two callers
//   can never drift (engineering-standards.md §src/shared reuse). The Architect ratified
//   this as an explicit, audited exception to MCP-only state mutation.
//
// CONSTRAINTS (Architect Ruling A):
//   1. Invoke the EXACT same state logic as the MCP tool — done via the shared
//      addTask() (nextId → DAG validate → INSERT → id high-water → regenerate views).
//   2. Stamp the caller_role: the created task's owner reflects the resolved Triad
//      role (architect → "Architect (Agy)", engineer → "Engineer (Claude)"), taken
//      from the bootloader-injected AI_OS_CALLER_ROLE (E-127) unless overridden.
//   3. Respect the sovereignty lock: writes go through getDb() (node:sqlite WAL,
//      single-writer) — the same handle discipline the MCP uses; no divergent raw write.
//
// E-204 (auto-handoff): after a task is created FOR the other role (prefix E→engineer,
//   P→architect, when it differs from the creator's AI_OS_CALLER_ROLE), this primitive
//   auto-emits an `ai handoff` bridge signal so the executing role is woken with no
//   manual step. Best-effort + fail-open (a handoff error never fails the add); deduped
//   against an already-pending signal; disabled by AI_OS_NO_AUTO_HANDOFF=1 (rollback).

import { existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { getDb, addTask } from "../mcp/shared/state-db.js";
import { emitHandoff, hasPendingHandoff } from "./signal-handoff.mjs";
import { roleProvider } from "./provider-adapter.mjs";

// Triad caller_role → TASKS.md owner label. Attribution only (safe-exec-mcp owns the
// tamper-resistant HMAC role boundary, E-129); here we just record who created the row.
//
// E-213 (architect-provider-parity.md §Components 4): the PROVIDER half is resolved
// from .ai/roles.json rather than hardcoded. "Architect (Agy)" was baked in, so an
// all-Claude Triad (D-054) attributed every Architect-created task to Agy — a provider
// that is not even running. state-db::roleFromOwner splits on " (" for the generated
// TASKS.md section headers, so making the provider dynamic cannot churn those headers.
export const DEFAULT_ROLE_OWNER = {
  architect: "Architect (Agy)",
  engineer:  "Engineer (Claude)",
};

// Kept as a named export for back-compat with existing importers/tests.
export const ROLE_OWNER = DEFAULT_ROLE_OWNER;

// "claude" → "Claude". Cosmetic only: the label is human-facing and the previous
// hardcoded values were capitalized, so this keeps TASKS.md reading the same way.
function _titleProvider(p) {
  const t = String(p || "").trim();
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : "";
}

/**
 * Resolve the owner label. Explicit --owner wins; else map the Triad role
 * (--role, then the bootloader-injected AI_OS_CALLER_ROLE, then 'engineer') and
 * pair it with the provider that role is bound to in .ai/roles.json.
 * Fails soft to the D-050 defaults — an attribution label must never break task
 * creation just because roles.json is missing or unreadable.
 */
export function resolveOwner({ owner, role, aiDir } = {}) {
  if (typeof owner === "string" && owner.trim()) return owner.trim();
  const r = String(role || process.env.AI_OS_CALLER_ROLE || "engineer").toLowerCase();
  const known = r === "architect" ? "architect" : "engineer";
  const label = known === "architect" ? "Architect" : "Engineer";
  try {
    const dir = aiDir || findAiDir(process.cwd());
    const provider = _titleProvider(roleProvider(dir, known));
    if (provider) return `${label} (${provider})`;
  } catch {
    /* fall through to the default */
  }
  return DEFAULT_ROLE_OWNER[known];
}

/**
 * Walk up from a start dir to find the project's .ai/ directory (state.sqlite lives
 * under it). Mirrors advisor-mcp::findProjectRoot — tolerant of being invoked from a
 * subdirectory. Falls back to <cwd>/.ai even if absent (getDb will surface the error).
 */
export function findAiDir(startDir) {
  let dir = startDir;
  for (let i = 0; i < 6; i++) {
    const candidate = join(dir, ".ai");
    if (existsSync(join(candidate, "state.sqlite")) || existsSync(join(candidate, "state.json"))) {
      return candidate;
    }
    const parent = resolve(dir, "..");
    if (parent === dir) break;
    dir = parent;
  }
  return join(startDir, ".ai");
}

/**
 * Parse `ai add-task` argv (tokens AFTER the `add-task` subcommand). Supports
 * `--flag value` and `--flag=value`; every non-flag token is part of the description.
 * Recognised flags: --prefix, --owner, --role, --tier, --depends-on (comma-separated).
 * @returns {{prefix,owner,role,tier,depends_on:string[],description:string}}
 */
export function parseArgs(argv) {
  const out = { prefix: "E", owner: null, role: null, tier: null, depends_on: [], _desc: [] };
  const takesValue = new Set(["--prefix", "--owner", "--role", "--tier", "--depends-on"]);
  for (let i = 0; i < argv.length; i++) {
    let tok = argv[i];
    if (tok.startsWith("--")) {
      let val = null;
      const eq = tok.indexOf("=");
      if (eq !== -1) { val = tok.slice(eq + 1); tok = tok.slice(0, eq); }
      else if (takesValue.has(tok)) { val = argv[++i]; }
      switch (tok) {
        case "--prefix":     out.prefix = (val || "E").toUpperCase(); break;
        case "--owner":      out.owner = val; break;
        case "--role":       out.role = val; break;
        case "--tier":       out.tier = val != null ? parseInt(val, 10) : null; break;
        case "--depends-on": out.depends_on = String(val || "").split(",").map(s => s.trim()).filter(Boolean); break;
        default: /* unknown flag → ignore (forward-compatible) */ break;
      }
    } else {
      out._desc.push(tok);
    }
  }
  const { _desc, ...rest } = out;
  return { ...rest, description: _desc.join(" ").trim() };
}

/**
 * Create a task from resolved options. Pure of process state (caller supplies aiDir),
 * so it is unit-testable and reusable. Routes through the shared addTask().
 * @returns {{ok:true, task:object, owner:string} | {ok:false, code:string, error:string}}
 */
export function runAddTask({ aiDir, description, owner, role, tier, prefix, depends_on } = {}) {
  const finalOwner = resolveOwner({ owner, role });
  let db;
  try {
    db = getDb(aiDir);
  } catch (e) {
    return { ok: false, code: "STATE_DB_UNAVAILABLE", error: `could not open state.sqlite under ${aiDir}: ${e.message}` };
  }
  const res = addTask(aiDir, db, { owner: finalOwner, description, tier, prefix, depends_on });
  if (!res.ok) return res;
  return { ok: true, task: res.task, owner: finalOwner };
}

// ── E-204: auto-handoff on cross-role task creation ─────────────────────────────
// Eliminates the manual `ai handoff` step: when a role creates a task the OTHER role
// must execute, wake that role automatically. The task prefix is the authoritative
// signal for WHICH queue the task lands in (E-## → Engineer, P-## → Architect); the
// creator is the bootloader-injected AI_OS_CALLER_ROLE (E-127: agy→architect,
// claude→engineer). This mirrors the shell-native philosophy of `ai handoff` (E-158)
// and closes the loop with the E-200 settle barrier from the opposite side.

// Task-id prefix → the Triad role that owns/executes that queue.
export const PREFIX_ROLE = { E: "engineer", P: "architect" };

/**
 * Resolve the auto-handoff target for a just-created task, or null when none applies.
 * A task is "created for another role" when the role that will execute it (from its
 * prefix) differs from the creator (AI_OS_CALLER_ROLE). A role queuing its OWN work
 * (creator === target) returns null — no self-handoff. An unrecognised prefix returns
 * null rather than guessing.
 * @param {{prefix?:string, callerRole?:string}} opts callerRole is injectable for tests;
 *        it defaults to AI_OS_CALLER_ROLE, then 'engineer' (matching resolveOwner()).
 * @returns {"architect"|"engineer"|null}
 */
export function autoHandoffTarget({ prefix, callerRole } = {}) {
  const target = PREFIX_ROLE[String(prefix || "E").toUpperCase()];
  if (!target) return null;
  const creator = String(callerRole || process.env.AI_OS_CALLER_ROLE || "engineer").toLowerCase();
  return creator === target ? null : target;
}

/**
 * Best-effort auto-handoff after a cross-role task creation. Side-effect-isolated:
 * NEVER throws and never blocks — the task is already persisted, so a handoff failure
 * must not fail `ai add-task`. Disabled entirely by AI_OS_NO_AUTO_HANDOFF=1 (rollback /
 * test isolation). Deduped against an already-pending undelivered signal so a burst of
 * creations coalesces into a single wake.
 * @returns {{emitted:boolean, target?:string, reason?:string}}
 */
export function maybeAutoHandoff({ aiDir, task, prefix, callerRole } = {}) {
  if (process.env.AI_OS_NO_AUTO_HANDOFF === "1") return { emitted: false, reason: "disabled" };
  const target = autoHandoffTarget({ prefix, callerRole });
  if (!target) return { emitted: false, reason: "same-role" };
  try {
    if (hasPendingHandoff(aiDir, target)) return { emitted: false, target, reason: "already-pending" };
    const id = task && task.id ? task.id : "a task";
    const message = `Auto-handoff: ${id} was queued for the ${target}. Review TASKS.md and execute the open queue.`;
    const res = emitHandoff({ aiDir, target, message });
    return res.ok ? { emitted: true, target } : { emitted: false, target, reason: res.code };
  } catch (e) {
    return { emitted: false, target, reason: e.message };
  }
}

// ── CLI entrypoint ────────────────────────────────────────────────────────────
// Invoked as: node cli-add-task.mjs <args…>  (from bin/ai `do_add_task`).
function main() {
  const argv = process.argv.slice(2);
  const opts = parseArgs(argv);
  if (!opts.description) {
    process.stderr.write("usage: ai add-task [--prefix E|P] [--owner <name>] [--role architect|engineer] [--tier N] [--depends-on E-1,E-2] <description>\n");
    process.exit(2);
  }
  const aiDir = findAiDir(process.cwd());
  const res = runAddTask({ aiDir, ...opts });
  if (!res.ok) {
    process.stderr.write(`ai add-task: [${res.code}] ${res.error}\n`);
    process.exit(1);
  }
  // stdout: the created id (scriptable) + a human line; full record to stderr for logs.
  process.stdout.write(`${res.task.id}\n`);
  process.stderr.write(`✓ Added ${res.task.id} (${res.task.status}) owner="${res.owner}": ${res.task.description}\n`);

  // E-204: if this task is for the OTHER role, wake it automatically (no manual
  // `ai handoff`). Creator = AI_OS_CALLER_ROLE (NOT opts.role, which is the task's
  // owner). Best-effort — a handoff failure never fails the already-persisted add.
  const auto = maybeAutoHandoff({ aiDir, task: res.task, prefix: opts.prefix });
  if (auto.emitted) process.stderr.write(`↪ auto-handoff → ${auto.target} (E-204)\n`);
}

// Run only when executed directly (not when imported by tests). Mirrors the
// is-main guard used across the MCP servers.
import { fileURLToPath } from "node:url";
if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main();
}
