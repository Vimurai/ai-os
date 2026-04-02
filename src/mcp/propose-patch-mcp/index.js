#!/usr/bin/env node
/**
 * propose-patch-mcp — AI-OS Human-in-the-Loop Safe Diff Flow (E-141, §30)
 *
 * Instead of directly writing files, Claude proposes a formatted diff and
 * waits for explicit human confirmation before applying it.
 *
 * Tools:
 *   propose_patch(path, diff_content, description?)
 *     → Stores patch, formats diff for review. Returns patch_id.
 *   confirm_patch(patch_id)
 *     → Applies the stored patch to disk. Requires explicit human approval.
 *   reject_patch(patch_id)
 *     → Discards the stored patch. No changes made.
 *   list_pending_patches()
 *     → Shows all patches awaiting confirmation.
 *   preview_patch(patch_id)
 *     → Re-displays formatted diff without applying it.
 *
 * Diff format:
 *   Uses `delta` if available, falls back to `diff --color` or plain unified diff.
 *
 * Security:
 *   - Path traversal blocked (must resolve within cwd).
 *   - Patches stored in-memory only (no disk persistence of diffs).
 *   - confirm_patch is disable-model-invocation safe — requires explicit call.
 *   - Role-aware RBAC: Architect writes blocked outside .ai/ and plans/ (E-143, §35).
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve, relative } from "path";
import { spawnSync } from "child_process";
import { randomBytes } from "crypto";

// ── Patch store (in-memory) ───────────────────────────────────────────────────
// Map<patch_id, { path, diff_content, description, created_at, status }>
const patches = new Map();

function newPatchId() {
  return "patch-" + randomBytes(4).toString("hex");
}

function safePath(filePath, cwd) {
  const abs = resolve(cwd, filePath);
  const rel = relative(cwd, abs);
  if (rel.startsWith("..")) return null;
  return abs;
}

/**
 * Role-Aware RBAC guard (E-143, §35 ANTI-DRIFT).
 * Architect (Gemini) may only write to .ai/ or plans/ — never src/.
 * Returns an error result object if blocked, null if allowed.
 */
function roleGuard(callerRole, absPath, cwd) {
  if (!callerRole || callerRole.toLowerCase() !== "architect") return null;
  const rel = relative(cwd, absPath).replace(/\\/g, "/");
  const allowed = rel === ".ai" || rel.startsWith(".ai/") ||
                  rel === "plans" || rel.startsWith("plans/");
  if (!allowed) {
    return {
      content: [{
        type: "text",
        text:
          `[ANTI_DRIFT_VIOLATION] Architect attempted to write outside allowed scope.\n` +
          `  path:    ${absPath}\n` +
          `  role:    ${callerRole}\n` +
          `  allowed: .ai/, plans/\n\n` +
          `The Architect (Gemini) may only modify .ai/ and plans/.\n` +
          `To modify src/, switch to the Engineer (Claude).`,
      }],
      isError: true,
    };
  }
  return null;
}

/**
 * Attempt to format diff_content using delta, diff --color, or plain text.
 * Returns the formatted string.
 */
function formatDiff(diffContent, absPath) {
  // Try `delta` (https://github.com/dandavison/delta) — best TUI rendering
  const delta = spawnSync("delta", ["--no-gitconfig"], {
    input: diffContent,
    encoding: "utf8",
    timeout: 5000,
  });
  if (!delta.error && delta.status === 0 && delta.stdout?.trim()) {
    return delta.stdout;
  }

  // Try `diff --color` against empty baseline (for new files) or actual file
  if (existsSync(absPath)) {
    const diffResult = spawnSync("diff", ["--color=always", "-u", absPath, "-"], {
      input: diffContent,
      encoding: "utf8",
      timeout: 5000,
    });
    // diff exits 1 when files differ (that's expected), 2 on error
    if (diffResult.status !== 2 && diffResult.stdout?.trim()) {
      return diffResult.stdout;
    }
  }

  // Plain fallback — annotate the unified diff with line numbers
  const lines = diffContent.split("\n");
  const annotated = lines.map((l, i) => {
    if (l.startsWith("+++") || l.startsWith("---")) return l;
    if (l.startsWith("+")) return `\x1b[32m${l}\x1b[0m`; // green
    if (l.startsWith("-")) return `\x1b[31m${l}\x1b[0m`; // red
    if (l.startsWith("@@")) return `\x1b[36m${l}\x1b[0m`; // cyan
    return l;
  });
  return annotated.join("\n");
}

