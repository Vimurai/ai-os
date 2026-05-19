#!/usr/bin/env bash
# pre_commit_standards_gate_test.sh — Tests for E-82.
#
# Verifies hooks/pre-commit.sh wires the E-80 standards-checker CLI into
# the commit pipeline per .ai/blueprints/engineering-standards.md §Components
# 2 + §Rollback Plan:
#
#   - check_standards_gate() function defined and invoked
#   - Honors AI_OS_SKIP_STANDARDS=1 rollback flag (silent skip)
#   - Locator chain: in-tree scripts/standards.mjs → ~/.ai-os/scripts/
#     fallback → graceful skip when neither present (pre-E-80 install)
#   - Skips silently when node is unavailable
#   - On CLI exit 1, prints structured [STANDARDS_BLOCK] banner + exits 1
#   - On CLI exit 0, returns 0 silently (no banner spam)
#   - ~/.ai-os mirror byte-identical
#
# Strategy: drive a sandbox git repo with controlled staged files, invoke
# the hook as a sourced function (the hook script doesn't accept args, so
# we source it and trigger only check_standards_gate to isolate the gate).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/pre-commit.sh"

echo "===== pre_commit_standards_gate_test.sh ====="

# ── T-PCS-S01: Source contract — function defined + invoked ─────────────────
echo ""
echo "  [T-PCS-S01] hooks/pre-commit.sh defines + calls check_standards_gate"

assert_status 0 "hook file exists"                       test -f "$HOOK"
assert_status 0 "bash syntax check passes"              bash -n "$HOOK"
assert_status 0 "check_standards_gate function defined" \
  grep -q 'check_standards_gate()' "$HOOK"
assert_status 0 "check_standards_gate invoked"          \
  grep -qE '^check_standards_gate$' "$HOOK"

# ── T-PCS-S02: Rollback contract — AI_OS_SKIP_STANDARDS=1 ───────────────────
echo ""
echo "  [T-PCS-S02] AI_OS_SKIP_STANDARDS=1 short-circuits the gate"

assert_status 0 "AI_OS_SKIP_STANDARDS guard present" \
  grep -q 'AI_OS_SKIP_STANDARDS' "$HOOK"
# The block must short-circuit BEFORE invoking the CLI.
assert_status 0 "skip guard appears before the CLI invocation" \
  python3 -c "
import re, sys
text = open('$HOOK').read()
# Find the function block
m = re.search(r'check_standards_gate\(\)\s*\{(.*?)\n\}\n', text, flags=re.S)
if not m: sys.exit(1)
body = m.group(1)
i_skip = body.find('AI_OS_SKIP_STANDARDS')
i_cli  = body.find('node \"\$cli\"')
sys.exit(0 if 0 <= i_skip < i_cli else 2)
"

# ── T-PCS-S03: Locator chain — in-tree → ~/.ai-os → graceful skip ────────────
echo ""
echo "  [T-PCS-S03] Locator chain matches E-58/E-65/E-75 pattern"

assert_status 0 "checks in-tree scripts/standards.mjs first" \
  grep -q '\${repo_root}/scripts/standards.mjs' "$HOOK"
assert_status 0 "falls back to ~/.ai-os/scripts/standards.mjs" \
  grep -q '\${HOME}/.ai-os/scripts/standards.mjs' "$HOOK"
assert_status 0 "graceful skip when both absent (pre-E-80 install)" \
  python3 -c "
import re, sys
text = open('$HOOK').read()
m = re.search(r'check_standards_gate\(\)\s*\{(.*?)\n\}\n', text, flags=re.S)
body = m.group(1) if m else ''
# After the locator chain there must be a 'return 0' path for the
# absent-CLI case (the third arm).
sys.exit(0 if re.search(r'cli=\"\"', body) and 'return 0' in body else 1)
"

# ── T-PCS-S04: Node-absent guard ─────────────────────────────────────────────
echo ""
echo "  [T-PCS-S04] Gate skips when node binary missing"

assert_status 0 "command -v node guard present" \
  grep -q 'command -v node' "$HOOK"

# ── T-PCS-S05: Block banner shape on CLI failure ────────────────────────────
echo ""
echo "  [T-PCS-S05] STANDARDS_BLOCK banner + exit 1 on CLI failure"

assert_status 0 "STANDARDS_BLOCK heredoc tag present"     grep -q 'STANDARDS_BLOCK' "$HOOK"
assert_status 0 "banner names the gate verbatim"          grep -q 'ENGINEERING-STANDARDS — COMMIT BLOCKED' "$HOOK"
assert_status 0 "banner documents the rollback flag"      \
  bash -c "awk '/STANDARDS_BLOCK/{f=1; next} /STANDARDS_BLOCK\$/{f=0} f' '$HOOK' | grep -q 'AI_OS_SKIP_STANDARDS=1'"
assert_status 0 "banner mentions kebab-case / shared / NDJSON fix hints" \
  bash -c "awk '/STANDARDS_BLOCK/{f=1; next} /STANDARDS_BLOCK\$/{f=0} f' '$HOOK' | grep -qiE 'kebab|shared|NDJSON'"
assert_status 0 "exit 1 follows the banner on failure" \
  python3 -c "
import re, sys
text = open('$HOOK').read()
m = re.search(r'check_standards_gate\(\)\s*\{(.*?)\n\}\n', text, flags=re.S)
body = m.group(1) if m else ''
i_banner = body.find('STANDARDS_BLOCK')
i_exit   = body.find('exit 1', i_banner) if i_banner >= 0 else -1
sys.exit(0 if i_banner >= 0 and i_exit > i_banner else 1)
"

