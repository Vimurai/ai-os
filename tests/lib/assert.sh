#!/usr/bin/env bash
# assert.sh — AI-OS Test Assertion Library (P-15 / §22)
# All functions print pass/fail and update global counters PASS_COUNT / FAIL_COUNT.

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Colour control — only emit ANSI escapes when stdout is an interactive TTY.
if [[ -t 1 ]]; then
  _C_OK="\033[32m"; _C_FAIL="\033[31m"; _C_SKIP="\033[33m"; _C_RESET="\033[0m"
else
  _C_OK=""; _C_FAIL=""; _C_SKIP=""; _C_RESET=""
fi

_pass() {
  PASS_COUNT=$(( PASS_COUNT + 1 ))
  printf "  ${_C_OK}✓${_C_RESET} %s\n" "$1"
}

_fail() {
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  printf "  ${_C_FAIL}✗${_C_RESET} %s\n" "$1"
}

# E-236 (D-061 §4). A SKIP is its own outcome: the requirement was genuinely optional and
# absent, so there was nothing to assert. It is NOT a pass.
#
# Counting an unmet optional requirement as a pass is how a suite reports "all green" while
# testing less than it claims — the shape behind several defects this sprint, where an
# assertion silently measured whatever the host happened to have. Skips are counted
# separately so a run that quietly stops exercising a layer is VISIBLE in the totals.
_skip() {
  SKIP_COUNT=$(( SKIP_COUNT + 1 ))
  printf "  ${_C_SKIP}~${_C_RESET} %s (SKIPPED)\n" "$1"
}

# Call at end of each suite to emit machine-readable summary line
assert_summary() {
  # SKIP is appended rather than inserted: tests/run.sh greps PASS= and FAIL= independently,
  # so older parsers keep working unchanged.
  printf "SUITE_RESULT PASS=%d FAIL=%d SKIP=%d\n" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
}

# ── E-236 (D-061 §4): optional requirements SKIP, they do not fake a result ──
#
# The standing question this exists to answer: does this assertion depend on what the
# running machine happens to have? Three tests written during the 2026-09-09 sprint did,
# and each passed on a developer Mac while failing on CI — a `~/.ai-os` mirror in a
# pre-strip state, an unpruned node_modules, an ambient tmux server. The fix for a
# GENUINELY optional dependency is to skip loudly; the fix for an accidental one is to
# make the test supply what it needs. These helpers are for the first kind only.

# skip_unless_cmd <command> <reason-label> → 0 if present, 1 (and a SKIP line) if not
#
# Usage:  if skip_unless_cmd tmux "live tmux layer"; then  …assertions…  fi
skip_unless_cmd() {
  local cmd="$1" label="${2:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  _skip "${label} — '${cmd}' is not installed on this host"
  return 1
}

# skip_unless_env <VAR> <reason-label> → 0 if set and non-empty, 1 (and a SKIP line) if not
skip_unless_env() {
  local var="$1" label="${2:-$1}"
  if [[ -n "${!var:-}" ]]; then
    return 0
  fi
  _skip "${label} — \$${var} is not set"
  return 1
}

# file_mtime <path> → a single numeric mtime, or "" if unreadable
#
# NEVER chain `stat -f … || stat -c …` inside one command substitution. On Linux
# `stat -f %m FILE` means --file-system with `%m` read as a FILENAME: GNU stat prints a
# whole filesystem report for the real operand AND exits non-zero, so `$(bsd || gnu)`
# captures BOTH outputs. The result is a multi-line blob containing FREE-BLOCK COUNTS,
# which change as the machine works — so two "mtimes" taken seconds apart differ even when
# the file was never touched.
#
# That is not hypothetical: it is the E-229 `_self_stamp` bug, and it is what made
# mcp_doc_sync_test's "mtime unchanged after --check" assertion flake on CI while passing
# on macOS, where the BSD form succeeds first and the GNU form is never reached.
#
# Each form is tried separately and its result accepted only if the command SUCCEEDED and
# returned a single numeric token.
file_mtime() {
  local f="$1" m=""
  m="$(stat -c %Y "$f" 2>/dev/null)" || m=""
  if [[ -z "$m" || "$m" == *$'\n'* || ! "$m" =~ ^[0-9]+$ ]]; then
    m="$(stat -f %m "$f" 2>/dev/null)" || m=""
  fi
  if [[ -z "$m" || "$m" == *$'\n'* || ! "$m" =~ ^[0-9]+$ ]]; then
    m=""
  fi
  printf '%s' "$m"
}


