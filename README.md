<div align="center">
  <h1>🤖 AI-OS v3.2: The Autonomous Triad</h1>
  <p><b>A Self-Regulating Framework for AI-Native Software Engineering</b></p>
  <p><i>Don't copy-paste prompts. Command a self-aware engineering team.</i></p>
</div>

---

## 🚨 The Core Philosophy

AI-OS is not just a prompt library. It is an **autonomous operating system for AI agents** (Claude Code and Gemini CLI). By installing AI-OS, you transform standalone CLIs into a highly structured, self-regulating team of experts.

**Key Innovations in v3.2:**
1. **Dynamic Context Invocation:** Claude and Gemini automatically load specialized skills and agent personas (like `security_engineer` or `chaos_monkey`) into their context on the fly using the custom `context-invoker-mcp`.
2. **Automated State Tracking:** Built-in shell hooks (`stop-hook.sh`, `post-tool-log.sh`) automatically record every action your agents take into `.ai/LOG.md` and stamp `.ai/SESSION.md` when they exit.
3. **The `.ai/` Sovereignty:** The `.ai/` directory acts as the system's "Absolute Memory." If it's not in the `.ai/` blueprints or task lists, the agents are explicitly forbidden from building it.

---

## 🏛️ The Triad Architecture

AI-OS divides cognitive labor into a **Triad**, ensuring small context windows, focused expertise, and robust token-saving economics.

| Entity | Intelligence | Role | Autonomous Behaviors |
| :--- | :--- | :--- | :--- |
| **Principal Architect** | **Gemini** | Owns `.ai/architect.md` and `.ai/TASKS.md`. Designs systems, dictates UX/SEO strategy. | Auto-loads `ux_template` and `ai-update` skills to plan features and split them into tickets. **Never writes code.** |
| **Lead Engineer** | **Claude** | Owns `src/`. Implements the Architect's blueprints. | Auto-loads `claude_tasks` or `devops_engineer` as needed. Updates `LOG.md` automatically via hooks. |
| **Quality/QA** | **TestSprite** | Owns verification. | Runs automated tests, Vibe audits (visual UX), and Chaos Monkey stress tests via MCP. |

---

## 🚀 Installation & Setup

