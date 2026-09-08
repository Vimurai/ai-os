#!/usr/bin/env bash
# patch_project_boundary_test.sh — E-221 (D-057 §1): the propose→confirm project boundary.
#
# `propose_patch` stored an ABSOLUTE path resolved against the proposing process's root;
# `confirm_patch` wrote to it without re-checking against its OWN root. Confirming a
# pending patch from a different project therefore landed the write outside that project.
# Not a role escape — the role is re-derived per process since E-219 — the boundary that
# was missing is the PROJECT one.
#
# Every case drives the REAL server over stdio through a full two-phase cycle
# (tests/lib/propose-patch-driver.mjs). A static grep cannot express a defect that lives
# in the relationship between two calls made from two working directories.
#
# NON-VACUITY: the `cross` case was run against the pre-fix server and DID write into the
# other project ("applied  patched|original"). It fails against the vulnerable code, which
# is the only thing that makes it worth keeping.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/assert.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRIVER="${REPO_ROOT}/tests/lib/propose-patch-driver.mjs"
SERVER="${REPO_ROOT}/src/mcp/propose-patch-mcp/index.js"
STATE_DB="${REPO_ROOT}/src/mcp/shared/state-db.js"

echo "── Suite: patch_project_boundary_test (E-221) ───────────────────────"

_drive() { node --no-warnings "$DRIVER" "$1" 2>/dev/null | tail -1; }

# ── E-221.1: the ordinary path still works ──────────────────────────────────
# A boundary check that breaks the legitimate case is not a fix. This runs first for
# that reason: everything below is a refusal, and refusals are cheap to get right by
# refusing everything.
_r="$(_drive same)"
assert_contains "E-221.01a: propose+confirm in ONE project applies the patch" "applied" "$_r"
assert_contains "E-221.01b: the target file actually changed" "patched" "$_r"

# ── E-221.2: confirming from another project is refused ─────────────────────
# The vulnerability itself. The second project reaches the same patch store through a
# `.ai` symlink — without that the store simply is not shared and the case is unreachable.
_r="$(_drive cross)"
assert_contains "E-221.02a: a cross-project confirm returns PROJECT_MISMATCH" "PROJECT_MISMATCH" "$_r"
assert_contains "E-221.02b: NEITHER project's file was written" "original|original" "$_r"
assert_not_contains "E-221.02c: the proposing project was not silently patched" "patched" "$_r"

# ── E-221.3: the stored relative path is data, not a destination ─────────────
# Storing the root alone would only DETECT a mismatch. Re-resolving the relative path is
# what stops a row edited in the DB from escaping while the roots still agree.
_r="$(_drive tampered-rel)"
assert_contains "E-221.03a: a tampered rel_path is refused" "PROJECT_ESCAPE" "$_r"
assert_match "E-221.03b: nothing was written outside the root" '(^|	)-$|	-$' "$_r"

# ── E-221.4: pre-migration rows are refused, not guessed at ─────────────────
# A legacy row records no project root, so nothing in it says which project it belonged
# to. Guessing is the behaviour being removed.
_r="$(_drive legacy)"
assert_contains "E-221.04a: a legacy record is rejected" "LEGACY_PATCH" "$_r"
assert_contains "E-221.04b: it is left unapplied" "original" "$_r"
assert_status 0 "E-221.04c: the rejection tells the caller to re-propose" \
  bash -c "grep -q 'Re-propose it here' '$SERVER'"

# ── E-221.5: the rollback flag restores acceptance, but not the hole ────────
_r="$(_drive legacy-ok)"
assert_contains "E-221.05a: AI_OS_PATCH_LEGACY=1 accepts an in-project legacy record" "applied" "$_r"
_r="$(_drive legacy-escape)"
assert_contains "E-221.05b: even then, an out-of-root absolute path is refused" "PROJECT_ESCAPE" "$_r"
assert_match "E-221.05c: the out-of-root canary was never written" '	-$' "$_r"

