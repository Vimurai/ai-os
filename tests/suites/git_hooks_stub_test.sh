#!/usr/bin/env bash
# git_hooks_stub_test.sh — Tests for E-41 git-hook stub model.
#
# Verifies install_git_hooks emits a thin execution stub instead of a full
# copy of pre-commit.sh / post-commit.sh, that the chained-hook path still
# preserves a user's pre-existing hook, that do_sync upgrades legacy copies
# in place, and that the stub fails closed when the canonical script is
# missing (Gate 2 contract).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI_BIN="${REPO_ROOT}/src/bin/ai"

echo "===== git_hooks_stub_test.sh ====="

# ── Sandbox setup ─────────────────────────────────────────────────────────────
# Create a throwaway git repo and a fake AIOS install directory under it so
# every test runs against an isolated environment. AIOS is exported via env
# so the ai bin uses our sandbox instead of the real ~/.ai-os.

TMP="$(mktemp -d -t aios-git-hooks-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="${TMP}/project"
FAKE_AIOS="${TMP}/.ai-os"

mkdir -p "$PROJECT" "${FAKE_AIOS}/hooks" "${FAKE_AIOS}/templates"
git -C "$PROJECT" init -q
# Provide canonical hook sources so install_git_hooks finds them.
cat > "${FAKE_AIOS}/hooks/pre-commit.sh" <<'PRE'
#!/usr/bin/env bash
# AI-OS Gate 2 — Quality Gate
echo "canonical pre-commit ran" >&2
exit 0
PRE
cat > "${FAKE_AIOS}/hooks/post-commit.sh" <<'POST'
#!/usr/bin/env bash
# AI-OS TASKS.md Auto-Sync
echo "canonical post-commit ran" >&2
exit 0
POST
chmod +x "${FAKE_AIOS}/hooks/"*.sh

# Source only the helpers we need from src/bin/ai. The bin guards its
# dispatcher behind argv parsing, so sourcing it without args is safe.
# To keep the test fast and side-effect free we extract the functions via
# a tiny shim that defines AIOS, HOME, then pulls in the function bodies.
SHIM="${TMP}/shim.sh"
cat > "$SHIM" <<SHIM
AIOS="${FAKE_AIOS}"
HOME="${TMP}"  # so \$HOME/.ai-os/hooks/... resolves to the fake AIOS
SHIM

# Extract just the helper block (lines around install_git_hooks &
# _upgrade_legacy_git_hooks) by sourcing the full bin in a fresh subshell
# with --no-op argv. Easier: pull functions via awk into the shim.
awk '
  /^AIOS_STUB_MARKER=/ { p = 1 }
  /^_upgrade_legacy_git_hooks\(\)/ { p = 1 }
  /^install_git_hooks\(\)/ { p = 1 }
  /^_write_pre_commit_stub\(\)/ { p = 1 }
  /^_write_post_commit_stub\(\)/ { p = 1 }
  /^_is_aios_stub\(\)/ { p = 1 }
  p { print }
  /^}/ && p { p = 0; print "" }
' "$AI_BIN" >> "$SHIM"

source "$SHIM"

# ── T-HOOK-S01: Fresh install → stub written, not a copy ─────────────────────
echo ""
echo "  [T-HOOK-S01] Fresh install emits stub"

(
  cd "$PROJECT"
  install_git_hooks >/dev/null
)

PRE_DST="${PROJECT}/.git/hooks/pre-commit"
POST_DST="${PROJECT}/.git/hooks/post-commit"

assert_status 0 "pre-commit hook installed" test -f "$PRE_DST"
assert_status 0 "pre-commit hook executable" test -x "$PRE_DST"
assert_status 0 "pre-commit is a stub (carries E-41 marker)" \
  grep -q "AI-OS Execution Stub (E-41)" "$PRE_DST"

# Stub must be small. The legacy copy is hundreds of lines; a stub is < 30.
PRE_LINES="$(wc -l < "$PRE_DST")"
assert_status 0 "pre-commit stub under 30 lines (got ${PRE_LINES})" \
  bash -c "[[ $PRE_LINES -lt 30 ]]"

