/**
 * mcp-domains.js — Curated domain → MCP-server mapping.
 *
 * Single source of truth shared between:
 *   - mcp-router (E-40): progressive tool discovery surface
 *   - scripts/generate_mcp_docs.js (E-52): auto-generates .ai/blueprints/mcp.md
 *
 * Update this map whenever a new server is added to src/config/registry.json.
 * The CI test tests/suites/mcp_doc_sync_test.sh fails if mcp.md falls out of
 * sync with the generator output, so any change here must be paired with a
 * regenerated mcp.md commit.
 */

export const DOMAINS = {
  State: {
    description: "State and task management — TASKS.md, state.json, archives, semantic memory.",
    servers: [
      "task-synchronizer-mcp",
      "orchestrator-mcp",
      "archive-manager-mcp",
      "memory",
      "memory-manager-mcp",
    ],
  },
  Code: {
    description: "Code intelligence and editing — filesystem, LSP, atomic patching.",
    servers: ["filesystem", "lsp-mcp", "patch-mcp", "propose-patch-mcp"],
  },
  Safety: {
    description: "Pre-execution safety gates — command analysis, scope checks, risk classification, agent verification.",
    servers: [
      "safe-exec-mcp",
      "context-guardian-mcp",
      "risk-analyzer-mcp",
      "verification-mcp",
    ],
  },
  Intelligence: {
    description: "Skill/agent loading, blueprint alignment, GitHub bridge, token budgeting.",
    servers: [
      "context-invoker-mcp",
      "blueprint-aligner-mcp",
      "github-bridge-mcp",
      "token-budget-mcp",
    ],
  },
  Quality: {
    description: "Test generation, visual audit, OS-level computer use.",
    servers: ["TestSprite", "vibe-check-mcp", "computer-use-mcp"],
  },
  Interop: {
    description: "A2A bridge to Gemini and HITL approval gate.",
    servers: ["advisor-mcp", "approval-mcp"],
  },
  Caching: {
    description: "Explicit Context Cache for blueprint-heavy prompts.",
    servers: ["cache-manager-mcp"],
  },
  Compute: {
    description: "Sandboxed code execution — ephemeral Docker REPL for Python and Node.",
    servers: ["code-execution-mcp"],
  },
};

// E-52: classify a server by domain. Servers not in any DOMAINS list are
// reported under "Routing & Misc" by the doc generator. mcp-router itself
// lives here intentionally — it orchestrates other domains rather than
// belonging to one.
export function domainForServer(serverName) {
  for (const [domain, def] of Object.entries(DOMAINS)) {
    if (def.servers.includes(serverName)) return domain;
  }
  return null;
}
