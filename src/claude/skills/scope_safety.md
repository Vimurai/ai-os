SKILL: Scope Safety (mandatory — applied to every file/shell operation)

Rules:
- Never read or write outside repo root unless CAPABILITIES.md explicitly allows it.
- Reject any path containing ../ — log it as a P0 security issue.
- Shell execution: only allow commands listed in CAPABILITIES.md (shell.exec).
- Default-deny: if a path or command is not in CAPABILITIES.md, stop and propose a Capability Gate decision.
- The .mcp.json filesystem server enforces these restrictions at the MCP layer — align with it.
- If the PreToolUse secret scan hook blocks a write: do not bypass. Fix the content.
