#!/usr/bin/env bash
# browser_optin_test.sh — E-235 (D-061 §3): the browser download is opt-in and bounded.
#
# `ai mcp-setup` ran `npx playwright install chromium` unconditionally, inside the path
# that install-ai-os.sh — and so every user install and every CI run — depends on. It is an
# unbounded ~150MB fetch, and on 2026-09-09 it ran for over an HOUR on a developer machine
# without finishing.
#
# The `|| true` that wrapped it was worthless: the failure mode is HANGING, not erroring,
# and you cannot `|| true` your way out of a process that never returns. That is why the
# assertions below are about ABSENCE FROM THE DEFAULT PATH and about a real bound — not
# about error handling, which was never the problem.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AI="${REPO_ROOT}/src/bin/ai"
VC="${REPO_ROOT}/src/mcp/vibe-check-mcp"

echo "── Suite: browser_optin_test (E-235) ───────────────────────────────"

# ── E-235.1: the default path no longer downloads ─────────────────────────
assert_status 0 "E-235.01a: the default branch tells the operator how to opt in" \
  grep -q "skipping Playwright browsers — run: ai mcp-setup --browsers" "$AI"
assert_status 0 "E-235.01b: the download is gated on WANT_BROWSERS" \
  grep -q 'if \[\[ "$WANT_BROWSERS" -eq 1 \]\]; then' "$AI"
# NON-VACUITY: the download must still EXIST — this task moves it, it does not delete the
# capability. An assertion that only checked for absence would pass on a broken removal.
assert_status 0 "E-235.01c: the download still exists, inside the bounded helper" \
  grep -q 'npx playwright install chromium' "$AI"
assert_status 0 "E-235.01d: and lives in _install_browsers, not the install loop" \
  bash -c "sed -n '/^_install_browsers()/,/^}/p' '$AI' | grep -q 'npx playwright install chromium'"

# ── E-235.2: --browsers and the env rollback both opt in ──────────────────
assert_status 0 "E-235.02a: --browsers sets the flag" \
  grep -q '\[\[ "$_a" == "--browsers" \]\] && WANT_BROWSERS=1' "$AI"
assert_status 0 "E-235.02b: AI_OS_INSTALL_BROWSERS=1 restores the old behaviour" \
  grep -q 'AI_OS_INSTALL_BROWSERS:-0' "$AI"

# ── E-235.3: the download is BOUNDED, and the bound is enforced not assumed ─
# `timeout(1)` is absent on macOS by default, so a script that merely CALLS timeout has a
# limit only on some hosts. A bound that silently is not applied is worse than none,
# because it is believed. This asserts a watchdog is actually used.
assert_status 0 "E-235.03a: a timeout budget exists and is configurable" \
  grep -q 'AI_OS_BROWSER_TIMEOUT:-600' "$AI"
assert_status 0 "E-235.03b: enforced by a watchdog, not by the absent timeout(1)" \
  bash -c "sed -n '/^_install_browsers()/,/^}/p' '$AI' | grep -q 'kill -TERM'"
assert_status 1 "E-235.03c: it does NOT rely on timeout(1) being installed" \
  bash -c "sed -n '/^_install_browsers()/,/^}/p' '$AI' | grep -qE '^\s*timeout '"
# Progress: output piped through `tail -2` made a long download look exactly like a hung
# one. Nothing tells an operator less than a silent process.
assert_status 1 "E-235.03d: progress is not swallowed by tail" \
  bash -c "sed -n '/^_install_browsers()/,/^}/p' '$AI' | grep -q 'tail -2'"
assert_status 0 "E-235.03e: the operator is told what is happening and for how long" \
  bash -c "sed -n '/^_install_browsers()/,/^}/p' '$AI' | grep -q 'bounded to'"
# An optional browser must never fail the install.
assert_status 0 "E-235.03f: a failed download does not fail the install" \
  bash -c "sed -n '/^_install_browsers()/,/^}/p' '$AI' | grep -q 'return 0'"

# ── E-235.4: first use fails FAST and says what to run ────────────────────
assert_status 0 "E-235.04a: the browser-check helper exists" test -f "${VC}/browser-check.mjs"
assert_status 0 "E-235.04b: every launch site is guarded" \
  bash -c "[[ \"\$(grep -c 'assertBrowserAvailable(chromium)' '${VC}/index.js')\" -eq 3 ]]"
assert_status 0 "E-235.04c: the rejection is machine-greppable" \
  grep -q 'BROWSER_MISSING' "${VC}/browser-check.mjs"
# A diagnostic that does not tell you what to run is half a message.
assert_status 0 "E-235.04d: and names the one command that fixes it" \
  grep -q 'ai mcp-setup --browsers' "${VC}/browser-check.mjs"

# The helper's logic, exercised rather than grepped.
_probe() {  # <mode> → ok|missing
  MODE="$1" node --input-type=module -e '
    const { browserStatus } = await import(process.env.BC);
    // A stub chromium that behaves like Playwright with no browser downloaded.
    const missing = { executablePath: () => { throw new Error("Executable doesn'"'"'t exist"); } };
    const present = { executablePath: () => process.env.BC.replace("file://", "") };
    const c = process.env.MODE === "present" ? present : missing;
    console.log(browserStatus(c).ok ? "ok" : "missing");
  ' 2>/dev/null
}
export BC="file://${VC}/browser-check.mjs"
assert_contains "E-235.04e: a missing executable is detected"        "missing" "$(_probe missing)"
assert_contains "E-235.04f: a present executable is accepted"        "ok"      "$(_probe present)"
assert_contains "E-235.04g: AI_OS_SKIP_BROWSER_CHECK=1 bypasses the probe" "ok" \
  "$(AI_OS_SKIP_BROWSER_CHECK=1 _probe missing)"

# ── E-235.5: doctor reports browser status ────────────────────────────────
assert_status 0 "E-235.05a: doctor has a browser section" \
  grep -q 'Vibe-check browsers' "$AI"
assert_status 0 "E-235.05b: and tells the operator how to fix it" \
  bash -c "grep -A12 'Vibe-check browsers' '$AI' | grep -q 'ai mcp-setup --browsers'"

# ── E-235.6: CI installs them explicitly, and caches ──────────────────────
WF="${REPO_ROOT}/.github/workflows/test.yml"
assert_status 0 "E-235.06a: the workflow installs Chromium explicitly" \
  grep -q 'npx playwright install --with-deps chromium' "$WF"
assert_status 0 "E-235.06b: cached, so it is a download once per version" \
  grep -q 'ms-playwright' "$WF"
assert_status 0 "E-235.06c: the cache key tracks the package that pins the version" \
  grep -q "hashFiles('src/mcp/vibe-check-mcp/package.json')" "$WF"

# ── E-235.7: DEVOPS.md records the change (ci_gate) ───────────────────────
assert_status 0 "E-235.07a: DEVOPS-006 exists" \
  grep -q 'DEVOPS-006' "${REPO_ROOT}/.ai/DEVOPS.md"
assert_status 0 "E-235.07b: with a rollback plan" \
  bash -c "grep -A4 'Rollback plan' '${REPO_ROOT}/.ai/DEVOPS.md' | grep -q 'AI_OS_INSTALL_BROWSERS=1'"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== browser_optin_test.sh PASS ====="
else
  echo "===== browser_optin_test.sh FAIL (${FAIL_COUNT}) ====="
fi
