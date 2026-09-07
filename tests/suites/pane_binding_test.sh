#!/usr/bin/env bash
# pane_binding_test.sh — E-208 (D-054, role-abstraction.md §Same-Provider Triad):
# per-pane role binding. Covers the `ai pane <role>` launcher, the per-role settings
# overlay, the launch-time role reaching the SessionStart mint, and the Write/Edit
# sovereignty gate that makes §35 ANTI-DRIFT enforced rather than merely prompted.
#
# No tmux required: the launcher is exercised through its resolution helper and its
# argument validation, and the gate is driven with synthetic PreToolUse payloads.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"
HOOK="${REPO_ROOT}/hooks/pre-tool-use.sh"
SS_HOOK="${REPO_ROOT}/hooks/session-start.sh"
SAFE_EXEC="${REPO_ROOT}/src/mcp/safe-exec-mcp/index.js"
# E-216 split the Architect scope/write policy into its own module (index.js passed
# the 1000-line standards limit); the scope notes moved with it.
ARCH_WRITES="${REPO_ROOT}/src/mcp/safe-exec-mcp/architect-writes.mjs"
ADAPTER="${REPO_ROOT}/src/shared/provider-adapter.mjs"

echo "── Suite: pane_binding_test (E-208) ─────────────────────────────────"

# ── E-208.1: `ai pane` argument contract ─────────────────────────────────────
assert_status 0 "E-208.01a: 'ai pane --help' prints usage" \
  bash -c "bash '$AI_BIN' pane --help | grep -q 'Usage: ai pane'"
assert_status 2 "E-208.01b: unknown role exits 2" \
  bash -c "bash '$AI_BIN' pane bogus 2>/dev/null"
assert_contains "E-208.01c: unknown role names the valid roles" "architect | engineer" \
  "$(bash "$AI_BIN" pane bogus 2>&1)"
assert_status 0 "E-208.01d: 'pane' is wired into the CLI dispatch table" \
  grep -qE '^\s*pane\)\s+do_pane' "$AI_BIN"

# ── E-208.2: role → provider → argv resolution (shared module, E-210 reuse) ──
# The launcher and advisor-mcp MUST resolve through the SAME module so the bridge
# and the pane binding can never disagree about which provider owns a role.
assert_status 0 "E-208.02a: launcher resolves through the shared resolve-launch seam" \
  grep -q '_locate_resolve_launch' "$AI_BIN"
assert_status 0 "E-208.02a2: the seam imports the same adapter advisor-mcp uses" \
  grep -q 'from "./provider-adapter.mjs"' "${REPO_ROOT}/src/shared/resolve-launch.mjs"

# Drive the SAME seam do_pane uses (src/shared/resolve-launch.mjs), not a
# reimplementation — otherwise the launcher and these assertions can drift apart
# without any test failing (E-208 critic_tests P2).
RESOLVER="${REPO_ROOT}/src/shared/resolve-launch.mjs"
_resolve() {  # <role> <aidir> → newline argv flattened to a single quoted string
  node --no-warnings "$RESOLVER" "$1" "$2" 2>/dev/null | tr '\n' '|'
}

