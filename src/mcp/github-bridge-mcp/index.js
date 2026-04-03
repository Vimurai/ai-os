#!/usr/bin/env node
/**
 * github-bridge-mcp — AI-OS GitHub Bridge (E-142, §28)
 *
 * Connects GitHub events to the AI-OS Architect cycle.
 * Fetches assigned issues via `gh` CLI and formats them as P-## task proposals for Gemini.
 *
 * Requires: GitHub CLI (`gh`) installed and authenticated (`gh auth status`).
 *
 * Tools:
 *   fetch_assigned_issues(limit?)         → assigned open issues for current user
 *   get_issue(number)                     → full details of a specific issue
 *   create_intent_from_issues(numbers[])  → formats selected issues as P-## task proposals
 *   get_pr_status(pr?)                    → current PR status / review state
 *   check_gh_auth()                       → verify gh CLI is installed + authenticated
 *
 * Security:
 *   - All gh invocations use spawnSync with explicit arg arrays (no shell injection).
 *   - Only whitelisted gh subcommands used: issue, pr, auth.
 *   - No tokens or credentials are read or stored by this server.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
import { spawnSync } from "child_process";

// ── Helpers ───────────────────────────────────────────────────────────────────

const GH_TIMEOUT = 15000;

/**
 * Run a gh command. Returns { ok, stdout, stderr, status }.
 * WHITELIST: only 'issue', 'pr', 'auth', 'repo' subcommands allowed.
 */
function gh(subcommand, args = []) {
  const allowed = ["issue", "pr", "auth", "repo"];
  if (!allowed.includes(subcommand)) {
    return { ok: false, stdout: "", stderr: `Blocked: gh ${subcommand} is not whitelisted.`, status: 1 };
  }
  const result = spawnSync("gh", [subcommand, ...args], {
    encoding: "utf8",
    timeout: GH_TIMEOUT,
    maxBuffer: 10 * 1024 * 1024,
  });
  const ok = !result.error && result.status === 0;
  return { ok, stdout: result.stdout || "", stderr: result.stderr || "", status: result.status };
}

function ghJson(subcommand, args = []) {
  const r = gh(subcommand, args);
  if (!r.ok) return { ok: false, data: null, error: r.stderr || `gh ${subcommand} failed (exit ${r.status})` };
  try {
    return { ok: true, data: JSON.parse(r.stdout), error: null };
  } catch (e) {
    return { ok: false, data: null, error: `JSON parse error: ${e.message}\nRaw: ${r.stdout.slice(0, 200)}` };
  }
}

