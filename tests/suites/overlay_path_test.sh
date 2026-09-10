#!/usr/bin/env bash
# overlay_path_test.sh — E-242 (D-066): launch paths are absolute, overlays self-heal.
#
# The reported failure was `ai start` → "Settings file not found:
# .claude/settings.architect.json" for a file that EXISTS (793 B, right there). The path was
# wrong, not the file: the adapter templates emit PROJECT-RELATIVE paths, which resolve only
# when the CLI's cwd happens to be the project root. An rc-file `cd`, a pre-existing tmux
# session or window, or a pane opened in a subdirectory all break it.
#
# THE RULEFILE WAS BROKEN THE SAME WAY, and that half is worse: `--append-system-prompt-file
# ARCHITECT.md` failing does not produce an error, it produces the WRONG PERSONA — a claude
# Architect pane boots the ENGINEER from CLAUDE.md. That is gap G1, the thing the
# same-provider Triad depends on. A missing settings file is loud; a missing rulefile is
# silent, so it is asserted here first.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVE="${REPO_ROOT}/src/shared/resolve-launch.mjs"
AI="${REPO_ROOT}/src/bin/ai"

echo "── Suite: overlay_path_test (E-242) ────────────────────────────────"

# A project fixture with both roles mapped to claude, per the D-066 default.
_proj() {
  local d; d="$(test_tmpdir e242)"
  mkdir -p "$d/.ai" "$d/.claude"
  cat > "$d/.ai/roles.json" <<'JSON'
{ "roles": { "architect": {"provider":"claude","pane_identifier":"1","model":"fable"},
             "engineer":  {"provider":"claude","pane_identifier":"0","model":"opus"} } }
JSON
  : > "$d/.claude/settings.architect.json"
  : > "$d/.claude/settings.engineer.json"
  : > "$d/ARCHITECT.md"; : > "$d/ENGINEER.md"
  printf '%s' "$d"
}

_argv() {  # <cwd> <role> <aiDir> → argv on one line
  ( cd "$1" && node "$RESOLVE" "$2" "$3" 2>/dev/null | tr '\n' ' ' )
}

# ── E-242.1: every path operand is ABSOLUTE, from any cwd ─────────────────
_p="$(_proj)"
_from_root="$(_argv "$_p" architect "$_p/.ai")"
mkdir -p "$_p/deep/nested"
_from_sub="$(_argv "$_p/deep/nested" architect "$_p/.ai")"
_from_out="$(_argv / architect "$_p/.ai")"

assert_contains "E-242.01a: settings path is absolute (from the project root)" \
  "--settings ${_p}/.claude/settings.architect.json" "$_from_root"
# THE SILENT HALF: a relative rulefile yields the wrong persona, not an error.
assert_contains "E-242.01b: rulefile path is absolute — a relative one boots the WRONG PERSONA (G1)" \
  "--append-system-prompt-file ${_p}/ARCHITECT.md" "$_from_root"
assert_contains "E-242.01c: identical from a SUBDIRECTORY (the reported failure)" \
  "--settings ${_p}/.claude/settings.architect.json" "$_from_sub"
assert_contains "E-242.01d: and the rulefile too, from a subdirectory" \
  "--append-system-prompt-file ${_p}/ARCHITECT.md" "$_from_sub"
assert_contains "E-242.01e: identical from a cwd OUTSIDE the project" \
  "--settings ${_p}/.claude/settings.architect.json" "$_from_out"
# The strongest form of the property: cwd cannot change the argv at all.
assert_status 0 "E-242.01f: the argv does not depend on cwd (root == subdir == outside)" \
  bash -c "[[ '$_from_root' == '$_from_sub' && '$_from_sub' == '$_from_out' ]]"
# NON-VACUITY: a relative path must be absent, or 01a-f could pass on a broken build that
# emitted both forms.
assert_status 1 "E-242.01g: no bare relative '.claude/settings' survives (non-vacuity)" \
  bash -c "printf '%s' '$_from_root' | grep -q -- '--settings \.claude/'"

# The engineer role resolves the same way, with its own model.
_eng="$(_argv "$_p/deep/nested" engineer "$_p/.ai")"
assert_contains "E-242.01h: engineer overlay is absolute too" \
  "--settings ${_p}/.claude/settings.engineer.json" "$_eng"
assert_contains "E-242.01i: and carries its own model (D-066: opus)" "--model opus" "$_eng"
assert_contains "E-242.01j: architect carries fable" "--model fable" "$_from_root"

# ── E-242.2: an ALREADY-absolute operand is left alone ────────────────────
# The rewrite must not mangle a path an author anchored deliberately.
_abs="$(node --input-type=module -e '
  const { absolutisePathOperands } = await import(process.env.PA);
  const a = ["--settings", "/etc/x.json", "--append-system-prompt-file", "~/R.md", "--model", "opus"];
  console.log(absolutisePathOperands(a, "/proj").join(" "));
