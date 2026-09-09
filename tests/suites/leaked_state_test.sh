#!/usr/bin/env bash
# leaked_state_test.sh — E-240 (D-063 §2): a test run leaves nothing behind.
#
# The third variety of environment dependence, after "what the machine has" (E-236) and
# "how fast it is" (E-239): WHAT A PREVIOUS RUN LEFT BEHIND.
#
# The E-227/E-228 suites leaked 50 tmux servers. Cleanup was the LAST LINE of a block, so a
# FAILING assertion never reached it — the tests leaked precisely when something was
# already wrong. Their socket names used `$$`, which recycles, so a later run attached to a
# leftover server still holding windows and read `windows=3`.
#
# The assertions are weighted toward two things:
#   * cleanup must survive the FAILING path, which is the only one that ever leaked;
#   * the sweep must NEVER touch state outside the test prefix. A cleanup tool that can
#     kill the operator's own tmux session is worse than the leak it fixes.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${REPO_ROOT}/tests/lib/assert.sh"
RUNNER="${REPO_ROOT}/tests/run.sh"
SOCKDIR="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"

echo "── Suite: leaked_state_test (E-240) ────────────────────────────────"

# ── E-240.1: cleanup survives a mid-suite failure ─────────────────────────
# This is the case that leaked. A fixture that aborts halfway must still tear down.
_fixture() {  # <body> → the path it created, after the fixture has exited
  local body="$1" out; out="$(mktemp)"
  ( source "$LIB"; eval "$body" ) >/dev/null 2>&1
  cat "$out" 2>/dev/null; rm -f "$out"
}
_probe="$(mktemp)"
( source "$LIB"
  d="$(test_tmpdir midfail)"
  printf '%s' "$d" > "$_probe"
  exit 1 ) >/dev/null 2>&1
_leftover="$(cat "$_probe")"; rm -f "$_probe"
assert_status 0 "E-240.01a: the fixture actually created something (non-vacuity)" \
  bash -c "[[ -n '$_leftover' ]]"
assert_status 1 "E-240.01b: a temp dir is removed even when the suite ABORTS midway" \
  test -d "$_leftover"

# A tmux socket, the thing that actually leaked 50 times.
_probe2="$(mktemp)"
( source "$LIB"
  s="$(test_tmux_socket midfail)"
  tmux -L "$s" new-session -d -s x 2>/dev/null
  printf '%s' "$s" > "$_probe2"
  exit 1 ) >/dev/null 2>&1
_sock="$(cat "$_probe2")"; rm -f "$_probe2"
assert_status 0 "E-240.01c: the fixture actually created a socket (non-vacuity)" \
  bash -c "[[ -n '$_sock' ]]"
assert_status 1 "E-240.01d: the tmux SERVER is gone after an aborted suite" \
  bash -c "tmux -L '$_sock' list-sessions >/dev/null 2>&1"
# kill-server leaves the socket FILE; a leftover file is still state the sweep would count.
assert_status 1 "E-240.01e: and the socket FILE is removed too" \
  test -e "${SOCKDIR}/${_sock}"

# ── E-240.2: registration works from a SUBSHELL ───────────────────────────
# Helpers are called as `$(test_tmux_socket …)`, which IS a subshell. The first version of
# register_cleanup used an array and a lazily-installed trap, so both died with that
# subshell and nothing was ever cleaned. Same defect as E-239's baseline cache.
_probe3="$(mktemp)"
( source "$LIB"
  d="$(test_tmpdir subshell)"      # created inside a command substitution
  printf '%s' "$d" > "$_probe3" ) >/dev/null 2>&1
_sub="$(cat "$_probe3")"; rm -f "$_probe3"
assert_status 0 "E-240.02a: the subshell fixture created something (non-vacuity)" \
  bash -c "[[ -n '$_sub' ]]"
assert_status 1 "E-240.02b: cleanup registered INSIDE a subshell still runs" \
  test -d "$_sub"

# ── E-240.3: names carry entropy, never $$ ────────────────────────────────
# `$$` recycles, and a recycled name attaches to whatever the previous owner left running.
_n1="$( source "$LIB"; test_tmux_socket n )"
_n2="$( source "$LIB"; test_tmux_socket n )"
assert_status 1 "E-240.03a: two sockets in a row are not the same name" \
  bash -c "[[ '$_n1' == '$_n2' ]]"
assert_match "E-240.03b: the name carries the sweepable test prefix" '^aios-test-' "$_n1"
assert_status 1 "E-240.03c: helpers do not use \$\$ for socket names" \
  bash -c "sed -n '/^test_tmux_socket() {/,/^}/p' '$LIB' | grep -q '\\\$\\\$'"

# ── E-240.4: THE SAFETY PROPERTY — the sweep spares foreign state ─────────
# A sweep that can kill the operator's own tmux session is worse than the leak it fixes.
_foreign="e240-not-a-test-socket-$$"
tmux -L "$_foreign" new-session -d -s work 2>/dev/null
_victim="aios-test-victim-$(basename "$(mktemp -u)")"
tmux -L "$_victim" new-session -d -s v 2>/dev/null
assert_status 0 "E-240.04a: both probe servers are up (non-vacuity)" \
  bash -c "tmux -L '$_foreign' has-session -t work 2>/dev/null && tmux -L '$_victim' has-session -t v 2>/dev/null"