# ── E-221.6: the read-only tools are unchanged (D-057 §1) ───────────────────
_r="$(_drive preview)"
assert_contains "E-221.06a: preview_patch still renders the pending diff" "previewed" "$_r"
assert_contains "E-221.06b: preview writes nothing" "original" "$_r"
_r="$(_drive reject)"
assert_contains "E-221.06c: reject_patch still discards the patch" "rejected" "$_r"
assert_contains "E-221.06d: reject writes nothing" "original" "$_r"

# ── E-221.7: the schema carries the evidence ────────────────────────────────
assert_status 0 "E-221.07a: fresh DBs create project_root + rel_path" \
  bash -c "grep -q 'project_root TEXT' '$STATE_DB' && grep -q 'rel_path     TEXT' '$STATE_DB'"
assert_status 0 "E-221.07b: legacy DBs get an idempotent ALTER" \
  bash -c "grep -q '_migratePatchProjectRoot' '$STATE_DB'"
assert_status 0 "E-221.07c: the INSERT actually names the new columns" \
  bash -c "grep -q 'project_root, rel_path' '$SERVER'"

# ── E-221.8: confirm never writes to the stored absolute path ───────────────
# The regression that would quietly reopen this: re-deriving targetPath and then applying
# to `patch.path` anyway. E-219 F4 is the precedent — a test that asserted a COPY of the
# guard passed while the shipped code was wrong.
_apply_block="$(sed -n '/Apply the patch — determine if diff_content/,/reject_patch/p' "$SERVER")"
assert_not_contains "E-221.08a: the apply block references no stored absolute path" "patch.path" "$_apply_block"
assert_contains "E-221.08b: it writes to the re-derived path" "targetPath" "$_apply_block"
assert_contains "E-221.08c: the role re-check uses the re-derived path too" \
  "roleGuard(patch.caller_role, targetPath, cwd)" "$(cat "$SERVER")"

# ── E-221.10: a symlinked directory component cannot forward a write out ────
# The E-221 audit's H1, reproduced independently: `src/esc -> ../outside`, one project,
# no cross-project confirm, no DB tampering. The old four-line safePath was LEXICAL, so
# the relative path held no ".." and the write followed the link out of the root.
# Non-vacuity: against the pre-fix server this mode prints "applied  patched" — the file
# OUTSIDE the project was rewritten.
_r="$(_drive symlink-escape)"
assert_not_contains "E-221.10a: the symlinked write is refused" "applied" "$_r"
assert_contains "E-221.10b: the file outside the root is untouched" "UNTOUCHED" "$_r"
assert_status 0 "E-221.10c: safePath delegates to the shared predicate, not a local copy" \
  bash -c "grep -q 'projectPathVerdict(filePath, cwd)' '$SERVER'"
assert_status 1 "E-221.10d: no hand-rolled lexical bounds test survives" \
  bash -c "grep -q 'rel.startsWith(\"..\")' '$SERVER'"

# ── E-221.11: an empty rel_path does not select the legacy branch ───────────
# The audit's L1. Legacy is the branch that SKIPS the equality check, so it must be
# chosen by column ABSENCE, never by a value the record itself controls.
_r="$(_drive root-target)"
assert_not_contains "E-221.11a: a root-naming patch is not misreported as legacy" "LEGACY_PATCH" "$_r"
assert_not_contains "E-221.11b: and it is never applied" "applied" "$_r"
assert_status 0 "E-221.11c: legacy is detected by NULL columns, not falsiness" \
  bash -c "grep -q 'patch.project_root == null || patch.rel_path == null' '$SERVER'"

# ── E-221.12: a failed apply leaves the file byte-identical and no debris ────
# The audit's H2 was reported as a dry-run BYPASS; that payload did not reproduce here
# (patch 2.0-12u11-Apple refuses it at the dry-run and the message is accurate). The
# rollback SHAPE was wrong regardless: patch(1) writes `.orig` per SECTION, so a later
# failure could "restore" partially-applied content, and `${target}.orig` clobbered a
# real file of that name. The rollback now uses an in-memory pre-image and verifies it.
_r="$(_drive failed-apply)"
assert_contains "E-221.12a: a failed apply leaves the file unchanged" "unchanged" "$_r"
assert_contains "E-221.12b: no stray .orig is left in the tree" "clean" "$_r"
assert_status 1 "E-221.12c: patch(1) is no longer asked to write its own backup" \
  bash -c "grep -q '\"-b\", \"-f\"' '$SERVER'"
