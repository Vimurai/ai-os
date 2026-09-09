#!/usr/bin/env bash
# conflict_gate_test.sh — E-238 (D-062): conflict markers and unparseable .ai JSON never
# reach a commit.
#
# On 2026-09-09 a conflicted `git stash pop` left conflict markers inside .ai/state.json.
# Git reported the conflict; the file was staged and committed to master UNREAD (44243bc).
# Master carried invalid JSON for four commits, and every task read goes through that file.
#
# The over-block half is the hard half, and it is weighted accordingly below. This
# repository's own prose QUOTES conflict markers — .ai/DECISIONS.md documents this very
# gate using them — so a substring search would make the gate reject the document that
# defines it. That is exactly the trap E-224 hit when a P0 blocked the Architect's text for
# quoting the example it was defining.
#
# `=======` alone is NOT treated as a marker: exactly seven '=' at line start is also a
# valid Markdown setext H2 underline, and rejecting on it would fail any document that
# happens to underline a heading.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/pre-commit.sh"

echo "── Suite: conflict_gate_test (E-238) ───────────────────────────────"

# A scratch repo per case, so nothing here can touch the real one — and so the gate is
# exercised through `git diff --cached`, the way it runs for real, rather than by grepping
# a file directly.
_gate() {  # <filename> <content> → BLOCK | ALLOW
  local name="$1" body="$2"
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t
    mkdir -p "$(dirname "$name")" 2>/dev/null
    printf '%s' "$body" > "$name"
    git add "$name" >/dev/null 2>&1
    # Source only the two gate functions; the rest of the hook needs a provisioned project.
    source /dev/stdin <<< "$(sed -n '/^_conflict_marker_gate() {/,/^}/p;/^_ai_json_parse_gate() {/,/^}/p' "$HOOK")"
    if _conflict_marker_gate >/dev/null 2>&1 && _ai_json_parse_gate >/dev/null 2>&1; then
      echo ALLOW
    else
      echo BLOCK
    fi )
  rm -rf "$d"
}

# ── E-238.1: the real thing is caught ──────────────────────────────────────
_conflicted=$'{\n  "a": 1,\n<<<<<<< Updated upstream\n=======\n  "b": 2\n>>>>>>> Stashed changes\n}\n'
assert_contains "E-238.01a: a conflicted .ai/state.json is BLOCKED" "BLOCK" \
  "$(_gate .ai/state.json "$_conflicted")"
assert_contains "E-238.01b: markers in ANY staged file are blocked, not just .ai" "BLOCK" \
  "$(_gate src/thing.mjs $'const a = 1;\n<<<<<<< HEAD\nconst b = 2;\n=======\nconst b = 3;\n>>>>>>> other\n')"
assert_contains "E-238.01c: a bare marker with no label is blocked" "BLOCK" \
  "$(_gate notes.md $'text\n<<<<<<<\nmore\n>>>>>>>\n')"
assert_contains "E-238.01d: a rebase-style marker is blocked" "BLOCK" \
  "$(_gate f.txt $'x\n<<<<<<< HEAD (current)\ny\n>>>>>>> abc1234 (topic)\n')"

# ── E-238.2: unparseable .ai JSON is caught even WITHOUT markers ───────────
# The two failures are independent: a truncated write corrupts state.json with no conflict
# anywhere, and the gate must still stop it.
assert_contains "E-238.02a: a truncated .ai/state.json is BLOCKED" "BLOCK" \
  "$(_gate .ai/state.json '{ "tasks": [ {"id": "E-1"')"
assert_contains "E-238.02b: a trailing-comma .ai json is BLOCKED" "BLOCK" \
  "$(_gate .ai/roles.json '{ "roles": { "engineer": {} }, }')"
assert_contains "E-238.02c: valid .ai json is ALLOWED" "ALLOW" \
  "$(_gate .ai/state.json '{ "tasks": [], "stamps": [] }')"
# Scope: a non-.ai JSON file is not this gate's business — package.json is validated
# elsewhere, and widening here would block legitimate JSON-with-comments fixtures.
assert_contains "E-238.02d: a broken NON-.ai json is not this gate's business" "ALLOW" \
  "$(_gate fixtures/broken.json '{ "not": ')"

# ── E-238.3: OVER-BLOCK GUARD — prose that QUOTES markers must pass ────────
# Every case here exists in this repository or is a shape a document may legitimately have.
assert_contains "E-238.03a: backtick-quoted markers in prose are ALLOWED" "ALLOW" \
  "$(_gate .ai/DECISIONS.md 'The gate rejects a marker at line start (`<<<<<<< `, `=======`, `>>>>>>> `).')"
