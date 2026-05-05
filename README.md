<div align="center">
  <h1>AI-OS — The Autonomous Triad</h1>
  <p><b>A self-regulating operating system for AI software engineering agents</b></p>
  <p><i>Stop copy-pasting prompts. Start commanding a structured engineering team.</i></p>

  [![Version](https://img.shields.io/badge/version-v3.2-blue.svg)](#)
  [![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
  [![Tests](https://img.shields.io/badge/tests-686%2F686%20passed-brightgreen.svg)](tests/)
</div>

---

## What AI-OS Is

AI-OS turns Claude Code, Gemini CLI, and TestSprite into a coordinated **Triad** that shares ACID-compliant project memory, enforces role boundaries, and runs deterministic quality gates before any commit.

It is a thin layer on top of the CLIs — no proxy, no cloud — so it works wherever your terminal works.

| Entity | Backed by | Owns | Hard boundary |
| :--- | :--- | :--- | :--- |
| **Principal Architect** | Gemini CLI | `.ai/architect.md`, `.ai/blueprints/`, `P-##` tasks | Cannot write source code |
| **Principal Engineer** | Claude Code | `src/`, `tests/`, `E-##` tasks | Cannot rewrite blueprints |
| **Quality Tester** | TestSprite + chaos/vibe critics | `REVIEWS.md`, `LOG.md` quality stamps | Cannot bypass `[SEC_CLEARED]` |

State lives in `.ai/state.sqlite` (WAL mode), so two agents in two terminals never corrupt the task list.

---

## Highlights

- **20 custom MCP servers** + 3 third-party (`filesystem`, `memory`, `TestSprite`) wired automatically by `ai sync`.
- **SQLite-first task store** with crash-safe writes and per-project isolation (E-15 fix: each `.ai/` gets its own connection).
- **Tiered quality gates** — Tier 1 (docs) skips review, Tier 2 runs blueprint alignment, Tier 3 runs the full critic constellation (arch + security + tests + chaos + vibe).
- **JIT skill loading** via `context-invoker-mcp` — agents pull only the skill bytes they need, keeping context windows small.
- **Anti-drift interceptors** — Architect cannot edit source, Engineer cannot rewrite `architect.md`. Enforced by `context-guardian-mcp`.
- **Sandboxed `computer-use-mcp`** — DISPLAY=`:99`, HOME=`/tmp/computer-use-sandbox`, no host env spread (D-002).

---

## Prerequisites

| Requirement | Why |
| :--- | :--- |
| macOS or Linux (bash/zsh) | The installer and hooks are bash-native. |
| **Node.js 22.5+** | Custom MCP servers use `node:sqlite` (DatabaseSync), which is stable from Node 22.5. Node 20 will boot some servers but not the SQLite-backed ones. |
| **Python 3.10+** | Generates `.mcp.json` from the registry; bash/jq fallback exists. |
| **sqlite3 CLI** | Used by hooks to read `.ai/state.sqlite`. |
| Claude Code and/or Gemini CLI | At least one is required to drive the Triad. |

Optional: `gh` for GitHub issue ingestion, `xdotool` + `Xvfb` on Linux for `computer-use-mcp`.

**Strongly recommended: `tmux`** — see [Recommended Workflow](#recommended-workflow--tmux-split-panes) below. The Triad is designed to run with Gemini CLI and Claude Code side-by-side; tmux makes that ergonomic without juggling terminal tabs.

---

## Recommended Workflow — tmux Split Panes

The `ai` shell CLI is a thin bootloader (install / init / sync / doctor / uninstall). Everything else — planning, review, testing, archive, digest — runs as a prompt or skill *inside* Claude Code or Gemini CLI. The intended UX is to keep both agents open in adjacent panes so you can hand work back and forth without context-switching tabs.

### Prerequisite

```bash
# macOS
brew install tmux

# Debian/Ubuntu
sudo apt install tmux
```

A subscription / install for **Claude Code** and/or **Gemini CLI** is also required — at least one of them is what drives the Triad.

### Layout

```
┌─────────────────────────┬─────────────────────────┐
│  Architect (Gemini CLI) │  Engineer (Claude Code) │
│                         │                         │
│  - blueprints           │  - implements E-## tasks│
│  - P-## tasks           │  - runs skills          │
│  - DIGEST refresh       │  - tests / commits      │
├─────────────────────────┴─────────────────────────┤
│  Bash terminal — `ai sync`, `ai doctor`, git ops  │
└───────────────────────────────────────────────────┘
```

### `~/.tmux.conf` snippet

Drop this into `~/.tmux.conf` (or merge with your existing config) to get a one-command Triad layout:

```tmux
# AI-OS Triad layout — bound to prefix + T
# Produces:  pane 0 top-left (Gemini), pane 2 top-right (Claude), pane 1 bottom (bash)
bind-key T split-window -v -p 30 \; \
           select-pane -t 0 \; \
           split-window -h \; \
           select-pane -t 0 \; \
           send-keys 'gemini' C-m \; \
           select-pane -t 2 \; \
           send-keys 'claude' C-m \; \
           select-pane -t 1

# Sane defaults for split panes
set -g mouse on
set -g pane-border-status top
set -g pane-border-format ' #{pane_index}: #{pane_current_command} '
```

### Starting a session

```bash
cd /path/to/your-project
tmux new-session -s ai-os
# Inside tmux: press your prefix (default Ctrl-b) then T
# Pane 0 (top-left)  → Gemini CLI  (Architect)
# Pane 2 (top-right) → Claude Code (Engineer)
# Pane 1 (bottom)    → bash for `ai *` and git
```

If you don't use the keybinding, you can also start the layout manually:

```bash
tmux new-session -s ai-os -n triad \; \
  split-window -v -p 30 \; \
  select-pane -t 0 \; \
  split-window -h \; \
  select-pane -t 0 \; \
  send-keys 'gemini' C-m \; \
  select-pane -t 2 \; \
  send-keys 'claude' C-m \; \
  select-pane -t 1
# Pane 0 (top-left) → Gemini  | Pane 2 (top-right) → Claude  | Pane 1 (bottom) → bash
```

The bottom pane is plain bash — that's where you run `ai sync` after pulling, `ai doctor` when something feels off, and git commands. The two agent panes are where the actual engineering happens via prompts and skills.

> Non-tmux users: the workflow still works. Just open three terminals — one for each role — and switch between them however your terminal handles it. tmux is recommended, not required.

---

## Onboarding — First Time Install

### 1. Install AI-OS globally
```bash
git clone https://github.com/Vimurai/ai-os.git
cd ai-os
bash install-ai-os.sh         # copies src/ → ~/.ai-os/
ai install                    # writes ~/.claude, ~/.gemini configs + hooks
source ~/.zshrc               # or ~/.bashrc — picks up PATH=~/.ai-os/bin
ai doctor                     # verifies PATH, MCP servers, hooks
```

### 2. Activate the Triad in a project
Two paths, depending on what you have:

**A. New repo (greenfield)**
```bash
cd my-new-project
ai init                       # scaffolds .ai/, .claude/, .gemini/, .mcp.json
# Then fill in:
#   .ai/BRIEF.md       — product goals & non-goals
#   .ai/DIGEST.md      — one-paragraph snapshot
#   .ai/architect.md   — system vision (the Architect will expand this)
```
Open Gemini CLI in the repo and prompt it directly: *"Plan the first feature: <intent>"*. The Architect writes blueprints + P-## tasks.

**B. Existing codebase**
```bash
cd my-existing-repo
ai init                       # safe — only writes files that don't exist
```
Open Gemini CLI and prompt: *"Reverse-engineer this repository — populate `.ai/DIGEST.md`, `.ai/BRIEF.md`, and seed `.ai/architect.md` from the real code. Read at most 6 files."*

### 3. First development loop
```bash
# Bottom pane — confirm setup:
ai doctor

# Top-left pane (Gemini CLI / Architect):
#   Prompt: "Plan a /metrics endpoint with auth and rate-limiting."
#   → Gemini writes .ai/blueprints/, adds P-## tasks to .ai/TASKS.md

# Top-right pane (Claude Code / Engineer):
#   The CLAUDE.md bootloader auto-runs the ai-preflight skill.
#   Prompt: "Implement the open E-## tasks."
#   When done, run: skill: ai-review  → tier-aware critic dispatch
#                   skill: ai-test     → TestSprite E2E (use --vibe for chaos)

# Bottom pane — commit:
git commit                    # pre-commit hook enforces Gate 2
```

---

## Upgrading an Existing Project to a Newer AI-OS Version

You have a project with `.ai/` already initialized, and you've just pulled a newer AI-OS release. Run the upgrade in this order:

```bash
# 1. Update the global install (re-copies src/ → ~/.ai-os/, refreshes MCP code)
cd /path/to/ai-os
git pull
bash install-ai-os.sh

# 2. (Optional but recommended) re-install user configs + hooks
ai install

# 3. In every project that uses AI-OS, sync the project-scoped artifacts
cd /path/to/your-project
ai sync                       # regenerates .mcp.json, .claude/, .gemini/, hooks
ai init                       # safe re-run — only adds missing .ai/ files
ai doctor                     # confirms MCP, hooks, pre-commit are wired
```

What `ai sync` does (and does not do):
- ✅ Updates `CLAUDE.md` and `GEMINI.md` bootloaders to the current version.
- ✅ Regenerates `.mcp.json` from `~/.ai-os/config/registry.json` (preserves your `TestSprite` API key).
- ✅ Refreshes `.claude/agents/`, `.claude/skills/`, `.gemini/agents/`, `.gemini/skills/` and the `_SKILLS_INDEX.md` files.
- ✅ Re-installs git hooks under `~/.ai-os/hooks/`.
- ❌ Does **not** touch `.ai/architect.md`, `.ai/BRIEF.md`, `.ai/TASKS.md`, `.ai/DIGEST.md`, or anything you authored. Your project memory is yours.

If `ai sync` reports schema migrations or new mandatory fields, run `ai migrate-state --force` to re-seed `state.sqlite` from `TASKS.md`.

---

## Daily Workflow — Professional Project Development

```
  Architect (Gemini CLI)    Engineer (Claude Code)    Tester (TestSprite/Critics)
        │                         │                          │
   prompt: plan X            ai-preflight (auto)        skill: ai-test
   skill: blueprint-writer   read DIGEST + TASKS        skill: ai-test --vibe
   → P-## tasks              skill: ai-review --tier N
        │                         │                          │
        └────────► .ai/state.sqlite (single source of truth) ◄────────┘
                              │
                       git commit (Gate 2)
                              │
                         skill: ai-archive   (weekly hygiene)
                         skill: ai-digest    (when stale)
```

### The five phases

| Phase | Owner | How | What happens |
| :--- | :--- | :--- | :--- |
| **1. Plan** | Architect (Gemini) | Prompt the Architect with the intent, e.g. *"Plan a /metrics endpoint with auth"*. Architect uses `blueprint-writer` + `task-planner` skills. | Refreshes DIGEST, reads TASKS, writes blueprint + `P-##` tasks. |
| **2. Implement** | Engineer (Claude) | Open Claude Code; bootloader auto-runs `skill: ai-preflight`. | Engineer reads `E-##` tasks, edits code under `src/` and `tests/`. |
| **3. Validate** | Tester | Inside Claude Code: `skill: ai-test` (or with --vibe for UX + chaos). | TestSprite runs E2E; vibe/chaos critics audit UI; results stamp `REVIEWS.md`. |
| **4. Review** | Engineer | Inside Claude Code: `skill: ai-review` (auto-detects tier). | Dispatches `critic_arch`, `critic_security`, `critic_tests` in parallel for Tier 3. |
| **5. Commit** | Engineer | `git commit` from the bottom tmux pane (pre-commit hook enforces Gate 2). | Hook checks Ghost Tools, frontmatter, `[SEC_CLEARED]` for Tier 3. |

### Mid-task triggers (Claude side)
The bootloader fires these automatically when it detects matching diffs:

| Touched | Skill | Why |
| :--- | :--- | :--- |
| auth, secrets, capabilities | `security_engineer` | Forces threat-model update |
| new dependency | `dependency_gate` | Logs justification + alternatives in `DECISIONS.md` |
| CI/CD config | `ci_gate` | Documents rollback plan in `DEVOPS.md` |
| failing test | `ai-debug` | LOCKS commits until green |
| existing code | `repo-oracle` | Surfaces history before edits |

### Hand-off between agents
```text
# Engineer → Architect (escalate a design question):
skill: ai-handoff             # produces .ai/COMM.md packet, then switch tmux pane

# Architect → Engineer:
# In the Gemini pane, prompt: "Approve P-43 and add E-## breakdown."
# Engineer's next preflight in the Claude pane will surface the unread delta automatically.
```

---

## Command Reference

The shell `ai` CLI is now a thin bootloader. Operational commands run as prompts and skills inside the agent CLIs (see the migration map under `ai` for what moved where).

```text
ai install     Install configs to ~/.gemini, ~/.claude, ~/.config/github-copilot;
               enable agent teams; install hooks. Run after install-ai-os.sh.
ai init        Create or upgrade .ai/ in current repo (idempotent — never overwrites).
ai sync        Re-sync agents, skills, bootloaders, .mcp.json, and hooks
               from ~/.ai-os into the current project.
ai sync --github   Fetch assigned GitHub issues for the Architect cycle (§28).
ai doctor [--repair] [--compliance]
               Diagnose PATH, configs, hooks, MCP. --compliance runs the
               §32 frontmatter audit (Ghost Tool detection).
ai uninstall   Remove the global ~/.ai-os install (project .ai/ stays).
ai version     Print version.
```

Removed in the v3.x cli-collapse — use the agent skill instead:

| Removed shell command | Replacement |
| :--- | :--- |
| `ai update`, `ai onboard` | Open Gemini CLI and prompt the Architect directly |
| `ai preflight` | `skill: ai-preflight` (auto-runs at every Claude session start) |
| `ai digest` | `skill: ai-digest` |
| `ai archive` | `skill: ai-archive` |
| `ai review` | `skill: ai-review` |
| `ai test` / `ai test --vibe` | `skill: ai-test` (use `--vibe` arg for chaos audit) |
| `ai migrate-state` | `mcp__task-synchronizer-mcp__verify_markdown_sync` |
| `ai mcp-setup` | `cd ~/.ai-os && bash install-ai-os.sh` |
| `ai where` | `echo $HOME/.ai-os` |

### Picking the right path

| Situation | What to do |
| :--- | :--- |
| First time on this machine | `bash install-ai-os.sh` then `ai install` |
| New repo, want the Triad | `ai init`, then prompt Gemini to plan the first feature |
| Existing repo, want the Triad | `ai init`, then prompt Gemini to reverse-engineer the codebase |
| Pulled a newer AI-OS version | `bash install-ai-os.sh && ai sync` (in each project) |
| Starting a feature | Prompt Gemini in the Architect pane |
| Need to know what to work on | `skill: ai-preflight` (auto-fires on session start) |
| About to commit | `skill: ai-test` then `skill: ai-review` in Claude |
| Context feels heavy / DIGEST stale | `skill: ai-digest` |
| `LOG.md` over 200 lines | `skill: ai-archive` |
| Something broke | `ai doctor --repair` |
| Auditing skill/agent frontmatter | `ai doctor --compliance` |

---

## The MCP Nervous System (20 custom + 3 third-party)

### State and orchestration
| Server | Purpose |
| :--- | :--- |
| `orchestrator-mcp` | Triad conductor — preflight, handover, review dispatch |
| `task-synchronizer-mcp` | ACID SQLite backend for tasks, stamps, deltas |
| `context-invoker-mcp` | JIT loader for skills and agent personas |
| `archive-manager-mcp` | Context health + LOG/COMM rotation |
| `token-budget-mcp` | Per-session token spend tracking |
| `cache-manager-mcp` | Explicit context cache (mtime-invalidated, prompt-cacheable) |

### Code and file operations
| Server | Purpose |
| :--- | :--- |
| `patch-mcp` | High-perf editor with MD5 optimistic locking + fuzzy fallback |
| `propose-patch-mcp` | Staged patches: preview → confirm/reject before apply |
| `lsp-mcp` | Definitions, references, diagnostics without an IDE |
| `filesystem` (3rd party) | Sandboxed read/write within allowed paths |

### Safety, compliance, and review
| Server | Purpose |
| :--- | :--- |
| `safe-exec-mcp` | UACS gate — blocks destructive shell + secrets in args |
| `risk-analyzer-mcp` | Tier classifier (1/2/3) + required critic dispatch list |
| `context-guardian-mcp` | Role-based access — workspace + agent permission checks |
| `verification-mcp` | §32 audit — Ghost Tool detection, frontmatter validation |
| `blueprint-aligner-mcp` | Diffs implementation vs. blueprint; flags drift |
| `approval-mcp` | HITL gate — human-in-the-loop approval prompts |
| `advisor-mcp` | A2A bridge — Claude queries Gemini Architect mid-execution |

### Intelligence, memory, and integration
| Server | Purpose |
| :--- | :--- |
| `memory` (3rd party) | Knowledge-graph store (entities, relations, observations) |
| `memory-manager-mcp` | Higher-level queries + signature export over the graph |
| `github-bridge-mcp` | Pulls assigned issues, converts them into `P-##` intents |

### Quality, testing, and computer use
| Server | Purpose |
| :--- | :--- |
| `vibe-check-mcp` | Headless Playwright — screenshots, CLS, a11y |
| `TestSprite` (3rd party) | Cloud E2E test generation and execution |
| `computer-use-mcp` | Sandboxed mouse/keyboard/screen for visual QA |

---

## Anatomy of `.ai/`

```
.ai/
  state.sqlite       # ACID source of truth (WAL mode). Never hand-edit.
  state.json         # Mirrored, human-readable view (regenerated post-mutation).
  DIGEST.md          # 50-line project snapshot (refreshed by digest_updater).
  TASKS.md           # P-## (Architect) and E-## (Engineer) tasks.
  architect.md       # System blueprint. Architect-owned.
  blueprints/        # Domain-scoped blueprints (frontend.md, mcp.md, ...).
  BRIEF.md           # Product goals, non-goals, lore.
  RULES.md           # Token economics + Triad contract.
  CAPABILITIES.md    # Allowed read/write/exec paths (Tier 3 gate input).
  REVIEWS.md         # Critic stamps ([SEC_PASS], [ARCH_PASS], ...).
  LOG.md             # Append-only action log. Auto-archived past 200 lines.
  COMM.md            # Hand-off packets between Architect and Engineer.
  SESSION.md         # Per-session preflight stamps.
  archive/YYYY-MM/   # Rotated LOG/COMM/REVIEWS.
```

---

## Troubleshooting

| Symptom | First check | Then |
| :--- | :--- | :--- |
| `ai: command not found` | Is `~/.ai-os/bin` on `PATH`? | `ai doctor` will print the export line. |
| MCP servers fail to start | `ai mcp-setup` (npm install for all servers) | `ai doctor` for connectivity. |
| Pre-commit hook missing | `.git/hooks/pre-commit` exists? | `ai init` re-installs it. |
| State drift across machines | Did you run `ai sync` after `install-ai-os.sh`? | `ai migrate-state --force` re-seeds. |
| Ghost Tool errors at commit | `ai doctor --compliance` | Fix `allowed-tools` in the offending skill/agent frontmatter. |
| DIGEST feels stale | Run `skill: ai-digest` inside Claude or Gemini | Regenerates `.ai/DIGEST.md` from current state. |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, skill/MCP authoring, the test gate, and commit conventions.

---

<p align="center"><i>AI-OS — Stop typing. Start directing intelligence.</i><br/><b>v3.2 — Robustness Singularity</b></p>
