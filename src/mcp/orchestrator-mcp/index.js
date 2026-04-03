#!/usr/bin/env node
/**
 * orchestrator-mcp — AI-OS Deterministic Workflow Execution
 * Replaces LLM-interpreted multi-step workflows with programmatic execution.
 *
 * Tools:
 *   run_preflight()               → reads .ai/ files in mandated order, returns context
 *   run_handover({ task_id })     → marks task DONE, appends LOG, triggers digest prompt
 *   run_review({ tier })          → tier-aware review: T1 skip, T2 aligner, T3 deterministic checks + agent dispatch
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync } from "fs";
import { resolve } from "path";
import { spawnSync } from "child_process";
import { readStateStrict, writeState } from "../shared/state-writer.js";

// ── Helpers ───────────────────────────────────────────────────────────────────
function readSafe(p) {
  try { return existsSync(p) ? readFileSync(p, "utf8") : ""; } catch { return ""; }
}

function today() {
  return new Date().toISOString().split("T")[0];
}

function gitRead(args, cwd) {
  const r = spawnSync("git", args, { cwd, encoding: "utf8", timeout: 10000 });
  return r.error ? "" : (r.stdout || "");
}

function getDiff(cwd) {
  let d = gitRead(["diff", "--staged"], cwd);
  if (!d.trim()) d = gitRead(["diff", "HEAD"], cwd);
  return d;
}

// ── Server ────────────────────────────────────────────────────────────────────
const server = new Server(
  { name: "orchestrator-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "run_preflight",
      description:
        "Reads .ai/ files in the mandated DIGEST-first order and returns a token-optimized " +
        "preflight context string. Stamps SESSION.md. Call this at the start of every session.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "run_handover",
      description:
        "Marks an E-## task as DONE in TASKS.md, appends a LOG entry, and returns a digest " +
        "regeneration prompt. Call this after completing an implementation task.",
      inputSchema: {
        type: "object",
        properties: {
          task_id: {
            type: "string",
            description: "The task ID to mark complete (e.g. 'E-65')",
          },
          summary: {
            type: "string",
            description: "One-line summary of what was implemented",
          },
        },
        required: ["task_id"],
      },
    },
    {
      name: "run_intent_cleanup",
      description:
        "DEPRECATED (E-147): UPDATE.md has been removed from AI-OS. Intent is now provided via conversation context. " +
        "This tool is a no-op and returns a deprecation notice. Use `skill: ai-compact` to manage session context instead.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "run_review",
      description:
        "Executes a tier-aware code review. Tier 1: skips. Tier 2: runs blueprint-aligner " +
        "checks. Tier 3: runs deterministic security/test/architecture checks and returns " +
        "which critic agents need to be spawned for LLM-level review.",
      inputSchema: {
        type: "object",
        properties: {
          tier: {
            type: "number",
            description: "Risk tier (1, 2, or 3)",
            enum: [1, 2, 3],
          },
        },
        required: ["tier"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const cwd = process.cwd();
  const ai = resolve(cwd, ".ai");

  switch (name) {
    // ── run_preflight ─────────────────────────────────────────────────────────
    case "run_preflight": {
      const files = [
        { name: "DIGEST.md", path: resolve(ai, "DIGEST.md") },
        { name: "TASKS.md", path: resolve(ai, "TASKS.md") },
      ];

      const sections = [];
      for (const f of files) {
        const content = readSafe(f.path);
        if (content.trim()) {
          // For large files, truncate to keep context manageable
          const lines = content.split("\n");
          const truncated = lines.length > 80
            ? lines.slice(0, 80).join("\n") + `\n... (${lines.length - 80} more lines)`
            : content;
          sections.push(`## ${f.name}\n${truncated}`);
        } else {
          sections.push(`## ${f.name}\n(empty)`);
        }
      }

      // Add pointer for architect.md index — skip by default to save tokens
      sections.push(`## architect.md (INDEX)\n(Skipped to save tokens. Use \`filesystem.read\` on \`.ai/architect.md\` ONLY if you need architectural details for your specific task.\nIt is now a lightweight index (~30 lines). Domain blueprints are in \`.ai/blueprints/<domain>.md\` — load only the one relevant to your task.)`);

      // E-103: state.json summary — task counts + last 3 stamps (structured data preferred over MD view)
      const statePath = resolve(ai, "state.json");
      if (existsSync(statePath)) {
        try {
          const state = JSON.parse(readFileSync(statePath, "utf8"));

          // Task count summary by status
          const counts = { OPEN: 0, BLOCKED: 0, DONE: 0 };
          for (const t of state.tasks || []) counts[t.status] = (counts[t.status] || 0) + 1;
          const lastStamps = (state.stamps || []).slice(-3).map(s =>
            `  [${s.type}] ${s.timestamp ? s.timestamp.split("T")[0] : "??"} | ${s.summary || s.agent || ""}`
          );
          const stateSummaryLines = [
            `Tasks: ${counts.OPEN} OPEN | ${counts.BLOCKED} BLOCKED | ${counts.DONE} DONE (total: ${state.tasks.length})`,
            lastStamps.length > 0 ? `Last stamps:\n${lastStamps.join("\n")}` : "Stamps: none",
            state.project?.focus ? `Focus: ${state.project.focus}` : "",
          ].filter(Boolean);
          sections.push(`## state.json Summary\n${stateSummaryLines.join("\n")}`);

          // Reactive Memory (E-138, §24): surface stale DIGEST warning at preflight
          if (state.digest_stale) {
            sections.push(
              `## ⚠ DIGEST.md IS STALE (Reactive Memory §24)\n` +
              `Reason: ${state.digest_stale_reason || "task completed"}\n\n` +
              `**Action**: Regenerate DIGEST.md before proceeding:\n` +
              `  skill: "ai-digest"  OR  activate_agent('digest_updater')\n\n` +
              `_Clear the flag after regeneration: set state.digest_stale = false_`
            );
          }

          // Check for unread implementation deltas (P-42 §29)
          const unread = (state.deltas || []).filter(d => !d.read);
          if (unread.length > 0) {
            sections.push("## Unread Implementation Deltas");
            for (const d of unread) {
              sections.push(`- ${d.task_id}: ${d.summary}`);
              d.read = true;
            }
            sections.push("\n**Architect**: Review these deltas. If any diverge from your blueprint, update architect.md.");
            writeFileSync(statePath, JSON.stringify(state, null, 2) + "\n");
          }
        } catch { /* ignore state.json parse errors */ }
      }

      // Stamp SESSION.md
      const sessionPath = resolve(ai, "SESSION.md");
      const stamp = `${today()} | orchestrator-mcp | run_preflight | Files read: ${files.map(f => f.name).join(", ")}\n`;
      try { appendFileSync(sessionPath, stamp); } catch { /* ignore if can't write */ }

      return {
        content: [{
          type: "text",
          text: `# Preflight Context (${today()})\n\n${sections.join("\n\n")}`,
        }],
      };
    }

    // ── run_handover ──────────────────────────────────────────────────────────
    case "run_handover": {
      const taskId = (args.task_id || "").trim().toUpperCase();
      const summary = args.summary || "Implementation complete";

      if (!/^[EPT]-\d+$/.test(taskId)) {
        return {
          content: [{ type: "text", text: `✗ Invalid task ID: '${taskId}'. Expected format: E-##, P-##, or T-##` }],
          isError: true,
        };
      }

      const logPath = resolve(ai, "LOG.md");
      const results = [];

      // 1. Mark task DONE in state.json → TASKS.md regenerated as view (E-99: D-001 compliance)
      const state = readStateStrict(ai);
      if (state) {
        const task = (state.tasks || []).find(t => t.id === taskId);
        if (task) {
          if (task.status === "DONE") {
            results.push(`⚠ ${taskId} already marked DONE`);
          } else {
            task.status = "DONE";
            task.completed_at = new Date().toISOString();
            task.summary = summary;
            writeState(ai, state);  // writes state.json + regenerates TASKS.md + REVIEWS.md
            results.push(`✓ ${taskId} marked DONE in state.json (TASKS.md regenerated)`);
          }
        } else {
          results.push(`⚠ ${taskId} not found in state.json`);
        }
      } else {
        results.push(`⚠ state.json missing — run: ai migrate-state to enable task sync`);
      }

      // 2. Append LOG entry
      if (existsSync(logPath)) {
        const logEntry = `${today()} | Claude | ${taskId} | ${summary}\n`;
        appendFileSync(logPath, logEntry);
        results.push(`✓ LOG.md updated`);
      }

      // 3. Generate implementation delta and save to state.json (P-42 §29)
      const diff = getDiff(cwd);
      if (diff.trim()) {
        // Read blueprint section for comparison
        const archPath = resolve(ai, "architect.md");
        let bpSection = "";
        if (existsSync(archPath)) {
          const arch = readFileSync(archPath, "utf8");
          const idx = arch.indexOf(taskId);
          if (idx !== -1) {
            const before = arch.lastIndexOf("\n## ", idx);
            const after = arch.indexOf("\n## ", idx + 1);
            bpSection = arch.slice(
              before !== -1 ? before : Math.max(0, idx - 500),
              after !== -1 ? after : Math.min(arch.length, idx + 2000)
            );
          }
        }

        // Generate delta summary
        const changedFiles = [...diff.matchAll(/^\+\+\+ b\/(.+)$/gm)].map(m => m[1]);
        const deltaText = `${taskId}: ${summary} | Files: ${changedFiles.slice(0, 5).join(", ")}`;

        // Save delta to state.json if it exists
        const statePath = resolve(ai, "state.json");
        if (existsSync(statePath)) {
          try {
            const state = JSON.parse(readFileSync(statePath, "utf8"));
            if (!state.deltas) state.deltas = [];
            state.deltas.push({
              task_id: taskId,
              timestamp: new Date().toISOString(),
              summary: deltaText,
              files_changed: changedFiles.slice(0, 10),
              read: false,
            });
            writeFileSync(statePath, JSON.stringify(state, null, 2) + "\n");
            results.push(`✓ Implementation delta saved to state.json`);
          } catch {
            results.push(`⚠ Could not save delta to state.json`);
          }
        }
      }

      // 4. Reactive Memory (E-138, §24): mark digest_stale in state.json so
      //    stop-hook.sh and the next preflight can detect and trigger DIGEST update.
      const statePath2 = resolve(ai, "state.json");
      if (existsSync(statePath2)) {
        try {
          const st2 = JSON.parse(readFileSync(statePath2, "utf8"));
          st2.digest_stale = true;
          st2.digest_stale_reason = `${taskId} marked DONE — ${summary}`;
          writeFileSync(statePath2, JSON.stringify(st2, null, 2) + "\n");
          results.push(`✓ digest_stale=true set in state.json (Reactive Memory §24)`);
        } catch {
          results.push(`⚠ Could not set digest_stale flag`);
        }
      }

      // 5. Return digest prompt
      results.push("");
      results.push(
        "## Reactive Memory — DIGEST Update Required\n" +
        `Task ${taskId} is complete. DIGEST.md is now stale.\n\n` +
        "**Action required**: Run the digest_updater agent to refresh DIGEST.md:\n" +
        "  activate_agent('digest_updater')\n\n" +
        "Or use the skill: `skill: \"ai-digest\"`"
      );

      return { content: [{ type: "text", text: results.join("\n") }] };
    }

    // ── run_review ────────────────────────────────────────────────────────────
    case "run_review": {
      const tier = args.tier;

      if (![1, 2, 3].includes(tier)) {
        return {
          content: [{ type: "text", text: "✗ Invalid tier. Must be 1, 2, or 3." }],
          isError: true,
        };
      }

      const diff = getDiff(cwd);
      const date = today();

      // ── Tier 1: Skip ────────────────────────────────────────────────────
      if (tier === 1) {
        return {
          content: [{
            type: "text",
            text: `## Review — Tier 1 (${date})\n\n` +
              `Verdict: SKIP\n` +
              `CSS/docs/typos only. No critic agents needed.\n` +
              `Commit with: \`git commit -m "[TIER_1] <description>"\``,
          }],
        };
      }

      // ── Shared deterministic checks ──────────────────────────────────────
      const checks = [];

      // Check 1: Hardcoded secrets in diff
      const secretPattern = /^\+[^+].*\b(password|passwd|api.?key|secret|token|private.?key)\s*=\s*["'][^"']{4,}/gim;
      const secretMatches = [...diff.matchAll(secretPattern)].map(m => m[0].trim().slice(0, 60));
      if (secretMatches.length > 0) {
        checks.push({ id: "HARDCODED_SECRET", severity: "P0", status: "FAIL", detail: secretMatches[0] });
      }

      // Check 2: Path traversal
      const traversalPattern = /^\+[^+].*(\.\.\/|\/etc\/|\/root\/)/gm;
      const traversalMatches = [...diff.matchAll(traversalPattern)].map(m => m[0].trim().slice(0, 80));
      if (traversalMatches.length > 0) {
        checks.push({ id: "PATH_TRAVERSAL", severity: "P0", status: "FAIL", detail: traversalMatches[0] });
      }

      // Check 3: Blueprint alignment — architect-owned files modified
      const geminiFiles = [".ai/architect.md", ".ai/BRIEF.md"];
      const sovereigntyViolations = geminiFiles.filter(f => diff.includes(`a/${f}`) || diff.includes(`b/${f}`));
      if (sovereigntyViolations.length > 0) {
        checks.push({ id: "SOVEREIGNTY_VIOLATION", severity: "P0", status: "FAIL", detail: sovereigntyViolations.join(", ") });
      }

      // Check 4: New deps without DECISIONS.md
      const pkgPattern = /^\+\s+"[a-z@][a-z0-9\-@/.]+"\s*:/gm;
      const newDeps = [...diff.matchAll(pkgPattern)].map(m => m[0].trim());
      if (newDeps.length > 0 && !diff.includes("DECISIONS.md")) {
        checks.push({ id: "UNAPPROVED_DEP", severity: "P1", status: "WARN", detail: newDeps.slice(0, 3).join(", ") });
      }

      // Check 5: LOG.md update check
      const hasSrcChanges = diff.includes("a/src/") || diff.includes("b/src/");
      const hasLogUpdate = diff.includes(".ai/LOG.md");
      if (hasSrcChanges && !hasLogUpdate) {
        checks.push({ id: "NO_LOG_UPDATE", severity: "P1", status: "WARN", detail: "src/ changed but LOG.md not updated" });
      }

      // Check 6: Test file existence for modified src/ files
      const changedSrcFiles = [...diff.matchAll(/^\+\+\+ b\/(src\/[^\n]+)$/gm)].map(m => m[1]);
      const missingTests = [];
      for (const f of changedSrcFiles) {
        if (f.endsWith(".md")) continue; // Skip markdown
        if (f.includes("/agents/") || f.includes("/skills/")) continue; // Skip agent/skill docs
        // Check if a test suite likely covers this
        const testsDir = resolve(cwd, "tests/suites");
        if (existsSync(testsDir)) {
          const base = f.split("/").pop().replace(/\.[^.]+$/, "").replace(/-/g, "_");
          const hasTest = existsSync(resolve(testsDir, `${base}_test.sh`));
          // Also check by parent dir name
          const parentDir = f.split("/").slice(-2, -1)[0];
          const hasParentTest = existsSync(resolve(testsDir, `${parentDir}_test.sh`))
            || existsSync(resolve(testsDir, `${parentDir}_integration_test.sh`));
          if (!hasTest && !hasParentTest) {
            missingTests.push(f);
          }
        }
      }

      const p0Failures = checks.filter(c => c.severity === "P0");
      const hasP0 = p0Failures.length > 0;

      // ── Tier 2: Deterministic checks + aligner ──────────────────────────
      if (tier === 2) {
        const lines = [
          `## Review — Tier 2 (${date})`,
          ``,
          `### Deterministic Checks`,
        ];

        if (checks.length === 0) {
          lines.push("✓ All automated checks passed.");
        } else {
          for (const c of checks) {
            lines.push(`- [${c.id}] ${c.severity} ${c.status}: ${c.detail}`);
          }
        }

        lines.push("");
        lines.push("### Blueprint Alignment");
        lines.push("Run `align_diff()` via blueprint-aligner-mcp to complete Tier 2 review.");
        lines.push("");

        if (hasP0) {
          lines.push(`Verdict: **BLOCKED** — ${p0Failures.length} P0 failure(s) found.`);
        } else {
          lines.push("Verdict: Automated checks passed. Awaiting blueprint-aligner result.");
          lines.push("After aligner passes, append to .ai/REVIEWS.md:");
          lines.push("```");
          lines.push(`[ALIGN_PASS] ${date} | [TIER_2] Blueprint aligned`);
          lines.push(`[CRITIC_STAMP] ${date} | [TIER_2] Blueprint aligned`);
          lines.push("```");
        }

        return { content: [{ type: "text", text: lines.join("\n") }] };
      }

      // ── Tier 3: Full analysis + agent dispatch instructions ─────────────
      const lines = [
        `## Review — Tier 3 (${date})`,
        ``,
        `### Phase 1: Deterministic Checks (automated)`,
      ];

      if (checks.length === 0 && missingTests.length === 0) {
        lines.push("✓ All automated security/architecture/dependency checks passed.");
      } else {
        for (const c of checks) {
          lines.push(`- [${c.id}] ${c.severity} ${c.status}: ${c.detail}`);
        }
        if (missingTests.length > 0) {
          lines.push(`- [COVERAGE_GAP] P1 WARN: ${missingTests.length} modified src/ file(s) with no matching test suite: ${missingTests.slice(0, 3).join(", ")}`);
        }
      }

      lines.push("");
      lines.push("### Phase 2: Agent Dispatch (spawn these in parallel)");
      lines.push("");

      if (hasP0) {
        lines.push(`⚠ **${p0Failures.length} P0 failure(s) detected in automated checks.**`);
        lines.push("Fix these BEFORE spawning critic agents.");
        lines.push("");
        for (const f of p0Failures) {
          lines.push(`- **${f.id}**: ${f.detail}`);
        }
      } else {
        lines.push("All automated checks passed. Now spawn the critic team:");
        lines.push("");
        lines.push("```");
        lines.push('Agent("Run the critic_arch agent to audit the codebase and append its stamp to .ai/REVIEWS.md")');
        lines.push('Agent("Run the critic_security agent to audit the codebase and append its stamp to .ai/REVIEWS.md")');
        lines.push('Agent("Run the critic_tests agent to audit the codebase and append its stamp to .ai/REVIEWS.md")');
        lines.push('Agent("Run blueprint-aligner-mcp align_diff(). Append [ALIGN_PASS] or [ALIGN_FAIL] to .ai/REVIEWS.md")');
        lines.push('Agent("Run the security_engineer agent. Append [SEC_CLEARED] to .ai/LOG.md if clear")');
        lines.push("```");
        lines.push("");
        lines.push("### Phase 3: After all agents complete");
        lines.push("Invoke `activate_agent('review_synthesizer')` to aggregate stamps and write [CRITIC_STAMP].");
      }

      lines.push("");
      lines.push(`Files in diff: ${changedSrcFiles.length} src/ files, ${[...diff.matchAll(/^\+\+\+ b\/(.+)$/gm)].length} total`);

      return { content: [{ type: "text", text: lines.join("\n") }] };
    }

    // ── run_intent_cleanup (DEPRECATED E-147) ─────────────────────────────────
    case "run_intent_cleanup":
      return {
        content: [{
          type: "text",
          text: "⚠ DEPRECATED (E-147): run_intent_cleanup is a no-op. UPDATE.md has been removed from AI-OS.\n" +
                "Intent is provided via conversation context. Use `skill: ai-compact` to manage session context instead.",
        }],
      };

    default:
      return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