assert_contains "E-238.03b: a marker mid-line is not at line start" "ALLOW" \
  "$(_gate doc.md 'git leaves <<<<<<< HEAD in the file when a merge conflicts.')"
assert_contains "E-238.03c: an INDENTED marker (a fenced example) is ALLOWED" "ALLOW" \
  "$(_gate doc.md $'Example:\n\n    <<<<<<< HEAD\n    yours\n    >>>>>>> theirs\n')"
# THE SETEXT CASE. Seven '=' at line start is a valid Markdown H2 underline. A gate that
# rejected it would fail ordinary documents for looking like a conflict.
assert_contains "E-238.03d: a Markdown setext H2 underline is ALLOWED" "ALLOW" \
  "$(_gate doc.md $'Heading\n=======\n\nbody text\n')"
assert_contains "E-238.03e: a long === rule is ALLOWED" "ALLOW" \
  "$(_gate doc.md $'Title\n==========================\n\nbody\n')"
assert_contains "E-238.03f: this repo's own DECISIONS.md passes the gate" "ALLOW" \
  "$(_gate .ai/DECISIONS.md "$(cat "${REPO_ROOT}/.ai/DECISIONS.md")")"
assert_contains "E-238.03g: and its COMM.md, which narrates the incident" "ALLOW" \
  "$(_gate .ai/COMM.md "$(cat "${REPO_ROOT}/.ai/COMM.md" 2>/dev/null || echo 'no comm')")"

# NON-VACUITY for the 03 block: if _gate always answered ALLOW these would pass for the
# wrong reason, so pin that the same helper still blocks a genuine marker.
assert_contains "E-238.03h: the probe still BLOCKS a real marker (non-vacuity)" "BLOCK" \
  "$(_gate doc.md $'a\n<<<<<<< HEAD\nb\n>>>>>>> x\n')"

# ── E-238.4: the rollback exists, and the gate is wired into the hook ──────
assert_status 0 "E-238.04a: AI_OS_SKIP_CONFLICT_GATE is honoured" \
  grep -q 'AI_OS_SKIP_CONFLICT_GATE' "$HOOK"
assert_status 0 "E-238.04b: the gate runs in the hook, not merely defined" \
  grep -q '_conflict_marker_gate || _cm_ok=1' "$HOOK"
assert_status 0 "E-238.04c: the JSON gate runs too" \
  grep -q '_ai_json_parse_gate   || _cm_ok=1' "$HOOK"
# It must read the STAGED blob: worktree and index differ when only part of a file is
# staged, and what is being committed is what matters.
assert_status 0 "E-238.04d: the JSON gate inspects the STAGED blob, not the worktree" \
  bash -c "sed -n '/^_ai_json_parse_gate() {/,/^}/p' '$HOOK' | grep -q 'git show \":\\\${f}\"'"

# ── E-238.5: the rules are written down where they are read ───────────────
assert_status 0 "E-238.05a: ENGINEER.md forbids stashing bookkeeping" \
  grep -q 'Never move bookkeeping with' "${REPO_ROOT}/ENGINEER.md"
assert_status 0 "E-238.05b: and the template matches (they are one file)" \
  diff -q "${REPO_ROOT}/ENGINEER.md" "${REPO_ROOT}/src/templates/ENGINEER.md"
assert_status 0 "E-238.05c: the triage rule is recorded" \
  grep -q 'presumed REAL until you have read its log' "${REPO_ROOT}/ENGINEER.md"
# The triage rule is only useful if it says what a flake claim REQUIRES; "rerun it" is how
# a real failure gets filed as noise.
assert_status 0 "E-238.05d: and it demands a NAMED nondeterminism, not just a rerun" \
  grep -q 'named nondeterminism' "${REPO_ROOT}/ENGINEER.md"
assert_status 0 "E-238.05e: commit-crafter carries the staging rule" \
  grep -q 'Stage named paths, not' "${REPO_ROOT}/src/claude/skills/commit-crafter/SKILL.md"
assert_status 0 "E-238.05f: commit-crafter mirror is in sync" \
  diff -q "${REPO_ROOT}/src/claude/skills/commit-crafter/SKILL.md" \
          "${REPO_ROOT}/.claude/skills/commit-crafter/SKILL.md"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== conflict_gate_test.sh PASS ====="
else
  echo "===== conflict_gate_test.sh FAIL (${FAIL_COUNT}) ====="
fi
