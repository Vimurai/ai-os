<div align="center">
  <h1>🤖 AI-OS v3.2</h1>
  <p><b>A High-Performance, Triad-Based Framework for AI-Native Software Engineering</b></p>
  <p><i>Stop typing code. Start directing intelligence.</i></p>
</div>

---

## 🚨 CRITICAL WARNING: Paradigm Shift

**This framework will fundamentally override your existing development workflow.** 

AI-OS is not a simple helper utility or a code autocomplete tool. It is an entirely new operational paradigm for building software. By adopting AI-OS, you are agreeing to the following absolute laws:

1. **You are no longer the primary typist.** You are the Director and Operator. 
2. **The `.ai/` directory is the Absolute Source of Truth.** If a decision, architecture plan, or task is not written in `.ai/`, *it does not exist*.
3. **Strict Separation of Concerns.** You cannot ask the Engineer (Claude) to design the architecture, and you cannot ask the Architect (Gemini) to write the implementation logic.
4. **No Unverified Commits.** High-risk changes cannot be committed without automated AI reviews, security checks, and visual (Vibe) audits.

If you try to use AI-OS like a standard chat window, you will fail. Read this documentation carefully.

---

## 🏛️ The Triad Architecture

AI-OS divides cognitive labor into a **Triad**, ensuring small context windows, focused expertise, and robust token-saving economics.

| Entity | Intelligence | Role & Domain | Forbidden Actions |
| :--- | :--- | :--- | :--- |
| **Principal Architect** | **Gemini** | Owns the `.ai/` directory. Writes system blueprints (`architect.md`), scopes tasks (`TASKS.md`), and dictates UX/SEO strategy. | **NEVER** writes or edits application source code. |
| **Lead Engineer** | **Claude** | Owns `src/`. Reads blueprints, implements application logic, runs dev servers, and updates `LOG.md` with progress. | **NEVER** starts work without a blueprint. Cannot redefine architecture. |
| **Quality/QA** | **TestSprite / Playwright** | Owns `tests/`. Runs automated E2E tests, visual "Vibe" audits, and Chaos Monkey stress tests. | Cannot modify business logic. |

---

## 🚀 Installation & Setup

AI-OS requires a global installation to configure your AI CLI tools (Claude Code, Gemini CLI), followed by local initialization in your specific project repositories.