# ── E-239 (D-062 §2): host-relative performance budgets ─────────────────────
#
# An absolute millisecond budget measures the MACHINE, not the code. `incident_aggregator`
# asserted "under 200ms" and measured 381ms on the Engineer's laptop while passing on CI
# (20/20); `node -e ''` alone costs ~197ms there, so a 250ms wallclock budget was
# arithmetically unreachable. The same suite then PASSED once 54 leaked tmux servers and a
# wedged download were cleared — the number was tracking machine load the whole time.
#
# So: enforce the declared ABSOLUTE budget where the hardware is known (CI), and a
# RATIO-TO-BASELINE everywhere else. The baseline is measured on the SAME HOST, in the same
# run, against the cost the code cannot avoid — a bare interpreter spawn for spawn-bound
# work, a no-op hook for hook paths.
#
# BOTH NUMBERS ARE PRINTED EVERY RUN, pass or fail. A perf assertion that prints only a
# verdict teaches nothing: you cannot tell "the code got slower" from "the machine is busy"
# without seeing the baseline next to the elapsed.

# perf_baseline_node → median ms for a bare `node -e ''` spawn on THIS host, cached per run.
#
# MEDIAN, not mean: a single scheduling hiccup would otherwise inflate the baseline and
# hide a real regression behind a generous limit. Measured inside ONE python3 process so
# the harness's own spawn cost is not folded into the number it is trying to isolate.
# CACHED IN A FILE, not a variable. Callers write `$(perf_baseline_node)`, which runs in a
# SUBSHELL — so a variable set inside it dies immediately and every assertion would
# re-measure with five node spawns. The first version of this helper claimed to cache and
# did not; the suite's own "identical within a run" assertion caught it.
#
# The cache key is the suite's PID, and any file left by a previous process with the same
# PID is cleared when this library is sourced — PIDs recycle, which is precisely how E-238's
# tmux sockets went stale.
_PERF_CACHE_DIR="${TMPDIR:-/tmp}"
_PERF_CACHE_NODE="${_PERF_CACHE_DIR}/aios-perf-node-$$"
_PERF_CACHE_HOOK="${_PERF_CACHE_DIR}/aios-perf-hook-$$"
rm -f "$_PERF_CACHE_NODE" "$_PERF_CACHE_HOOK" 2>/dev/null || true