# ── Behavioural tests: drive the hook in a sandbox git repo ─────────────────
SBOX="$(mktemp -d -t e82-XXXXXX)"
trap 'rm -rf "$SBOX"' EXIT
PROJ="${SBOX}/proj"
mkdir -p "${PROJ}/.ai" "${PROJ}/src/mcp/foo" "${PROJ}/scripts"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email "t@t"
git -C "$PROJ" config user.name "tester"
# Pre-seed .ai/TASKS.md with the generated header so check_markdown_sync
# passes through and lets the test reach check_standards_gate. The sandbox
# is deliberately stamp-free — the final has_recent_critic_stamp gate will
# still block, but only AFTER check_standards_gate runs.
cat > "${PROJ}/.ai/TASKS.md" <<'TASKS'
# TASKS (Generated from state.json)

## Engineer (Claude)
TASKS

# Copy the standards machinery + a CRITIC_STAMP into the sandbox so the
# downstream check_critic_stamp gate isn't the one tripping the test.
cp "${REPO_ROOT}/src/shared/standards.json" "${PROJ}/src/shared/standards.json" 2>/dev/null || mkdir -p "${PROJ}/src/shared" && cp "${REPO_ROOT}/src/shared/standards.json" "${PROJ}/src/shared/standards.json"
cp "${REPO_ROOT}/src/shared/standards-checker.mjs" "${PROJ}/src/shared/standards-checker.mjs"
cp "${REPO_ROOT}/scripts/standards.mjs" "${PROJ}/scripts/standards.mjs"

# Hook helper: source the file with a controlled environment.
_run_gate() {
  # $1 = extra env (KEY=VAL pairs, space-separated)
  (
    cd "$PROJ"
    eval "$1" bash -c "
      AI_DIR='${PROJ}/.ai'
      source '$HOOK' 2>/dev/null || true
      # The 'source' executes the whole hook; if the gate didn't already
      # exit, capture its exit by re-invoking. We bypass that risk by
      # running the hook as a subprocess directly.
    " >/dev/null 2>&1
  )
}

# Cleaner approach: invoke the hook as a subprocess. Stage a file that
# trips the gate (an .orig file) and confirm exit 1.
echo "junk" > "${PROJ}/leftover.orig"
git -C "$PROJ" add leftover.orig

# ── T-PCS-S06: Hook blocks commit when standards-checker fails ──────────────
echo ""
echo "  [T-PCS-S06] Hook exits 1 with banner when CLI returns error"

OUT_FILE="${SBOX}/hook.out"
(cd "$PROJ" && bash "$HOOK") > "$OUT_FILE" 2>&1
rc=$?
assert_status 0 "hook exits non-zero on standards failure" bash -c "[[ $rc -ne 0 ]]"
assert_status 0 "banner surfaced on stderr" \
  grep -q "ENGINEERING-STANDARDS — COMMIT BLOCKED" "$OUT_FILE"
assert_status 0 "CLI report appended after the banner" \
  grep -q "no_committed_tmp_files" "$OUT_FILE"

# ── T-PCS-S07: AI_OS_SKIP_STANDARDS=1 bypasses the gate ─────────────────────
echo ""
echo "  [T-PCS-S07] AI_OS_SKIP_STANDARDS=1 silences the gate"

(cd "$PROJ" && AI_OS_SKIP_STANDARDS=1 bash "$HOOK") > "$OUT_FILE" 2>&1 || true
assert_status 1 "standards banner NOT printed when skip flag set" \
  grep -q "ENGINEERING-STANDARDS — COMMIT BLOCKED" "$OUT_FILE"

# ── T-PCS-S08: Clean staged set → standards gate passes ─────────────────────
echo ""
echo "  [T-PCS-S08] Clean staged file does NOT trip the gate"

# Remove the offending .orig file from staging, stage a clean source file.
git -C "$PROJ" rm --cached leftover.orig >/dev/null 2>&1
rm "${PROJ}/leftover.orig"
echo "export const x = 1;" > "${PROJ}/src/clean.mjs"
git -C "$PROJ" add src/clean.mjs

(cd "$PROJ" && bash "$HOOK") > "$OUT_FILE" 2>&1 || true
assert_status 1 "standards banner NOT printed on clean diff" \
  grep -q "ENGINEERING-STANDARDS — COMMIT BLOCKED" "$OUT_FILE"

# ── T-PCS-S09: Node-absent path returns 0 silently (degradation) ────────────
echo ""
echo "  [T-PCS-S09] Hook degrades gracefully when node is unavailable"

# Simulate by stripping node from PATH for the hook invocation.
(cd "$PROJ" && env -i HOME="$HOME" PATH=/usr/bin:/bin bash "$HOOK") > "$OUT_FILE" 2>&1 || true
assert_status 1 "no STANDARDS banner when node absent" \
  grep -q "ENGINEERING-STANDARDS — COMMIT BLOCKED" "$OUT_FILE"

# ── T-PCS-S10: ~/.ai-os mirror byte-identical ──────────────────────────────
echo ""
echo "  [T-PCS-S10] ~/.ai-os/hooks/pre-commit.sh mirror matches src/"

MIRROR="${HOME}/.ai-os/hooks/pre-commit.sh"
if [[ -f "$MIRROR" ]]; then
  assert_status 0 "mirror is byte-identical to src/" diff -q "$HOOK" "$MIRROR"
else
  echo "    ⚠  mirror absent — skipping"
fi

echo ""
assert_summary
echo "===== pre_commit_standards_gate_test.sh PASS ====="