assert_status 0 "pre-commit stub references \$HOME/.ai-os/hooks/pre-commit.sh" \
  grep -q '\$HOME/.ai-os/hooks/pre-commit.sh' "$PRE_DST"

assert_status 0 "pre-commit stub forwards \"\$@\" to canonical" \
  grep -qE 'exec bash "\$CANONICAL" "\$@"' "$PRE_DST"

assert_status 0 "post-commit hook installed" test -f "$POST_DST"
assert_status 0 "post-commit is a stub (carries E-41 marker)" \
  grep -q "AI-OS Execution Stub (E-41)" "$POST_DST"

POST_LINES="$(wc -l < "$POST_DST")"
assert_status 0 "post-commit stub under 30 lines (got ${POST_LINES})" \
  bash -c "[[ $POST_LINES -lt 30 ]]"

# ── T-HOOK-S02: Stub executes the canonical hook end-to-end ──────────────────
echo ""
echo "  [T-HOOK-S02] Stub runs canonical script"

# The shim points HOME at $TMP so $HOME/.ai-os/hooks/pre-commit.sh resolves
# to the fake canonical. Run the stub directly under that HOME.
PRE_OUTPUT="$(HOME="$TMP" bash "$PRE_DST" 2>&1)"
assert_contains "stub invokes canonical pre-commit" "canonical pre-commit ran" "$PRE_OUTPUT"

POST_OUTPUT="$(HOME="$TMP" bash "$POST_DST" 2>&1)"
assert_contains "stub invokes canonical post-commit" "canonical post-commit ran" "$POST_OUTPUT"

# ── T-HOOK-S03: Re-running install_git_hooks is idempotent ───────────────────
echo ""
echo "  [T-HOOK-S03] Idempotent install"

PRE_BEFORE_HASH="$(md5sum "$PRE_DST" | awk '{print $1}')"
(
  cd "$PROJECT"
  install_git_hooks >/dev/null
)
PRE_AFTER_HASH="$(md5sum "$PRE_DST" | awk '{print $1}')"
assert_status 0 "pre-commit stub unchanged on second install" \
  bash -c "[[ '$PRE_BEFORE_HASH' == '$PRE_AFTER_HASH' ]]"

# ── T-HOOK-S04: Legacy copy upgraded in place ────────────────────────────────
echo ""
echo "  [T-HOOK-S04] do_sync upgrades legacy copies"

# Replace the stub with a "legacy copy" — i.e. the literal canonical script
# without the stub marker — and confirm _upgrade_legacy_git_hooks rewrites it.
cp "${FAKE_AIOS}/hooks/pre-commit.sh" "$PRE_DST"
chmod +x "$PRE_DST"
# Sanity: it is NOT yet a stub.
assert_status 1 "legacy copy lacks stub marker (precondition)" \
  grep -q "AI-OS Execution Stub (E-41)" "$PRE_DST"

(
  cd "$PROJECT"
  _upgrade_legacy_git_hooks >/dev/null
)

assert_status 0 "legacy pre-commit upgraded to stub" \
  grep -q "AI-OS Execution Stub (E-41)" "$PRE_DST"

# Same for post-commit.
cp "${FAKE_AIOS}/hooks/post-commit.sh" "$POST_DST"
chmod +x "$POST_DST"
assert_status 1 "legacy post-commit copy lacks stub marker (precondition)" \
  grep -q "AI-OS Execution Stub (E-41)" "$POST_DST"
(
  cd "$PROJECT"
  _upgrade_legacy_git_hooks >/dev/null
)
assert_status 0 "legacy post-commit upgraded to stub" \
  grep -q "AI-OS Execution Stub (E-41)" "$POST_DST"

# ── T-HOOK-S05: Third-party hook preserved via chain ─────────────────────────
echo ""
echo "  [T-HOOK-S05] Third-party hook chained, not overwritten"

