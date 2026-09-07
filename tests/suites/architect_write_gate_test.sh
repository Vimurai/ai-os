#!/usr/bin/env bash
# architect_write_gate_test.sh — E-216 (D-055 R1, role-abstraction.md §Security
# "Write-gate coverage"): the widened Architect write gate.
#
# E-208 covered only the native Write/Edit tools. The security audit proved the shell
# channel wide open for an architect caller — `echo x > src/bin/ai` wrote real bytes to
# a real source file. E-216 closes the recognised shell forms and denies the MCP write
# tools; this suite pins BOTH directions, form by form, because an over-block is as
# much a bug as an under-block (it would stop the Architect writing its own blueprints).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SAFE_EXEC="${REPO_ROOT}/src/mcp/safe-exec-mcp/index.js"
# E-216: the Architect scope/write policy lives in its own module — index.js passed
# the 1000-line standards limit, and this is the cohesive piece to split out.
ARCH_WRITES="${REPO_ROOT}/src/mcp/safe-exec-mcp/architect-writes.mjs"
AI_BIN="${REPO_ROOT}/src/bin/ai"
HOOK="${REPO_ROOT}/hooks/pre-tool-use.sh"

echo "── Suite: architect_write_gate_test (E-216) ─────────────────────────"

_verdict() {  # <role> <command> → BLOCK | pass
  AI_OS_CALLER_ROLE="$1" node --no-warnings "$SAFE_EXEC" --check "$2" >/dev/null 2>&1
  [[ $? -eq 2 ]] && echo BLOCK || echo pass
}

# ── E-216.1: shell write forms with an out-of-scope target → BLOCK ──────────
_blocks() {  # <label> <command>
  assert_contains "E-216.01 [$1]" "BLOCK" "$(_verdict architect "$2")"
}
_blocks "redirect >"        'echo x > src/x.js'
_blocks "redirect >>"       'echo x >> src/x.js'
_blocks "fd redirect 1>"    'echo x 1> src/x.js'
_blocks "tee"               'echo x | tee src/x.js'
_blocks "cp"                'cp /tmp/a src/x.js'
_blocks "mv"                'mv /tmp/a src/x.js'
_blocks "install"           'install -m 644 /tmp/a src/x.js'
_blocks "ln -s"             'ln -s /tmp/a src/link'
_blocks "sed -i"            "sed -i '' s/a/b/ src/x.js"
_blocks "perl -i"           'perl -i -pe s/a/b/ src/x.js'
_blocks "rsync"             'rsync -a /tmp/a src/'
_blocks "dd of="            'dd if=/tmp/a of=src/x.js'
_blocks "truncate"          'truncate -s 0 src/x.js'
_blocks "patch"             'patch src/x.js'
_blocks "git apply"         'git apply /tmp/evil.patch'

# ── E-216.2: inline interpreters → BLOCKED OUTRIGHT ────────────────────────
# Their write target lives inside a program string this analyser does not execute, so
# "is the target in scope?" is a question it cannot answer. Refusing is the only
# honest verdict — including when the program happens to target .ai/.
_blocks "python3 -c"        'python3 -c open("src/x.js","w")'
_blocks "node -e"           'node -e process.exit(0)'
_blocks "perl -e"           'perl -e print'
_blocks "bash -c"           'bash -c echo'
_blocks "sh -c"             'sh -c echo'
_blocks "eval"              'eval echo'
assert_contains "E-216.02g: an inline interpreter is refused even when it targets .ai/" \
  "BLOCK" "$(_verdict architect 'python3 -c open(".ai/notes.md","w")')"
assert_contains "E-216.02h: a heredoc-fed interpreter is refused" \
  "BLOCK" "$(_verdict architect 'python3 <<EOF')"

