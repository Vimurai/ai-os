/**
 * state-writer.js — Shared state.json read/write helper (E-99)
 *
 * Extracted from task-synchronizer-mcp so that orchestrator-mcp and any future
 * MCP servers can mutate state.json + regenerate TASKS.md/REVIEWS.md views
 * without duplicating the logic or writing to markdown files directly.
 *
 * D-001: state.json is the exclusive write target.
 * TASKS.md and REVIEWS.md are generated views — never write to them directly.
 */

import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";
import { roleFromOwner } from "./state-db.js"; // E-136: provider-agnostic TASKS.md headers

/**
 * Read state.json — returns null if missing, corrupt, or wrong schema version.
 * Used by write tools that must refuse to operate without state.json.
 * E-117: version guard prevents silent acceptance of v0.x / future schemas.
 */
export function readStateStrict(aiDir) {
  const p = resolve(aiDir, "state.json");
  if (!existsSync(p)) return null;
  try {
    const state = JSON.parse(readFileSync(p, "utf8"));
    if (state.version !== "1.0") {
      process.stderr.write(`[WARN] state.json schema version '${state.version ?? "missing"}' != '1.0' — treating as corrupt\n`);
      return null;
    }
    return state;
  } catch { return null; }
}

/**
 * Write state.json and immediately regenerate TASKS.md + REVIEWS.md views.
 * This is the ONLY correct path for mutating task/stamp state.
 */
export function writeState(aiDir, state) {
  const p = resolve(aiDir, "state.json");
  writeFileSync(p, JSON.stringify(state, null, 2) + "\n", "utf8");
  regenerateMarkdown(aiDir, state);
}

/**
 * Regenerate TASKS.md and REVIEWS.md as read-only views from state.json.
 * Called automatically by writeState — do not call directly unless regenerating
 * views from an already-valid state object.
 */
export function regenerateMarkdown(aiDir, state) {
  // Regenerate TASKS.md view
  const tasksPath = resolve(aiDir, "TASKS.md");
  if (state.tasks.length > 0) {
    const lines = ["# TASKS (Generated from state.json)", ""];

    const byRole = {}; // E-136 (role-abstraction.md): group by provider-agnostic role
    for (const t of state.tasks) {
      const role = roleFromOwner(t.owner);
      if (!byRole[role]) byRole[role] = [];
      byRole[role].push(t);
    }

    for (const [role, tasks] of Object.entries(byRole)) {
      lines.push(`## ${role}`);
      for (const t of tasks) {
        const check = t.status === "DONE" ? "x" : " ";
        const tierStr = t.tier ? ` | Tier: ${t.tier}` : "";
        lines.push(`- [${check}] ${t.id}: ${t.description}${tierStr}`);
        if (t.status === "DONE" && t.completed_at) {
          lines.push(`  Status: DONE ${t.completed_at.split("T")[0]} — ${t.summary || "Complete"}`);
        }
      }
      lines.push("");
    }

    writeFileSync(tasksPath, lines.join("\n"), "utf8");
  }

  // Regenerate REVIEWS.md view from stamps
  if (state.stamps.length > 0) {
    const reviewsPath = resolve(aiDir, "REVIEWS.md");
    const stampLines = ["# REVIEWS.md (Generated from state.json)", ""];
    for (const s of state.stamps) {
      const date = s.timestamp ? s.timestamp.split("T")[0] : "unknown";
      stampLines.push(`[${s.type}] ${date} | ${s.summary || s.agent || ""}`);
    }
    stampLines.push("");
    writeFileSync(reviewsPath, stampLines.join("\n"), "utf8");
  }
}
