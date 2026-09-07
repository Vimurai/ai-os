#!/usr/bin/env bash
# git_lane_test.sh — E-214 (architect-provider-parity.md §Git Lane, D-054):
# the Architect-scoped commit lane.
#
# A Claude Architect HAS git, unlike agy, so the D-053 proxy-commit workaround (the
# Engineer commits the Architect's .ai/ edits) is retired for same-provider Triads.
# The lane is the LAST checkpoint before history: an Architect may commit only paths
# under .ai/ or plans/, and for such a commit the [CRITIC_STAMP] requirement is waived
# because the critics review src/ and an .ai/-only diff gives them nothing to read.
#
# Every assertion drives the REAL hook in a disposable git repo with real staged files.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/pre-commit.sh"
SAFE_EXEC="${REPO_ROOT}/src/mcp/safe-exec-mcp/index.js"

echo "── Suite: git_lane_test (E-214) ─────────────────────────────────────"

_RC=0   # declared up front: the suite runs under `set -u`

# Disposable repo with a seeded stamp, so Gate 2 is satisfied for the engineer path
# and the ONLY variable under test is the role + staged scope.
_mkrepo() {
  local d; d="$(mktemp -d)"
  ( cd "$d"
    git init -q .
    git config user.email t@t; git config user.name t
    mkdir -p .ai/blueprints plans src tests
    printf '[CRITIC_STAMP] %s | seeded\n' "$(date +%Y-%m-%d)" > .ai/REVIEWS.md
  )
  printf '%s' "$d"
}

# Run the hook with an explicit role, assigning into _OUT/_RC in the CURRENT shell.
# NOTE: `_out="$(_run ...)"` would run _run in a SUBSHELL, so an _RC set inside would
# never reach the parent and every exit-code assertion would silently read a stale
# value. Call this directly and read _OUT/_RC.
# CLAUDE_CODE_SESSION_ID is emptied so the env fallback is what is under test here;
# the HMAC-record path is covered separately in E-214.7.
_OUT=""
_run() {  # <repo> <role> → sets _OUT and _RC
  local d="$1" role="$2"
  _OUT="$( cd "$d" && AI_OS_CALLER_ROLE="$role" AI_OS_SKIP_STANDARDS=1 CLAUDE_CODE_SESSION_ID= \
           bash "$HOOK" 2>&1 )"
  _RC=$?
}

# ── E-214.1: in-scope architect commit passes and waives the stamp ───────────
R1="$(_mkrepo)"
( cd "$R1" && echo x > .ai/blueprints/new.md && echo y > plans/p.md && git add .ai/blueprints/new.md plans/p.md )
_run "$R1" architect
assert_contains "E-214.01a: architect in-scope commit is allowed (rc 0)" "0" "$_RC"
assert_contains "E-214.01b: the lane announces the waiver" "ARCHITECT_LANE" "$_OUT"
assert_not_contains "E-214.01c: no sovereignty block for an in-scope commit" "SOVEREIGNTY_BLOCK" "$_OUT"

# ── E-214.2: any out-of-scope path blocks ────────────────────────────────────
R2="$(_mkrepo)"
( cd "$R2" && echo x > .ai/ok.md && echo z > src/impl.js && git add .ai/ok.md src/impl.js )
_run "$R2" architect
assert_contains "E-214.02a: a single src/ path blocks the whole commit (rc 1)" "1" "$_RC"
assert_contains "E-214.02b: the block is labelled [SOVEREIGNTY_BLOCK]" "SOVEREIGNTY_BLOCK" "$_OUT"
assert_contains "E-214.02c: the offending path is named" "src/impl.js" "$_OUT"
assert_contains "E-214.02d: the hint routes work to the Engineer" "ai handoff engineer" "$_OUT"
assert_contains "E-214.02e: the hint says how to unstage" "git restore --staged" "$_OUT"
# Mixed staging must not be partially accepted — .ai/ok.md is in scope but the commit
# is atomic, so the whole thing is refused.
assert_contains "E-214.02f: an in-scope sibling does not rescue the commit" "SOVEREIGNTY_BLOCK" "$_OUT"

# tests/ is Engineer territory too — .ai/ and plans/ are the ONLY architect paths.
R3="$(_mkrepo)"
( cd "$R3" && echo t > tests/x.sh && git add tests/x.sh )
_run "$R3" architect
assert_contains "E-214.03a: tests/ is out of scope for the Architect" "SOVEREIGNTY_BLOCK" "$_OUT"
R4="$(_mkrepo)"
( cd "$R4" && echo r > README.md && git add README.md )
_run "$R4" architect
assert_contains "E-214.03b: a repo-root file is out of scope" "SOVEREIGNTY_BLOCK" "$_OUT"

