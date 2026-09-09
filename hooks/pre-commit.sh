#!/usr/bin/env bash
# AI-OS Gate 2 — Quality Gate (pre-commit hook)
# Logic: Block git commit if no recent [CRITIC_STAMP] exists in .ai/REVIEWS.md.
# Action: Print the 'ai review claude' critic prompt and exit 1.
# Install: ai init copies this to .git/hooks/pre-commit in the project repo.

# ── E-223 (D-057 §3): install-first helper resolution ────────────────────────
# The locators below used to start at "$(git rev-parse --show-toplevel)/src/...", which
# names the USER's repository, not the AI-OS install. Any project containing
# src/mcp/safe-exec-mcp/index.js had THAT file executed by node from inside this hook,
# with its stdout trusted to decide whether a write is allowed — cloning a repo was
# enough to run its code and disable the gate meant to stop it.
#
# Bootstrapping the shared resolver must not repeat the mistake, so it is install-mirror
# first and script-relative second — never the visited repo.
# The env here may have been chosen by the repo we are visiting (a project's
# .claude/settings.json `env` block is inherited by hooks), so AI_OS_HOME is NOT read:
# pointing it at a decoy made this bootstrap SOURCE the decoy's own locate.sh, i.e.
# arbitrary shell inside a fail-closed gate. Assigned here, in the hook's own text, so it
# overrides anything inherited.
# Exported so a child process — an `ai` subcommand spawned from this hook — inherits
# the same judgement rather than defaulting back to trusting the environment.
export AI_OS_LOCATE_UNTRUSTED_ENV=1
_AI_OS_HOME_DIR="${HOME}/.ai-os"
# The guard below asks `declare -f ai_os_locate`, which means "is a name defined", NOT
# "did my source succeed". bash imports exported functions from the environment at
# startup, so an inherited `ai_os_locate` satisfies it, the safe inline fallback is never
# installed, and the attacker's function IS the resolver — reachable whenever
# shared/locate.sh is absent, i.e. exactly the degraded install the fallback exists for.
unset -f ai_os_locate ai_os_locate_enable_dev_tree ai_os_is_framework_clone 2>/dev/null || true
for _l in "${_AI_OS_HOME_DIR}/shared/locate.sh" \
          "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/../src/shared/locate.sh"; do
  [[ -f "$_l" ]] && { . "$_l"; break; }
done
# Fail-open: these hooks must still run without the resolver (a missing helper is a
# degraded gate, an aborted hook is a broken session). The fallback is the install
# mirror alone — it never falls back to the visited repo.
if ! declare -f ai_os_locate >/dev/null 2>&1; then
  ai_os_locate() { local _c="${_AI_OS_HOME_DIR}/${1}"; [[ -f "$_c" ]] && { printf '%s' "$_c"; return 0; }; return 1; }
fi

AI_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.ai"

# Not an AI-OS project — skip gate entirely
[[ -d "$AI_DIR" ]] || exit 0

REVIEWS_FILE="${AI_DIR}/REVIEWS.md"
MAX_AGE_DAYS=7

