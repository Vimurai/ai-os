# Git Hooks Synchronization

## Goal & Architecture
**Goal**: Guarantee that project-level `.git/hooks` always execute the latest canonical AI-OS hook logic without requiring manual synchronization or risking drift.
**Architecture**: Transition from a "copy-by-value" hook installation model to a "call-by-reference" (execution stub) model.

## Core Concept
When a user initializes an AI-OS project (`ai init`), the system currently copies the canonical hook scripts (e.g., `~/.ai-os/hooks/pre-commit.sh`) into the local `.git/hooks/` directory. This creates split-brain drift when the canonical scripts are updated. The core concept is to replace copied files with permanent execution stubs that dynamically invoke the canonical scripts.

## Components
1. **`install_git_hooks` (Installer in `src/bin/ai`)**
   - Responsibility: Modify the `ai init` process to write an execution stub to `.git/hooks/` instead of using `cp`. If chaining with an existing hook, the wrapper must also call the canonical path dynamically.
2. **Hook Execution Stub**
   - Responsibility: A minimal bash script placed in `.git/hooks/` that passes all arguments to the global canonical hook (e.g., `bash ~/.ai-os/hooks/pre-commit.sh "$@"`).
3. **`ai sync` (Drift Upgrader)**
   - Responsibility: Scan the current repository's `.git/hooks/` during `ai sync`. If it detects a legacy copied hook (by checking if the file is a large script rather than a 3-line stub), it automatically upgrades it to the new execution stub.

## Data Model
- **Legacy Hook**: Full bash script copied into `.git/hooks/pre-commit`.
- **Execution Stub**: 
  ```bash
  #!/usr/bin/env bash
  # AI-OS Execution Stub
  bash "$HOME/.ai-os/hooks/pre-commit.sh" "$@" || exit 1
  ```

## API / Interface Contracts
- **Input**: Git hook arguments (passed natively by `git`).
- **Output**: Exit code `0` (success) or `1` (blocked).
- The stub MUST preserve standard input and arguments (`"$@"`) to ensure hooks like `commit-msg` or `pre-push` function correctly if added in the future.

## Security
- **Trust Boundary**: The local project delegates execution to `~/.ai-os/hooks/`. Since `~/.ai-os/` is managed by the AI-OS installer and owned by the user, this maintains the existing trust model.
- **Path Resolution**: The stub must use an absolute path (e.g., via `$HOME/.ai-os/`) to prevent path injection or ambiguity.

## Execution Constraints
- The stub must add near-zero latency to the Git workflow.
- It must gracefully handle cases where `~/.ai-os/hooks/pre-commit.sh` is temporarily missing (e.g., echo a warning and exit 0 to fail open, or exit 1 to fail closed depending on security posture; defaulting to fail closed for Gate 2).

## Rollback Plan
- To revert, users can manually delete the `.git/hooks/pre-commit` file, or a future `ai doctor --fix` could restore legacy behavior if required.

## E-## Task Breakdown
- **E-41**: Update `install_git_hooks` in `src/bin/ai` to generate execution stubs instead of copying files, and implement the auto-upgrade logic in `do_sync()`.