bash -c "
  AIOS_TEST_SOCK_PREFIX='aios-test-'; AIOS_TEST_TMP_PREFIX='aios-t-'
  eval \"\$(sed -n '/^_leak_sweep() {/,/^}/p' '$RUNNER')\"
  _leak_sweep 'tmux-server|$_foreign
tmux-server|$_victim'" >/dev/null 2>&1
assert_status 0 "E-240.04b: a FOREIGN tmux server SURVIVES the sweep" \
  bash -c "tmux -L '$_foreign' has-session -t work 2>/dev/null"
assert_status 1 "E-240.04c: a test-prefixed server is swept (non-vacuity)" \
  bash -c "tmux -L '$_victim' list-sessions >/dev/null 2>&1"
tmux -L "$_foreign" kill-server 2>/dev/null || true
rm -f "${SOCKDIR}/${_foreign}" "${SOCKDIR}/${_victim}" 2>/dev/null || true

# ── E-240.5: the runner reports and gates ─────────────────────────────────
assert_status 0 "E-240.05a: the runner snapshots external state" \
  grep -q '_leak_snapshot' "$RUNNER"
assert_status 0 "E-240.05b: it reports LEAKED n <kind> per suite" \
  grep -q 'LEAKED \${_n} \${_kinds}' "$RUNNER"
assert_status 0 "E-240.05c: a leak FAILS the run on CI" \
  bash -c "grep -A3 'LEAK_FAILED' '$RUNNER' | grep -q 'TOTAL_FAIL'"
assert_status 0 "E-240.05d: --sweep is offered locally" \
  grep -q 'tests/run.sh --sweep' "$RUNNER"
assert_status 0 "E-240.05e: AI_OS_TEST_NO_SWEEP=1 disables the check" \
  grep -q 'AI_OS_TEST_NO_SWEEP' "$RUNNER"
# The sweep re-checks the prefix at the kill site as well as at snapshot time. Defence in
# depth on the one branch that can destroy an operator's session.
assert_status 0 "E-240.05f: the sweep re-checks the prefix before killing" \
  bash -c "sed -n '/^_leak_sweep() {/,/^}/p' '$RUNNER' | grep -q 'AIOS_TEST_SOCK_PREFIX}\"\\*'"

# ── E-240.6: the previously-leaking suites are converted ──────────────────
for f in ai_start_test ai_start_surface_test; do
  assert_status 0 "E-240.06: ${f} uses test_tmux_socket" \
    grep -q 'test_tmux_socket' "${REPO_ROOT}/tests/suites/${f}.sh"
  assert_status 1 "E-240.06: ${f} no longer names a socket with \$\$" \
    grep -q 'aios-e22[78]-\$\$' "${REPO_ROOT}/tests/suites/${f}.sh"
done

# ── E-240.7: review question #3 is recorded ──────────────────────────────
assert_status 0 "E-240.07a: critic_tests asks what a halfway failure leaves behind" \
  grep -q 'What does this test leave behind when an assertion fails HALFWAY' \
    "${REPO_ROOT}/src/claude/agents/critic_tests.md"
assert_status 0 "E-240.07b: ai-review asks it too" \
  grep -q 'What does this test leave behind when an assertion fails HALFWAY' \
    "${REPO_ROOT}/src/claude/skills/ai-review/SKILL.md"
assert_status 0 "E-240.07c: it insists cleanup is registered BEFORE the state exists" \
  grep -q 'registered before' "${REPO_ROOT}/src/claude/agents/critic_tests.md"
assert_status 0 "E-240.07d: the generated plugin artifact was rebuilt (E-236 lesson)" \
  grep -q 'leave behind when an assertion fails' \
    "${REPO_ROOT}/src/agents/plugin/agents/critic_tests/agent.json"


# ── E-241 (D-064 §1): trap chaining — the limitation E-240 could not close ──
# A bare `trap 'cmd' EXIT` REPLACES the handler, so 42 suites silently discarded the
# cleanup registry and only the runner's sweep noticed. `trap` is now shadowed for the EXIT
# form so it CHAINS. This is the acceptance case: a suite that installs its own trap AFTER
# sourcing assert.sh must still self-clean.
# Run the probe as its OWN PROCESS, not `( … )`. Inside a subshell the guard correctly
# passes `trap` through to the builtin (native semantics), so a subshell fixture would test
# the opposite of the real case — a suite is a process, launched as `bash suite.sh`.
_chain_probe="$(mktemp)"; _chain_own="$(mktemp)"; _chain_sh="$(mktemp)"
cat > "$_chain_sh" <<CHAINEOF
source "$LIB"
d="\$(test_tmpdir chain)"; printf '%s' "\$d" > "$_chain_probe"
own="\$(mktemp -d)";       printf '%s' "\$own" > "$_chain_own"
trap "rm -rf '\$own'" EXIT  # standards:allow-raw-trap - fixture data, not an installation
exit 1
CHAINEOF
bash "$_chain_sh" >/dev/null 2>&1
rm -f "$_chain_sh"
_cl="$(cat "$_chain_probe")"; _co="$(cat "$_chain_own")"; rm -f "$_chain_probe" "$_chain_own"
assert_status 0 "E-241.01a: both fixtures created something (non-vacuity)" \
  bash -c "[[ -n '$_cl' && -n '$_co' ]]"
