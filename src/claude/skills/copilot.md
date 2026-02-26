SKILL: Copilot CLI (gh copilot)

Use this skill when the task is purely:
- Generating a shell / bash command you are uncertain about
- Finding the right `gh` CLI invocation for GitHub tasks (PRs, issues, releases, CI)
- Explaining a complex bash pipeline or flag combination
- Quick CLI lookup that does not require code reasoning or architecture judgment

## Invocation

```bash
# Suggest a shell command:
gh copilot suggest "<natural-language task description>" -t shell

# Suggest a gh CLI command:
gh copilot suggest "<task description>" -t gh

# Explain an existing command:
gh copilot explain "<command string>"
```

## Delegation guide

| Use Copilot                          | Use Claude                              |
|--------------------------------------|-----------------------------------------|
| Shell command lookup                 | Code generation, logic, architecture    |
| GitHub API / gh CLI queries          | Security analysis, threat modeling      |
| Build system / package commands      | Complex refactoring, test writing       |
| File system operations (mv/cp/find)  | API design, data modeling               |
| CI trigger / release tagging         | Multi-file implementation               |

## Rules
1. Always confirm the suggested command with the user before executing.
2. Do NOT use Copilot for: code review, security decisions, or architecture.
3. If Copilot is not installed, fall back to Claude's own reasoning — do not block.
4. Availability check: `command -v gh && gh extension list 2>/dev/null | grep -q copilot`

## Install (if missing)
```bash
brew install gh          # macOS
gh auth login
gh extension install github/gh-copilot
gh copilot config        # accept terms, configure telemetry
```
