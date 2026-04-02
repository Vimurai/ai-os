<div align="center">
  <h1>🤖 AI-OS v3.2: The Autonomous Triad</h1>
  <p><b>A Self-Regulating Framework for AI-Native Software Engineering</b></p>
  <p><i>Don't copy-paste prompts. Command a self-aware engineering team.</i></p>
</div>

---

## 🚨 The Core Philosophy

AI-OS is not a prompt library. It is an **autonomous operating system for AI agents** (Claude Code and Gemini CLI). By installing AI-OS, you are transforming your standalone CLIs into a highly structured, self-regulating team of experts.

**Key Innovations in v3.2:**
1. **Dynamic Context Invocation:** Claude and Gemini automatically load specialized skills and agent personas (like the Security Engineer or Chaos Monkey) into their context on the fly using the custom `context-invoker-mcp`.
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
> Running `ai init` configures project-scoped `.claude/settings.json` and `.gemini/settings.json` to enforce strict AI-OS rules, injects MCP servers, and installs auto-logging hooks.

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

You don't need to manually fill out forms or copy-paste giant prompts. Because of the `context-invoker-mcp`, the LLMs know how to use their tools automatically.

### Step 1: Planning (The Architect)
Open your terminal and launch the Gemini CLI. Tell the Architect what you want.

> **You:** "Plan a new OAuth2 login flow using our existing user models."

**What happens automatically:**
1. Gemini dynamically loads the `ai-update` and `repo-oracle` skills into its context.
2. It researches your codebase constraints.
3. It drafts a technical blueprint in `.ai/architect.md`.
4. It creates actionable `P-##` tickets in `.ai/TASKS.md`.

### Step 2: Execution (The Engineer)
Exit Gemini and launch Claude Code. Tell the Engineer to get to work.

> **You:** "Execute the next open ticket in TASKS.md."

**What happens automatically:**
1. Claude reads the project `DIGEST.md` and the Architect's blueprint.
2. Claude writes the source code and runs local dev servers to verify it.
3. **The Hooks Fire:** As Claude works, the `post-tool-log.sh` hook automatically records every shell command and file edit into `.ai/LOG.md`. When you stop the session, `stop-hook.sh` stamps `.ai/SESSION.md`.

### Step 3: Automated Quality Gates
Before you commit, the system enforces safety and architectural alignment. 

You can trigger these via terminal commands (which output the exact validation prompts for the agents to run):
```bash
ai review claude  # Triggers Claude to run the blueprint-aligner-mcp on its own diff
ai test           # Runs the test suite via TestSprite
ai test --vibe    # Runs visual UX audits (Lighthouse/CLS) and Chaos Monkey stress tests
```
*If a high-risk (Tier 3) feature is built, Git will actively reject your commit until the Security Engineer agent stamps `[SEC_CLEARED]` in the logs.*

---

## 🔌 The MCP Nervous System

AI-OS operates autonomously because it is powered by a custom Model Context Protocol (MCP) suite. These aren't just instructions; they are executable tools the agents use on themselves:

* **`context-invoker-mcp`**: The core engine that allows Claude and Gemini to dynamically fetch specialized personas (`security_engineer`, `chaos_monkey`) and skills without manual prompting.
* **`blueprint-aligner-mcp`**: A tool Claude uses to `git diff` its own work against Gemini's `architect.md` to ensure it didn't drift from the plan.
* **`vibe-check-mcp`**: Allows agents to spin up Headless Playwright, capture screenshots, measure Cumulative Layout Shift (CLS), and audit contrast.
* **`context-guardian-mcp`**: Scans the workspace for unresolved `TODO`s and open tasks, blocking releases until the codebase is clean.

---

## 🛠️ System Maintenance Utilities

To keep token usage low and context windows razor-sharp, run these built-in utilities periodically:

* **`ai digest`**: The Token Saver Cache. Compresses your entire project state into a concise 50-line summary in `DIGEST.md`. Run this if the digest is >3 days old.
* **`ai archive`**: Rotates bloated `LOG.md` and `REVIEWS.md` files into `.ai/archive/YYYY-MM/` and resets the active files.
* **`ai sync`**: When you pull updates from the AI-OS repo, run this to update your global agent skills without wiping your environment.

---
<p align="center">
  <i>AI-OS — Stop typing. Start directing intelligence.</i>
</p>