assert_status 0 "E-221.12d: the restore is verified before it is claimed" \
  bash -c "grep -q 'rollback could not be verified' '$SERVER'"

# ── E-221.13: rollback housekeeping never destroys a user's file ────────────
# patch(1) backs up to `${target}.orig` on its own initiative, so a user file of that
# name sat in the blast radius of the cleanup. Same class of harm as the E-220 over-prune:
# a maintenance path deleting something real.
_r="$(_drive orig-collateral)"
assert_contains "E-221.13a: the patch still applies" "applied" "$_r"
assert_contains "E-221.13b: a pre-existing .orig file is left intact" "MY OWN FILE" "$_r"

# ── E-221.14: diff_content cannot name its own write targets ────────────────
# The audit's H3, and the finding that mattered most: E-221 validated the PATH three ways
# and none of it bounded what patch(1) WRITES. The operand governs the FIRST diff section
# only; later sections take their targets from their own headers. An ed-style prelude
# needs no header at all, so "at most one section" — my first rule — was not enough
# either. The rule is now "unified diff and nothing else".
#
# Non-vacuity, both modes against the pre-fix server:
#   multi-section-redirect → "applied  benign|TARGET_ORIGINAL|PWNED"   (wrote OUTSIDE the root)
#   ed-prelude             → "applied  ATTACKER_CONTENT|z|VICTIM_ORIGINAL" (wrote TWO files)
_r="$(_drive multi-section-redirect)"
assert_contains "E-221.14a: a second diff section is refused" "DIFF_REDIRECT" "$_r"
assert_contains "E-221.14b: nothing anywhere was written" "TARGET_ORIGINAL|TARGET_ORIGINAL|VICTIM_ORIGINAL" "$_r"
_r="$(_drive ed-prelude)"
assert_contains "E-221.14c: an ed-script prelude is refused" "DIFF_REDIRECT" "$_r"
assert_contains "E-221.14d: neither the operand nor the header file changed" \
  "TARGET_ORIGINAL|TARGET_ORIGINAL|VICTIM_ORIGINAL" "$_r"
assert_status 0 "E-221.14e: the blob is validated at propose AND at confirm" \
  bash -c "test \$(grep -c 'validateDiffContent' '$SERVER') -ge 2"

# A removed line beginning with '--' renders as '--- x' and must be read as hunk DATA,
# never as a section header — the E-216 invariant, in a new parser.
assert_status 0 "E-221.14f: hunk data that looks like a header is not read as syntax" \
  node --input-type=module --no-warnings -e '
    import { validateDiffContent } from "'"${REPO_ROOT}"'/src/mcp/propose-patch-mcp/diff-targets.mjs";
    const b = "--- a/x\n+++ b/x\n@@ -1,3 +1,1 @@\n-- dashes\n--- three\n-plain\n+new\n";
    process.exit(validateDiffContent(b).ok ? 0 : 1);
  '
assert_status 0 "E-221.14g: an ordinary single-file diff still passes" \
  node --input-type=module --no-warnings -e '
    import { validateDiffContent } from "'"${REPO_ROOT}"'/src/mcp/propose-patch-mcp/diff-targets.mjs";
    const b = "--- a/src/x.js\n+++ b/src/x.js\n@@ -1,2 +1,2 @@\n-old\n+new\n ctx\n";
    process.exit(validateDiffContent(b).ok ? 0 : 1);
  '
assert_status 0 "E-221.14h: full-file content (no hunks) is unaffected" \
  node --input-type=module --no-warnings -e '
    import { validateDiffContent } from "'"${REPO_ROOT}"'/src/mcp/propose-patch-mcp/diff-targets.mjs";
    process.exit(validateDiffContent("just\nsome\nfile content\n").ok ? 0 : 1);
  '

