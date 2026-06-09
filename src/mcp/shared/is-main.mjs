/**
 * is-main.mjs — ESM "run directly vs. imported" detector (E-160).
 *
 * MCP servers start a StdioServerTransport at module top-level. When a unit
 * test `import()`s the server file to exercise its pure helpers, that transport
 * would attach to stdin and the test process would hang forever. Guarding the
 * `server.connect(...)` call with isMainModule(import.meta.url) means the
 * transport only starts when the file is the process entry point (launched as
 * `node .../index.js`), never on import.
 *
 * @param {string} metaUrl  Pass `import.meta.url` from the calling module.
 * @returns {boolean} true when this module is the process entry point.
 */
import { pathToFileURL } from "node:url";

export function isMainModule(metaUrl) {
  const entry = process.argv[1];
  if (!entry) return false;
  return metaUrl === pathToFileURL(entry).href;
}