assert_status 1 "E-241.01b: the LIBRARY cleanup still ran despite the suite's own trap" \
  test -d "$_cl"
assert_status 1 "E-241.01c: and the suite's OWN trap ran too (chained, not replaced)" \
  test -d "$_co"

# A `trap … EXIT` inside a SUBSHELL must keep NATIVE semantics — it fires when THAT
# subshell exits, not at the parent's. Redirecting it into the shared registry would defer
# it and change its meaning. The guard uses BASH_SUBSHELL because BASHPID does not exist in
# bash 3.2, so a BASHPID test would behave differently on macOS and on CI — the exact
# environment dependence E-236 exists to remove.
_sub_out="$( ( source "$LIB"; ( trap 'echo SUBSHELL_FIRED' EXIT; true ); echo PARENT_LINE ) 2>&1 )"
assert_contains "E-241.02a: a subshell trap fires at the SUBSHELL's exit" "SUBSHELL_FIRED" "$_sub_out"
assert_status 0 "E-241.02b: and it fires BEFORE the parent continues (native order)" \
  bash -c "[[ \"\$(printf '%s' '$_sub_out' | grep -n SUBSHELL_FIRED | cut -d: -f1)\" -lt \"\$(printf '%s' '$_sub_out' | grep -n PARENT_LINE | cut -d: -f1)\" ]]"
assert_status 0 "E-241.02c: the guard uses BASH_SUBSHELL (bash 3.2 safe)" \
  grep -q 'BASH_SUBSHELL:-0' "$LIB"

assert_status 0 "E-241.03a: on_exit is the documented spelling" grep -q '^on_exit() {' "$LIB"
assert_status 0 "E-241.03b: CLEANUP n handlers is printed" grep -q "CLEANUP %d handlers" "$LIB"
assert_status 0 "E-241.03c: handlers run in their own subshell (one cannot skip the next)" \
  bash -c "sed -n '/^_run_cleanups() {/,/^}/p' '$LIB' | grep -q '( eval'"
assert_status 0 "E-241.03d: AI_OS_TEST_NO_TRAP_CHAIN=1 restores the builtin" \
  grep -q 'AI_OS_TEST_NO_TRAP_CHAIN' "$LIB"
# The library's own installation MUST use `builtin`, or the shadow swallows it and no
# handler is installed at all — which is exactly what happened on the first attempt.
assert_status 0 "E-241.03e: the library installs its handler with builtin trap" \
  grep -q "^builtin trap '_run_cleanups' EXIT" "$LIB"

# Counted with the RULE ITSELF rather than a hand-rolled grep, so the assertion and the
# gate cannot disagree about what counts — the E-232 lesson (one definition, reused).
export REPO_ROOT
export CHECKER_URL="file://${REPO_ROOT}/src/shared/standards-checker.mjs"
_raw_traps="$(node --input-type=module -e '
  const { RULE_REGISTRY } = await import(process.env.CHECKER_URL);
  const { readFileSync } = await import("fs");
  const { execSync } = await import("child_process");
  const r = RULE_REGISTRY.no_raw_exit_trap_in_tests;
  const files = execSync("find tests -name \"*.sh\"", {encoding:"utf8", cwd: process.env.REPO_ROOT}).trim().split("\n").filter(Boolean);
  let n = 0;
  for (const f of files) {
    const c = readFileSync(process.env.REPO_ROOT + "/" + f, "utf8");
    const res = r({ relPath: f, content: c, lines: c.split("\n"), rule: { rule_id: "x" } });
    if (res) n += res.length;
  }
  console.log(n);
' 2>/dev/null)"
assert_contains "E-241.04a: no raw 'trap … EXIT' remains anywhere in tests/ (found=${_raw_traps})" \
  "0" "${_raw_traps:-unknown}"
assert_status 0 "E-241.04b: the standards rule exists" \
  grep -q 'no_raw_exit_trap_in_tests' "${REPO_ROOT}/src/shared/standards-checker.mjs"
assert_status 0 "E-241.04c: and is registered" \
  grep -q 'no_raw_exit_trap_in_tests' "${REPO_ROOT}/src/shared/standards.json"
assert_status 0 "E-241.05a: review question #4 is in critic_tests" \
  grep -q 'called inside a command substitution' "${REPO_ROOT}/src/claude/agents/critic_tests.md"
assert_status 0 "E-241.05b: and in ai-debug" \
  grep -q 'called inside a command substitution' "${REPO_ROOT}/src/shared/skills/ai-debug/SKILL.md"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== leaked_state_test.sh PASS ====="
else
  echo "===== leaked_state_test.sh FAIL (${FAIL_COUNT}) ====="
fi