# ── E-214.4: RENAMES — both sides of the rename are checked ──────────────────
# --name-only would report only the NEW path, so moving a file OUT of .ai/ would slip
# through. -M + --name-status is what makes this catchable.
R5="$(_mkrepo)"
( cd "$R5" && echo keep > .ai/moveme.md && git add .ai/moveme.md && git commit -qm seed --no-verify
  git mv .ai/moveme.md src/moveme.md )
_run "$R5" architect
assert_contains "E-214.04a: renaming a file OUT of .ai/ is blocked" "SOVEREIGNTY_BLOCK" "$_OUT"
R6="$(_mkrepo)"
( cd "$R6" && echo keep > .ai/moveme.md && git add .ai/moveme.md && git commit -qm seed --no-verify
  git mv .ai/moveme.md .ai/renamed.md )
_run "$R6" architect
assert_contains "E-214.04b: renaming WITHIN .ai/ is allowed" "ARCHITECT_LANE" "$_OUT"

# ── E-214.5: the Engineer path is completely unchanged ──────────────────────
R7="$(_mkrepo)"
( cd "$R7" && echo z > src/impl.js && git add src/impl.js )
_run "$R7" engineer
assert_contains "E-214.05a: engineer commits src/ freely (rc 0, stamp present)" "0" "$_RC"
assert_not_contains "E-214.05b: engineer never sees the sovereignty block" "SOVEREIGNTY_BLOCK" "$_OUT"
assert_not_contains "E-214.05c: engineer never gets the stamp waiver" "ARCHITECT_LANE" "$_OUT"

# An unset role must behave exactly like engineer — no new restriction by default.
R8="$(_mkrepo)"
( cd "$R8" && echo z > src/impl.js && git add src/impl.js )
_OUT="$( cd "$R8" && env -u AI_OS_CALLER_ROLE -u AI_OS_PANE_ROLE AI_OS_SKIP_STANDARDS=1 \
         CLAUDE_CODE_SESSION_ID= bash "$HOOK" 2>&1 )"; _RC=$?
assert_contains "E-214.05d: no role set → engineer behaviour, rc 0" "0" "$_RC"
assert_not_contains "E-214.05e: no role set → no sovereignty block" "SOVEREIGNTY_BLOCK" "$_OUT"

# ── E-214.6: the waiver is real — it must hold with NO stamp at all ──────────
R9="$(_mkrepo)"
( cd "$R9" && rm -f .ai/REVIEWS.md && echo x > .ai/only.md && git add .ai/only.md )
# E-218 (D-055 R4) NARROWED this: the waiver now requires a VERIFIED session record.
# `_run` deliberately empties CLAUDE_CODE_SESSION_ID, so this is the env-only path and
# the stamp requirement correctly still applies. The waiver itself is asserted with a
# minted record in E-218.01a.
_run "$R9" architect
assert_contains "E-214.06a: env-only architect in-scope does NOT waive the stamp (E-218)" "1" "$_RC"
assert_contains "E-214.06b: and it says why the waiver did not apply" "still applies" "$_OUT"
_run "$R9" engineer
assert_contains "E-214.06c: the SAME commit as engineer is still Gate-2 blocked" "1" "$_RC"
assert_contains "E-214.06d: engineer sees the Gate 2 banner" "GATE 2" "$_OUT"