function formatIssueForUpdate(issue) {
  return [
    `## Issue #${issue.number}: ${issue.title}`,
    `URL: ${issue.url}`,
    issue.labels?.length ? `Labels: ${issue.labels.map(l => l.name).join(", ")}` : "",
    issue.milestone ? `Milestone: ${issue.milestone.title}` : "",
    "",
    issue.body ? issue.body.slice(0, 1000) : "(no description)",
    "",
  ].filter(l => l !== null).join("\n");
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "github-bridge-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "check_gh_auth",
      description:
        "Verifies that the GitHub CLI (gh) is installed and authenticated. " +
        "Run this first to ensure github-bridge-mcp can reach the GitHub API.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "fetch_assigned_issues",
      description:
        "Fetches open GitHub issues assigned to the current authenticated user. " +
        "Returns issue numbers, titles, labels, and URLs. " +
        "Use to discover work items that should become AI-OS tasks.",
      inputSchema: {
        type: "object",
        properties: {
          limit: { type: "number", description: "Max issues to return (default: 20, max: 50)." },
          repo:  { type: "string", description: "Repo in 'owner/repo' format. Defaults to current repo." },
        },
      },
    },
    {
      name: "get_issue",
      description:
        "Fetches full details (title, body, labels, comments) for a specific GitHub issue. " +
        "Use before create_intent_from_issues to review the full context.",
      inputSchema: {
        type: "object",
        properties: {
          number: { type: "number", description: "Issue number." },
          repo:   { type: "string", description: "Repo in 'owner/repo' format. Defaults to current repo." },
        },
        required: ["number"],
      },
    },
    {
      name: "create_intent_from_issues",
      description:
        "Formats selected GitHub issues as structured P-## task proposals for the Architect (Gemini) cycle. " +
        "Returns formatted issue content with an 'Action Required' prompt — Gemini then creates tasks via add_task. " +
        "Does not write to any file — intent is returned inline for immediate use in conversation.",
      inputSchema: {
        type: "object",
        properties: {
          numbers: {
            type: "array",
            items: { type: "number" },
            description: "Array of issue numbers to include (e.g. [42, 43]).",
          },
          repo: { type: "string", description: "Repo in 'owner/repo' format. Defaults to current repo." },
        },
        required: ["numbers"],
      },
    },
    {
      name: "get_pr_status",
      description:
        "Returns the status of the current branch's PR (or a specified PR number). " +
        "Shows review state, CI checks, and merge readiness.",
      inputSchema: {
        type: "object",
        properties: {
          pr_number: { type: "number", description: "PR number. Omit to use current branch's PR." },
          repo: { type: "string", description: "Repo in 'owner/repo' format. Defaults to current repo." },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const cwd = process.cwd();

  switch (name) {
    // ── check_gh_auth ─────────────────────────────────────────────────────────
    case "check_gh_auth": {
      const version = spawnSync("gh", ["--version"], { encoding: "utf8", timeout: 5000, maxBuffer: 10 * 1024 * 1024 });
      if (version.error || version.status !== 0) {
        return {
          content: [{
            type: "text",
            text:
              "✗ GitHub CLI (gh) not found.\n" +
              "Install: https://cli.github.com/\n" +
              "  macOS:   brew install gh\n" +
              "  Linux:   https://github.com/cli/cli#installation\n\n" +
              "Then authenticate: gh auth login",
          }],
          isError: true,
        };
      }

      const auth = gh("auth", ["status"]);
      const versionStr = version.stdout.split("\n")[0] || "unknown";

      if (!auth.ok) {
        return {
          content: [{
            type: "text",
            text: `✗ gh is installed (${versionStr}) but not authenticated.\nRun: gh auth login`,
          }],
          isError: true,
        };
      }

      return {
        content: [{
          type: "text",
          text: `✓ GitHub CLI ready.\n  Version: ${versionStr}\n  Auth: ${auth.stdout.trim().split("\n")[0] || "authenticated"}`,
        }],
      };
    }

    // ── fetch_assigned_issues ─────────────────────────────────────────────────
    case "fetch_assigned_issues": {
      const limit = Math.min(50, Math.max(1, Number(args.limit) || 20));
      const repoFlag = args.repo ? ["-R", args.repo] : [];

      const r = ghJson("issue", [
        "list",
        "--assignee", "@me",
        "--state", "open",
        "--limit", String(limit),
        "--json", "number,title,labels,url,milestone,updatedAt,body",
        ...repoFlag,
      ]);

      if (!r.ok) {
        return {
          content: [{ type: "text", text: `✗ Failed to fetch issues: ${r.error}` }],
          isError: true,
        };
      }

      const issues = r.data || [];
      if (issues.length === 0) {
        return { content: [{ type: "text", text: "No open issues assigned to you." }] };
      }

      const lines = [`Assigned open issues (${issues.length}):`, ""];
      for (const issue of issues) {
        const labels = issue.labels?.map(l => l.name).join(", ") || "";
        lines.push(`#${issue.number} — ${issue.title}`);
        if (labels) lines.push(`  Labels: ${labels}`);
        lines.push(`  URL: ${issue.url}`);
        lines.push(`  Updated: ${issue.updatedAt?.slice(0, 10) || "?"}`);
        lines.push("");
      }
      lines.push(`To fetch issue content into context: create_tasks_from_issues([${issues.slice(0, 3).map(i => i.number).join(", ")}])`);

      return { content: [{ type: "text", text: lines.join("\n") }] };
    }

    // ── get_issue ─────────────────────────────────────────────────────────────
    case "get_issue": {
      const num = Math.round(Number(args.number));
      if (!num || num < 1) {
        return { content: [{ type: "text", text: "✗ Invalid issue number." }], isError: true };
      }

      const repoFlag = args.repo ? ["-R", args.repo] : [];
      const r = ghJson("issue", [
        "view", String(num),
        "--json", "number,title,body,labels,milestone,url,comments,assignees,state",
        ...repoFlag,
      ]);

      if (!r.ok) {
        return {
          content: [{ type: "text", text: `✗ Failed to fetch issue #${num}: ${r.error}` }],
          isError: true,
        };
      }

      const issue = r.data;
      const lines = [
        `## Issue #${issue.number}: ${issue.title}`,
        `State: ${issue.state} | URL: ${issue.url}`,
        issue.labels?.length ? `Labels: ${issue.labels.map(l => l.name).join(", ")}` : "",
        issue.milestone ? `Milestone: ${issue.milestone.title}` : "",
        issue.assignees?.length ? `Assignees: ${issue.assignees.map(a => a.login).join(", ")}` : "",
        "",
        "### Description",
        issue.body || "(no description)",
      ].filter(l => l !== null);

      if (issue.comments?.length) {
        lines.push("", `### Comments (${issue.comments.length})`);
        for (const c of issue.comments.slice(-3)) {
          lines.push(`**${c.author?.login || "?"}** (${c.createdAt?.slice(0, 10) || "?"}): ${c.body?.slice(0, 200) || ""}`);
        }
        if (issue.comments.length > 3) lines.push(`... and ${issue.comments.length - 3} more`);
      }

      return { content: [{ type: "text", text: lines.join("\n") }] };
    }

    // ── create_intent_from_issues ─────────────────────────────────────────────
    case "create_intent_from_issues": {
      const numbers = (args.numbers || []).map(n => Math.round(Number(n))).filter(n => n > 0);
      if (numbers.length === 0) {
        return { content: [{ type: "text", text: "✗ No valid issue numbers provided." }], isError: true };
      }

      const repoFlag = args.repo ? ["-R", args.repo] : [];
      const fetchedIssues = [];
      const errors = [];

      for (const num of numbers.slice(0, 10)) {
        const r = ghJson("issue", [
          "view", String(num),
          "--json", "number,title,body,labels,milestone,url",
          ...repoFlag,
        ]);
        if (r.ok && r.data) {
          fetchedIssues.push(r.data);
        } else {
          errors.push(`#${num}: ${r.error}`);
        }
      }

      if (fetchedIssues.length === 0) {
        return {
          content: [{ type: "text", text: `✗ Could not fetch any issues.\n${errors.join("\n")}` }],
          isError: true,
        };
      }

      const date = new Date().toISOString().split("T")[0];
      const header = `\n## GitHub Issues — imported ${date}\n\n`;
      const body   = fetchedIssues.map(formatIssueForUpdate).join("\n---\n\n");
      const footer = `\n## Action Required\nGemini (Architect): Review the issues above and create P-## blueprint tasks in state.json using add_task.\n`;

      const lines = [
        `✓ Fetched ${fetchedIssues.length} issue(s):`,
        ...fetchedIssues.map(i => `  #${i.number}: ${i.title}`),
        "",
        header + body + footer
      ];

      if (errors.length) {
        lines.push("", `⚠ Failed to fetch: ${errors.join(", ")}`);
      }

      return { content: [{ type: "text", text: lines.join("\n") }] };
    }

    // ── get_pr_status ─────────────────────────────────────────────────────────
    case "get_pr_status": {
      const repoFlag = args.repo ? ["-R", args.repo] : [];
      const prArgs   = args.pr_number
        ? ["view", String(Math.round(Number(args.pr_number))), "--json", "number,title,state,reviews,statusCheckRollup,url,mergeable", ...repoFlag]
        : ["view", "--json", "number,title,state,reviews,statusCheckRollup,url,mergeable", ...repoFlag];

      const r = ghJson("pr", prArgs);
      if (!r.ok) {
        return {
          content: [{ type: "text", text: `✗ No PR found or gh error: ${r.error}` }],
          isError: true,
        };
      }

      const pr = r.data;
      const checkSummary = (pr.statusCheckRollup || []).map(c =>
        `  ${c.conclusion === "SUCCESS" ? "✓" : c.conclusion === "FAILURE" ? "✗" : "○"} ${c.name || c.context || "check"}: ${c.conclusion || c.state || "pending"}`
      ).join("\n") || "  (no checks)";

      const reviewSummary = (pr.reviews || []).slice(-5).map(r =>
        `  ${r.state} by ${r.author?.login || "?"}`
      ).join("\n") || "  (no reviews)";

      return {
        content: [{
          type: "text",
          text: [
            `## PR #${pr.number}: ${pr.title}`,
            `State: ${pr.state} | Mergeable: ${pr.mergeable || "unknown"}`,
            `URL: ${pr.url}`,
            "",
            "### CI Checks",
            checkSummary,
            "",
            "### Reviews",
            reviewSummary,
          ].join("\n"),
        }],
      };
    }

    default:
      return { content: [{ type: "text", text: `✗ Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