perf_baseline_node() {
  if [[ -s "$_PERF_CACHE_NODE" ]]; then
    cat "$_PERF_CACHE_NODE"
    return 0
  fi
  local _v
  _v="$(python3 - <<'PYBASE' 2>/dev/null || echo 0
import subprocess, time
runs = []
for _ in range(5):
    t = time.perf_counter()
    subprocess.run(["node", "-e", ""], capture_output=True)
    runs.append((time.perf_counter() - t) * 1000)
runs.sort()
print(int(runs[len(runs) // 2]))
PYBASE
)"
  [[ -z "$_v" ]] && _v=0
  printf '%s' "$_v" > "$_PERF_CACHE_NODE" 2>/dev/null || true
  printf '%s' "$_v"
}

# perf_baseline_hook <hook-path> → median ms for invoking a hook that does nothing.
# The floor for any hook path is "bash starts, reads the file, exits".
perf_baseline_hook() {
  if [[ -s "$_PERF_CACHE_HOOK" ]]; then
    cat "$_PERF_CACHE_HOOK"
    return 0
  fi
  local noop _v; noop="$(mktemp)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$noop"; chmod +x "$noop"
  _v="$(NOOP="$noop" python3 - <<'PYHOOK' 2>/dev/null || echo 0
import os, subprocess, time
runs = []
for _ in range(5):
    t = time.perf_counter()
    subprocess.run(["bash", os.environ["NOOP"]], capture_output=True)
    runs.append((time.perf_counter() - t) * 1000)
runs.sort()
print(int(runs[len(runs) // 2]))
PYHOOK
)"
  rm -f "$noop"
  [[ -z "$_v" ]] && _v=0
  printf '%s' "$_v" > "$_PERF_CACHE_HOOK" 2>/dev/null || true
  printf '%s' "$_v"
}

# perf_time_ms <command...> → wallclock ms for one invocation.
perf_time_ms() {
  local s e
  s="$(python3 -c 'import time; print(time.time_ns())')"
  "$@" >/dev/null 2>&1
  e="$(python3 -c 'import time; print(time.time_ns())')"
  printf '%s' "$(( (e - s) / 1000000 ))"
}

# assert_perf <label> <elapsed_ms> <absolute_ms> <baseline_ms> [k] [slack_ms]
#
# CI (or AI_OS_PERF_ABSOLUTE=1) → the declared absolute budget, because the hardware is
# known and a real regression must not hide behind a slow runner.
# Anywhere else → elapsed <= k*baseline + slack, which asks the question that actually
# matters off CI: is this code slow RELATIVE to what this machine can do at all?
assert_perf() {
  local label="$1" elapsed="$2" absolute="$3" baseline="$4" k="${5:-2}" slack="${6:-50}"
  local mode limit
  if [[ "${AI_OS_PERF_ABSOLUTE:-0}" == "1" || "${CI:-}" == "true" ]]; then
    mode="absolute"
    limit="$absolute"
  else
    mode="relative"
    limit=$(( k * baseline + slack ))
  fi
  # Both numbers, every run, pass or fail.
  printf "  ⓘ %s: elapsed=%sms baseline=%sms limit=%sms [%s] (k=%s slack=%sms absolute=%sms)\n" \
    "$label" "$elapsed" "$baseline" "$limit" "$mode" "$k" "$slack" "$absolute"
  if [[ "${elapsed:-999999}" -le "${limit:-0}" ]]; then
    _pass "${label} (${elapsed}ms <= ${limit}ms, ${mode})"
  else
    _fail "${label} (${elapsed}ms > ${limit}ms, ${mode}; baseline ${baseline}ms on this host)"
  fi
}


# ── E-240 (D-063 §2): leaked external state ─────────────────────────────────
#
# The THIRD variety of environment dependence, after "what the machine has" (E-236) and
# "how fast it is" (E-239): WHAT A PREVIOUS RUN LEFT BEHIND.
#
# The E-227/E-228 suites leaked 50 tmux servers. The socket name used `$$`, which recycles,
# so a later run attached to a stale server still holding windows and read `windows=3`
# where it expected none. They leaked because cleanup was the LAST LINE of a block and a
# FAILING assertion never reached it — so the tests leaked precisely when something was
# already wrong, which is the worst possible time to lose cleanup.
#
# Hence: register the cleanup BEFORE creating the state. A trap that is installed after the
# resource exists has a window where a failure leaks, and that window is exactly where
# failures happen.

# THE REGISTRY IS A FILE, and the trap is installed AT SOURCE TIME. Both are forced by the
# same fact that bit E-239's baseline cache: helpers are called as `$(test_tmux_socket …)`,
# and a command substitution is a SUBSHELL. An array appended inside it dies instantly, and
# a trap installed inside it fires when that subshell exits — which is immediately, and in
# the wrong process. The first version of this did exactly that: the socket was created,
# the cleanup was registered into a subshell's array, and the array evaporated. The suite's
# own leak check caught it.
_CLEANUP_FILE="${TMPDIR:-/tmp}/aios-cleanup-$$"
# PIDs recycle (E-238), so a file left by a previous process with this PID must not be
# inherited — it would run someone else's stale teardown.
rm -f "$_CLEANUP_FILE" 2>/dev/null || true
: > "$_CLEANUP_FILE" 2>/dev/null || true

# register_cleanup <shell-command>
#
# Call this BEFORE creating the thing it cleans up. A trap installed after the resource
# exists has a window in which a failure leaks — and that window is exactly where failures
# happen. Commands run in REVERSE order (LIFO, like defer).
register_cleanup() {
  printf '%s\n' "$1" >> "$_CLEANUP_FILE" 2>/dev/null || true
}

_run_cleanups() {
  local _rc=$?
  [[ -s "$_CLEANUP_FILE" ]] || { rm -f "$_CLEANUP_FILE" 2>/dev/null; return "$_rc"; }
  local _line _n=0
  # LIFO, and EACH HANDLER IN ITS OWN SUBSHELL. One cleanup that calls `exit`, or that
  # trips `set -e`, must not skip the handlers after it — that is how a partial teardown
  # leaks the remainder, which is the failure E-240 was ruled over.
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    _n=$(( _n + 1 ))
    ( eval "$_line" ) >/dev/null 2>&1 || true
  done < <(tail -r "$_CLEANUP_FILE" 2>/dev/null || tac "$_CLEANUP_FILE" 2>/dev/null)
  # Visible, so a suite that registers nothing is distinguishable from one whose handlers
  # never ran. "It cleaned up" and "there was nothing to clean" look identical otherwise.
  [[ "$_n" -gt 0 ]] && printf 'CLEANUP %d handlers\n' "$_n"
  rm -f "$_CLEANUP_FILE" 2>/dev/null || true
  return "$_rc"
}

_clear_cleanups() {
  : > "$_CLEANUP_FILE" 2>/dev/null || true
}

# on_exit <command> — THE DOCUMENTED SPELLING (D-064). Registers a teardown that runs when
# the suite exits, however it exits. Prefer it to `trap … EXIT`: a bare trap REPLACES the
# previous handler, which is precisely how 46 suites silently disabled the cleanup
# registry.
on_exit() {
  register_cleanup "$1"
}

# ── The `trap` shadow (D-064 §1) ────────────────────────────────────────────
#
# `trap 'cmd' EXIT` REPLACES any existing EXIT handler. A suite that installed its own
# after sourcing this library therefore threw away the cleanup registry, and only the
# runner's sweep noticed. Shadowing `trap` makes the safe thing automatic instead of
# depending on every author remembering.
#
# ONLY the EXIT form is intercepted, and ONLY in the main shell. A `trap … EXIT` inside a
# SUBSHELL is meant to fire when THAT subshell exits; redirecting it into the shared
# registry would defer it to the parent's exit and change its meaning. So subshells fall
# through to the builtin and keep native semantics.
trap() {
  if [[ "${AI_OS_TEST_NO_TRAP_CHAIN:-0}" == "1" ]]; then
    builtin trap "$@"
    return $?
  fi
  # BASH_SUBSHELL counts how deep we are in subshells, and it exists in bash 3.2 — BASHPID
  # does NOT (added in 4.0), so a BASHPID comparison silently degrades to "always the main
  # shell" on macOS while working on CI's bash 5.2. That is an environment-dependent guard,
  # the very class E-236 exists to remove, and it was caught by the subshell fixture below.
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 || "${BASHPID:-$$}" != "$$" ]]; then
    builtin trap "$@"
    return $?
  fi
  if [[ $# -eq 2 ]]; then
    local _sig="$2"
    case "$_sig" in
      EXIT|exit|0)
        if [[ "$1" == "-" ]]; then
          # An explicit clear means the author wants the slate empty; honour it rather
          # than quietly keeping handlers they asked to drop.
          _clear_cleanups
          return 0
        fi
        register_cleanup "$1"
        return 0 ;;
    esac
  fi
  builtin trap "$@"
}

# `builtin` is REQUIRED here: the shadow function above intercepts `trap … EXIT`, so this
# line would otherwise REGISTER _run_cleanups as a cleanup command and install no handler
# at all — leaving nothing to run it. Caught by the acceptance fixture, which cleaned up
# nothing whatsoever.
builtin trap '_run_cleanups' EXIT

# The prefixes the runner's leak sweep matches. A suite that uses these gets swept; one
# that invents its own name does not, which is why the helpers below exist.
AIOS_TEST_SOCK_PREFIX="${AIOS_TEST_SOCK_PREFIX:-aios-test-}"
AIOS_TEST_TMP_PREFIX="${AIOS_TEST_TMP_PREFIX:-aios-t-}"

# test_tmux_socket [label] → a socket name that is unique, sweepable, and self-cleaning.
#
# NEVER `$$`: PIDs recycle, and a recycled name attaches to whatever the previous owner
# left running. The entropy comes from mktemp, and the server is killed pre-emptively in
# case a name somehow collides anyway.
test_tmux_socket() {
  local label="${1:-s}"
  local name="${AIOS_TEST_SOCK_PREFIX}${label}-$(basename "$(mktemp -u)")"
  # `tmux kill-server` stops the server but LEAVES THE SOCKET FILE. A leftover file is
  # still state a later run can trip over — and it is what the sweep counts — so remove it
  # too, or every run would report a leak it had actually cleaned up.
  register_cleanup "tmux -L '${name}' kill-server 2>/dev/null || true; rm -f \"\${TMUX_TMPDIR:-/tmp}/tmux-\$(id -u)/${name}\" 2>/dev/null || true"
  tmux -L "$name" kill-server 2>/dev/null || true
  printf '%s' "$name"
}

# test_tmpdir [label] → a temp dir that the sweep can recognise, removed on EXIT.
test_tmpdir() {
  local label="${1:-d}"
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/${AIOS_TEST_TMP_PREFIX}${label}-XXXXXX")"
  # NORMALISE. macOS sets TMPDIR with a trailing slash, so the raw path contains `//` —
  # harmless to the filesystem, but any assertion comparing it against a path that has been
  # through realpath/resolve() fails on a difference that is not real. Caught by E-242's own
  # fixture, whose expected argv had the double slash and the actual did not.
  d="$(cd "$d" && pwd -P)"
  register_cleanup "rm -rf '${d}'"
  printf '%s' "$d"
}

# test_bg <command...> → run in the background, killed on EXIT. Returns the pid.
test_bg() {
  "$@" >/dev/null 2>&1 &
  local pid=$!
  register_cleanup "kill -TERM ${pid} 2>/dev/null || true"
  printf '%s' "$pid"
}

# assert_status <expected_code> <label> <command...>
assert_status() {
  local expected="$1" label="$2"; shift 2
  local actual=0
  # Use || to safely capture non-zero exit without triggering set -e
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "$label (exit=$actual)"
  else
    _fail "$label (expected exit=$expected, got $actual)"
  fi
}

# assert_contains <label> <substring> <string>
assert_contains() {
  local label="$1" sub="$2" str="$3"
  if [[ "$str" == *"$sub"* ]]; then
    _pass "$label"
  else
    _fail "$label (expected to contain: '$sub')"
  fi
}

# assert_not_contains <label> <substring> <string>
assert_not_contains() {
  local label="$1" sub="$2" str="$3"
  if [[ "$str" != *"$sub"* ]]; then
    _pass "$label"
  else
    _fail "$label (expected NOT to contain: '$sub')"
  fi
}

# assert_exists <path>
assert_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    _pass "exists: $path"
  else
    _fail "missing: $path"
  fi
}

# assert_match <label> <regex> <string>
assert_match() {
  local label="$1" regex="$2" str="$3"
  if echo "$str" | grep -qE "$regex"; then
    _pass "$label"
  else
    _fail "$label (expected to match regex: '$regex')"
  fi
}
