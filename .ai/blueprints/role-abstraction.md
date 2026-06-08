# Role Abstraction (CLI-Agnostic Triad)

## Goal & Architecture
**Goal**: Decouple the functional roles (Architect, Engineer, Tester) from specific CLI tools (Gemini CLI, Claude Code, TestSprite), allowing any compatible agent to act in any role. Future-proof the OS for *any* upcoming CLI.
**Architecture**: Introduce a global/local Role Mapping Configuration (`.ai/roles.json`), a **Provider Adapter Registry** (`.ai/providers.json`), and dynamic TMUX pane routing. Update `handoff_control` and `ai-watch` to route semantic roles (`architect`, `engineer`) dynamically.

## Core Concept
Currently, the OS is hardcoded to Gemini = Architect, Claude = Engineer. To support dynamic assignment (e.g., Claude playing both roles via TMUX pane isolation: `claude:1` and `claude:0`), or to drop in a brand new, unknown CLI released next year, we need a **Provider Adapter System**. 
1. **Roles** (What is done) map to **Pane Identifiers** (Where it is done).
2. **Providers** (Who does it) declare their unique config requirements (e.g., where they read MCP settings).

## Components
1. **Role Configuration Store**: A JSON configuration (`.ai/roles.json`) tracking the active provider and pane index for `architect` and `engineer`.
2. **Provider Adapter Registry**: A JSON configuration (`.ai/providers.json` or within `registry.json`) that dictates how a CLI is configured by the OS (e.g., config path, MCP schema format).
3. **Dynamic Bootloader (`src/bin/ai`)**: Parses the Provider Adapter to generate the correct configuration files during `ai init`/`ai sync`, and injects the `AI_OS_CALLER_ROLE` HMAC token.
4. **Semantic Handoff Control**: `ai-watch` reads the `.ai/roles.json` mapping to route `tmux send-keys` signals strictly to the assigned pane, preventing infinite loops when one CLI (e.g., Claude) operates in both panes.

## Data Model

**1. `.ai/roles.json` (Role Mapping):**
```json
{
  "roles": {
    "architect": {
      "provider": "claude",
      "pane_identifier": "1"
    },
    "engineer": {
      "provider": "claude",
      "pane_identifier": "0"
    }
  }
}
```

**2. `.ai/providers.json` (Provider Adapter Schema):**
```json
{
  "providers": {
    "claude": {
      "mcp_config_path": ".claude.json",
      "mcp_key": "mcpServers"
    },
    "agy": {
      "mcp_config_path": ".agents/mcp_config.json",
      "mcp_key": "mcpServers"
    },
    "gemini": {
      "mcp_config_path": ".gemini/settings.json",
      "mcp_key": "mcp_servers"
    }
  }
}
```

## API / Interface Contracts
- **CLI Bootloader**: `ai install --architect claude:1 --engineer claude:0` parses the pane indices, saves them to `.ai/roles.json`, and looks up `claude` in the Provider Registry to know how to install the MCPs.
- **Provider Registration**: `ai provider add <name> --config-path <path> --mcp-key <key>`
- **`handoff_control`**: Accepts `target: "architect" | "engineer"`.

## Security
- Role spoofing remains protected by the HMAC session token (`AI_OS_CALLER_ROLE`). The bootloader still mints the token based on the semantic role map.
- Provider configurations cannot point outside the local repository bounds (no arbitrary path traversal for `mcp_config_path`).

## Execution Constraints
- If a provider acts as both Architect and Engineer, explicit pane indices (e.g. `1` and `0`) MUST be provided so `ai-watch` routes signals safely.

## Rollback Plan
- Delete `.ai/roles.json` and `.ai/providers.json`. Hardcode the fallback mapping: `architect` = `gemini`, `engineer` = `claude`.

## E-## Task Breakdown
- **E-135**: Implement the Role Configuration Store (`.ai/roles.json`) supporting explicit pane indices (`claude:1`, `claude:0`).
- **E-136**: Refactor `task-synchronizer-mcp` to use semantic targets in `handoff_control` and `TASKS.md` generation.
- **E-137**: Update `src/bin/ai-watch` to dynamically map semantic roles to specific `tmux` pane identifiers via `.ai/roles.json`.
- **E-138**: Implement the **Provider Adapter System** (`.ai/providers.json`) in the bootloader (`src/bin/ai`), allowing seamless registration and configuration of new CLI agents.