# BRIEF (Living product brief)

## Product Summary
- What is this? AI-OS is a CLI-based framework that integrates AI agent roles (Gemini as Architect, Claude as Engineer) directly into local codebases. It scaffolds a unified memory `.ai/` directory and installs system-wide hooks.
- Who is it for? Developers using AI agents (Claude Code, GitHub Copilot, Gemini) wanting a structured, token-efficient, and role-separated workflow (The Triad).
- What problem does it solve? Prevents context loss, enforces token discipline, stops AI looping by separating planning (Gemini/Architect) from execution (Claude/Engineer) and testing (TestSprite).

## Goals
- Establish a zero-dependency CLI core that injects the `.ai` memory standard into any codebase.
- Unify multiple LLMs through strict file-based protocol contracts.
- **The 2026 Skills Initiative (Skills 2.0)**: Migrate from flat `.md` files to modular folder-based skills (`skill-name/SKILL.md`) using 3-level progressive disclosure.
- **Missing Agent Onboarding**: Implement the full Triad including `prd_writer`, `ux_reviewer`, `knowledge_architect`, and `chaos_monkey`.

## The Triad Roles
| Role | Identity | Primary Target |
| :--- | :--- | :--- |
| **Architect** | Gemini 2.0 Flash/Pro | `.ai/architect.md`, `.ai/BRIEF.md` |
| **Engineer** | Claude 3.7 Sonnet | `src/`, `hooks/`, `.ai/LOG.md` |
| **Tester** | TestSprite / Playwright | `tests/`, `Vibe Audit` |
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

## Strategic Research: Claude Code Skills Integration

Based on the [Claude Code Skills documentation](https://code.claude.com/docs/en/skills), here is a breakdown of the key concepts, paired with strategic suggestions and questions for our implementation of AI-OS v2.

### 1. Skill Discovery & Structure
**Concept:** 
Skills live in `.claude/skills/<skill-name>/SKILL.md`. They rely on YAML frontmatter (`name`, `description`) at the top of a markdown file to define their identity and metadata, followed by instructional text.
**Architectural Suggestion:**
We should adopt a similarly strict Markdown + Frontmatter structure for our ZeroClaw WASM/HTTP skills (e.g., in `.ai/skills/SKILL.md`). This eliminates the need for complex metadata sidecar files and keeps the instructions colocated with the skill definition.
**Question 1:** Should we enforce a strict `SKILL.md` file naming convention and directory structure for all future ZeroClaw HTTP skills?

### 2. Invocation Control (`disable-model-invocation` & `user-invocable`)
**Concept:**
- `disable-model-invocation: true`: Only the user can run this command (e.g. `/deploy`, `/commit`). The AI cannot autonomously trigger it.
- `user-invocable: false`: The user cannot run this command. It operates as background context or internal triggers only (e.g., legacy system context).
**Architectural Suggestion:**
Adding these access control flags to our frontmatter is crucial for safety and scoping. It prevents the Executor from making unapproved destructive changes, and allows us to feed background context seamlessly.
**Question 2:** Are there specific actions in AI-OS v2 (like deployment scripts or infrastructure changes) that you want strictly designated as `disable-model-invocation: true`?

### 3. Sandboxed Tool Access (`allowed-tools`)
**Concept:**
A skill can restrict which external tools it can access via `allowed-tools: Read, Grep, Glob`.
**Architectural Suggestion:**
This forms an excellent RBAC pattern. Limiting the Executor's toolset *per-skill* prevents hallucinated tool use and escalation of privileges.
**Question 3:** Would you like our blueprint to include a mechanism that parses `allowed-tools` before spawning the executor to execute a skill?

### 4. Advanced Patterns: Dynamic Context Injection
**Concept:**
Using `!command` in the markdown allows the shell to inject dynamic context *before* the LLM sees the prompt (e.g., `Changed files: !git diff --name-only`).
**Architectural Suggestion:**
We can replicate this pattern in ZeroClaw. Before passing the skill prompt to the LLM, the system runs designated fast, read-only bash commands and interpolates the results directly.
**Question 4:** Does dynamic context injection via pre-flight bash commands align with your vision, or do you prefer the Executor to manually run tools during the session?

### 5. Subagents (`context: fork`, `agent: Explore`)
**Concept:**
A skill can run in an isolated environment (`context: fork`) using a specialized subagent profile (`agent: Explore`). This prevents the main context window from being flooded by deep research or parallel tasks.
**Architectural Suggestion:**
We should incorporate an explicit Subagent orchestration model. A task like rewriting a Golang app could be spawned into multiple isolated `context: fork` agents that report back statuses to `.ai/TASKS.md`.
**Question 5:** Should we define specialized agent profiles (e.g., "Researcher", "Tester", "Implementer") in our architecture that skills can explicitly invoke?