# ── E-216.3: in-scope writes must still WORK (over-blocking is a bug too) ───
_allows() {  # <label> <command>
  assert_contains "E-216.03 [$1]" "pass" "$(_verdict architect "$2")"
}
_allows "redirect into .ai/"     'echo x > .ai/notes.md'
_allows "append into plans/"     'echo x >> plans/p.md'
_allows "cp INTO .ai/"           'cp /tmp/draft .ai/notes.md'
_allows "mv INTO plans/"         'mv /tmp/draft plans/p.md'
_allows "sed -i inside .ai/"     "sed -i '' s/a/b/ .ai/notes.md"
_allows "tee into .ai/"          'tee .ai/out.md'
# Sources are READS — checking them too would block copying INTO the Architect's scope.
assert_contains "E-216.03g: an out-of-scope SOURCE does not block an in-scope destination" \
  "pass" "$(_verdict architect 'cp /etc/hostname .ai/copy.md')"

# ── E-216.4: reads are untouched ───────────────────────────────────────────
for _r in 'cat src/x.js' 'grep -r foo src/' 'ls -la src/' 'git status' 'git diff --cached' 'node --version'; do
  assert_contains "E-216.04 [$_r]: read is unaffected" "pass" "$(_verdict architect "$_r")"
done

# ── E-216.5: the ENGINEER is completely unaffected ─────────────────────────
for _c in 'echo x > src/x.js' 'cp /tmp/a src/x.js' "sed -i '' s/a/b/ src/x.js" \
          'python3 -c open("src/x.js","w")' 'git apply /tmp/p.patch' 'eval echo' \
          'node -e x' 'rsync -a /tmp/a src/'; do
  assert_contains "E-216.05 [$_c]: engineer unrestricted" "pass" "$(_verdict engineer "$_c")"
done

# ── E-216.6: fail-closed on an unresolvable target ─────────────────────────
assert_contains "E-216.06a: a write verb with no resolvable target is blocked" \
  "BLOCK" "$(_verdict architect 'tee')"
assert_contains "E-216.06b: sed -i with no file operand is blocked" \
  "BLOCK" "$(_verdict architect "sed -i ''")"

# ── E-216.7: MCP write tools denied in the overlay ─────────────────────────
_OV="$(mktemp -d)/.claude"; mkdir -p "$_OV"
_AID="$(mktemp -d)"
cat > "$_AID/roles.json" <<'JSON'
{ "roles": { "architect": { "provider": "claude", "pane_identifier": "1" },
             "engineer":  { "provider": "claude", "pane_identifier": "0" } } }
JSON
bash -c "source '$AI_BIN' 2>/dev/null; _write_role_settings_overlays '$_OV' '$_AID'" >/dev/null 2>&1
_ARCH="$(cat "$_OV/settings.architect.json" 2>/dev/null)"
_ENG="$(cat "$_OV/settings.engineer.json" 2>/dev/null)"
for _d in mcp__filesystem__write_file mcp__filesystem__edit_file mcp__filesystem__move_file \
          mcp__filesystem__create_directory mcp__patch-mcp__patch_file \
          mcp__propose-patch-mcp__propose_patch mcp__propose-patch-mcp__confirm_patch; do
  assert_contains "E-216.07 [$_d]: denied for the architect" "$_d" "$_ARCH"
done
assert_not_contains "E-216.07h: the engineer overlay has no deny list" '"deny"' "$_ENG"
# The E-208 double-mint guard must survive this change.
assert_not_contains "E-216.07i: the overlay still registers NO hooks" '"hooks"' "$_ARCH"

# ── E-216.8: the three comment sites state coverage AND residual ───────────
assert_status 0 "E-216.08a: safe-exec names the shell-write analyser" \
  grep -q "analyzeArchitectWrites" "$SAFE_EXEC"
assert_status 0 "E-216.08a2: the policy module exports it" \
  grep -q "export function analyzeArchitectWrites" "$ARCH_WRITES"
assert_status 0 "E-216.08b: the policy module states its residual" \
  grep -q "STATED RESIDUAL" "$ARCH_WRITES"
assert_status 0 "E-216.08c: it says plainly that the channel is not airtight" \
  grep -q "not airtight" "$ARCH_WRITES"
assert_status 0 "E-216.08d: the hook enumerates all three layers" \
  grep -q "THREE layers" "$HOOK"
assert_status 0 "E-216.08e: the hook states its residual" \
  grep -q "STATED RESIDUAL" "$HOOK"
# The residual must name the specific uncovered forms, not hand-wave.
for _res in "encodings" "plumbing" "editors"; do
  assert_status 0 "E-216.08f [$_res]: the residual names it explicitly" \
    grep -qi "$_res" "$ARCH_WRITES"
