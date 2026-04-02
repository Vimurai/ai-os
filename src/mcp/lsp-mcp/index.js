#!/usr/bin/env node
/**
 * lsp-mcp — AI-OS Code Intelligence Layer (E-136, §23)
 *
 * Provides true symbol/type awareness via the TypeScript compiler API.
 * Mandatory for Tier 3 refactors to ensure type safety across boundary changes.
 *
 * Tools:
 *   get_definitions(path, line, col) → jump-to-definition for symbol at position
 *   get_references(path, line, col)  → all usages of symbol at position
 *   get_diagnostics(path)            → real-time type/lint errors for a file
 *
 * Graceful fallback: if TypeScript is not installed, all tools return a clear
 * error message rather than crashing — projects without tsconfig.json still work.
 *
 * Security: spawnSync whitelist enforced — only `npx tsc --noEmit` allowed.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { existsSync, readFileSync } from "fs";
import { resolve, dirname } from "path";
import { createRequire } from "module";
import { spawnSync } from "child_process";

// ── TypeScript Compiler API (optional — graceful fallback if unavailable) ─────

let ts = null;
try {
  const require = createRequire(import.meta.url);
  ts = require("typescript");
} catch {
  // TypeScript not installed — tools will return informative errors
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Locate the nearest tsconfig.json walking up from `filePath`.
 * Returns null if none found.
 */
function findTsConfig(filePath) {
  if (!ts) return null;
  const configPath = ts.findConfigFile(
    dirname(resolve(filePath)),
    ts.sys.fileExists,
    "tsconfig.json"
  );
  return configPath || null;
}

/**
 * Build a TypeScript LanguageService for the project containing `filePath`.
 * Returns null if TypeScript is unavailable or no tsconfig exists.
 */
function buildLanguageService(filePath) {
  if (!ts) return null;

  const configPath = findTsConfig(filePath);
  const rootNames = configPath
    ? (() => {
        const cfg = ts.readConfigFile(configPath, ts.sys.readFile);
        const parsed = ts.parseJsonConfigFileContent(cfg.config, ts.sys, dirname(configPath));
        return parsed.fileNames;
      })()
    : [resolve(filePath)];

  const serviceHost = {
    getScriptFileNames: () => rootNames,
    getScriptVersion: () => "0",
    getScriptSnapshot: (fileName) => {
      if (!existsSync(fileName)) return undefined;
      return ts.ScriptSnapshot.fromString(readFileSync(fileName, "utf8"));
    },
    getCurrentDirectory: () => process.cwd(),
    getCompilationSettings: () => configPath
      ? (() => {
          const cfg = ts.readConfigFile(configPath, ts.sys.readFile);
          const parsed = ts.parseJsonConfigFileContent(cfg.config, ts.sys, dirname(configPath));
          return parsed.options;
        })()
      : ts.getDefaultCompilerOptions(),
    getDefaultLibFileName: (options) => ts.getDefaultLibFilePath(options),
    fileExists: ts.sys.fileExists,
    readFile: ts.sys.readFile,
    readDirectory: ts.sys.readDirectory,
  };

  return ts.createLanguageService(serviceHost, ts.createDocumentRegistry());
}

/**
 * Convert 1-based (line, col) to TS compiler's 0-based offset in a file.
 */