function renderPatch(patchData, formatted) {
  return [
    `╔══ PROPOSED PATCH ═══════════════════════════════════════════════╗`,
    `║  ID:   ${patchData.id}`,
    `║  File: ${patchData.path}`,
    `║  Desc: ${(patchData.description || "(none)").slice(0, 60)}`,
    `║  Time: ${patchData.created_at}`,
    `╚═════════════════════════════════════════════════════════════════╝`,
    "",
    formatted,
    "",
    `┌─────────────────────────────────────────────────────────────────┐`,
    `│  To APPLY:   confirm_patch("${patchData.id}")                   │`,
    `│  To DISCARD: reject_patch("${patchData.id}")                    │`,
    `└─────────────────────────────────────────────────────────────────┘`,
  ].join("\n");
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "propose-patch-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "propose_patch",
      description:
        "Proposes a file edit as a formatted diff for human review. " +
        "Does NOT write to disk — returns a patch_id that must be confirmed via confirm_patch(). " +
        "Use instead of direct file edits for Tier 2/3 logic changes requiring human review.",
      inputSchema: {
        type: "object",
        properties: {
          path:         { type: "string", description: "Relative or absolute file path to patch." },
          diff_content: { type: "string", description: "Unified diff content (output of: diff -u old new) OR the full new file content." },
          description:  { type: "string", description: "One-line description of what this patch does." },
          caller_role:  {
            type: "string",
            enum: ["engineer", "architect"],
            description: "Role of the calling agent. If 'architect', writes outside .ai/ and plans/ are blocked with [ANTI_DRIFT_VIOLATION].",
          },
        },
        required: ["path", "diff_content"],
      },
    },
    {
      name: "confirm_patch",
      description:
        "Applies a previously proposed patch to disk. " +
        "IMPORTANT: Only call this after the user has reviewed and approved the diff. " +
        "This is a destructive write — back up the file if needed.",
      inputSchema: {
        type: "object",
        properties: {
          patch_id: { type: "string", description: "The patch_id returned by propose_patch()." },
        },
        required: ["patch_id"],
      },
    },
    {
      name: "reject_patch",
      description:
        "Discards a proposed patch without making any changes. " +
        "Call this if the user rejects the diff or you want to revise the patch.",
      inputSchema: {
        type: "object",
        properties: {
          patch_id: { type: "string", description: "The patch_id returned by propose_patch()." },
        },
        required: ["patch_id"],
      },
    },
    {
      name: "list_pending_patches",
      description:
        "Lists all patches currently awaiting confirmation. " +
        "Use to review outstanding patches before committing.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "preview_patch",
      description:
        "Re-displays the formatted diff for a pending patch without applying it. " +
        "Use to re-review a patch before confirming.",
      inputSchema: {
        type: "object",
        properties: {
          patch_id: { type: "string", description: "The patch_id returned by propose_patch()." },
        },
        required: ["patch_id"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const cwd = process.cwd();

  switch (name) {
    // ── propose_patch ─────────────────────────────────────────────────────────
    case "propose_patch": {
      const abs = safePath(args.path, cwd);
      if (!abs) {
        return {
          content: [{ type: "text", text: `✗ Path traversal blocked: '${args.path}'` }],
          isError: true,
        };
      }

      const roleBlock = roleGuard(args.caller_role, abs, cwd);
      if (roleBlock) return roleBlock;

      const id = newPatchId();
      const patchData = {
        id,
        path: abs,
        diff_content: args.diff_content,
        description: args.description || "",
        caller_role: args.caller_role || null,
        created_at: new Date().toISOString(),
        status: "pending",
      };
      patches.set(id, patchData);

      const formatted = formatDiff(args.diff_content, abs);
      const rendered  = renderPatch(patchData, formatted);

      return { content: [{ type: "text", text: rendered }] };
    }

    // ── confirm_patch ─────────────────────────────────────────────────────────
    case "confirm_patch": {
      const patch = patches.get(args.patch_id);
      if (!patch) {
        return {
          content: [{ type: "text", text: `✗ Patch not found: '${args.patch_id}'. It may have already been applied or rejected.` }],
          isError: true,
        };
      }
      if (patch.status !== "pending") {
        return {
          content: [{ type: "text", text: `✗ Patch '${args.patch_id}' is already ${patch.status}.` }],
          isError: true,
        };
      }

      // Defense-in-depth: re-check role at apply time
      const roleBlock = roleGuard(patch.caller_role, patch.path, cwd);
      if (roleBlock) return roleBlock;

      // Apply the patch — determine if diff_content is a unified diff or full file
      const isDiff = patch.diff_content.startsWith("---") || patch.diff_content.startsWith("@@");

      try {
        if (isDiff) {
          // Use `patch` command to apply unified diff
          const result = spawnSync("patch", [patch.path, "-"], {
            input: patch.diff_content,
            encoding: "utf8",
            timeout: 10000,
          });
          if (result.status !== 0) {
            return {
              content: [{
                type: "text",
                text: `✗ patch command failed (exit ${result.status}):\n${result.stderr || result.stdout || "(no output)"}`,
              }],
              isError: true,
            };
          }
        } else {
          // Treat as full file replacement
          writeFileSync(patch.path, patch.diff_content, "utf8");
        }

        patch.status = "applied";
        patches.delete(args.patch_id);

        return {
          content: [{
            type: "text",
            text: `✓ Patch applied: ${patch.path}\n  ID: ${args.patch_id}\n  Desc: ${patch.description || "(none)"}`,
          }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: `✗ Write failed: ${e.message}` }],
          isError: true,
        };
      }
    }

    // ── reject_patch ──────────────────────────────────────────────────────────
    case "reject_patch": {
      const patch = patches.get(args.patch_id);
      if (!patch) {
        return {
          content: [{ type: "text", text: `✗ Patch not found: '${args.patch_id}'.` }],
          isError: true,
        };
      }
      patches.delete(args.patch_id);
      return {
        content: [{
          type: "text",
          text: `✓ Patch rejected and discarded.\n  ID: ${args.patch_id}\n  File: ${patch.path}\n  No changes were made.`,
        }],
      };
    }

    // ── list_pending_patches ──────────────────────────────────────────────────
    case "list_pending_patches": {
      const pending = [...patches.values()].filter(p => p.status === "pending");
      if (pending.length === 0) {
        return { content: [{ type: "text", text: "No pending patches." }] };
      }
      const lines = [`Pending patches (${pending.length}):`, ""];
      for (const p of pending) {
        lines.push(`  ${p.id} — ${p.path}`);
        lines.push(`    Desc: ${p.description || "(none)"} | Created: ${p.created_at}`);
      }
      return { content: [{ type: "text", text: lines.join("\n") }] };
    }

    // ── preview_patch ─────────────────────────────────────────────────────────
    case "preview_patch": {
      const patch = patches.get(args.patch_id);
      if (!patch) {
        return {
          content: [{ type: "text", text: `✗ Patch not found: '${args.patch_id}'.` }],
          isError: true,
        };
      }
      const formatted = formatDiff(patch.diff_content, patch.path);
      return { content: [{ type: "text", text: renderPatch(patch, formatted) }] };
    }

    default:
      return { content: [{ type: "text", text: `✗ Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