done
# The module must carry the invariant it exists to uphold, so the next person adding a
# matcher reads it before writing one.
assert_status 0 "E-216.08g: the module records the data-vs-syntax invariant" \
  grep -q "CLASSIFIED AS DATA MUST NEVER BE READ AS SYNTAX" "$ARCH_WRITES"

# ── E-216.9: security-audit regressions (2026-09-07) ────────────────────────
# 20 mismatches, every one reproduced before fixing. The first cut read redirects from
# the RAW STRING with a regex; shell-quote's parse() gives them structurally and never
# fires inside quotes, which fixed both directions at once.
echo "  [E-216.9] security-audit regressions"

_b() { assert_contains "E-216.09 [$1]" "BLOCK" "$(_verdict architect "$2")"; }
_p() { assert_contains "E-216.09 [$1]" "pass"  "$(_verdict architect "$2")"; }

# (a) redirect forms the raw-string regex missed
_b "no-space redirect"      'echo x>src/x'
_b "&> redirect"            'echo x &> src/x'
_b ">| redirect"            'echo x >| src/x'
_b "fd redirect 2>"         'echo x 2> src/x'

# (b) path traversal — a bare prefix test let .ai/.. walk straight out, while the
# Write/Edit layer resolved it. Two layers of one rule must not disagree.
_b "traversal via .ai/.."   'echo x > .ai/../src/x'
_b "traversal with ./"      'echo x > ./.ai/../src/x'
_b "traversal via plans/.." 'echo x > plans/../src/x'
_b "traversal in cp dest"   'cp .ai/a .ai/../src/x'

# (c) absolute-path verb invocation — the interpreter loop basename-stripped, the
# verb matcher did not.
_b "/bin/cp"                '/bin/cp .ai/a src/x'
_b "/usr/bin/tee"           '/usr/bin/tee src/x'

# (d) verbs that were never enumerated
_b "curl -o"                'curl -o src/x http://e'
_b "wget -O"                'wget -O src/x http://e'
_b "git restore"            'git restore src/x'
_b "git stash pop"          'git stash pop'
_b "tar extract"            'tar -xf a.tar -C src/'
_b "unzip -d"               'unzip a.zip -d src/'
_b "sponge"                 'sponge src/x'

# (e) inline-interpreter evasions
_b "versioned python"       'python3.11 -c pass'
_b "versioned node"         'node20 -e x'
_b "node -p"                'node -p x'
_b "php -r"                 'php -r 1'
_b "python3 -m"             'python3 -m py_compile src/x'
_b "--eval long flag"       'node --eval x'

# (f) OVER-BLOCKS — the more damaging half. The Architect's job is writing prose into
# .ai/, and this repo's own notation is full of `->`; blocking that would have made
# the role unusable while looking like a security win.
_p "arrow in double quotes" 'echo "arrow a -> b"'
_p "gt in single quotes"    "echo 'use > for redirect'"
_p "gt in a format string"  "git log --pretty=format:'%h > %s'"
_p "grep for a gt char"     "grep '>' .ai/notes.md"
_p "redirect to /dev/null"  'grep -rn foo src/ > /dev/null'
_p "stderr to /dev/null"    'ls src 2>/dev/null'
_p "both to /dev/null"      'command -v node >/dev/null 2>&1'
_p "flag VALUE not a path"  'truncate -s 0 .ai/log'
_p "install -m mode value"  'install -m 644 /tmp/a .ai/b'

# (g) the deny list must cover the ROUTER, not just the tool names it forwards to.
assert_contains "E-216.09h: mcp-router proxy_call is denied for the architect" \
  "mcp__mcp-router__proxy_call" "$_ARCH"
assert_contains "E-216.09i: computer-use type_text is denied (GUI-editor channel)" \
  "mcp__computer-use-mcp__type_text" "$_ARCH"
assert_contains "E-216.09j: computer-use key_press is denied" \
  "mcp__computer-use-mcp__key_press" "$_ARCH"

# (h) the residual must NAME what it does not cover — the comment previously implied
# coverage of forms that were in fact open.
for _res in "encodings" "plumbing" "editors" "proxying" "deletion" "awk -f"; do
  assert_status 0 "E-216.09k [$_res]: named in the stated residual" \
    grep -qi -- "$_res" "$ARCH_WRITES"
