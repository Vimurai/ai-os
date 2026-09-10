// provider-adapter.mjs — single source of truth for resolving a ROLE to a PROVIDER
// and building that provider's argv from the Provider Adapter Registry.
//
// WHY THIS EXISTS (E-210, D-054 / role-abstraction.md §Same-Provider Triad):
//   Two callers need exactly this resolution and must never drift apart:
//     - advisor-mcp::ask_architect  — the SYNCHRONOUS A2A bridge (print mode)
//     - `ai pane <role>` (src/bin/ai) — the per-pane role binding launcher
//   Before E-210 the bridge hardcoded `execFileSync("agy", ...)`, so an all-Claude
//   Triad (D-054) either failed outright (agy uninstalled / auth lapsed) or silently
//   consulted the WRONG architect. Vendor literals are banned here by construction:
//   the executable and its argv both come from .ai/roles.json × .ai/providers.json.
//
// DATA MODEL (role-abstraction.md §Data Model):
//   .ai/roles.json     { roles: { <role>: { provider, pane_identifier, model? } } }
//   .ai/providers.json { providers: { <name>: { launch[], print_mode[],
//                                               child_env_unset[] } } }
//   Templates substitute {role} {rulefile} {model} {prompt}. An entry whose
//   placeholder resolves to EMPTY is dropped — together with an immediately
//   preceding flag entry, so `["--model", "{model}"]` with no model configured
//   collapses to nothing rather than emitting a dangling `--model`.

import { readFileSync, existsSync } from "node:fs";
import { resolve as resolvePath, join } from "node:path";

// D-066 defaults — used when .ai/roles.json is absent or malformed. Kept in sync with
// src/templates/roles.json (architect=claude:1 · fable, engineer=claude:0 · opus).
// The all-Claude Triad is the DEFAULT topology; agy and gemini remain selectable providers.
export const DEFAULT_ROLE_PROVIDERS = { architect: "claude", engineer: "claude" };
// Per-role model fallbacks, applied only when the role's provider is claude — another
// provider has no use for a claude model name.
export const DEFAULT_ROLE_MODELS = { architect: "fable", engineer: "opus" };

// Built-in adapter fallbacks, so a project whose .ai/providers.json predates E-210
// (no launch/print_mode keys) still resolves a working argv instead of throwing.
export const DEFAULT_ADAPTERS = {
  claude: {
    launch: ["--settings", ".claude/settings.{role}.json", "--append-system-prompt-file", "{rulefile}", "--model", "{model}"],
    print_mode: ["-p", "--append-system-prompt-file", "{rulefile}", "{prompt}"],
    child_env_unset: ["CLAUDECODE"],
  },
  agy: { launch: [], print_mode: ["--print-timeout", "90s", "-p", "{prompt}"] },
  gemini: { launch: [], print_mode: ["-p", "{prompt}"] },
};

function readJson(path) {
  try {
    if (!existsSync(path)) return null;
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null; // corrupt config must degrade to defaults, never throw at a caller
  }
}

/** Role entry from .ai/roles.json, or {} when absent/malformed. */
export function roleEntry(aiDir, role) {
  const cfg = readJson(join(aiDir, "roles.json"));
  const entry = cfg?.roles?.[role];
  return entry && typeof entry === "object" ? entry : {};
}

/** Provider bound to `role`. Falls back to the D-050 default map. */
export function roleProvider(aiDir, role) {
  const p = roleEntry(aiDir, role).provider;
  return (typeof p === "string" && p.trim()) ? p.trim() : (DEFAULT_ROLE_PROVIDERS[role] ?? "");
}

/** Optional per-role model override ("" when unset). */
export function roleModel(aiDir, role) {
  const m = roleEntry(aiDir, role).model;
  return (typeof m === "string" && m.trim()) ? m.trim() : "";
}

