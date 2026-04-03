# Blueprint: Git Identity Remediation

## The Violation
Commit `d351dc9` (and potentially others) includes a `Co-Authored-By: Claude Sonnet` trailer. This violates the strict Git Identity mandate documented in `.ai/blueprints/security.md`, which states: "Claude MUST NEVER override git identity. No `--author` flags, no `Co-authored-by` trailers."

## The Remediation Plan (Chosen over Ratification)
We will **remediate** this violation rather than ratify it, preserving the integrity of the Git Identity mandate. 

The Engineer (Claude) must implement a safe, automated history rewrite to strip the unauthorized trailers.

### Implementation Steps
1. **Create Remediation Script**: Create `scripts/remediate_git_identity.sh`.
2. **Logic**: Use `git filter-branch --msg-filter` (or `git filter-repo` if preferred/available) to programmatically remove any lines matching `^Co-[Aa]uthored-[Bb]y: Claude` or `^Co-[Aa]uthored-[Bb]y: Gemini` from all commit messages in the current branch.
3. **Execution & Validation**: Run the script. Validate success by running `git log | grep -i "Co-Authored-By: Claude"`. It must return no results.
4. **Cleanup**: Remove the script after successful execution to keep the workspace clean.