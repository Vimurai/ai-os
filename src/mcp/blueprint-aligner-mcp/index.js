#!/usr/bin/env node
/**
 * blueprint-aligner-mcp — AI-OS UACS MCP Server
 * Compares git diff against architect.md rules to detect sovereignty violations,
 * forbidden patterns, and missing blueprint coverage.
 *
 * Tools:
 *   align_diff(diff?, architect_content?) → PASS/FAIL alignment report
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { execSync } from "child_process";
import { readFileSync, existsSync } from "fs";
import { resolve } from "path";

const server = new Server(
  { name: "blueprint-aligner-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "align_diff",
      description:
        "Compares staged git diff against .ai/architect.md rules. Returns PASS or FAIL with specific violations. Intended as a pre-commit gate.",
      inputSchema: {
        type: "object",
        properties: {
          diff: {
            type: "string",
            description: "Git diff text to analyze (optional — reads `git diff --staged` if omitted)",
          },
          architect_content: {
            type: "string",
            description: "architect.md content to check against (optional — reads .ai/architect.md if omitted)",
          },
        },
      },
    },
  ],
}));

// ── Alignment rules ───────────────────────────────────────────────────────────
// Each rule checks the diff for a violation of the System Philosophy.

const ALIGNMENT_RULES = [
  {
    id: "GEMINI_FILE_MODIFIED",
    severity: "FAIL",
    check: (diff) => {
      const geminiFiles = [".ai/architect.md", ".ai/BRIEF.md"];
      return geminiFiles.filter((f) => diff.includes(`a/${f}`) || diff.includes(`b/${f}`));
    },
    message: (violations) =>
      `Claude modified Architect-owned files: ${violations.join(", ")} — Domain Sovereignty violation (§12)`,
  },
  {
    id: "HARDCODED_SECRET",
    severity: "FAIL",
    check: (diff) => {
      const secretPattern = /^\+[^+].*\b(password|passwd|api.?key|secret|token|private.?key)\s*=\s*["'][^"']{4,}/gim;
      const matches = [...diff.matchAll(secretPattern)].map((m) => m[0].trim().slice(0, 60));
      return matches;
    },
    message: (violations) =>
      `Hardcoded secret detected in diff: ${violations[0]}... — Security violation (§5)`,
  },
  {
    id: "CAPABILITIES_BYPASS",
    severity: "FAIL",
    check: (diff) => {
      // Adding ../ path traversal or explicit /etc /root paths in source
      const traversalPattern = /^\+[^+].*(\.\.\/|\/etc\/|\/root\/|\/home\/\w+\/\.)/gm;
      const matches = [...diff.matchAll(traversalPattern)].map((m) => m[0].trim().slice(0, 80));
      return matches;
    },
    message: (violations) =>
      `Path traversal or forbidden path in code: "${violations[0]}" — CAPABILITIES.md violation (§6)`,
  },
  {
    id: "UNAPPROVED_DEPENDENCY",
    severity: "WARN",
    check: (diff) => {
      // New dependency added to package.json without DECISIONS.md entry
      const pkgPattern = /^\+\s+"[a-z@][a-z0-9\-@/.]+"\s*:/gm;
      const newDeps = [...diff.matchAll(pkgPattern)].map((m) => m[0].trim());
      if (newDeps.length === 0) return [];
      // Check if DECISIONS.md is also modified in this diff
      if (diff.includes("DECISIONS.md")) return []; // Decision recorded — OK
      return newDeps.slice(0, 3);
    },
    message: (violations) =>
      `New dependency added without DECISIONS.md entry: ${violations.join(", ")} — Dependency Gate violation`,
  },
  {
    id: "NO_LOG_UPDATE",
    severity: "WARN",
    check: (diff) => {
      const hasSrcChanges = diff.includes("a/src/") || diff.includes("b/src/");
      const hasLogUpdate = diff.includes(".ai/LOG.md");
      if (hasSrcChanges && !hasLogUpdate) return ["src/ changed but LOG.md not updated"];
      return [];
    },
    message: (violations) =>
      `${violations[0]} — Handover Protocol violation (update LOG.md per §12)`,
  },
];

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name !== "align_diff") {
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  }

  // Get diff
  let diff = args.diff;
  if (!diff) {
    try {
      diff = execSync("git diff --staged", { cwd: process.cwd(), encoding: "utf8" });
    } catch {
      diff = "";
    }
  }

  if (!diff.trim()) {
    return {
      content: [{ type: "text", text: "No staged changes found. Nothing to align." }],
    };
  }

  // Get architect.md
  let architectContent = args.architect_content;
  if (!architectContent) {
    const archPath = resolve(process.cwd(), ".ai/architect.md");
    architectContent = existsSync(archPath) ? readFileSync(archPath, "utf8") : "";
  }

  // Run alignment rules
  const failures = [];
  const warnings = [];

  for (const rule of ALIGNMENT_RULES) {
    const violations = rule.check(diff);
    if (violations.length > 0) {
      const entry = { id: rule.id, message: rule.message(violations) };
      if (rule.severity === "FAIL") failures.push(entry);
      else warnings.push(entry);
    }
  }

  // Check if diff touches areas not mentioned in architect.md (orphaned work)
  const changedFiles = [...diff.matchAll(/^\+\+\+ b\/(.+)$/gm)].map((m) => m[1]);
  const orphaned = changedFiles.filter((f) => {
    if (f.startsWith(".ai/")) return false; // Always valid
    const basename = f.split("/").pop().replace(/\.[^.]+$/, "");
    return architectContent && !architectContent.includes(basename);
  });
  if (orphaned.length > 0) {
    warnings.push({
      id: "ORPHANED_WORK",
      message: `Files changed but not mentioned in architect.md: ${orphaned.slice(0, 3).join(", ")} — verify these are covered by a blueprint`,
    });
  }

  const verdict = failures.length > 0 ? "FAIL" : warnings.length > 0 ? "WARN" : "PASS";
  const date = new Date().toISOString().split("T")[0];

  const lines = [
    `## blueprint-aligner-mcp Report — ${date}`,
    `Verdict: ${verdict === "PASS" ? "✓ PASS" : verdict === "WARN" ? "⚠ WARN" : "✗ FAIL"}`,
    `Files analyzed: ${changedFiles.length}`,
    ``,
  ];

  if (failures.length > 0) {
    lines.push("### Failures (Block Commit)");
    failures.forEach((f) => lines.push(`- [${f.id}] ${f.message}`));
    lines.push("");
  }

  if (warnings.length > 0) {
    lines.push("### Warnings (Review Required)");
    warnings.forEach((w) => lines.push(`- [${w.id}] ${w.message}`));
    lines.push("");
  }

  if (verdict === "PASS") {
    lines.push("✓ All changes align with blueprint. Safe to commit.");
  } else if (verdict === "FAIL") {
    lines.push(`Resolve all failures before committing.\nAppend [BLUEPRINT_FAIL] ${date} to .ai/LOG.md.`);
  }

  return { content: [{ type: "text", text: lines.join("\n") }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