' 2>/dev/null)"
export PA="file://${REPO_ROOT}/src/shared/provider-adapter.mjs"
_abs="$(PA="file://${REPO_ROOT}/src/shared/provider-adapter.mjs" node --input-type=module -e '
  const { absolutisePathOperands } = await import(process.env.PA);
  const a = ["--settings", "/etc/x.json", "--append-system-prompt-file", "~/R.md", "--model", "opus"];
  console.log(absolutisePathOperands(a, "/proj").join(" "));
' 2>/dev/null)"
assert_contains "E-242.02a: an absolute operand is untouched" "/etc/x.json" "$_abs"
assert_contains "E-242.02b: a ~-anchored operand is untouched" "~/R.md" "$_abs"
assert_status 1 "E-242.02c: and neither was rewritten under the project root" \
  bash -c "printf '%s' '$_abs' | grep -q '/proj/'"
# A non-path flag's operand must never be treated as a path.
_np="$(PA="file://${REPO_ROOT}/src/shared/provider-adapter.mjs" node --input-type=module -e '
  const { absolutisePathOperands } = await import(process.env.PA);
  console.log(absolutisePathOperands(["--model","opus","-p","hello world"], "/proj").join("|"));
' 2>/dev/null)"
assert_contains "E-242.02d: --model's operand is not a path and is untouched" "opus" "$_np"
assert_status 1 "E-242.02e: a prompt is not rewritten either" \
  bash -c "printf '%s' '$_np' | grep -q '/proj/hello'"

# ── E-242.3: self-heal — a MISSING overlay is regenerated ─────────────────
# Distinct from the path bug: a project cloned before E-208, or one whose .claude/ was
# cleaned, produces the same message for a genuinely absent file.
# A REAL run, not --dry-run: a dry run DESCRIBES and must not write, so it cannot be used
# to exercise the self-heal. Driven through a private tmux socket so no real session is
# touched, and torn down by the registered cleanup.
_h="$(_proj)"
rm -f "$_h/.claude/settings.architect.json"
if skip_unless_cmd tmux "E-242.03 self-heal (needs a real ai start)"; then
  _hs="$(test_tmux_socket e242)"
  _hshim="$(test_tmpdir e242shim)"
  printf '#!/usr/bin/env bash\nexec %s -L %s "$@"\n' "$(command -v tmux)" "$_hs" > "${_hshim}/tmux"
  chmod +x "${_hshim}/tmux"
  _out="$( cd "$_h" && PATH="${_hshim}:$PATH" bash "$AI" start --detach --no-watch 2>&1 )"
  assert_contains "E-242.03a: a real ai start reports it is regenerating the overlay" \
    "regenerating missing per-role settings overlays" "$_out"
  assert_status 0 "E-242.03b: and the overlay actually exists afterwards" \
    test -f "$_h/.claude/settings.architect.json"
else
  _skip "E-242.03b: self-heal overlay check (tmux not installed)"
fi

# --dry-run DESCRIBES and must never write. A "show me what you would do" invocation that
# modifies the project is the one thing a dry run promises not to be.
_dr="$(_proj)"
rm -f "$_dr/.claude/settings.architect.json"
_dout="$( cd "$_dr" && bash "$AI" start --dry-run 2>&1 )"
assert_contains "E-242.03a-dry: a dry run SAYS the overlays are missing" \
  "(dry run) per-role settings overlays are missing" "$_dout"
assert_status 1 "E-242.03b-dry: and does NOT write the overlay" \
  test -f "$_dr/.claude/settings.architect.json"
# It must NOT rewrite settings.json — that file carries hooks and env, a far larger side
# effect than "start a pane" implies.
assert_status 0 "E-242.03c: ai pane self-heals the same way" \
  grep -q 'missing — regenerating it' "$AI"
assert_status 0 "E-242.03d: only the ROLE overlay is written, never settings.json" \
  bash -c "grep -A3 'missing — regenerating it' '$AI' | grep -q '_write_role_settings_overlays'"

# ── E-242.4: nothing regenerates when the overlays are already present ────
# A pre-check that fires every run would rewrite files on every launch.
_q="$(_proj)"
_quiet="$( cd "$_q" && bash "$AI" start --dry-run 2>&1 )"
assert_status 1 "E-242.04a: no regeneration when both overlays exist" \
  bash -c "printf '%s' '$_quiet' | grep -q 'regenerating missing'"

echo ""
assert_summary
if [[ "${FAIL_COUNT:-0}" -eq 0 ]]; then
  echo "===== overlay_path_test.sh PASS ====="
else
  echo "===== overlay_path_test.sh FAIL (${FAIL_COUNT}) ====="
fi
