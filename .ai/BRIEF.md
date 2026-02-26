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

## Security/DevOps Notes (Claude-owned)
- Secrets: No secrets managed. Relies on existing API keys in host tools.
- Deployment: Bash-based installation via `install-ai-os.sh` to `~/.ai-os`, altering `~/.zshrc` and global tool configurations.