# ── Helper: check for a recent [CRITIC_STAMP] ────────────────────────────────
has_recent_critic_stamp() {
  [[ -f "$REVIEWS_FILE" ]] || return 1

  # Extract all CRITIC_STAMP dates (format: [CRITIC_STAMP] YYYY-MM-DD | ...)
  while IFS= read -r line; do
    if [[ "$line" =~ \[CRITIC_STAMP\][[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      stamp_date="${BASH_REMATCH[1]}"
      # Calculate age in days
      stamp_epoch=$(date -j -f "%Y-%m-%d" "$stamp_date" "+%s" 2>/dev/null \
                    || date -d "$stamp_date" "+%s" 2>/dev/null || echo 0)
      now_epoch=$(date "+%s")
      age_days=$(( (now_epoch - stamp_epoch) / 86400 ))
      if [[ $age_days -le $MAX_AGE_DAYS ]]; then
        return 0
      fi
    fi
  done < "$REVIEWS_FILE"

  return 1
}

# ── E-238 (D-062): conflict-marker + .ai/*.json parse gate ───────────────────
#
# On 2026-09-09 a conflicted `git stash pop` left conflict markers inside
# .ai/state.json. Git reported the conflict; the file was staged and committed to master
# unread (44243bc). Master carried INVALID JSON for four commits, and every task read goes
# through that file. Two cheap, deterministic checks would have stopped it.
#
# MATCHING IS ANCHORED AT LINE START, and that is the whole difficulty. This repository's
# own prose QUOTES these markers — .ai/DECISIONS.md documents the gate using them inside
# backticks — so a substring search would make the gate reject the document describing it.
# That is the same trap E-224 hit when a P0 blocked the Architect's text for quoting the
# example it was defining.
#
# `=======` is deliberately NOT sufficient on its own: exactly seven '=' at line start is
# also a valid Markdown setext H2 underline. It counts only in a file that ALSO carries an
# unambiguous `<<<<<<< ` or `>>>>>>> ` marker. Rejecting on it alone would fail any
# document that happens to underline a heading.
_conflict_marker_gate() {
  local staged f bad=0
  staged="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)"
  [[ -z "$staged" ]] && return 0

  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    # Binary files have no lines to inspect and grep would be noise.
    if ! git diff --cached --numstat -- "$f" 2>/dev/null | grep -qv '^-'; then
      continue
    fi
    # The unambiguous halves: 7 markers followed by a space+label, or alone on the line.
    if grep -nE '^(<<<<<<<|>>>>>>>)( .*)?$' -- "$f" >/dev/null 2>&1; then
      echo "  ✗ ${f}: contains a git conflict marker at line start" >&2
      grep -nE '^(<<<<<<<|>>>>>>>)( .*)?$' -- "$f" 2>/dev/null | head -3 | sed 's/^/      /' >&2
      bad=1
    fi
  done <<< "$staged"

  if [[ "$bad" -eq 1 ]]; then
    echo "" >&2
    echo "  A conflicted merge/rebase/stash was staged without being resolved." >&2
    echo "  Open each file above, resolve it, and stage the NAMED paths (not 'git add -A')." >&2
    echo "  D-062: move bookkeeping between branches by commit + cherry-pick, never stash." >&2
    echo "  Rollback (only if you are certain): AI_OS_SKIP_CONFLICT_GATE=1" >&2
    return 1
  fi
  return 0
}

# A staged .ai/*.json that does not parse is the specific damage D-062 was ruled over:
# state.json is the store every task read goes through, and a fresh clone fails outright.
_ai_json_parse_gate() {
  command -v python3 >/dev/null 2>&1 || return 0
  local staged f bad=0
  staged="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '^\.ai/.*\.json$' || true)"
  [[ -z "$staged" ]] && return 0

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # Read the STAGED blob, not the worktree file: what is being committed is what matters,
    # and the two differ whenever only part of a file is staged.
    if ! git show ":${f}" 2>/dev/null | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
      echo "  ✗ ${f}: staged content is not valid JSON" >&2
      git show ":${f}" 2>/dev/null | python3 -c 'import json,sys
try:
    json.load(sys.stdin)
except Exception as e:
    print("      " + str(e))' 2>/dev/null >&2
      bad=1
    fi
  done <<< "$staged"

  if [[ "$bad" -eq 1 ]]; then
    echo "" >&2
    echo "  .ai/*.json is machine state — an unparseable file breaks every task read and" >&2
    echo "  fails a fresh clone outright (D-062; master carried invalid JSON for 4 commits)." >&2
    echo "  Rollback (only if you are certain): AI_OS_SKIP_CONFLICT_GATE=1" >&2
    return 1
  fi
  return 0
}

if [[ "${AI_OS_SKIP_CONFLICT_GATE:-0}" != "1" ]]; then
  echo "Conflict-marker + .ai JSON gate (E-238)..."
  _cm_ok=0
  _conflict_marker_gate || _cm_ok=1
  _ai_json_parse_gate   || _cm_ok=1
  if [[ "$_cm_ok" -ne 0 ]]; then
    echo "[COMMIT_BLOCKED] E-238 gate" >&2
    exit 1
  fi
  echo "  ✓ no conflict markers; staged .ai/*.json parses"
fi

# ── E-96: Markdown-as-Read-Only sync check (BLOCKING) ────────────────────────
check_markdown_sync() {
  local SQLITE_FILE="${AI_DIR}/state.sqlite"
  local TASKS_FILE="${AI_DIR}/TASKS.md"
  [[ -f "$TASKS_FILE" ]] || return 0  # skip if TASKS.md missing

  # Check 1: Verify TASKS.md has the generated header (indicates it wasn't hand-edited)
  if ! head -1 "$TASKS_FILE" 2>/dev/null | grep -q "Generated from state.json"; then
    cat >&2 <<'SYNC_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  TASKS.md is missing the generated header.                              ║
║  It may have been hand-edited, violating the Read-Only contract.        ║
║                                                                          ║
║  Fix: run `ai migrate-state --force` to regenerate TASKS.md from        ║
║       state.json, then re-stage and commit.                              ║
╚══════════════════════════════════════════════════════════════════════════╝

SYNC_BLOCK
    exit 1
  fi

  # Check 2: Compare task count in state.sqlite vs TASKS.md checkbox lines (P-30)
  if [[ -f "$SQLITE_FILE" ]] && command -v sqlite3 &>/dev/null; then
    local STATE_COUNT TASKS_COUNT STATE_STAMPS
    STATE_COUNT=$(sqlite3 "$SQLITE_FILE" "SELECT COUNT(*) FROM tasks" 2>/dev/null || echo 0)
    STATE_STAMPS=$(sqlite3 "$SQLITE_FILE" "SELECT COUNT(*) FROM stamps" 2>/dev/null || echo 0)
    TASKS_COUNT=$(grep -c '^\- \[' "$TASKS_FILE" 2>/dev/null || echo 0)

    local DRIFT=$(( STATE_COUNT - TASKS_COUNT ))
    # Allow ±2 drift (in-flight regeneration window); block on larger divergence
    if [[ $DRIFT -lt 0 ]]; then DRIFT=$(( -DRIFT )); fi
    if [[ $DRIFT -gt 2 ]]; then
      cat >&2 <<SYNC_BLOCK2

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  TASKS.md task count (${TASKS_COUNT}) diverges from state.json (${STATE_COUNT}).         ║
║  Drift: ${DRIFT} tasks — exceeds allowed tolerance of ±2.                   ║
║                                                                          ║
║  Fix: run \`ai migrate-state --force\` to resync, then re-stage + commit. ║
╚══════════════════════════════════════════════════════════════════════════╝

SYNC_BLOCK2
      exit 1
    fi

    # Check 3 (E-100): REVIEWS.md header check — only when state.json has stamps
    if [[ "$STATE_STAMPS" -gt 0 ]]; then
      local REVIEWS_FILE="${AI_DIR}/REVIEWS.md"
      if [[ -f "$REVIEWS_FILE" ]]; then
        if ! head -1 "$REVIEWS_FILE" 2>/dev/null | grep -q "Generated from state.json"; then
          cat >&2 <<'REVIEWS_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  REVIEWS.md is missing the generated header but state.json has stamps.  ║
║  REVIEWS.md may have been hand-edited, violating the Read-Only contract.║
║                                                                          ║
║  Fix: regenerate REVIEWS.md via task-synchronizer-mcp::writeState, or   ║
║       run `ai migrate-state --force` to resync, then re-stage + commit. ║
╚══════════════════════════════════════════════════════════════════════════╝

REVIEWS_BLOCK
          exit 1
        fi

        # Check 4 (E-113): Block if REVIEWS.md has manually-appended sections
        # Generated REVIEWS.md uses only [STAMP] lines — any ## heading signals hand-editing
        if grep -qE "^#{2,}" "$REVIEWS_FILE" 2>/dev/null; then
          cat >&2 <<'APPEND_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: SYNC GATE — COMMIT BLOCKED                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  REVIEWS.md has manually-appended sections (## headings detected).      ║
║  D-001: REVIEWS.md is a generated view — direct edits are forbidden.   ║
║                                                                          ║
║  Fix: run `ai migrate-state --force` to regenerate REVIEWS.md from      ║
║       state.json and remove hand-appended content. Then re-stage.       ║
╚══════════════════════════════════════════════════════════════════════════╝

APPEND_BLOCK
          exit 1
        fi
      fi
    fi
  fi
}

check_markdown_sync

# ── E-122: architect.md + src/ co-modification warning (§35) ─────────────────
check_architect_src_comodification() {
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null)

  local has_src=0 has_architect=0
  while IFS= read -r f; do
    [[ "$f" == src/* ]] && has_src=1
    [[ "$f" == .ai/architect.md ]] && has_architect=1
  done <<< "$staged_files"

  if [[ "$has_src" -eq 1 && "$has_architect" -eq 1 ]]; then
    # Allow if LOG.md staged change contains an implementation delta marker
    local log_staged
    log_staged=$(git diff --cached -- .ai/LOG.md 2>/dev/null)
    if echo "$log_staged" | grep -qiE "\[IMPL_DELTA\]|\[APPROVED\]|implementation delta"; then
      return 0
    fi
    cat >&2 <<'ARCH_WARN'

⚠  AI-OS GATE 2: ARCHITECT CO-MODIFICATION WARNING
   Both src/ and .ai/architect.md are staged in the same commit.
   This may indicate the Engineer rewrote the blueprint to match flawed logic (§35).

   If intentional, add an [IMPL_DELTA] marker to .ai/LOG.md explaining the
   approved blueprint update, then re-stage LOG.md before committing.

ARCH_WARN
    # Warning only — does not block (exit 0 continues to Gate 2 check)
  fi
}

check_architect_src_comodification

# ── E-33: Registry drift guard ───────────────────────────────────────────────
# Root cause of 2026-04-27 audit: src/config/registry.json gained a new MCP but
# ~/.ai-os/config/registry.json was never refreshed, so `ai sync` regenerated
# .mcp.json from a stale registry and silently dropped the server.
# Run the targeted drift suite only when registry-relevant files are staged.
check_registry_sync() {
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null)

  local touches_registry=0
  while IFS= read -r f; do
    case "$f" in
      src/config/registry.json|src/templates/.mcp.json|install-ai-os.sh|src/bin/ai)
        touches_registry=1
        ;;
    esac
  done <<< "$staged_files"

  [[ "$touches_registry" -eq 0 ]] && return 0

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local suite="${repo_root}/tests/suites/registry_sync_test.sh"
  [[ -f "$suite" ]] || return 0  # suite missing — nothing to enforce

  local out
  if ! out=$(bash "$suite" 2>&1); then
    cat >&2 <<REGISTRY_BLOCK

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: REGISTRY DRIFT — COMMIT BLOCKED                         ║
╠══════════════════════════════════════════════════════════════════════════╣
║  registry_sync_test.sh failed. The local registry, template .mcp.json,  ║
║  or installer is out of sync — shipping this commit would reproduce     ║
║  the 2026-04-27 silent-drop class of regression.                         ║
║                                                                          ║
║  Fix: run \`bash install-ai-os.sh\` to refresh ~/.ai-os/config/registry, ║
║       then re-run \`bash tests/suites/registry_sync_test.sh\` locally.  ║
╚══════════════════════════════════════════════════════════════════════════╝

REGISTRY_BLOCK
    echo "$out" >&2
    exit 1
  fi
}

check_registry_sync

# ── E-48: MCP Stdout Purity Gate ─────────────────────────────────────────────
# Forbids newly added console.log / console.info calls under src/mcp/. Those
# calls would corrupt the JSON-RPC stdout stream MCP clients parse.
# console.error / stderr writes are permitted (shared NDJSON logger).
check_mcp_stdout_purity() {
  local staged_files
  staged_files=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null)
  echo "$staged_files" | grep -qE '^src/mcp/.*\.(js|mjs|cjs|ts)$' || return 0

  local repo_root checker
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  checker="${repo_root}/tests/lib/mcp_purity_check.sh"
  [[ -f "$checker" ]] || return 0  # checker missing — nothing to enforce

  local out
  if ! out=$(bash "$checker" 2>&1); then
    cat >&2 <<MCP_PURITY_BLOCK

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: MCP STDOUT PURITY — COMMIT BLOCKED                      ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Newly added console.log / console.info found in src/mcp/.              ║
║  MCP servers must keep stdout reserved for JSON-RPC traffic; logging    ║
║  belongs on stderr via the shared NDJSON logger.                        ║
║                                                                          ║
║  Fix: replace with                                                       ║
║      import { createLogger } from "../shared/logger.js";                ║
║      const log = createLogger("my-mcp");                                ║
║      log.info("tool", "message", { extras });                           ║
╚══════════════════════════════════════════════════════════════════════════╝

MCP_PURITY_BLOCK
    echo "$out" >&2
    exit 1
  fi
}

check_mcp_stdout_purity

# ── E-82: Engineering-Standards Gate ────────────────────────────────────────
# Invokes the E-80 standards-checker CLI against the staged diff. The CLI
# encapsulates every rule (file size, mcp stdout purity, secrets, tmp-cruft,
# kebab-case naming, shared-helper reuse) defined in src/shared/standards.json.
#
# Honors the blueprint §Rollback Plan escape hatch: AI_OS_SKIP_STANDARDS=1
# bypasses the gate (the CLI itself also handles this; we short-circuit
# here to skip the subprocess fork entirely).
#
# Per blueprint §Execution Constraints: this gate runs in <200ms on a
# typical commit; the CLI emits its own perf-warn to stderr if exceeded.
check_standards_gate() {
  # Rollback flag — silent skip (CLI prints its own STANDARDS_SKIPPED notice
  # when invoked with the flag, but we don't need to spawn the subprocess
  # at all if it's set).
  if [[ "${AI_OS_SKIP_STANDARDS:-0}" == "1" ]]; then
    return 0
  fi

  # Node 22+ baseline (mirrors E-69 installer guard). If absent, skip the
  # gate rather than break commits — degrade gracefully.
  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$repo_root" ]] || return 0

  # Locator chain (mirrors E-58 / E-65 / E-75 patterns): in-tree → installed.
  local cli=""
  if [[ -f "${repo_root}/scripts/standards.mjs" ]]; then
    cli="${repo_root}/scripts/standards.mjs"
  elif [[ -f "${HOME}/.ai-os/scripts/standards.mjs" ]]; then
    cli="${HOME}/.ai-os/scripts/standards.mjs"
  else
    # Pre-E-80 install: gate not yet wired. Skip rather than fail.
    return 0
  fi

  # Run the CLI from the repo root so its `--staged` git query resolves
  # against the actual project.
  local out rc
  out=$(cd "$repo_root" && node "$cli" check --staged 2>&1)
  rc=$?

  if [[ $rc -eq 0 ]]; then
    return 0
  fi

  cat >&2 <<'STANDARDS_BLOCK'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: ENGINEERING-STANDARDS — COMMIT BLOCKED                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║  scripts/standards.mjs flagged one or more error-severity violations    ║
║  in the staged diff. The full report follows.                            ║
║                                                                          ║
║  Common fixes:                                                           ║
║    • Split files over 1000 lines into focused modules under src/shared/ ║
║    • Replace console.log/info in src/mcp/** with the shared NDJSON      ║
║      logger (src/mcp/shared/logger.js).                                 ║
║    • Remove .tmp / .bak / .swp / .orig editor cruft before staging.    ║
║    • Rename files to kebab-case / camelCase / PascalCase (no            ║
║      Mixed_Snake) for ESM resolver safety.                              ║
║    • Strip leaked secret patterns (AWS / Stripe / Slack / GitHub PATs / ║
║      PRIVATE KEY blocks).                                                ║
║                                                                          ║
║  Rollback (last resort): re-run with AI_OS_SKIP_STANDARDS=1.            ║
╚══════════════════════════════════════════════════════════════════════════╝

STANDARDS_BLOCK
  echo "$out" >&2
  exit 1
}

check_standards_gate


# ── E-214: Architect-scoped Git Lane (architect-provider-parity.md §Git Lane) ──
# A Claude Architect HAS git, unlike agy — so the D-053 proxy-commit workaround (the
# Engineer commits the Architect's .ai/ edits) is no longer needed for a same-provider
# Triad. The ruling: an Architect may commit ONLY when every staged path is under
# .ai/ or plans/. Anything else is implementation work and belongs to the Engineer.
#
# ROLE RESOLUTION — record first, env fallback. A git hook receives no PreToolUse
# payload, but Claude Code exports CLAUDE_CODE_SESSION_ID, so the hook can resolve the
# same HMAC-verified role record the Bash and Write gates use (safe-exec --verify-role,
# E-214) rather than trusting the mutable env. AI_OS_PANE_ROLE / AI_OS_CALLER_ROLE are
# the fallbacks; absent everything, the role is `engineer` and NOTHING below changes.
#
# HONEST SCOPE: when the record is unavailable this degrades to env, which an Architect
# session could unset — the same limitation the E-208 write gate carries. This lane's
# value is that it is the LAST checkpoint before history, and it catches the accidental
# case (which is the realistic one) deterministically.
#
# Rollback: AI_OS_SKIP_GIT_LANE=1.
ARCHITECT_SCOPED=0

# Prints "<source>:<role>", where source is "record" or "env".
#
# It PRINTS both rather than setting a global: the caller invokes this in a command
# substitution, so any variable assigned inside is set in the SUBSHELL and lost. That
# is not hypothetical — the first cut of this change set ROLE_SOURCE internally and the
# waiver silently never fired, because the parent always saw the default.
#
# E-218 (D-055 R4): the two are NOT interchangeable. The path-scope BLOCK may act on
# either — restricting an unverified session is safe in the strict direction. The
# [CRITIC_STAMP] WAIVER may act only on the verified record, because the waiver is a
# hole in the Engineer's own quality gate: anyone can export AI_OS_CALLER_ROLE=architect
# and commit `.ai/` without a stamp, and `.ai/` contains REVIEWS.md — the very file
# Gate 2 reads. Requiring the record closes that without weakening the restriction.
_resolve_commit_role() {
  [[ "${AI_OS_SKIP_GIT_LANE:-0}" == "1" ]] && { printf 'env:engineer'; return 0; }

  # 1. HMAC-verified session record (authoritative, and the ONLY source that may
  #    unlock the stamp waiver).
  local se sid role
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [[ -n "$sid" ]] && command -v node >/dev/null 2>&1; then
    for se in "$(ai_os_locate mcp/safe-exec-mcp/index.js || true)"; do
      if [[ -n "$se" && -f "$se" ]]; then
        role="$(node --no-warnings "$se" --verify-role "$sid" 2>/dev/null)" && [[ -n "$role" ]] && {
          printf 'record:%s' "$role"; return 0; }
        break
      fi
    done
  fi

  # 2. Launch-time pane role (set by `ai pane`), then the advisory env. These may
  #    RESTRICT but never WAIVE.
  if [[ -n "${AI_OS_PANE_ROLE:-}" ]]; then printf 'env:%s' "$AI_OS_PANE_ROLE"; return 0; fi
  if [[ -n "${AI_OS_CALLER_ROLE:-}" ]]; then printf 'env:%s' "$AI_OS_CALLER_ROLE"; return 0; fi

  # 3. Default — unchanged Engineer behaviour.
  printf 'env:engineer'
}

check_architect_git_lane() {
  local resolved; resolved="$(_resolve_commit_role)"
  local ROLE_SOURCE="${resolved%%:*}"
  local role="${resolved#*:}"
  # Normalize before comparing: an exact match meant `Architect` or a trailing space
  # silently DISABLED the lane for a real Architect. safe-exec already lower-cases its
  # role comparison; match that. (Fails safe for Gate 2 either way, but a silently
  # un-laned Architect is exactly the drift this gate exists to catch.)
  role="$(printf '%s' "$role" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [[ "$role" == "architect" ]] || return 0

  # Every staged path must be under .ai/ or plans/. --name-status is used (rather than
  # --name-only) so a RENAME's BOTH sides are checked: moving a file OUT of .ai/ is
  # exactly the escape a name-only check would miss.
  # FAIL CLOSED on a broken diff. Reading straight from a process substitution meant
  # git's exit status was never seen: a failed `git diff` produced ZERO records, the
  # out-of-scope list stayed empty, and the lane granted the waiver — so any diff
  # hiccup silently turned into a full Gate 2 bypass with arbitrary staged content.
  # Proven with a stubbed non-zero `git diff`: rc=0 and src/evil.js waived through.
  # This is the same rule already codified for --check-path in safe-exec: an error
  # must BLOCK, never allow.
  local records
  if ! records="$(git diff --cached --name-status -M 2>/dev/null)"; then
    {
      echo ""
      echo "[GIT_LANE] Could not read the staged file list (git diff failed)."
      echo "Blocking rather than assuming the commit is in scope (fail-closed)."
      echo "Rollback (only if you are certain): AI_OS_SKIP_GIT_LANE=1 git commit ..."
    } >&2
    exit 1
  fi

  # Nothing staged: NOT an architect-scoped commit. Returning without setting
  # ARCHITECT_SCOPED lets the commit fall through to the normal Gate 2 stamp check,
  # instead of handing out a waiver for a diff that was never classified.
  [[ -z "$records" ]] && return 0

  local out_of_scope="" classified=0
  while IFS=$'\t' read -r _status path1 path2 rest; do
    [[ -z "${_status:-}" ]] && continue
    # `read` folds every EXTRA tab field into the last variable, so a 4-field record
    # would hide a path inside path2 — `.ai/b<TAB>src/c` matches the .ai/* arm and the
    # src/ path is never classified, while the counter still reports progress. git's
    # --name-status emits at most 3 fields today (renames/copies), so this is not
    # reachable from git — but an unexpected shape is exactly what this loop must not
    # wave through, and the counter cannot catch it because it counts fields, not paths.
    if [[ -n "${rest:-}" ]]; then
      echo "[GIT_LANE] Unexpected diff record shape — blocking (fail-closed)." >&2
      exit 1
    fi
    local p
    for p in "$path1" "$path2"; do
      [[ -z "$p" ]] && continue
      classified=$((classified + 1))
      case "$p" in
        # NOTE: no bare `.ai` / `plans` arms. Git emits a bare entry only when the
        # path is NOT a directory — i.e. .ai/ was replaced by a file or a symlink,
        # which stages the deletion of every .ai/ file at once. That is precisely the
        # change that must NOT ride through on the stamp waiver.
        .ai/*|plans/*) ;;
        *) out_of_scope="${out_of_scope}  ${p}"$'\n' ;;
      esac
    done
  done <<< "$records"

  # Belt-and-braces: records were present but nothing was classified (an unexpected
  # diff shape). Never waive on an unparsed diff.
  if [[ "$classified" -eq 0 ]]; then
    echo "[GIT_LANE] Staged changes could not be classified — blocking (fail-closed)." >&2
    exit 1
  fi

  if [[ -n "$out_of_scope" ]]; then
    {
      echo ""
      echo "╔══════════════════════════════════════════════════════════════════════════╗"
      echo "║  [SOVEREIGNTY_BLOCK] ARCHITECT GIT LANE — COMMIT BLOCKED                 ║"
      echo "╚══════════════════════════════════════════════════════════════════════════╝"
      echo ""
      echo "Session role: architect. An Architect may commit only paths under .ai/ or plans/."
      echo "These staged paths are outside that scope:"
      echo ""
      printf '%s' "$out_of_scope"
      echo ""
      echo "The Architect designs; the Engineer implements (§35 ANTI-DRIFT, D-054)."
      echo "Hand the change list to the Engineer:  ai handoff engineer \"<what to implement>\""
      echo "Then unstage the out-of-scope paths:   git restore --staged <path>"
      echo ""
      echo "Rollback (only if you are certain): AI_OS_SKIP_GIT_LANE=1 git commit ..."
    } >&2
    exit 1
  fi

  # In scope. The [CRITIC_STAMP] requirement is WAIVED for this commit: the critics
  # review src/, and an .ai/-only diff gives them nothing to review — requiring a stamp
  # would just push the Architect to fabricate one. Every OTHER gate above has already
  # run (markdown sync, co-modification warning, registry drift, MCP stdout purity, and
  # the standards gate, which is where the credential scan lives).
  if [[ "$ROLE_SOURCE" == "record" ]]; then
    ARCHITECT_SCOPED=1
    echo "[ARCHITECT_LANE] All staged paths are within .ai//plans/ — Gate 2 stamp waived for this commit." >&2
  else
    echo "[ARCHITECT_LANE] All staged paths are within .ai//plans/, but this session's role came" >&2
    echo "  from the environment rather than a verified session record, so the [CRITIC_STAMP]" >&2
    echo "  requirement still applies (D-055 R4). The path restriction was enforced either way." >&2
    echo "  Start the pane with \`ai pane architect\` so the role is minted and verifiable." >&2
  fi
}

check_architect_git_lane

# ── Gate 2 check ─────────────────────────────────────────────────────────────
if [[ "$ARCHITECT_SCOPED" == "1" ]]; then
  exit 0
fi

if has_recent_critic_stamp; then
  exit 0
fi

# Gate blocked — no recent [CRITIC_STAMP] found
cat >&2 <<'GATE'

╔══════════════════════════════════════════════════════════════════════════╗
║  AI-OS GATE 2: QUALITY GATE — COMMIT BLOCKED                           ║
╠══════════════════════════════════════════════════════════════════════════╣
║  No recent [CRITIC_STAMP] found in .ai/REVIEWS.md (required: ≤7 days) ║
║                                                                          ║
║  A critic review is mandatory before committing.                         ║
║  Run `ai review claude` and paste the prompt into Claude Code.           ║
╚══════════════════════════════════════════════════════════════════════════╝

GATE

# Print the full critic prompt so the user can act immediately
cat >&2 <<'CLAUDE_PROMPT'
━━ REVIEW PROMPT — Claude (Parallel Critics) ━━━━━━━━━━━━━━━━━━━━━━━━
Paste this into Claude Code:

"You are the Principal Software Engineer running a self-review.
Execute these three critics IN PARALLEL using sub-agents:

1. critic_arch     — Review src/ against .ai/architect.md. Flag any
                     code that contradicts the System Philosophy or
                     breaks domain sovereignty rules.

2. critic_security — Review src/ and hooks/ for OWASP Top 10,
                     shell injection, env variable leakage, and
                     capability boundary violations per CAPABILITIES.md.

3. critic_tests    — Review test coverage. Identify untested paths,
                     missing edge cases, and quality gate gaps.

After all three complete, synthesize findings and append to .ai/REVIEWS.md:
  [CRITIC_STAMP] YYYY-MM-DD | <summary of critical findings>

A [CRITIC_STAMP] is required to unblock Gate 2 (pre-commit hook)."
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CLAUDE_PROMPT

exit 1