# ── E-221.15: the diff grammar must accept what git actually emits ──────────
# Strictness that rejects real input is not a security win, it is an outage. The
# `\ No newline at end of file` marker sits AFTER a hunk's last counted line, so the walk
# had already exited and read it as stray content — every diff of a file without a
# trailing newline was refused, which is the single most likely diff a model produces.
_dg() {  # <blob> → ok | REFUSED
  node --input-type=module --no-warnings -e '
    import { validateDiffContent } from "'"${REPO_ROOT}"'/src/mcp/propose-patch-mcp/diff-targets.mjs";
    const v = validateDiffContent(process.argv[1]);
    process.stdout.write(v.ok ? "ok" : "REFUSED");
  ' -- "$1" 2>/dev/null
}
assert_contains "E-221.15a: a no-newline marker is accepted" "ok" \
  "$(_dg '--- a/x
+++ b/x
@@ -1,1 +1,1 @@
-old
+new
\ No newline at end of file
')"
assert_contains "E-221.15b: a no-newline marker mid-hunk is accepted" "ok" \
  "$(_dg '--- a/x
+++ b/x
@@ -1,2 +1,2 @@
-old
\ No newline at end of file
+new
 ctx
')"
assert_contains "E-221.15c: /dev/null file creation is accepted" "ok" \
  "$(_dg '--- /dev/null
+++ b/new.txt
@@ -0,0 +1,1 @@
+hello
')"

# ── E-221.16: the parse holds on its OWN terms, not on patch(1)'s strictness ─
# An inflated hunk count runs the walk off the end of the blob with counters still
# positive, silently swallowing whatever followed — including a second `--- victim`
# header — and the walk would then report a clean single-section parse. patch(1) happens
# to reject those blobs here, but "the binary is strict" is the reasoning that hid the
# redirect in the first place.
assert_contains "E-221.16a: an inflated hunk count is refused" "REFUSED" \
  "$(_dg '--- a
+++ a
@@ -1,9 +1,9 @@
-L1
+ok
--- outside/victim.txt
+++ outside/victim.txt
')"
assert_contains "E-221.16b: a truncated hunk is refused" "REFUSED" \
  "$(_dg '--- a
+++ a
@@ -1,50 +1,50 @@
-one
+two
')"
assert_contains "E-221.16c: an ABSOLUTE header path is refused, not just a relative one" "REFUSED" \
  "$(_dg '--- /etc/hosts
+++ /etc/hosts
@@ -1,1 +1,1 @@
-a
+b
')"

# ── E-221.17: containment does NOT depend on which patch(1) is installed ────
# All local testing ran against `patch 2.0-12u11-Apple`; GNU patch 2.7.x was never
# exercised (no Docker, and this repo has no CI configuration at all). That gap is bounded
# rather than argued: both redirect payloads are refused by the JS validator BEFORE
# `patch` is spawned, so no behaviour of the binary can change the outcome. These
# assertions call the validator directly — no subprocess, nothing platform-specific —
# so they hold identically wherever the suite runs.
assert_contains "E-221.17a: the multi-section payload is refused in JS" "REFUSED" \
  "$(_dg '--- a
+++ a
@@ -1,1 +1,1 @@
-A
+B
--- ../outside/v.txt
+++ ../outside/v.txt
@@ -1,1 +1,1 @@
-C
+D
')"
assert_contains "E-221.17b: the ed-prelude payload is refused in JS" "REFUSED" \
  "$(_dg '1c
ATTACKER
.
w
--- z.txt
+++ z.txt
@@ -1,1 +1,1 @@
-ORIGINAL_LINE_1
+z
')"
assert_status 0 "E-221.17c: the blob is validated before patch(1) is ever spawned" \
  bash -c "python3 - '$SERVER' <<'PYX'
import sys
s = open(sys.argv[1]).read()
i = s.index('validateDiffContent(args.diff_content)')      # propose-time gate
j = s.index('spawnSync(\"patch\"')                          # first patch invocation
sys.exit(0 if i < j else 1)
PYX"

# ── E-221.9: roots compare by realpath ──────────────────────────────────────
# /tmp is a symlink to /private/tmp on macOS: a string compare would reject legitimate
# confirms there, and every case above runs under mktemp.
assert_contains "E-221.09a: root comparison canonicalises both sides" "canonicalRoot" "$(cat "$SERVER")"

assert_summary