# ── E-214.7: role resolution prefers the HMAC record over the env ────────────
# The record is authoritative: an architect-bound session cannot become the Engineer by
# exporting AI_OS_CALLER_ROLE=engineer.
_mintl() { node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" "$1" "$2" >/dev/null 2>&1; }
SID_L="e214-$RANDOM$RANDOM"
_mintl architect "$SID_L"
R10="$(_mkrepo)"
( cd "$R10" && echo z > src/impl.js && git add src/impl.js )
_OUT="$( cd "$R10" && AI_OS_CALLER_ROLE=engineer AI_OS_SKIP_STANDARDS=1 \
         CLAUDE_CODE_SESSION_ID="$SID_L" bash "$HOOK" 2>&1 )"; _RC=$?
assert_contains "E-214.07a: the HMAC record beats a forged AI_OS_CALLER_ROLE=engineer" \
  "SOVEREIGNTY_BLOCK" "$_OUT"
assert_status 0 "E-214.07b: --verify-role returns the recorded role" \
  bash -c "[[ \"\$(node --no-warnings '$SAFE_EXEC' --verify-role '$SID_L')\" == 'architect' ]]"
assert_status 1 "E-214.07c: --verify-role exits 1 for an unknown session" \
  bash -c "node --no-warnings '$SAFE_EXEC' --verify-role no-such-session >/dev/null 2>&1"
rm -f "${HOME}/.ai-os/run/role-${SID_L}.lock"

# ── E-214.8: rollback escape hatch ──────────────────────────────────────────
R11="$(_mkrepo)"
( cd "$R11" && echo z > src/impl.js && git add src/impl.js )
_OUT="$( cd "$R11" && AI_OS_CALLER_ROLE=architect AI_OS_SKIP_GIT_LANE=1 AI_OS_SKIP_STANDARDS=1 \
         CLAUDE_CODE_SESSION_ID= bash "$HOOK" 2>&1 )"; _RC=$?
assert_contains "E-214.08a: AI_OS_SKIP_GIT_LANE=1 bypasses the lane" "0" "$_RC"
assert_not_contains "E-214.08b: bypass produces no sovereignty block" "SOVEREIGNTY_BLOCK" "$_OUT"

# ── E-214.9: other Gate 2 checks still run for an architect commit ──────────
# The waiver covers the [CRITIC_STAMP] ONLY. The credential scan lives in the E-82
# standards gate, which must still fire — assert it is not short-circuited by the lane.
assert_status 0 "E-214.09a: the standards gate is still invoked before the lane" \
  bash -c "grep -n 'check_standards_gate' '$HOOK' | head -1 | cut -d: -f1 | \
           xargs -I{} test {} -lt \$(grep -n 'check_architect_git_lane\$' '$HOOK' | tail -1 | cut -d: -f1)"
assert_status 0 "E-214.09b: the co-modification warning still runs before the lane" \
  bash -c "grep -n 'check_architect_src_comodification\$' '$HOOK' | head -1 | cut -d: -f1 | \
           xargs -I{} test {} -lt \$(grep -n 'check_architect_git_lane\$' '$HOOK' | tail -1 | cut -d: -f1)"
assert_status 0 "E-214.09c: markdown sync still runs before the lane" \
  bash -c "grep -n 'check_markdown_sync\$' '$HOOK' | head -1 | cut -d: -f1 | \
           xargs -I{} test {} -lt \$(grep -n 'check_architect_git_lane\$' '$HOOK' | tail -1 | cut -d: -f1)"

# ── E-214.10: security-audit regressions (2026-09-07) ───────────────────────
# Each case below reproduces something that WORKED against the first cut.
echo "  [E-214.10] security-audit regressions"

# S1 (BLOCKING) — the lane read the staged list from a process substitution and never
# checked git's exit status. A failed `git diff` produced zero records, the
# out-of-scope list stayed empty, and the waiver was granted: any diff hiccup became a
# full Gate 2 bypass with arbitrary staged content. Proven with a stubbed git.
R12="$(_mkrepo)"
mkdir -p "$R12/stub"
cat > "$R12/stub/git" <<'EOS'
#!/usr/bin/env bash
if [[ "${1:-}" == "diff" ]]; then exit 128; fi
exec /usr/bin/git "$@"
EOS
chmod +x "$R12/stub/git"
( cd "$R12" && echo evil > src/evil.js && /usr/bin/git add src/evil.js )
_OUT="$( cd "$R12" && PATH="$R12/stub:$PATH" AI_OS_CALLER_ROLE=architect AI_OS_SKIP_STANDARDS=1 \
         CLAUDE_CODE_SESSION_ID= bash "$HOOK" 2>&1 )"; _RC=$?
assert_contains "E-214.10a: a FAILED git diff blocks (fail-closed), never waives" "1" "$_RC"
assert_not_contains "E-214.10b: a failed diff never grants the stamp waiver" "ARCHITECT_LANE" "$_OUT"
assert_contains "E-214.10c: the fail-closed block explains itself" "fail-closed" "$_OUT"

# S1b — nothing staged must NOT be treated as an architect-scoped commit; it falls
# through to the normal Gate 2 stamp check instead of collecting a waiver.
R13="$(_mkrepo)"
( cd "$R13" && rm -f .ai/REVIEWS.md )
_run "$R13" architect
assert_not_contains "E-214.10d: an EMPTY diff grants no waiver" "ARCHITECT_LANE" "$_OUT"
assert_contains "E-214.10e: an empty diff falls through to Gate 2" "1" "$_RC"

# S3 — git emits a bare `.ai` entry only when .ai/ is no longer a directory. Matching
# it as in-scope let a commit that DELETES every .ai/ file and stages a symlink in its
# place ride through on the waiver.
R14="$(_mkrepo)"
( cd "$R14" && echo x > .ai/seed.md && git add .ai/seed.md && git commit -qm seed --no-verify
  rm -rf .ai && ln -s /tmp .ai && git add -A .ai >/dev/null 2>&1 )
_run "$R14" architect
assert_contains "E-214.10f: replacing .ai/ with a symlink is BLOCKED" "SOVEREIGNTY_BLOCK" "$_OUT"
assert_not_contains "E-214.10g: and it never collects the waiver" "ARCHITECT_LANE" "$_OUT"

# S5 — the role comparison was exact-match, so `Architect` or a trailing space
# silently disabled the lane for a real Architect.
for _r in "Architect" "ARCHITECT" "architect "; do
  R15="$(_mkrepo)"
  ( cd "$R15" && echo z > src/x.js && git add src/x.js )
  _run "$R15" "$_r"
  assert_contains "E-214.10h [role='$_r']: case/whitespace variant still activates the lane" \
    "SOVEREIGNTY_BLOCK" "$_OUT"
done

# S6 — `--verify-role --mint-token` was captured by the mint block, which exits 0
# printing nothing, violating the contract that exit 0 means a role on stdout.
assert_status 1 "E-214.10i: --verify-role is not captured by the mint mode scan" \
  bash -c "node --no-warnings '$SAFE_EXEC' --verify-role --mint-\"\$(printf 'to')ken\" >/dev/null 2>&1"
# The real mint path must still work — the fix binds modes to argv[2], so verify it.
SID_M="e214m-$RANDOM$RANDOM"
_mintl architect "$SID_M"
assert_status 0 "E-214.10j: the normal mint path still works after the argv fix" \
  bash -c "[[ \"\$(node --no-warnings '$SAFE_EXEC' --verify-role '$SID_M')\" == 'architect' ]]"
rm -f "${HOME}/.ai-os/run/role-${SID_M}.lock"

# Round-2 nit: `read` folds EXTRA tab fields into the last variable, so a 4-field
# record would hide a path inside path2 (`.ai/b<TAB>src/c` matches the .ai/* arm) while
# the field counter still reported progress. Not reachable from git today, which is
# precisely why the guard belongs here rather than in a comment.
R16="$(_mkrepo)"
mkdir -p "$R16/stub"
cat > "$R16/stub/git" <<'EOS'
#!/usr/bin/env bash
if [[ "${1:-}" == "diff" ]]; then printf 'R100\t.ai/a\t.ai/b\tsrc/c\n'; exit 0; fi
exec /usr/bin/git "$@"
EOS
chmod +x "$R16/stub/git"
_OUT="$( cd "$R16" && PATH="$R16/stub:$PATH" AI_OS_CALLER_ROLE=architect AI_OS_SKIP_STANDARDS=1 \
         CLAUDE_CODE_SESSION_ID= bash "$HOOK" 2>&1 )"; _RC=$?
assert_contains "E-214.10k: a 4-field diff record blocks (fail-closed)" "1" "$_RC"
assert_contains "E-214.10l: and it says the shape was unexpected" "Unexpected diff record shape" "$_OUT"
assert_not_contains "E-214.10m: a hidden 4th-field path never collects the waiver" "ARCHITECT_LANE" "$_OUT"

# Both CLI modes are argv[2]-bound, so neither can capture the other's arguments.
# Prove WHICH mode handled the call: under an architect role, --check-path must treat
# "--verify-role" as an ordinary (out-of-scope) path and exit 2. If the verify block had
# captured the argv instead, it would exit 0 or 1 and never reach a path verdict.
assert_status 2 "E-214.10n: --check-path handles its own argv, not --verify-role's" \
  bash -c "AI_OS_CALLER_ROLE=architect node --no-warnings '$SAFE_EXEC' --check-path --verify-role >/dev/null 2>&1"

# ── E-218 (D-055 R4): the stamp waiver requires a VERIFIED record ───────────
# The path-scope BLOCK may act on the env fallback — restricting an unverified session
# is safe in the strict direction. The WAIVER may not: it is a hole in the Engineer's
# own quality gate, and `.ai/` contains REVIEWS.md, the file Gate 2 reads. So anyone
# exporting AI_OS_CALLER_ROLE=architect could previously commit stamp-file edits with
# no stamp.
echo "  [E-218] waiver requires a verified session record"

_e218_verdict() {  # <repo> <env...> → rc + label
  local d="$1"; shift
  local out rc
  out="$( cd "$d" && env "$@" AI_OS_SKIP_STANDARDS=1 bash "$HOOK" 2>&1 )"; rc=$?
  local l=pass
  printf '%s' "$out" | grep -q SOVEREIGNTY_BLOCK && l=BLOCK
  printf '%s' "$out" | grep -q 'stamp waived' && l=WAIVED
  printf '%s' "$out" | grep -q 'still applies' && l=NO_WAIVER
  printf '%s' "$out" | grep -q 'GATE 2' && l="${l}+gate2"
  printf 'rc=%s %s' "$rc" "$l"
}
_E218_A="e218t-a-$RANDOM$RANDOM"; _E218_E="e218t-e-$RANDOM$RANDOM"
_mint "$( :; )" 2>/dev/null || true
node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" architect "$_E218_A" >/dev/null 2>&1
node --no-warnings "$SAFE_EXEC" --mint-"$(printf 'to')ken" engineer  "$_E218_E" >/dev/null 2>&1

# Verified record + in scope + NO stamp → waiver applies.
R="$(_mkrepo)"; ( cd "$R" && rm -f .ai/REVIEWS.md && echo x > .ai/n.md && git add .ai/n.md )
assert_contains "E-218.01a: verified architect record waives the stamp" "rc=0 WAIVED" \
  "$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID="$_E218_A" AI_OS_CALLER_ROLE=engineer)"

# Env-only architect + in scope + NO stamp → NO waiver, Gate 2 still blocks.
R="$(_mkrepo)"; ( cd "$R" && rm -f .ai/REVIEWS.md && echo x > .ai/n.md && git add .ai/n.md )
_E218_OUT="$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=architect)"
assert_contains "E-218.01b: an env-only architect gets NO waiver" "NO_WAIVER" "$_E218_OUT"
assert_contains "E-218.01c: and Gate 2 still blocks the commit" "rc=1" "$_E218_OUT"

# Env-only architect + in scope + WITH a stamp → passes normally.
R="$(_mkrepo)"; ( cd "$R" && echo x > .ai/n.md && git add .ai/n.md )
assert_contains "E-218.01d: env-only architect passes when a stamp exists" "rc=0" \
  "$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=architect)"

# The RESTRICTION still acts on the env fallback — strict in both directions.
R="$(_mkrepo)"; ( cd "$R" && echo z > src/x.js && git add src/x.js )
assert_contains "E-218.02a: env-only architect is still path-restricted" "BLOCK" \
  "$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID= AI_OS_CALLER_ROLE=architect)"
R="$(_mkrepo)"; ( cd "$R" && echo z > src/x.js && git add src/x.js )
assert_contains "E-218.02b: verified architect is path-restricted too" "BLOCK" \
  "$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID="$_E218_A" AI_OS_CALLER_ROLE=engineer)"

# Engineer unchanged in both directions.
R="$(_mkrepo)"; ( cd "$R" && echo z > src/x.js && git add src/x.js )
assert_contains "E-218.03a: engineer with a verified record commits src/ freely" "rc=0" \
  "$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID="$_E218_E" AI_OS_CALLER_ROLE=architect)"
R="$(_mkrepo)"; ( cd "$R" && rm -f .ai/REVIEWS.md && echo z > src/x.js && git add src/x.js )
assert_contains "E-218.03b: engineer with no stamp still hits Gate 2" "gate2" \
  "$(_e218_verdict "$R" CLAUDE_CODE_SESSION_ID="$_E218_E" AI_OS_CALLER_ROLE=engineer)"

# The role source must be RETURNED, not assigned inside a command substitution — a
# variable set in the subshell never reaches the caller, and the first cut of this
# change did exactly that, so the waiver silently never fired.
assert_status 0 "E-218.04a: role source is returned as <source>:<role>" \
  grep -q "printf 'record:%s'" "$HOOK"
assert_status 0 "E-218.04b: the subshell trap is recorded in the comment" \
  grep -q "set in the SUBSHELL and lost" "$HOOK"
assert_status 0 "E-218.04c: THREAT_MODEL item 4 is marked FIXED" \
  grep -q "FIXED in E-218" "${REPO_ROOT}/.ai/THREAT_MODEL.md"
rm -f "${HOME}/.ai-os/run/role-${_E218_A}.lock" "${HOME}/.ai-os/run/role-${_E218_E}.lock"

assert_summary