### Prerequisites
* macOS/Linux (Bash/Zsh)
* [Node.js](https://nodejs.org/) & `npm` (Required for MCP servers)
* [Python 3](https://www.python.org/)
* `git`

### 1. Global Installation

Clone the AI-OS repository and run the global installer. This will copy the core engine to `~/.ai-os/`, inject AI-OS into your `$PATH`, and configure your `~/.claude/settings.json` and `~/.gemini/settings.json`.

```bash
git clone <repository-url> ai-os-v2
cd ai-os-v2
./install-ai-os.sh
```

**Reload your shell profile:**
```bash
source ~/.zshrc # or ~/.zprofile / ~/.bashrc
```

### 2. Verify Installation
Ensure the global configuration was successful and all MCP dependencies are installed:
```bash
ai doctor
```
*(If any MCP servers show as missing dependencies, run `ai mcp-setup`)*

---

## 📂 Project Integration (Local Setup)

To use AI-OS in an existing or new project, you must initialize it. Navigate to your project's root directory and run:

```bash
cd my-software-project
ai init
```

### What `ai init` actually does:
1. **Scaffolds `.ai/`**: Creates the intelligence directory (`architect.md`, `DIGEST.md`, `UPDATE.md`, `TASKS.md`, `LOG.md`, `RULES.md`).
2. **Git Hooks**: Installs the AI-OS `pre-commit` hook (Gate 2) to block misaligned architectural commits.
3. **Copilot Sync**: Creates `.github/copilot-instructions.md` so standard GitHub Copilot chat knows about your `.ai/` rules.
4. **MCP Configuration**: Generates a `.mcp.json` file in your project root pointing to the AI-OS custom servers.

---

## 🔄 The Core Workflow (How to build software)

Do not just open Claude and say "build me a feature". Follow the AI-OS Lifecycle. Your entry point depends on whether you have a new request or are working from an existing backlog.

### Pathway A: New Request
If you are starting a new feature or task that isn't documented yet:

**Step 1: The Intent (`UPDATE.md`)**
Open `.ai/UPDATE.md` and write your request. Be specific.
* *Bad:* "Fix the login."
* *Good:* "Add: OAuth2 Google Login. Constraints: Must use existing User model. No new UI libraries."

**Step 2: The Intent Gate (`ai update`)**
Run the update command:
```bash
ai update
```
The system will analyze your `UPDATE.md`. If it is too vague, **it will hard-block you**. If it passes, it will classify the risk level (Tier 1, 2, or 3) and generate the exact prompt you must feed to the agent.

### Pathway B: Existing Backlog (`TASKS.md`)
If your task is already defined in `.ai/TASKS.md` (e.g., created during a previous planning session), you can **skip `UPDATE.md` entirely**.
* To plan the task further, open the Gemini CLI directly.
* To execute the task, open Claude Code directly (or run `ai update --force` to bypass the Intent Gate and get a session prompt).

### Step 3: Planning (Architect)
If this is a new feature or architectural change, use Gemini:
1. Provide the intent (or refer to the task in `TASKS.md`).
2. Gemini will research your codebase and write a blueprint into `.ai/architect.md`.
3. Gemini will break the work down into `P-##` tickets in `.ai/TASKS.md`.

### Step 4: Execution (Engineer)
Open Claude Code:
1. Paste the preflight prompt provided by `ai update` (or instruct Claude to read the next task in `TASKS.md`).
2. Claude will read `DIGEST.md`, read the Architect's blueprint, and begin writing source code.
3. As Claude works, it will document its actions in `.ai/LOG.md`.

### Step 5: The Quality Gates
Once code is written, it must be verified before committing.

```bash
ai review claude  # Triggers the Critic Agent to review code against the blueprint
ai test           # Runs standard unit/E2E tests
ai test --vibe    # Runs visual UX audits (Lighthouse/CLS) and Chaos Monkey stress tests
```

---

## 🚄 TSRT: Tiered Session Response Theory

To prevent wasting expensive API tokens on simple tasks (like fixing typos) while maintaining rigorous security for critical tasks, AI-OS enforces **TSRT**. Every session is automatically classified:

* 🟢 **[TIER_1] (Low Risk):** CSS, Documentation, Typos. 
  * *Workflow:* No Architect required. No security agents. Claude fixes and commits directly.
* 🟡 **[TIER_2] (Medium Risk):** Standard Logic, Refactoring, Adding tests. 
  * *Workflow:* Requires Blueprint Aligner to ensure changes match `architect.md`. Requires manual developer approval.
* 🔴 **[TIER_3] (High Risk):** Auth, Secrets, Database Migrations, Core Features.
  * *Workflow:* Full Triad lockdown. Requires Security Engineer threat modeling. Requires `ai test --vibe`. Requires Architect sign-off before Git will allow a commit.

---

## 🔌 Advanced Integrations

### Model Context Protocol (MCP) Nervous System
AI-OS uses custom local MCP servers to give agents safe, scoped access to your machine:
* **`blueprint-aligner-mcp`**: Compares `git diff` against `.ai/architect.md`. Will fail a commit if Claude tries to go rogue.
* **`vibe-check-mcp`**: Uses Headless Playwright to capture screenshots, measure Cumulative Layout Shift (CLS), and run Accessibility audits.
* **`risk-analyzer-mcp`**: Parses human intent to automatically apply the correct TSRT Tier.
* **`context-guardian-mcp`**: Scans the codebase for unresolved `TODO`s or orphaned tasks before allowing a release.

### Git & IDE Integration
* **Pre-commit Hooks:** AI-OS natively integrates with Git. If Claude attempts a Tier 3 commit without a `[UACS_VERIFIED]` stamp in the log, Git will reject the commit.
* **GitHub Copilot:** AI-OS automatically synchronizes project rules into `.github/copilot-instructions.md` so your inline IDE completions match the Architect's vision.

---

## 🛠️ Maintaining the System

Your AI context windows will get bloated if you do not perform maintenance. Use these built-in utilities:

### 1. The Digest (`ai digest`)
`DIGEST.md` is the "Token Saver Cache". It is a highly compressed snapshot of your project's state. If it gets older than 3 days, regenerate it:
```bash
ai digest
```

### 2. Archiving (`ai archive`)
As Claude and Gemini work, `LOG.md`, `COMM.md`, and `REVIEWS.md` will grow massively. To save tokens, rotate them out:
```bash
ai archive
```
This moves historical logs to `.ai/archive/YYYY-MM/` and resets the active files.

### 3. Syncing Updates (`ai sync`)
If you pull a new version of the AI-OS core framework from GitHub, run `ai sync` to update your global agent skills (`~/.claude/skills`, `~/.gemini/skills`, etc.) without wiping out your personal configurations.

---
<p align="center">
  <i>AI-OS — Built for architects who want to build faster. Optimized for agents who need to know why.</i>
</p>