### Prerequisites
* macOS/Linux (Bash/Zsh)
* [Node.js](https://nodejs.org/) & `npm` (Required for MCP servers)
* [Python 3](https://www.python.org/)
* `git`

### 1. Global Installation

> ⚠️ **CAUTION: OVERWRITES EXISTING CONFIGURATIONS**
> Running `ai install` configures `~/.claude/settings.json` and `~/.gemini/settings.json` to enforce strict AI-OS rules, injects MCP servers, and installs auto-logging hooks. **If you have custom CLI setups, use a sandbox first!**

```bash
git clone <repository-url> ai-os-v2
cd ai-os-v2
./install-ai-os.sh

# Lock in the agent rules, MCPs, and system hooks
ai install
```

**Reload your shell profile:**
```bash
source ~/.zshrc # or ~/.zprofile / ~/.bashrc
```

### 2. Verify System Health
Ensure all MCP servers and hooks are online:
```bash
ai doctor
```
*(If any MCP node modules are missing, run `ai mcp-setup`)*

---

## 📂 Project Integration (Local Setup)

To activate the framework in a specific codebase, navigate to the project root and run:

```bash
cd my-software-project
ai init
```

**What happens under the hood:**
* **Memory Scaffold:** Creates the `.ai/` directory (`architect.md`, `DIGEST.md`, `TASKS.md`, `LOG.md`).
* **Git Pre-commit Hook:** Installs Gate 2, blocking any commits that the `blueprint-aligner-mcp` flags as violating the Architect's rules.
* **Copilot Sync:** Generates `.github/copilot-instructions.md` so your IDE's inline Copilot obeys the `.ai/` blueprint.
* **Local MCP Config:** Generates `.mcp.json` pointing to local filesystem, memory, and custom AI-OS servers.

---

## 🔄 The Zero-Friction Workflow

You don't need to manually fill out forms or `UPDATE.md`. Because of the `context-invoker-mcp`, the LLMs know how to use their tools automatically.

### Step 1: Planning (The Architect)
Open your terminal and launch the Gemini CLI. Tell the Architect what you want.

> **You:** "Plan a new OAuth2 login flow using our existing user models."

**What happens automatically:**
1. Gemini dynamically loads its skills to research your codebase constraints.
2. It drafts a technical blueprint in `.ai/architect.md`.
3. It creates actionable `P-##` tickets in `.ai/TASKS.md`.

### Step 2: Execution (The Engineer)
Exit Gemini and launch Claude Code. Tell the Engineer to get to work.

> **You:** "Execute the next open ticket in TASKS.md."

**What happens automatically:**
1. Claude reads the project `DIGEST.md` and the Architect's blueprint.
2. Claude writes the source code and runs local dev servers to verify it.
3. As Claude works, the `post-tool-log.sh` hook automatically records every shell command and file edit into `.ai/LOG.md`.

### Step 3: Quality Gates (Inline vs. Terminal)

Before committing code, you must pass Quality Gates (Testing, Blueprint alignment, Security). You have **two ways** to run these:

#### Option A: Native CLI Skills (Recommended)
You can trigger the testing and review gates *directly from inside* Claude or Gemini using slash commands or natural language, without leaving the chat interface:
* **Inside Claude/Gemini:** `Run the ai-review skill to check my work.`
* **Inside Claude/Gemini:** `Run the ai-test skill to verify this tier 3 feature.`

#### Option B: Terminal Generator Prompts
If you prefer, you can use the external `ai` terminal commands. 
*Note: Commands like `ai review claude` **do not launch the AI directly**. They simply print a highly-optimized prompt to your terminal that you copy and paste into the CLI.*
```bash
ai review claude  # Prints the blueprint-aligner review prompt for you to paste into Claude
ai test           # Executes the local test suite (or TestSprite) directly in the shell
ai test --vibe    # Prints the UX/Chaos audit prompts to paste into Gemini/Claude
```

---

## 🧰 The Agent & Skill Ecosystem

AI-OS automatically provisions your Claude and Gemini CLI tools with specialized personas (Agents) and executable workflows (Skills). The `context-invoker-mcp` allows the LLMs to switch into these modes dynamically.

### 🤖 Agents (Personas & Specialized Roles)
Agents completely alter the LLM's system prompt to focus on a hyper-specific task. 

**Claude Agents:**
* `security_engineer`: Threat-models your changes, checks for secrets, and stamps `[SEC_CLEARED]`. Required for High-Risk (Tier 3) changes.
* `chaos_monkey`: Tries to break your UI by injecting invalid inputs, simulating network latency, and rapid-clicking forms.
* `identity_guardian`: Ensures role-based access controls and auth flows are strictly protected.
* `vibe_sentinel`: Assesses structural integrity during complex merges.
* `devops_engineer`: Sets up CI/CD pipelines, Docker, and deployment configurations.
* `claude_tasks`: Specialized for parsing output and writing structured `E-##` sub-tasks into `TASKS.md`.
* `digest_updater`: Reads `.ai/` history and compresses it into the 50-line `DIGEST.md` snapshot.

**Gemini Agents:**
* `ux_reviewer`: Performs Vibe audits on running dev servers (Performance, CLS, Contrast, Touch Targets).
* `prd_writer`: Takes vague user intent and structures it into rigorous product requirement documents.
* `knowledge_architect`: Scans large codebases to define macro-level domain blueprints.
* `digest_updater`: (Gemini variant) Compresses project memory.
* `gemini_tasks`: Formats the Architect's plans into `P-##` tickets in `TASKS.md`.

### 🛠️ Skills (Executable Workflows)
Skills are procedural guides that tell the LLM exactly *how* to perform a complex multi-step process. You can call them natively using `/skill <name>` or asking the LLM to use them.

**Shared Skills (Available to both):**
* `ai-preflight`: The mandatory session-start sequence (Reads DIGEST -> architect -> TASKS).
* `ai-test`: The workflow for executing automated E2E tests or Vibe/Chaos audits.
* `ai-review`: The Critic Gate workflow. Compares staged code against `architect.md`.
* `ai-archive`: The cleanup sequence that rotates `LOG.md` and `REVIEWS.md` to save context tokens.
* `ai-digest`: The workflow for regenerating the `DIGEST.md` state file.
* `token-miser`: Aggressive context-pruning techniques for long sessions.

**Claude-Specific Skills:**
* `ai-update`: Runs the Intent Gate to start a session.
* `ci_gate`: The required safety checklist before touching GitHub Actions or deployment files.
* `dependency_gate`: The required safety checklist before adding new NPM/Pip packages.
* `obs_baseline`: Injects standardized logging/observability into new features.
* `scope_safety`: Enforces strict boundaries to prevent the LLM from deleting unrelated code.
* `copilot`: Delegates terminal/gh-cli lookups to GitHub Copilot to save main-session tokens.

**Gemini-Specific Skills:**
* `ux_template`: Generates structured UX documentation for mobile/web views.
* `seo_content_checklist`: Audits pages for Title tags, Canonical links, and H1/H2 compliance.
* `repo-oracle`: Uses `git blame` and git history to understand *why* a decision was made in the past.
* `architectural-aligner`: The strict workflow for auditing source code against `architect.md`.

---

## 🔌 The MCP Nervous System

AI-OS operates autonomously because it is powered by a custom Model Context Protocol (MCP) suite. These aren't just instructions; they are executable tools the agents use on themselves:

* **`context-invoker-mcp`**: The engine that allows Claude and Gemini to dynamically fetch the Agents and Skills listed above.
* **`blueprint-aligner-mcp`**: A tool Claude uses to `git diff` its own work against Gemini's `architect.md` to ensure it didn't drift from the plan.
* **`vibe-check-mcp`**: Allows agents to spin up Headless Playwright, capture screenshots, measure Cumulative Layout Shift (CLS), and audit contrast.
* **`context-guardian-mcp`**: Scans the workspace for unresolved `TODO`s and open tasks, blocking releases until the codebase is clean.

---

## 🛠️ System Maintenance Utilities

To keep token usage low and context windows razor-sharp, run these natively in the CLI or from the terminal:

* **`ai digest`**: The Token Saver Cache. Compresses your entire project state into a concise summary. Run this if the digest is >3 days old.
* **`ai archive`**: Rotates bloated log files into `.ai/archive/YYYY-MM/` and resets them.
* **`ai sync`**: When you pull updates from the AI-OS repo, run this to update your global agent skills without wiping your environment.

---
<p align="center">
  <i>AI-OS — Stop typing. Start directing intelligence.</i>
</p>
