# BRIEF (Living product brief)

## Product Summary
- What is this? AI-OS is a CLI-based framework that integrates AI agent roles (Gemini as Architect, Claude as Engineer) directly into local codebases. It scaffolds a unified memory `.ai/` directory and installs system-wide hooks.
- Who is it for? Developers using AI agents (Claude Code, GitHub Copilot, Gemini) wanting a structured, token-efficient, and role-separated workflow (The Triad).
- What problem does it solve? Prevents context loss, enforces token discipline, stops AI looping by separating planning (Gemini/Architect) from execution (Claude/Engineer) and testing (TestSprite).

## Goals
- Establish a zero-dependency CLI core that injects the `.ai` memory standard into any codebase.
- Unify multiple LLMs through strict file-based protocol contracts.

## Architecture Notes (Claude-owned)
- Modules/boundaries:
  - `src/bin/ai`: Core CLI for initialization, synchronization, and global installations.
  - `src/hooks/`: Git-like stop and post-tool AI memory lifecycle hooks.
  - `src/templates/`: Local codebase state tracking (DIGEST, BRIEF, TASKS).
  - `src/contracts/`: Core agent rules and discipline guidelines.
  - `src/claude/` & `src/gemini/`: Role-specific agent prompts, skills, and configuration.
- Data model: Pure file-based memory (`.ai/` markdown files).
- Integration points: Integrates with `~/.claude/settings.json`, GitHub Copilot instructions, and MCP server schemas.

## Optimized Workflow Patterns
Based on 2025 best practices, AI-OS v2 implements:
- **Hierarchical Oversight**: Gemini (Architect) designates high-risk tasks for explicit human or secondary-agent approval.
- **Hypothesis-Fix Protocol**: Claude (Engineer) must state a technical hypothesis and expected outcome in `LOG.md` before executing logic changes.
- **Swarm Critique**: The Architect can delegate Claude to "critique" a blueprint, acting as a temporary sub-agent to find design flaws.

## Security & Governance (Architect-owned)
- **"Default-Deny" Tool Registry**: Only MCP servers explicitly signed in `~/.ai-os/registry.json` can be executed with write/execute permissions.
- **Capability Isolation**:
  - **READ**: Filesystem and search tools (Low risk).
  - **WRITE**: Code formatting and local file edits (Isolated in Worktrees).
  - **EXECUTE**: Shell commands and script running (Mandatory User/Architect approval).
- **OAuth Governance**: Third-party integrations must use Architect-managed OAuth flows.
- **Verification Checkpoints**: Every session must end with a `LOG.md` entry that includes a "Security & Integrity" check.