# Reset .git/hooks and seed a user-authored hook lacking AI-OS markers.
rm -f "$PRE_DST" "$POST_DST" "${PRE_DST}.pre-aios" "${POST_DST}.pre-aios"
cat > "$PRE_DST" <<'USER'
#!/usr/bin/env bash
# user's own hook
echo "user pre-commit ran" >&2
exit 0
USER
chmod +x "$PRE_DST"

(
  cd "$PROJECT"
  install_git_hooks >/dev/null
)

assert_status 0 "user hook backed up to .pre-aios" test -f "${PRE_DST}.pre-aios"
assert_status 0 "user hook content preserved" \
  grep -q "user pre-commit ran" "${PRE_DST}.pre-aios"
assert_status 0 "new pre-commit is the AI-OS stub" \
  grep -q "AI-OS Execution Stub (E-41)" "$PRE_DST"
assert_status 0 "stub references the backup chain" \
  grep -q "pre-commit.pre-aios" "$PRE_DST"

# Run the chained stub under HOME=$TMP so the fake canonical also resolves.
CHAIN_OUT="$(HOME="$TMP" bash "$PRE_DST" 2>&1)"
assert_contains "chained stub runs user hook"      "user pre-commit ran"      "$CHAIN_OUT"
assert_contains "chained stub runs canonical hook" "canonical pre-commit ran" "$CHAIN_OUT"

# ── T-HOOK-S06: Fail-closed when canonical missing (pre-commit) ──────────────
echo ""
echo "  [T-HOOK-S06] Fail-closed when canonical missing"

# Reset to a fresh stub install.
rm -f "$PRE_DST" "${PRE_DST}.pre-aios" "$POST_DST" "${POST_DST}.pre-aios"
(
  cd "$PROJECT"
  install_git_hooks >/dev/null
)

# Aim HOME at an empty directory so $HOME/.ai-os/hooks/pre-commit.sh resolves
# to nothing — the stub must abort the commit.
EMPTY_HOME="$(mktemp -d)"
PRE_FAIL_OUT="$(HOME="$EMPTY_HOME" bash "$PRE_DST" 2>&1)"
PRE_FAIL_RC=0
HOME="$EMPTY_HOME" bash "$PRE_DST" >/dev/null 2>&1 || PRE_FAIL_RC=$?
assert_contains "pre-commit warns about missing canonical" "canonical missing" "$PRE_FAIL_OUT"
assert_status 0 "pre-commit fails closed (exit != 0)" bash -c "[[ $PRE_FAIL_RC -ne 0 ]]"

# Post-commit must fail OPEN — advisory, never blocks an otherwise-good commit.
POST_FAIL_OUT="$(HOME="$EMPTY_HOME" bash "$POST_DST" 2>&1)"
POST_FAIL_RC=0
HOME="$EMPTY_HOME" bash "$POST_DST" >/dev/null 2>&1 || POST_FAIL_RC=$?
assert_contains "post-commit warns about missing canonical" "canonical missing" "$POST_FAIL_OUT"
assert_status 0 "post-commit fails open (exit 0)" bash -c "[[ $POST_FAIL_RC -eq 0 ]]"

rm -rf "$EMPTY_HOME"

# ── T-HOOK-S07: Argument forwarding ──────────────────────────────────────────
echo ""
echo "  [T-HOOK-S07] Stub forwards arguments"

# Replace the canonical with one that echoes its argv so we can assert
# faithful forwarding through the stub.
cat > "${FAKE_AIOS}/hooks/pre-commit.sh" <<'PRE_ECHO'
#!/usr/bin/env bash
# AI-OS Gate 2 — argv probe
echo "ARGV: $*"
exit 0
PRE_ECHO
chmod +x "${FAKE_AIOS}/hooks/pre-commit.sh"

ARGV_OUT="$(HOME="$TMP" bash "$PRE_DST" alpha beta 2>&1 || true)"
assert_contains "alpha forwarded to canonical" "alpha" "$ARGV_OUT"
assert_contains "beta forwarded to canonical"  "beta"  "$ARGV_OUT"

assert_summary