/** Adapter for `provider`, merged over the built-in default. */
export function providerAdapter(aiDir, provider) {
  const cfg = readJson(join(aiDir, "providers.json"));
  const fromFile = cfg?.providers?.[provider];
  const builtin = DEFAULT_ADAPTERS[provider] ?? {};
  return { ...builtin, ...(fromFile && typeof fromFile === "object" ? fromFile : {}) };
}

const PLACEHOLDER = /\{(role|rulefile|model|prompt)\}/g;

/**
 * Substitute {placeholders} in an argv template.
 * Any entry whose placeholder resolves to an empty string is dropped, along with an
 * immediately preceding flag (`-`-prefixed) entry — so an unset {model} removes the
 * whole `--model {model}` pair rather than leaving a dangling flag.
 *
 * @param {string[]} template
 * @param {Record<string,string>} subs
 * @returns {string[]}
 */
export function buildArgv(template, subs = {}) {
  if (!Array.isArray(template)) return [];
  const out = [];
  for (const raw of template) {
    if (typeof raw !== "string") continue;
    let dropped = false;
    const val = raw.replace(PLACEHOLDER, (_m, key) => {
      const v = subs[key];
      if (v === undefined || v === null || v === "") { dropped = true; return ""; }
      return String(v);
    });
    if (dropped) {
      // Drop the flag this placeholder belonged to, if one was just emitted.
      if (out.length && /^-/.test(out[out.length - 1])) out.pop();
      continue;
    }
    out.push(val);
  }
  return out;
}

/**
 * Child environment for a spawned provider CLI.
 * `base` is an explicit ALLOWLIST (never process.env — spreading it would leak host
 * secrets to the child; same rule as computer-use-mcp, D-002). `child_env_unset` is
 * then applied on top as defence-in-depth: Claude Code refuses to nest while it sees
 * an inherited CLAUDECODE=1, and the strip keeps that true if the allowlist ever grows.
 */
/**
 * Flags whose OPERAND is a path the provider CLI must open. E-242 (D-066).
 *
 * Everything here is emitted PROJECT-RELATIVE by the adapter templates, which is correct
 * only when the CLI's cwd is the project root. It frequently is not: an rc-file `cd`, a
 * pre-existing tmux session or window, a pane opened in a subdirectory. The CLI then
 * reports "Settings file not found: .claude/settings.architect.json" for a file that
 * exists — the path is wrong, not the file.
 *
 * The rulefile is the more serious half and was failing the same way silently: without
 * ARCHITECT.md actually loading, a claude Architect pane boots the ENGINEER persona from
 * CLAUDE.md. That is gap G1, the very thing the same-provider Triad depends on, and a
 * missing file produces a wrong PERSONA rather than an error.
 */
export const PATH_OPERAND_FLAGS = new Set([
  "--settings",
  "--append-system-prompt-file",
]);

/**
 * Resolve project-relative path operands against the project root.
 *
 * Only the operand of a known path flag is touched, and only when it is relative — so a
 * prompt, a model name or a flag that merely looks path-like is never rewritten. Absolute
 * and `~`-anchored operands are left exactly as the author wrote them.
 *
 * @param {string[]} argv
 * @param {string} projectRoot absolute path to the project
 * @returns {string[]}
 */
export function absolutisePathOperands(argv, projectRoot) {
  if (!Array.isArray(argv) || !projectRoot) return Array.isArray(argv) ? argv : [];
  const out = [...argv];
  for (let i = 0; i < out.length - 1; i++) {
    if (!PATH_OPERAND_FLAGS.has(out[i])) continue;
    const operand = out[i + 1];
    if (typeof operand !== "string" || operand === "") continue;
    if (operand.startsWith("/") || operand.startsWith("~")) continue; // already anchored
    if (operand.startsWith("-")) continue;                            // a flag, not a path
    out[i + 1] = resolvePath(projectRoot, operand);
  }
  return out;
}

export function childEnv(base, adapter) {
  const env = { ...base };
  for (const k of adapter?.child_env_unset ?? []) delete env[k];
  return env;
}