function positionToOffset(filePath, line, col) {
  const src = readFileSync(filePath, "utf8");
  const lines = src.split("\n");
  let offset = 0;
  for (let i = 0; i < line - 1; i++) {
    offset += (lines[i] || "").length + 1; // +1 for \n
  }
  offset += (col - 1);
  return offset;
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "lsp-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_definitions",
      description:
        "Returns the definition location(s) for the symbol at the given file position. " +
        "Requires TypeScript to be installed and a tsconfig.json in the project. " +
        "Use for Tier 3 refactors to verify symbol origins before renaming.",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute or relative path to the TypeScript/JavaScript file." },
          line: { type: "number", description: "1-based line number." },
          col:  { type: "number", description: "1-based column number." },
        },
        required: ["path", "line", "col"],
      },
    },
    {
      name: "get_references",
      description:
        "Returns all usages of the symbol at the given file position. " +
        "Requires TypeScript to be installed and a tsconfig.json in the project.",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute or relative path to the TypeScript/JavaScript file." },
          line: { type: "number", description: "1-based line number." },
          col:  { type: "number", description: "1-based column number." },
        },
        required: ["path", "line", "col"],
      },
    },
    {
      name: "get_diagnostics",
      description:
        "Returns real-time type errors and diagnostics for a TypeScript file. " +
        "Runs tsc --noEmit internally — no files are written. " +
        "Use before committing Tier 2/3 changes to catch type regressions.",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute or relative path to the TypeScript file (or project root for full check)." },
        },
        required: ["path"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const cwd = process.cwd();

  if (!ts) {
    return {
      content: [{
        type: "text",
        text: `[lsp-mcp] TypeScript not available. Install it: npm install --save-dev typescript\n` +
              `Then re-run: ai mcp-setup`,
      }],
    };
  }

  switch (name) {
    // ── get_definitions ──────────────────────────────────────────────────────
    case "get_definitions": {
      const filePath = resolve(cwd, args.path);
      if (!existsSync(filePath)) {
        return { content: [{ type: "text", text: `✗ File not found: ${filePath}` }], isError: true };
      }

      const svc = buildLanguageService(filePath);
      if (!svc) {
        return { content: [{ type: "text", text: "✗ Could not build TypeScript language service. Check tsconfig.json." }], isError: true };
      }

      let offset;
      try { offset = positionToOffset(filePath, args.line, args.col); }
      catch { return { content: [{ type: "text", text: "✗ Could not read file to compute position." }], isError: true }; }

      const defs = svc.getDefinitionAtPosition(filePath, offset) || [];
      if (defs.length === 0) {
        return { content: [{ type: "text", text: `No definitions found at ${args.path}:${args.line}:${args.col}` }] };
      }

      const lines = defs.map(d => {
        const sf = svc.getProgram().getSourceFile(d.fileName);
        const { line, character } = sf
          ? sf.getLineAndCharacterOfPosition(d.textSpan.start)
          : { line: 0, character: 0 };
        return `${d.fileName}:${line + 1}:${character + 1} — ${d.name || "(symbol)"}`;
      });

      return { content: [{ type: "text", text: `Definitions:\n${lines.join("\n")}` }] };
    }

    // ── get_references ───────────────────────────────────────────────────────
    case "get_references": {
      const filePath = resolve(cwd, args.path);
      if (!existsSync(filePath)) {
        return { content: [{ type: "text", text: `✗ File not found: ${filePath}` }], isError: true };
      }

      const svc = buildLanguageService(filePath);
      if (!svc) {
        return { content: [{ type: "text", text: "✗ Could not build TypeScript language service. Check tsconfig.json." }], isError: true };
      }

      let offset;
      try { offset = positionToOffset(filePath, args.line, args.col); }
      catch { return { content: [{ type: "text", text: "✗ Could not read file to compute position." }], isError: true }; }

      const refs = svc.getReferencesAtPosition(filePath, offset) || [];
      if (refs.length === 0) {
        return { content: [{ type: "text", text: `No references found at ${args.path}:${args.line}:${args.col}` }] };
      }

      const lines = refs.map(r => {
        const sf = svc.getProgram().getSourceFile(r.fileName);
        const { line, character } = sf
          ? sf.getLineAndCharacterOfPosition(r.textSpan.start)
          : { line: 0, character: 0 };
        return `${r.fileName}:${line + 1}:${character + 1}${r.isDefinition ? " [def]" : ""}`;
      });

      return { content: [{ type: "text", text: `References (${refs.length}):\n${lines.join("\n")}` }] };
    }

    // ── get_diagnostics ──────────────────────────────────────────────────────
    case "get_diagnostics": {
      const targetPath = resolve(cwd, args.path);

      // Determine if path is a directory (project root) or a single file
      const isFile = existsSync(targetPath) && !targetPath.endsWith("/");

      if (isFile) {
        // Single-file diagnostics via compiler API
        const svc = buildLanguageService(targetPath);
        if (!svc) {
          return { content: [{ type: "text", text: "✗ Could not build TypeScript language service. Check tsconfig.json." }], isError: true };
        }

        const diags = [
          ...svc.getSyntacticDiagnostics(targetPath),
          ...svc.getSemanticDiagnostics(targetPath),
        ];

        if (diags.length === 0) {
          return { content: [{ type: "text", text: `✓ No diagnostics — ${args.path} is type-clean.` }] };
        }

        const lines = diags.map(d => {
          const pos = d.file && d.start != null
            ? (() => {
                const { line, character } = d.file.getLineAndCharacterOfPosition(d.start);
                return `:${line + 1}:${character + 1}`;
              })()
            : "";
          const category = ["warning", "error", "message", "suggestion"][d.category] || "error";
          return `[${category.toUpperCase()}] ${d.file?.fileName || "?"}${pos} — ${ts.flattenDiagnosticMessageText(d.messageText, "\n")}`;
        });

        return { content: [{ type: "text", text: `Diagnostics for ${args.path} (${diags.length}):\n\n${lines.join("\n")}` }] };
      }

      // Project-level: run tsc --noEmit via spawnSync (whitelisted command)
      const tscResult = spawnSync("npx", ["tsc", "--noEmit", "--pretty", "false"], {
        cwd: targetPath,
        encoding: "utf8",
        timeout: 30000,
      });

      const output = (tscResult.stdout || "") + (tscResult.stderr || "");
      if (tscResult.status === 0) {
        return { content: [{ type: "text", text: `✓ No type errors — project is type-clean.` }] };
      }

      return {
        content: [{
          type: "text",
          text: `TypeScript diagnostics:\n\n${output.trim() || "(tsc exited non-zero with no output)"}`,
        }],
      };
    }

    default:
      return { content: [{ type: "text", text: `✗ Unknown tool: ${name}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
