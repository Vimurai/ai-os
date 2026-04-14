<div align="center">
  <img src="https://raw.githubusercontent.com/google/gemini-cli/main/docs/assets/ai-os-logo.png" width="200" alt="AI-OS Logo">
  <h1>🤖 AI-OS: The Autonomous Triad</h1>
  <p><b>A Self-Regulating Framework for AI-Native Software Engineering</b></p>
  <p><i>Stop copy-pasting prompts. Start commanding a self-aware engineering team.</i></p>

  [![Version](https://img.shields.io/badge/version-v3.3-blue.svg)](https://github.com/google/gemini-cli)
  [![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
  [![Tests](https://img.shields.io/badge/tests-407%2F407%20passed-brightgreen.svg)](tests/)
</div>

---

## 🚨 The Core Philosophy

AI-OS is not a prompt library. It is an **autonomous operating system for AI agents** (Claude Code and Gemini CLI). By installing AI-OS, you transform your standalone CLIs into a highly structured, self-regulating team of experts governed by ACID-compliant state and strict architectural sovereignty.

### 🌟 Key Innovations in v3.3
*   **SQLite-First Singularity**: Task synchronization and system state are managed via a centralized, ACID-compliant SQLite database (`.ai/state.sqlite`), eliminating race conditions in multi-agent environments.
*   **Dynamic Context Invocation (JIT)**: Agents automatically load specialized skills and personas (Security, Chaos, DevOps) on the fly. Skills are loaded as **metadata-only** to save tokens until the full logic is required.
*   **Token Economics & OOM Prevention**: Monolithic context is dead. Blueprints are fragmented by domain, and agents use **bounded streams and iterative scanning** to handle massive diffs and log files without crashing.
*   **Role-Based Access Control (RBAC)**: Strict `ANTI_DRIFT_PROTOCOL` interceptors block the Architect (Gemini) from writing source code and the Engineer (Claude) from altering sovereign blueprints.

---

## 🏛️ The Triad Architecture

AI-OS divides cognitive labor into a **Triad**, ensuring small context windows, focused expertise, and robust economics.

| Entity | Intelligence | Sovereignty | Primary Tools |
| :--- | :--- | :--- | :--- |
| **Principal Architect** | **Gemini** | `.ai/blueprints/`, `TASKS.md` | `ai-update`, `ux_template`, `repo-oracle` |
| **Lead Engineer** | **Claude** | `src/`, `tests/` | `patch-mcp` (fuzzy), `lsp-mcp`, `propose-patch` |
| **Quality/QA** | **TestSprite** | `REVIEWS.md`, `LOG.md` | `vibe-check-mcp`, `chaos_monkey`, `lighthouse` |

---

## 🚀 Quick Start (Installer)

### Prerequisites
* macOS/Linux (Bash/Zsh)
* **Node.js 20+** (Required for MCP servers)
* **Python 3.10+** (Required for legacy fallbacks)
* **sqlite3 CLI** (Mandatory for system hooks)

### 1. Global Installation
```bash
git clone <repository-url> ai-os
cd ai-os
./install-ai-os.sh

# Lock in the agent rules, MCPs, and system hooks
ai install
source ~/.zshrc
```

### 2. Project Initialization
Activate the framework in any codebase:
```bash
cd my-cool-project
ai init
```
*This scaffolds the `.ai/` memory, initializes the SQLite state, and installs the Git Pre-commit alignment gates.*

---

## 🔄 The Zero-Friction Workflow

### Step 1: Planning (The Architect)
Launch **Gemini CLI** and describe your intent.
> **You:** "Plan a responsive dashboard with real-time telemetry charts."

**Autonomous Behavior:**
1. Gemini loads `ux_template` and `repo-oracle`.
2. It researches your existing UI patterns using **bounded reads**.
3. It writes a domain blueprint to `.ai/blueprints/frontend.md`.
4. It breaks the plan into `P-##` tickets in the SQLite task store.

### Step 2: Implementation (The Engineer)
Launch **Claude Code** and point it at the tasks.
> **You:** "Implement P-43 through P-45 from TASKS.md."

**Autonomous Behavior:**
1. Claude loads the `frontend` blueprint domain JIT.
2. It writes code using **Fuzzy Patching** to handle minor file drifts without retries.
3. Every action is auto-logged to `.ai/LOG.md` via system hooks.

### Step 3: Validation (The Tester)
Trigger the automated quality gates:
```bash
ai test --vibe    # Runs visual UX audits & Chaos Stress Tests
ai review claude  # Dispatches parallel critics (Arch, Security, Tests)
```

---

## 🔌 The MCP Nervous System

AI-OS is powered by a custom Model Context Protocol (MCP) suite that gives agents "hands" in your system:

*   **`task-synchronizer-mcp`**: The ACID backend coordinating state via SQLite.
*   **`context-invoker-mcp`**: The JIT engine for loading skills and agent personas.
*   **`blueprint-aligner-mcp`**: Prevents "Plan Drift" by diffing work against the Architect's rules.
*   **`safe-exec-mcp`**: An UACS-compliant gate that blocks destructive commands and plaintext secrets.
*   **`vibe-check-mcp`**: Headless Playwright for screenshots, CLS measurements, and accessibility audits.
*   **`patch-mcp`**: High-performance file editing with MD5 optimistic locking and fuzzy fallbacks.

---

## 🛠️ System Utilities (Token Saving)

| Command | Purpose | When to use? |
| :--- | :--- | :--- |
| **`ai digest`** | Compresses project state into a 50-line summary. | When context feels "heavy" or >3 days old. |
| **`ai archive`** | Rotates bloated logs to `.ai/archive/`. | Weekly, or when the `[BLOATED]` warning appears. |
| **`ai sync`** | Updates global skills/agents from the core repo. | After pulling new AI-OS updates. |
| **`ai doctor`** | Verifies SQLite health, MCP connectivity, and hooks. | When something feels broken. |

---

## 📜 Legal & Compliance
AI-OS enforces **§32 Verification Audits**. Every agent and skill must carry valid YAML frontmatter and authorized toolsets. Unsigned or "Ghost" tools are blocked by default.

<p align="center">
  <br>
  <i>AI-OS — Stop typing. Start directing intelligence.</i>
  <br>
  <b>v3.3 "Robustness Singularity" Release</b>
</p>