done

# (i) the ENGINEER must be untouched by every one of the above.
for _c in 'echo x>src/x' 'curl -o src/x http://e' 'git restore src/x' 'python3.11 -c pass' \
          'node -p x' 'tar -xf a.tar -C src/' 'echo x > .ai/../src/x'; do
  assert_contains "E-216.09l [$_c]: engineer unrestricted" "pass" "$(_verdict engineer "$_c")"
done

# ── E-216.10: round-2 audit regressions ────────────────────────────────────
echo "  [E-216.10] round-2 audit regressions"

# -t/--target-directory is a DESTINATION for cp/mv/install, not a swallowed flag value.
# A GLOBAL value-flag set consumed it, leaving the SOURCE as the "last operand" — so
# `cp -t src/bin .ai/payload` wrote a real source file. The same global set ate the
# legitimate target of `tee -p .ai/log`. One root cause, opposite symptoms.
_b "cp -t dest dir"          'cp -t src/ .ai/a'
_b "mv -t dest dir"          'mv -t src/ .ai/a'
_b "install -t dest dir"     'install -t src/ .ai/a'
_b "--target-directory="     'cp --target-directory=src/ .ai/a'
_b "--target-directory sep"  'cp --target-directory src/ .ai/a'
_p "tee -p is boolean"       'tee -p .ai/log'
_p "-t INTO .ai/ is allowed" 'cp -t .ai/ /tmp/draft'

# An interpreter fed by a PIPE receives its program on stdin — the same "target is in a
# program string we do not execute" case, which was answering allow. Heredoc and
# here-string were already caught, which made this an oversight, not a decision.
_b "pipe into sh"            'echo x | sh'
_b "pipe into bash"          'cat .ai/p.sh | bash'
_b "pipe into python3"       'echo x | python3'
_b "pipe into node"          'echo x | node'
_p "pipe into a READER"      'cat .ai/notes.md | grep foo'

# awk is a full interpreter (print >, printf >, system(), gawk -i inplace) but
# `awk '{print $1}' f` is an ordinary READ, so refusing every awk would over-block
# badly. The program TEXT is inspected instead. Note this was a REGRESSION against the
# first cut: the raw-string regex caught awk redirects by accident, and reading
# redirects structurally correctly stopped looking inside the awk program.
_b "awk print redirect"      "awk 'BEGIN{print \"x\" > \"src/x\"}'"
_b "awk system()"            "awk 'BEGIN{system(\"echo x > src/x\")}'"
_b "gawk -i inplace"         "gawk -i inplace '{print}' src/x"
_p "awk read (field print)"  "awk '{print \$1}' .ai/notes.md"
_p "awk read with -F"        "awk -F, '{print \$2}' .ai/data.csv"

# GNU spellings and modern git equivalents.
_b "--in-place=SUFFIX"       'sed --in-place=.bak s/a/b/ src/x'
_b "git switch"              'git switch master'


# ── E-216.11: round-3 audit regressions, driven from a JSON fixture ─────────
# These payloads depend on their own exact quoting (`awk 'BEGIN{print "x" > "src/x"}'`).
# Writing them as bash cases ate those quotes TWICE during development, turning a `>`
# inside an awk program into a real shell redirection and making a genuine bypass look
# like a pass. The driver passes each command as a single argv element, so no shell
# ever re-parses it.
echo "  [E-216.11] round-3 regressions (fixture-driven)"
_CASES_OUT="$(node --no-warnings "${REPO_ROOT}/tests/lib/arch-write-cases.mjs" \
  "$SAFE_EXEC" "${REPO_ROOT}/tests/fixtures/arch-write-cases.json" 2>&1)"
_CASES_RC=$?
while IFS=$'\t' read -r _st _got _role _label; do
  [[ -z "${_st:-}" ]] && continue
  assert_contains "E-216.11 [$_role] $_label" "ok" "$_st"
done <<< "$_CASES_OUT"
assert_contains "E-216.11z: every fixture case matched its expected verdict" "0" "$_CASES_RC"

assert_summary