TMP_AI="$(mktemp -d)/.ai"; mkdir -p "$TMP_AI"
cp "${REPO_ROOT}/src/templates/providers.json" "$TMP_AI/providers.json"
cat > "$TMP_AI/roles.json" <<'JSON'
{ "roles": {
    "architect": { "provider": "claude", "pane_identifier": "1", "model": "claude-opus-5" },
    "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON

assert_contains "E-208.02b: architect resolves to its own settings overlay" \
  ".claude/settings.architect.json" "$(_resolve architect "$TMP_AI")"
assert_contains "E-208.02c: architect gets ARCHITECT.md appended (else it boots ENGINEER — G1)" \
  "ARCHITECT.md" "$(_resolve architect "$TMP_AI")"
assert_contains "E-208.02d: engineer gets ENGINEER.md appended" \
  "ENGINEER.md" "$(_resolve engineer "$TMP_AI")"
assert_contains "E-208.02e: per-role model is forwarded when configured" \
  "--model|claude-opus-5" "$(_resolve architect "$TMP_AI")"
assert_not_contains "E-208.02f: no dangling --model when the role has none" \
  '--model' "$(_resolve engineer "$TMP_AI")"

# An agy-bound architect must NOT get claude's flags — proves it is adapter-driven.
cat > "$TMP_AI/roles.json.agy" <<'JSON'
{ "roles": { "architect": { "provider": "agy", "pane_identifier": "1" } } }
JSON
mv "$TMP_AI/roles.json" "$TMP_AI/roles.json.claude"
mv "$TMP_AI/roles.json.agy" "$TMP_AI/roles.json"
assert_contains "E-208.02g: agy-bound architect resolves to the agy provider" \
  "agy" "$(_resolve architect "$TMP_AI")"
assert_not_contains "E-208.02h: agy-bound architect gets no claude launch flags" \
  "settings.architect.json" "$(_resolve architect "$TMP_AI")"
mv "$TMP_AI/roles.json.claude" "$TMP_AI/roles.json"

# ── E-208.3: per-role settings overlay (env only, NEVER a second hook) ───────
OV_DIR="$(mktemp -d)/.claude"; mkdir -p "$OV_DIR"
bash -c "source '$AI_BIN' 2>/dev/null; _write_role_settings_overlays '$OV_DIR' '$TMP_AI'" >/dev/null 2>&1

assert_status 0 "E-208.03a: architect overlay generated" test -f "$OV_DIR/settings.architect.json"
assert_status 0 "E-208.03b: engineer overlay generated" test -f "$OV_DIR/settings.engineer.json"
assert_contains "E-208.03c: architect overlay carries its own caller role" '"AI_OS_CALLER_ROLE": "architect"' \
  "$(cat "$OV_DIR/settings.architect.json")"
# CRITICAL (D-054 §Alternatives option 3): Claude Code MERGES hook arrays, so a second
# SessionStart registration here would mint two role tokens for one session id.
assert_not_contains "E-208.03d: overlay registers NO hooks (double-mint guard)" '"hooks"' \
  "$(cat "$OV_DIR/settings.architect.json")"
assert_not_contains "E-208.03e: overlay registers no SessionStart" 'SessionStart' \
  "$(cat "$OV_DIR/settings.architect.json")"

# A non-claude role gets no claude overlay.
NO_OV="$(mktemp -d)/.claude"; mkdir -p "$NO_OV"
AGY_AI="$(mktemp -d)/.ai"; mkdir -p "$AGY_AI"
echo '{ "roles": { "architect": { "provider": "agy", "pane_identifier": "1" } } }' > "$AGY_AI/roles.json"
bash -c "source '$AI_BIN' 2>/dev/null; _write_role_settings_overlays '$NO_OV' '$AGY_AI'" >/dev/null 2>&1
assert_status 1 "E-208.03f: no overlay for a role bound to a non-claude provider" \
  test -f "$NO_OV/settings.architect.json"

# ── E-208.4: launch-time role reaches the SessionStart mint ─────────────────
_stamp() {  # <pane_role_env> <positional_role> → the [AI_OS_ROLE] line
  local pane="$1" pos="$2" sid="e208t-$RANDOM$RANDOM"
  printf '{"session_id":"%s"}' "$sid" \
    | AI_OS_DISABLE_CACHE=1 AI_OS_PANE_ROLE="$pane" bash "$SS_HOOK" "$pos" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"].splitlines()[0])' 2>/dev/null
}
assert_contains "E-208.04a: AI_OS_PANE_ROLE binds the session to architect" "[AI_OS_ROLE] architect" \
  "$(_stamp architect engineer)"
assert_contains "E-208.04b: plain launch still mints engineer (positional default)" "[AI_OS_ROLE] engineer" \
  "$(_stamp '' engineer)"
assert_contains "E-208.04c: an unknown pane role falls back, never mints a bogus role" "[AI_OS_ROLE] engineer" \
  "$(_stamp hacker engineer)"

# The stamp and the minted token must agree — the stamp drives the persona, the
# token drives enforcement; a mismatch would mean a pane that reads as one role and
# is gated as another.
SID_M="e208-mint-$RANDOM$RANDOM"
printf '{"session_id":"%s"}' "$SID_M" | AI_OS_DISABLE_CACHE=1 AI_OS_PANE_ROLE=architect bash "$SS_HOOK" engineer >/dev/null 2>&1
assert_contains "E-208.04d: minted role matches the emitted stamp" '"role":"architect"' \
  "$(cat "${HOME}/.ai-os/run/role-${SID_M}.lock" 2>/dev/null)"
rm -f "${HOME}/.ai-os/run/role-${SID_M}.lock"

# ── E-208.5: --check-path verdicts (the enforcement primitive) ──────────────
_cp() {  # <role> <path> → exit code
  AI_OS_CALLER_ROLE="$1" node --no-warnings "$SAFE_EXEC" --check-path "$2" >/dev/null 2>&1
  echo $?
}
assert_contains "E-208.05a: architect may write .ai/" "0" "$(_cp architect "$REPO_ROOT/.ai/blueprints/x.md")"
assert_contains "E-208.05b: architect may write plans/" "0" "$(_cp architect "$REPO_ROOT/plans/p.md")"
assert_contains "E-208.05c: architect BLOCKED from src/" "2" "$(_cp architect "$REPO_ROOT/src/bin/ai")"
assert_contains "E-208.05d: architect BLOCKED from tests/" "2" "$(_cp architect "$REPO_ROOT/tests/run.sh")"
assert_contains "E-208.05e: architect BLOCKED from a root rulefile" "2" "$(_cp architect "$REPO_ROOT/ENGINEER.md")"
assert_contains "E-208.05f: architect BLOCKED outside the project root" "2" "$(_cp architect "/tmp/outside.txt")"
assert_contains "E-208.05g: traversal escape from .ai/ is normalised then BLOCKED" "2" \
  "$(_cp architect "$REPO_ROOT/.ai/../src/evil.js")"
assert_contains "E-208.05h: relative paths are resolved against the project root" "2" \
  "$(_cp architect "src/rel.js")"
assert_contains "E-208.05i: engineer is never gated (fast no-op)" "0" "$(_cp engineer "$REPO_ROOT/src/bin/ai")"
assert_contains "E-208.05j: empty path is not an invented block" "0" "$(_cp architect "")"

# Fail-closed on analyzer crash — a crash must never become an allow (T-HITL-004).
AI_OS_SAFE_EXEC_SELFTEST_THROW=1 AI_OS_CALLER_ROLE=architect \
  node --no-warnings "$SAFE_EXEC" --check-path "$REPO_ROOT/.ai/ok.md" >/dev/null 2>&1
assert_contains "E-208.05k: analyzer crash FAILS CLOSED (blocks, never allows)" "2" "$?"

# ── E-208.6: hook end-to-end — the token must beat the mutable env ──────────
_mint() { node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" "$1" "$2" >/dev/null 2>&1; }
SID_A="e208-a-$RANDOM$RANDOM"; SID_E="e208-e-$RANDOM$RANDOM"
_mint architect "$SID_A"; _mint engineer "$SID_E"

_gate() {  # <sid> <tool> <pathkey> <path> → exit code
  printf '{"tool_name":"%s","tool_input":{"%s":"%s"},"session_id":"%s"}' "$2" "$3" "$4" "$1" \
    | AI_OS_CALLER_ROLE=engineer bash "$HOOK" >/dev/null 2>&1
  echo $?
}
# AI_OS_CALLER_ROLE=engineer is exported in every call below: if the env could win,
# these would all pass. They must not — E-129's whole point.
assert_contains "E-208.06a: Write to src/ BLOCKED in an architect session" "2" \
  "$(_gate "$SID_A" Write file_path "$REPO_ROOT/src/bin/ai")"
assert_contains "E-208.06b: Edit to tests/ BLOCKED in an architect session" "2" \
  "$(_gate "$SID_A" Edit file_path "$REPO_ROOT/tests/run.sh")"
assert_contains "E-208.06c: MultiEdit BLOCKED in an architect session" "2" \
  "$(_gate "$SID_A" MultiEdit file_path "$REPO_ROOT/src/x.js")"
assert_contains "E-208.06d: NotebookEdit (notebook_path) BLOCKED in an architect session" "2" \
  "$(_gate "$SID_A" NotebookEdit notebook_path "$REPO_ROOT/src/n.ipynb")"
assert_contains "E-208.06e: Write to .ai/ ALLOWED in an architect session" "0" \
  "$(_gate "$SID_A" Write file_path "$REPO_ROOT/.ai/blueprints/new.md")"
assert_contains "E-208.06f: Read is never gated" "0" \
  "$(_gate "$SID_A" Read file_path "$REPO_ROOT/src/bin/ai")"
assert_contains "E-208.06g: engineer session — Write to src/ ALLOWED (no new restriction)" "0" \
  "$(_gate "$SID_E" Write file_path "$REPO_ROOT/src/bin/ai")"
assert_contains "E-208.06h: engineer session — Edit to tests/ ALLOWED" "0" \
  "$(_gate "$SID_E" Edit file_path "$REPO_ROOT/tests/run.sh")"

# Rollback escape hatch still works.
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$REPO_ROOT/src/bin/ai" "$SID_A" \
  | AI_OS_SAFE_EXEC_GATE=0 bash "$HOOK" >/dev/null 2>&1
assert_contains "E-208.06i: AI_OS_SAFE_EXEC_GATE=0 bypasses the write gate" "0" "$?"
rm -f "${HOME}/.ai-os/run/role-${SID_A}.lock" "${HOME}/.ai-os/run/role-${SID_E}.lock"

# ── E-208.7: registration + rulefile clause ────────────────────────────────
assert_status 0 "E-208.07a: PreToolUse matcher covers the write tools" \
  grep -q 'Bash|Write|Edit|MultiEdit|NotebookEdit' "$AI_BIN"
assert_status 0 "E-208.07b: hook branches on the write tools" \
  grep -qE '^\s*Write\|Edit\|MultiEdit\|NotebookEdit\)' "$HOOK"
assert_status 0 "E-208.07c: ENGINEER.md carries the Role Resolution clause" \
  grep -q 'Role Resolution (D-054' "${REPO_ROOT}/src/templates/ENGINEER.md"
assert_status 0 "E-208.07d: ARCHITECT.md carries the Role Resolution clause" \
  grep -q 'Role Resolution (D-054' "${REPO_ROOT}/src/templates/ARCHITECT.md"
assert_status 0 "E-208.07e: session-start prefers the launch-time pane role" \
  grep -q 'AI_OS_PANE_ROLE:-' "$SS_HOOK"

# ── E-208.8: security-audit regressions (2026-09-05) ────────────────────────
# Each assertion below reproduces an attack that WORKED against the first cut of
# this gate. They are exploit regressions, not hypotheticals.
echo "  [E-208.8] security-audit regressions"

_mint2() { node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" "$1" "$2" >/dev/null 2>&1; }
_gate2() {  # <sid> <path> → exit code, through the REAL hook
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$2" "$1" \
    | AI_OS_CALLER_ROLE=engineer bash "$HOOK" >/dev/null 2>&1
  echo $?
}
SID_S="e208-sec-$RANDOM$RANDOM"
_mint2 architect "$SID_S"

# (a) SYMLINK ESCAPE — a link planted inside .ai/ (which the Architect MAY write)
# forwarded a write to any target, because the verdict normalised but never realpath'd.
ln -sfn "$REPO_ROOT/src/bin/ai" "$REPO_ROOT/.ai/__e208_seclink"
assert_contains "E-208.08a: symlinked FILE inside .ai/ pointing at src/ is BLOCKED" "2" \
  "$(_gate2 "$SID_S" "$REPO_ROOT/.ai/__e208_seclink")"
ln -sfn "$REPO_ROOT/src" "$REPO_ROOT/.ai/__e208_secdir"
assert_contains "E-208.08b: symlinked DIRECTORY component inside .ai/ is BLOCKED" "2" \
  "$(_gate2 "$SID_S" "$REPO_ROOT/.ai/__e208_secdir/bin/ai")"
assert_contains "E-208.08c: a real .ai/ path still resolves through realpath (no over-block)" "0" \
  "$(_gate2 "$SID_S" "$REPO_ROOT/.ai/blueprints/ok.md")"
rm -f "$REPO_ROOT/.ai/__e208_seclink" "$REPO_ROOT/.ai/__e208_secdir"

# (b) RE-MINT PRIVILEGE ESCALATION (P0) — the token gates writes as of E-208, so an
# unguarded re-mint of the same session id was a full architect→engineer role swap.
_mint2 engineer "$SID_S"
assert_contains "E-208.08d: re-minting a bound session with a DIFFERENT role is refused" "architect" \
  "$(python3 -c "import json;print(json.load(open('${HOME}/.ai-os/run/role-${SID_S}.lock'))['role'])" 2>/dev/null)"
assert_contains "E-208.08e: the write stays BLOCKED after an attempted role swap" "2" \
  "$(_gate2 "$SID_S" "$REPO_ROOT/src/bin/ai")"
# Same-role re-mint must still work — SessionStart fires on both startup and resume.
_mint2 architect "$SID_S"
assert_contains "E-208.08f: same-role re-mint still succeeds (resume path intact)" "architect" \
  "$(python3 -c "import json;print(json.load(open('${HOME}/.ai-os/run/role-${SID_S}.lock'))['role'])" 2>/dev/null)"
rm -f "${HOME}/.ai-os/run/role-${SID_S}.lock"

# (c) ARGV CONFUSION — a target literally named "--session" hijacked the flag scan
# and dropped the check to the env fallback.
assert_contains "E-208.08g: a path named '--session' cannot hijack the flag parse" "2" \
  "$(AI_OS_CALLER_ROLE=architect node --no-warnings "$SAFE_EXEC" --check-path "--session" >/dev/null 2>&1; echo $?)"

# (d) FAIL-OPEN ON NON-2 EXIT — a module that fails to LOAD exits 1, and the hook
# used to treat only 2 as a block.
assert_status 0 "E-208.08h: hook blocks on ANY non-zero check-path exit, not just 2" \
  grep -q 'W_RC" -ne 0' "$HOOK"

# (e) UNTRUSTED role key / provider name — both files are ARCHITECT-writable, so one
# feeds a path join and the other an exec target.
EVIL_AI="$(mktemp -d)/.ai"; mkdir -p "$EVIL_AI"
EVIL_OUT="$(mktemp -d)/.claude"; mkdir -p "$EVIL_OUT"
cat > "$EVIL_AI/roles.json" <<'JSON'
{ "roles": { "../../escape": { "provider": "claude", "pane_identifier": "0" },
             "engineer":     { "provider": "claude", "pane_identifier": "0" } } }
JSON
bash -c "source '$AI_BIN' 2>/dev/null; _write_role_settings_overlays '$EVIL_OUT' '$EVIL_AI'" >/dev/null 2>&1
assert_status 1 "E-208.08i: a traversal role key writes nothing outside the target dir" \
  bash -c "ls \"$EVIL_OUT/../..\"/settings.*.json >/dev/null 2>&1"
assert_status 0 "E-208.08j: the valid sibling role is still generated" \
  test -f "$EVIL_OUT/settings.engineer.json"
assert_status 0 "E-208.08k: launcher validates the provider name before exec" \
  grep -q "refusing to exec provider" "$AI_BIN"

# (f) SCOPE HONESTY — E-216/D-055 widened the gate to three layers, so the old
# "NARROWED, not closed" wording no longer applies. What must still hold is that the
# code names its REMAINING residual instead of claiming the channel is airtight.
assert_status 0 "E-208.08l: the scope note enumerates all three write channels" \
  grep -q "analyzeArchitectWrites" "$ARCH_WRITES"
assert_status 0 "E-208.08l2: and still states a residual rather than claiming closure" \
  grep -q "STATED RESIDUAL" "$ARCH_WRITES"
# Assert the honest statement POSITIVELY. A keyword-absence test was worse than
# useless here: it matched the word "airtight" inside the sentence that correctly says
# the channel is NOT airtight, i.e. it failed on the very wording it existed to require.
assert_status 0 "E-208.08l3: the code states plainly that the channel is not airtight" \
  grep -q "not airtight" "$ARCH_WRITES"


# ── E-208.9: do_pane error branches + _find_ai_dir walk (critic_tests P2) ────
echo "  [E-208.9] launcher error paths"

# Outside an AI-OS project: must refuse, not launch anything.
OUTSIDE="$(mktemp -d)"
assert_status 2 "E-208.09a: refuses to bind outside an AI-OS project" \
  bash -c "cd '$OUTSIDE' && bash '$AI_BIN' pane architect 2>/dev/null"
assert_contains "E-208.09b: the message names the missing .ai/ and the fix" "ai init" \
  "$(cd "$OUTSIDE" && bash "$AI_BIN" pane architect 2>&1)"

# Role mapped to a provider with no launch adapter → distinct message from "unmapped".
NOLAUNCH="$(mktemp -d)"; mkdir -p "$NOLAUNCH/.ai"
echo '{ "roles": { "architect": { "provider": "ghostcli", "pane_identifier": "1" } } }' > "$NOLAUNCH/.ai/roles.json"
echo '{ "providers": { "ghostcli": { "mcp_config_path": "x", "mcp_key": "y" } } }' > "$NOLAUNCH/.ai/providers.json"
assert_status 2 "E-208.09c: a provider with no launch template exits 2" \
  bash -c "cd '$NOLAUNCH' && bash '$AI_BIN' pane architect 2>/dev/null"
assert_contains "E-208.09d: that error names 'launch', not a bogus roles.json mapping" "launch" \
  "$(cd "$NOLAUNCH" && bash "$AI_BIN" pane architect 2>&1)"

# Provider adapter present but the CLI is not installed.
NOCLI="$(mktemp -d)"; mkdir -p "$NOCLI/.ai"
echo '{ "roles": { "architect": { "provider": "ghostcli", "pane_identifier": "1" } } }' > "$NOCLI/.ai/roles.json"
printf '{ "providers": { "ghostcli": { "launch": ["--flag"], "print_mode": ["-p","{prompt}"] } } }' > "$NOCLI/.ai/providers.json"
assert_status 2 "E-208.09e: a provider CLI missing from PATH exits 2" \
  bash -c "cd '$NOCLI' && bash '$AI_BIN' pane architect 2>/dev/null"
assert_contains "E-208.09f: that error names PATH" "PATH" \
  "$(cd "$NOCLI" && bash "$AI_BIN" pane architect 2>&1)"

# An invalid provider name must never reach exec.
BADPROV="$(mktemp -d)"; mkdir -p "$BADPROV/.ai"
echo '{ "roles": { "architect": { "provider": "../../bin/sh", "pane_identifier": "1" } } }' > "$BADPROV/.ai/roles.json"
printf '{ "providers": { "../../bin/sh": { "launch": ["-c","echo pwned"] } } }' > "$BADPROV/.ai/providers.json"
assert_status 2 "E-208.09g: a path-shaped provider name is refused before exec" \
  bash -c "cd '$BADPROV' && bash '$AI_BIN' pane architect 2>/dev/null"
assert_contains "E-208.09h: refusal names the invalid provider" "refusing to exec provider" \
  "$(cd "$BADPROV" && bash "$AI_BIN" pane architect 2>&1)"

# The .ai/ ancestor walk (git-style discovery) — asserted BEHAVIOURALLY via the
# launcher, because sourcing src/bin/ai aborts partway under `set -e` and never
# defines the late helpers. Running from a nested subdirectory must resolve the
# project root, which the error message then names.
SUBDIR="$(mktemp -d)"; mkdir -p "$SUBDIR/.ai" "$SUBDIR/a/b/c"
echo '{ "roles": { "architect": { "provider": "ghostcli", "pane_identifier": "1" } } }' > "$SUBDIR/.ai/roles.json"
echo '{ "providers": { "ghostcli": { "mcp_config_path": "x", "mcp_key": "y" } } }' > "$SUBDIR/.ai/providers.json"
assert_contains "E-208.09i: ancestor walk finds the project .ai/ from a nested subdir" "$SUBDIR/.ai/providers.json" \
  "$(cd "$SUBDIR/a/b/c" && bash "$AI_BIN" pane architect 2>&1)"


# ── E-208.10: round-2 audit regressions (symlink + lexical '..') ─────────────
# The round-1 fix resolved symlinks but still collapsed `..` LEXICALLY first, and the
# two orders disagree: `normalize` is a string op, the kernel is not. With
# `.ai/d2 -> src/deep`, the string `.ai/d2/../bin/ai` collapses to `.ai/bin/ai`
# (allowed) while the kernel resolves it to `src/bin/ai`. That wrote real bytes to a
# real source file through the native Write tool.
echo "  [E-208.10] symlink + '..' regressions"

SID_R2="e208-r2-$RANDOM$RANDOM"
_mint2 architect "$SID_R2"
mkdir -p "$REPO_ROOT/src/__e208_deep"
ln -sfn "$REPO_ROOT/src/__e208_deep" "$REPO_ROOT/.ai/__e208_d2"
ln -sfn /tmp "$REPO_ROOT/.ai/__e208_out"
ln -sfn "$REPO_ROOT/src/bin/ai" "$REPO_ROOT/.ai/__e208_leaf"

assert_contains "E-208.10a: symlink + '..' cannot reach src/ (lexical-vs-kernel escape)" "2" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/.ai/__e208_d2/../bin/ai")"
assert_contains "E-208.10b: symlink-to-outside + '..' cannot escape the project root" "2" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/.ai/__e208_out/../etc/x")"
assert_contains "E-208.10c: trailing slash on a symlinked leaf does not fail open" "2" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/.ai/__e208_leaf/")"
assert_contains "E-208.10d: the same symlinked leaf without the slash is still blocked" "2" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/.ai/__e208_leaf")"
# A bare '..' anywhere in the raw path is rejected as a class, not case by case.
assert_contains "E-208.10e: a '..' segment is rejected outright, even toward an allowed dir" "2" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/.ai/blueprints/../notes.md")"

# Legitimate Architect writes must still pass — the fix must not over-block.
assert_contains "E-208.10f: plain .ai/ write still allowed" "0" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/.ai/DECISIONS.md")"
assert_contains "E-208.10g: deep uncreated plans/ path still allowed" "0" \
  "$(_gate2 "$SID_R2" "$REPO_ROOT/plans/deep/new/x.md")"

# The Engineer is never subject to any of this.
SID_R2E="e208-r2e-$RANDOM$RANDOM"
_mint2 engineer "$SID_R2E"
assert_contains "E-208.10h: engineer unaffected by the '..' rejection" "0" \
  "$(_gate2 "$SID_R2E" "$REPO_ROOT/.ai/__e208_d2/../bin/ai")"

rm -f "$REPO_ROOT/.ai/__e208_d2" "$REPO_ROOT/.ai/__e208_out" "$REPO_ROOT/.ai/__e208_leaf"
rmdir "$REPO_ROOT/src/__e208_deep" 2>/dev/null
rm -f "${HOME}/.ai-os/run/role-${SID_R2}.lock" "${HOME}/.ai-os/run/role-${SID_R2E}.lock"

# Scope honesty must hold at ALL THREE sites, not just the one that was pinned.
assert_status 0 "E-208.10i: the policy module names its residual (E-216 wording)" \
  grep -q "STATED RESIDUAL" "$ARCH_WRITES"
assert_status 0 "E-208.10j: the check-path CLI comment does not claim G2 is closed" \
  bash -c "! grep -q 'only closes gap G2' '$SAFE_EXEC'"
assert_status 0 "E-208.10k: the hook comment does not claim G2 is closed" \
  bash -c "! grep -q 'This closes gap G2' '$HOOK'"
assert_status 0 "E-208.10l: the hook enumerates the three layers and the residual" \
  bash -c "grep -q 'THREE layers' '$HOOK' && grep -q 'STATED RESIDUAL' '$HOOK'"
# The mint guard must not be described as immutability — it is a partial guard.
assert_status 0 "E-208.10m: mint refusal does not over-claim immutability" \
  bash -c "! grep -q \"role is immutable for its lifetime\" '$SAFE_EXEC'"
assert_status 0 "E-208.10n: mint refusal states its own limitation" \
  grep -q "Partial guard" "$SAFE_EXEC"


# ── E-208.11: hardlink blind spot (round-3 audit) ───────────────────────────
# A hardlink is not a REFERENCE to a file, it IS the file under a second equally
# canonical name — realpath has nothing to see through, and every path-based check
# agrees the target sits inside .ai/. `ln src/bin/ai .ai/h` + `Write .ai/h` wrote
# real bytes to src/bin/ai. Only an inode property can distinguish it.
echo "  [E-208.11] hardlink blind spot"

SID_HL="e208-hl-$RANDOM$RANDOM"
_mint2 architect "$SID_HL"
ln -f "$REPO_ROOT/src/bin/ai" "$REPO_ROOT/.ai/__e208_hl" 2>/dev/null
assert_contains "E-208.11a: a hardlink in .ai/ aliasing src/ is BLOCKED (nlink check)" "2" \
  "$(_gate2 "$SID_HL" "$REPO_ROOT/.ai/__e208_hl")"
# The check must only ever ADD restriction — these are the false-positive guards.
assert_contains "E-208.11b: an ordinary .ai/ file is unaffected" "0" \
  "$(_gate2 "$SID_HL" "$REPO_ROOT/.ai/DECISIONS.md")"
assert_contains "E-208.11c: a not-yet-created target is unaffected" "0" \
  "$(_gate2 "$SID_HL" "$REPO_ROOT/.ai/__e208_brand_new.md")"
assert_contains "E-208.11d: a DIRECTORY (legitimately nlink>1) is not blocked" "0" \
  "$(_gate2 "$SID_HL" "$REPO_ROOT/.ai/blueprints")"
SID_HLE="e208-hle-$RANDOM$RANDOM"
_mint2 engineer "$SID_HLE"
assert_contains "E-208.11e: engineer unaffected by the nlink check" "0" \
  "$(_gate2 "$SID_HLE" "$REPO_ROOT/.ai/__e208_hl")"
rm -f "$REPO_ROOT/.ai/__e208_hl" "${HOME}/.ai-os/run/role-${SID_HL}.lock" "${HOME}/.ai-os/run/role-${SID_HLE}.lock"

# The scope block must name path gating's own limits, not just uncovered channels.
assert_status 0 "E-208.11f: scope note documents the hardlink limit" \
  grep -q "HARDLINKS are handled below by an nlink check" "$ARCH_WRITES"
assert_status 0 "E-208.11g: scope note documents the TOCTOU limit" \
  grep -q "TOCTOU" "$ARCH_WRITES"


assert_summary
